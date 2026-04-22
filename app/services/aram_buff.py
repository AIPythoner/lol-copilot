"""ARAM balance data.

The old CommunityDragon aggregate endpoint was removed. ARAM Mayhem publishes a
static, server-rendered balance page with the same per-champion modifiers, so we
scrape that page and map champion names back to CDragon champion ids.
"""
from __future__ import annotations

import re
from html import unescape
from typing import Any

import httpx

from app.common.logger import get_logger

log = get_logger(__name__)

ARAM_MAYHEM_URL = "https://arammayhem.com/aram-balance/"
CHAMPION_SUMMARY_URL = (
    "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/"
    "champion-summary.json"
)


def _norm_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", name.lower())


def _percent_to_factor(raw: str) -> float:
    value = float(raw.replace("%", "").replace("+", "").strip())
    return round(1.0 + value / 100.0, 4)


def _apply_modifier(entry: dict[str, Any], label: str, raw_value: str) -> None:
    value = _percent_to_factor(raw_value)
    label = label.lower().strip()
    if label == "damage dealt":
        entry["damageDealt"] = value
    elif label == "damage received":
        entry["damageReceived"] = value
    elif label == "healing":
        entry["healingReceived"] = value
    elif label == "shielding":
        entry["shielding"] = value
    elif label == "ability haste":
        entry["abilityHaste"] = int(round((value - 1.0) * 100))
    elif label == "tenacity":
        entry["tenacity"] = value
    elif label == "energy regen":
        entry["energyRegen"] = value
    elif label == "attack speed":
        entry["attackSpeed"] = value


def _strip_tags(html: str) -> str:
    return re.sub(r"<[^>]+>", "", html)


async def fetch_aram() -> dict[int, dict[str, Any]]:
    async with httpx.AsyncClient(timeout=20.0) as c:
        champions_resp, aram_resp = await c.get(CHAMPION_SUMMARY_URL), await c.get(ARAM_MAYHEM_URL)
        champions_resp.raise_for_status()
        aram_resp.raise_for_status()

    champions = champions_resp.json()
    name_to_id: dict[str, int] = {}
    for champ in champions if isinstance(champions, list) else []:
        if not isinstance(champ, dict) or champ.get("id") in (None, -1):
            continue
        cid = int(champ["id"])
        for key in (champ.get("name"), champ.get("alias")):
            if key:
                name_to_id[_norm_name(str(key))] = cid

    out: dict[int, dict[str, Any]] = {}
    for row_match in re.finditer(
        r'<a\b(?=[^>]*class="[^"]*\bchampion-row\b[^"]*")[\s\S]*?</a>',
        aram_resp.text,
    ):
        row = row_match.group(0)
        name_match = re.search(r'alt="([^"]+)"', row)
        if name_match is None:
            continue
        champion_name = unescape(name_match.group(1))
        cid = name_to_id.get(_norm_name(champion_name))
        if cid is None:
            log.debug("unknown ARAM champion row: %s", champion_name)
            continue
        entry: dict[str, Any] = {
            "championId": cid,
            "damageDealt": 1.0,
            "damageReceived": 1.0,
            "healingReceived": 1.0,
            "shielding": 1.0,
            "abilityHaste": 0.0,
            "tenacity": 1.0,
            "energyRegen": 1.0,
            "attackSpeed": 1.0,
        }
        for span in re.findall(r"<span\b[^>]*>([\s\S]*?)</span>", row):
            text = unescape(_strip_tags(span)).strip()
            match = re.match(r"(.+?):\s*([+-]?\d+(?:\.\d+)?%)$", text)
            if match:
                _apply_modifier(entry, match.group(1), match.group(2))
        out[cid] = {
            k: v for k, v in entry.items()
            if k == "championId" or v not in (1.0, 0.0)
        }
    return out
