"""OP.GG scraper — champion builds for ranked and alt modes.

OP.GG renders pages server-side with React Server Components; the data is
embedded in `self.__next_f.push([1, "..."])` payloads. We fetch the HTML,
extract the RSC stream, and parse out item sets, rune pages, skill order,
and summoner spells.

This is a best-effort scraper — OP.GG's layout changes every few months.
Fall back to a clear error when we can't find expected markers, rather
than returning garbage.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Any, Optional

import httpx

from app.common.logger import get_logger

log = get_logger(__name__)

BASE_URL = "https://www.op.gg"
RANKED_PATH = "/champions/{champ}/build"
MODE_PATH = "/modes/{mode}/{champ}/build"

DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
}

_RSC_RE = re.compile(r'self\.__next_f\.push\(\[1,"((?:\\.|[^"\\])*)"\]\)', re.DOTALL)


@dataclass
class RunePage:
    primary_style_id: int
    sub_style_id: int
    selected_perk_ids: list[int]


@dataclass
class BuildVariant:
    name: str  # "Most Popular" / "Highest Win Rate" / mode-specific
    items_start: list[int] = field(default_factory=list)
    items_core: list[int] = field(default_factory=list)
    items_boots: list[int] = field(default_factory=list)
    items_situational: list[int] = field(default_factory=list)
    skill_order: list[str] = field(default_factory=list)
    summoner_spells: list[int] = field(default_factory=list)
    rune_page: Optional[RunePage] = None


@dataclass
class ChampionBuild:
    champion: str
    mode: str  # "ranked" | "aram" | "urf" | ...
    position: Optional[str]
    tier: Optional[str]
    patch: Optional[str]
    variants: list[BuildVariant] = field(default_factory=list)


class OpggError(RuntimeError):
    pass


def _slugify(name: str) -> str:
    return name.lower().replace("'", "").replace(" ", "").replace(".", "")


async def fetch_build(
    champion: str,
    *,
    mode: str = "ranked",
    position: Optional[str] = None,
    tier: str = "emerald_plus",
    region: str = "global",
    timeout: float = 15.0,
) -> ChampionBuild:
    slug = _slugify(champion)
    if mode == "ranked":
        url = BASE_URL + RANKED_PATH.format(champ=slug)
        params: dict[str, str] = {"region": region, "tier": tier}
        if position:
            params["position"] = position
    else:
        url = BASE_URL + MODE_PATH.format(mode=mode, champ=slug)
        params = {}

    async with httpx.AsyncClient(headers=DEFAULT_HEADERS, follow_redirects=True) as c:
        resp = await c.get(url, params=params, timeout=timeout)
        if resp.status_code != 200:
            raise OpggError(f"op.gg {resp.status_code} for {url}")
        html = resp.text

    return _parse_build(html, champion=champion, mode=mode, position=position)


def _extract_rsc_chunks(html: str) -> list[str]:
    chunks = []
    for m in _RSC_RE.finditer(html):
        raw = m.group(1)
        try:
            decoded = bytes(raw, "utf-8").decode("unicode_escape")
        except UnicodeDecodeError:
            decoded = raw
        chunks.append(decoded)
    return chunks


def _parse_build(html: str, *, champion: str, mode: str, position: Optional[str]) -> ChampionBuild:
    chunks = _extract_rsc_chunks(html)
    if not chunks:
        raise OpggError("op.gg: no RSC chunks found (layout changed?)")

    # Heuristic scan: concatenate, find any embedded JSON arrays/objects we care about.
    blob = "".join(chunks)
    patch = _scan_patch(blob)
    tier = None

    build = ChampionBuild(champion=champion, mode=mode, position=position, patch=patch, tier=tier)
    build.variants = _scan_variants(blob)
    if not build.variants:
        log.warning("op.gg: no variants parsed for %s/%s — site format may have changed", champion, mode)
    return build


def _scan_patch(blob: str) -> Optional[str]:
    m = re.search(r'"version"\s*:\s*"([^"]+)"', blob)
    if m:
        return m.group(1)
    m = re.search(r'"patch"\s*:\s*"([^"]+)"', blob)
    return m.group(1) if m else None


def _scan_variants(blob: str) -> list[BuildVariant]:
    variants: list[BuildVariant] = []

    # Look for common build-item arrays. These selectors are intentionally loose
    # so we tolerate minor schema drift.
    for label, key in (
        ("Most Popular", "most_popular"),
        ("Highest Win Rate", "highest_win_rate"),
    ):
        items_start = _find_int_array(blob, rf'{key}[^\{{]*?"starter[^"]*"\s*:\s*\[([^\]]*)\]')
        items_core = _find_int_array(blob, rf'{key}[^\{{]*?"core[^"]*"\s*:\s*\[([^\]]*)\]')
        items_boots = _find_int_array(blob, rf'{key}[^\{{]*?"boots?"\s*:\s*\[([^\]]*)\]')
        items_extra = _find_int_array(blob, rf'{key}[^\{{]*?"extra[^"]*"\s*:\s*\[([^\]]*)\]')
        spells = _find_int_array(blob, rf'{key}[^\{{]*?"(?:summoner|spells?)"\s*:\s*\[([^\]]*)\]')

        if any((items_start, items_core, items_boots, items_extra)):
            variants.append(
                BuildVariant(
                    name=label,
                    items_start=items_start,
                    items_core=items_core,
                    items_boots=items_boots,
                    items_situational=items_extra,
                    summoner_spells=spells,
                    rune_page=_scan_rune_page(blob, key),
                )
            )
    return variants


def _find_int_array(blob: str, pattern: str) -> list[int]:
    m = re.search(pattern, blob, flags=re.IGNORECASE)
    if not m:
        return []
    raw = m.group(1)
    return [int(x) for x in re.findall(r"\d+", raw)]


def _scan_rune_page(blob: str, key: str) -> Optional[RunePage]:
    m = re.search(
        rf'{key}[^\{{]*?"primary_page_id"\s*:\s*(\d+)[^\{{]*?"sub_page_id"\s*:\s*(\d+)[^\{{]*?"rune_ids"\s*:\s*\[([^\]]*)\]',
        blob,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not m:
        return None
    return RunePage(
        primary_style_id=int(m.group(1)),
        sub_style_id=int(m.group(2)),
        selected_perk_ids=[int(x) for x in re.findall(r"\d+", m.group(3))],
    )


def to_item_set(build: ChampionBuild, variant_index: int = 0, map_id: int = 11) -> dict[str, Any]:
    """Convert a build variant to a Riot ItemSet JSON (writable to Game/Config/...)."""
    v = build.variants[variant_index]
    blocks = []
    if v.items_start:
        blocks.append({"type": "Starting Items", "items": [{"id": str(i), "count": 1} for i in v.items_start]})
    if v.items_boots:
        blocks.append({"type": "Boots", "items": [{"id": str(i), "count": 1} for i in v.items_boots]})
    if v.items_core:
        blocks.append({"type": "Core", "items": [{"id": str(i), "count": 1} for i in v.items_core]})
    if v.items_situational:
        blocks.append({"type": "Situational", "items": [{"id": str(i), "count": 1} for i in v.items_situational]})
    return {
        "title": f"OP.GG {build.mode} {v.name}",
        "associatedMaps": [map_id],
        "associatedChampions": [],
        "blocks": blocks,
        "sortrank": 0,
        "type": "custom",
    }


def to_rune_page_payload(build: ChampionBuild, variant_index: int = 0, name: Optional[str] = None) -> Optional[dict]:
    v = build.variants[variant_index]
    if not v.rune_page:
        return None
    rp = v.rune_page
    return {
        "name": name or f"OPGG {build.champion}",
        "primaryStyleId": rp.primary_style_id,
        "subStyleId": rp.sub_style_id,
        "selectedPerkIds": rp.selected_perk_ids,
        "current": True,
    }


def variant_to_json(v: BuildVariant) -> str:
    return json.dumps(
        {
            "name": v.name,
            "items_start": v.items_start,
            "items_core": v.items_core,
            "items_boots": v.items_boots,
            "items_situational": v.items_situational,
            "summoner_spells": v.summoner_spells,
            "rune_page": None
            if v.rune_page is None
            else {
                "primary": v.rune_page.primary_style_id,
                "sub": v.rune_page.sub_style_id,
                "perks": v.rune_page.selected_perk_ids,
            },
        },
        ensure_ascii=False,
        indent=2,
    )
