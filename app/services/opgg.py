"""OP.GG scraper — champion builds for ranked and alt modes.

OP.GG renders pages server-side with React Server Components; the data is
embedded in `self.__next_f.push([1, "..."])` payloads. We fetch the HTML,
extract the RSC stream, and parse out item sets, rune pages, skill order,
and summoner spells.

The 2026-05 site format dropped the dual "Most Popular / Highest Win Rate"
JSON blobs in favor of pre-rendered component trees that reference items via
`{"metaType":"item","metaId":<id>}` markers, grouped under captioned section
headers ("Starter Items", "Boots Table", "Core Builds", "Fourth/Fifth/Sixth
Item"). Runes still arrive as a `rune_pages` JSON object on the /runes page.

This is a best-effort scraper — OP.GG's layout changes every few months.
Fall back to a clear error when we can't find expected markers, rather
than returning garbage.
"""
from __future__ import annotations

import asyncio
import json
import re
from dataclasses import dataclass, field
from typing import Any, Optional

import httpx

from app.common.logger import get_logger

log = get_logger(__name__)

BASE_URL = "https://op.gg"
RANKED_BUILD_PATH = "/lol/champions/{champ}/build"
RANKED_RUNES_PATH = "/lol/champions/{champ}/runes"
MODE_BUILD_PATH = "/lol/modes/{mode}/{champ}/build"

DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
}

_RSC_RE = re.compile(r'self\.__next_f\.push\(\[1,"((?:\\.|[^"\\])*)"\]\)', re.DOTALL)
# OP.GG renders metaId/metaType in either order depending on the component:
# item refs are `"metaType":"item","metaId":N`, spell refs in the
# SummonerSpells table are `"metaId":N,"metaType":"spell"`.
_META_RE = re.compile(
    r'"metaType":"(item|spell)","metaId":(\d+)'
    r'|"metaId":(\d+),"metaType":"(item|spell)"'
)
# Each rendered row in the build page carries a stable key like
# `"$","tr","starter_items_0"` — first row = most popular. We slice by row
# rather than by section header because section headers are siblings of
# multiple inner tables.
_ROW_KEY_RE = re.compile(r'"\$","tr","([a-z_0-9]+)_(\d+)"')
# Count badge: when a row reuses an item (e.g. 2× health potion), a small
# badge `{"children":N}` is rendered after the item. Capturing it lets us
# emit the right number of copies.
_BADGE_RE = re.compile(r'"children":(\d{1,2})\s*\}\s*\]\s*\]\s*\}')


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
        build_url = BASE_URL + RANKED_BUILD_PATH.format(champ=slug)
        runes_url = BASE_URL + RANKED_RUNES_PATH.format(champ=slug)
        params: dict[str, str] = {"region": region, "tier": tier}
        if position:
            params["position"] = position
    else:
        build_url = BASE_URL + MODE_BUILD_PATH.format(mode=mode, champ=slug)
        runes_url = ""  # alt modes embed runes (if any) directly in /build
        params = {}

    async with httpx.AsyncClient(headers=DEFAULT_HEADERS, follow_redirects=True, timeout=timeout) as c:
        build_task = c.get(build_url, params=params)
        runes_task = c.get(runes_url, params=params) if runes_url else None
        if runes_task is not None:
            build_resp, runes_resp = await asyncio.gather(build_task, runes_task)
        else:
            build_resp = await build_task
            runes_resp = None
        if build_resp.status_code != 200:
            raise OpggError(f"op.gg {build_resp.status_code} for {build_url}")
        build_blob = _extract_blob(build_resp.text)
        runes_blob = _extract_blob(runes_resp.text) if runes_resp and runes_resp.status_code == 200 else build_blob

    variant = _parse_build_blob(build_blob)
    rune_page = _parse_rune_page(runes_blob)
    if rune_page:
        variant.rune_page = rune_page

    patch = _scan_patch(build_blob) or _scan_patch(runes_blob)
    variants = [variant] if _variant_has_content(variant) else []
    if not variants:
        log.warning("op.gg: no variants parsed for %s/%s — site format may have changed", champion, mode)
    build = ChampionBuild(
        champion=champion,
        mode=mode,
        position=position,
        tier=tier,
        patch=patch,
        variants=variants,
    )
    return build


