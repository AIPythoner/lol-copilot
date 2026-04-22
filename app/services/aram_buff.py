"""ARAM balance data.

Source: CommunityDragon's aggregated `aram.json` — more reliable than scraping
jddld.com, and the numbers are the same (both ultimately come from Riot).

Returns per-champion mul/div factors for damage dealt / received / ability
haste / shielding / tenacity etc.
"""
from __future__ import annotations

from typing import Any

import httpx

from app.common.logger import get_logger

log = get_logger(__name__)

CDRAGON_URL = "https://raw.communitydragon.org/latest/cdragon/aram/default.json"


async def fetch_aram() -> dict[int, dict[str, Any]]:
    async with httpx.AsyncClient(timeout=20.0) as c:
        resp = await c.get(CDRAGON_URL)
        resp.raise_for_status()
        data = resp.json()
    out: dict[int, dict[str, Any]] = {}
    for entry in (data.get("data") or {}).values():
        try:
            cid = int(entry.get("id"))
        except (TypeError, ValueError):
            continue
        out[cid] = {
            "championId": cid,
            "damageDealt": entry.get("stats", {}).get("dmg_dealt", 1.0),
            "damageReceived": entry.get("stats", {}).get("dmg_taken", 1.0),
            "healingReceived": entry.get("stats", {}).get("healing", 1.0),
            "shielding": entry.get("stats", {}).get("shielding", 1.0),
            "abilityHaste": entry.get("stats", {}).get("ability_haste", 0.0),
            "tenacity": entry.get("stats", {}).get("tenacity", 1.0),
            "energyRegen": entry.get("stats", {}).get("energy_regen", 1.0),
            "attackSpeed": entry.get("stats", {}).get("attack_speed", 1.0),
        }
    return out