def _extract_blob(html: str) -> str:
    chunks = []
    for m in _RSC_RE.finditer(html):
        raw = m.group(1)
        try:
            decoded = bytes(raw, "utf-8").decode("unicode_escape")
        except UnicodeDecodeError:
            decoded = raw
        chunks.append(decoded)
    return "".join(chunks)


def _extract_rsc_chunks(html: str) -> list[str]:
    """Back-compat helper used by integration scripts."""
    return [_extract_blob(html)] if html else []


def _scan_patch(blob: str) -> Optional[str]:
    if not blob:
        return None
    m = re.search(r'/meta/images/lol/(\d+\.\d+)(?:\.\d+)?/', blob)
    if m:
        return m.group(1)
    m = re.search(r'"version"\s*:\s*"([^"]+)"', blob)
    if m:
        return m.group(1)
    m = re.search(r'"patch"\s*:\s*"([^"]+)"', blob)
    return m.group(1) if m else None


def _variant_has_content(v: BuildVariant) -> bool:
    return bool(
        v.items_core
        or v.items_boots
        or v.items_start
        or v.items_situational
        or v.summoner_spells
        or v.rune_page
    )


def _parse_build_blob(blob: str) -> BuildVariant:
    """Parse the /build page blob into a single Most-Popular variant.

    OP.GG embeds rendered React rows keyed by stable strings like
    `starter_items_0`, `boots_0`, `core_items_0`, `depth_4_item_0`,
    `depth_5_item_0`, `depth_6_item_0`. The `_0` row is the most popular for
    each section. We slice the blob by row boundaries and read item/spell
    refs from row 0 of each section. Duplicate items are surfaced via
    `{"children":N}` count badges which we expand.
    """
    variant = BuildVariant(name="Most Popular")
    if not blob:
        return variant

    rows = _split_rows(blob)
    if not rows:
        return variant

    # Pick the FIRST row from each section. OP.GG sorts rows by pick rate.
    starter_row = _first_row(rows, "starter_items")
    boots_row = _first_row(rows, "boots")
    core_row = _first_row(rows, "core_items")
    fourth_row = _first_row(rows, "depth_4_item")
    fifth_row = _first_row(rows, "depth_5_item")
    sixth_row = _first_row(rows, "depth_6_item")

    variant.items_start = _row_items(blob, starter_row)
    variant.items_boots = _row_items(blob, boots_row)[:1]
    variant.items_core = _row_items(blob, core_row)
    situational: list[int] = []
    seen: set[int] = set()
    for slot in (fourth_row, fifth_row, sixth_row):
        for item in _row_items(blob, slot):
            if item not in seen:
                seen.add(item)
                situational.append(item)
                break
    variant.items_situational = situational
    variant.summoner_spells = _top_spell_pair(blob)
    variant.skill_order = _parse_skill_order(blob)
    return variant


def _split_rows(blob: str) -> list[tuple[str, int, int, int]]:
    """Return [(section_name, row_index, start_offset, end_offset), ...]."""
    matches = list(_ROW_KEY_RE.finditer(blob))
    rows: list[tuple[str, int, int, int]] = []
    for i, m in enumerate(matches):
        start = m.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(blob)
        try:
            idx = int(m.group(2))
        except ValueError:
            continue
        rows.append((m.group(1), idx, start, end))
    return rows


def _first_row(rows: list[tuple[str, int, int, int]], section: str) -> Optional[tuple[int, int]]:
    best: Optional[tuple[str, int, int, int]] = None
    for row in rows:
        if row[0] != section:
            continue
        if best is None or row[1] < best[1]:
            best = row
    if best is None:
        return None
    return best[2], best[3]


def _row_items(blob: str, span: Optional[tuple[int, int]]) -> list[int]:
    """Extract item IDs from a row, expanding count badges where present."""
    if span is None:
        return []
    start, end = span
    segment = blob[start:end]
    out: list[int] = []
    for m in _META_RE.finditer(segment):
        kind = m.group(1) or m.group(4)
        if kind != "item":
            continue
        item_id = int(m.group(2) or m.group(3))
        # Look for a count badge in the next ~400 chars (the badge follows
        # the item ref inside the same wrapper div).
        tail = segment[m.end(): m.end() + 400]
        # Stop scanning at the next item ref so we don't grab a neighbour's
        # badge.
        next_ref = _META_RE.search(tail)
        scope = tail[: next_ref.start()] if next_ref else tail
        badge = _BADGE_RE.search(scope)
        count = int(badge.group(1)) if badge else 1
        # Sanity: badges are 2–6 for stacked consumables; anything larger is
        # almost certainly a pick-rate value we matched by accident.
        if count < 1 or count > 6:
            count = 1
        out.extend([item_id] * count)
    return out


def _top_spell_pair(blob: str) -> list[int]:
    """Find the first SummonerSpells table and return its top spell pair."""
    idx = blob.find('"caption",null,{"children":"SummonerSpells Table"}')
    if idx < 0:
        return []
    end = blob.find('"caption"', idx + 50)
    if end < 0:
        end = idx + 4000
    segment = blob[idx:end]
    spells: list[int] = []
    for m in _META_RE.finditer(segment):
        kind = m.group(1) or m.group(4)
        if kind != "spell":
            continue
        spells.append(int(m.group(2) or m.group(3)))
        if len(spells) >= 2:
            break
    return spells


def _parse_skill_order(blob: str) -> list[str]:
    """Best-effort: pull out the first `order` array from a skill_masteries
    block, if the build/skills page embedded one."""
    if "skill_masteries" not in blob and "skill_orders" not in blob:
        return []
    m = re.search(r'"order":\[((?:"[QWER]",?\s*)+)\]', blob)
    if not m:
        return []
    return re.findall(r'"([QWER])"', m.group(1))


def _parse_rune_page(blob: str) -> Optional[RunePage]:
    """Parse rune_pages[0].builds[0] into a RunePage by finding the active
    perks in each row of main_runes/sub_runes."""
    if not blob:
        return None
    idx = blob.find('"rune_pages":[')
    if idx < 0:
        return None

    # Primary + sub style id (first occurrence inside the rune_pages block).
    primary = _first_int_after(blob, idx, r'"primary_perk_style":\{"id":(\d+)')
    sub = _first_int_after(blob, idx, r'"perk_sub_style":\{"id":(\d+)')
    if primary is None or sub is None:
        return None

    # The first builds[] entry runs from after primary_perk_style to the
    # closing of its `shards` array. Stay inside that window so we don't
    # accidentally grab perks from a later (less popular) rune build.
    build_start = blob.find('"primary_perk_style"', idx)
    build_end = blob.find('"shards"', build_start)
    if build_end < 0:
        build_end = build_start + 6000
    # Extend a bit to capture the shards' own active entries.
    shard_end = blob.find(']]', build_end)
    if shard_end > 0:
        build_end = shard_end + 2
    window = blob[build_start:build_end]

    active_ids: list[int] = []
    for m in re.finditer(r'"id":(\d+)[^{}]*?"isActive":true', window):
        try:
            active_ids.append(int(m.group(1)))
        except ValueError:
            pass

    if not active_ids:
        return None
    return RunePage(primary_style_id=primary, sub_style_id=sub, selected_perk_ids=active_ids)


def _first_int_after(blob: str, start: int, pattern: str) -> Optional[int]:
    m = re.search(pattern, blob[start:])
    if not m:
        return None
    try:
        return int(m.group(1))
    except ValueError:
        return None


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
