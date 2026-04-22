"""CDragon asset URL builders.

LCU ``/lol-game-data/assets/...`` paths map 1-to-1 to public CDragon mirror
URLs with a lowercase rule. There are two roots:

* ``/lol-game-data/assets/v1/...``  →  ``plugins/rcp-be-lol-game-data/global/default/v1/...``
* ``/lol-game-data/assets/DATA|ASSETS/...``  →  ``game/data|assets/...``

Tier emblems and position icons live in other CDragon plugins — covered
by dedicated builders below.
"""
from __future__ import annotations

_CDRAGON_ROOT = "https://raw.communitydragon.org/latest"
_BE_LOL_GAME_DATA = f"{_CDRAGON_ROOT}/plugins/rcp-be-lol-game-data/global/default"
_FE_STATIC = f"{_CDRAGON_ROOT}/plugins/rcp-fe-lol-static-assets/global/default"
_FE_CHAMP_SELECT = f"{_CDRAGON_ROOT}/plugins/rcp-fe-lol-champ-select/global/default"
_GAME_ROOT = f"{_CDRAGON_ROOT}/game"

_LCU_PREFIX = "/lol-game-data/assets/"


def cdragon_url(lcu_icon_path: str) -> str:
    """Convert an LCU asset path to a public CDragon URL.

    Returns the input unchanged if it doesn't start with the expected prefix
    (so callers can pass absolute URLs through unchanged).
    """
    if not lcu_icon_path or not lcu_icon_path.startswith(_LCU_PREFIX):
        return lcu_icon_path
    rel = lcu_icon_path[len(_LCU_PREFIX):]
    if rel.lower().startswith("v1/"):
        return f"{_BE_LOL_GAME_DATA}/{rel.lower()}"
    return f"{_GAME_ROOT}/{rel.lower()}"


# ----- direct-id patterns (when iconPath isn't available) -----

def champion_icon(champion_id: int) -> str:
    return f"{_BE_LOL_GAME_DATA}/v1/champion-icons/{champion_id}.png"


def profile_icon(icon_id: int) -> str:
    return f"{_BE_LOL_GAME_DATA}/v1/profile-icons/{icon_id}.jpg"


# ----- tier emblems (ranked) -----

_TIER_ALIASES = {
    "UNRANKED": "unranked",
    "NONE": "unranked",
}


def tier_emblem(tier: str) -> str:
    key = _TIER_ALIASES.get(tier.upper(), tier.lower())
    return f"{_FE_STATIC}/images/ranked-emblem/emblem-{key}.png"


def tier_mini_crest(tier: str) -> str:
    key = _TIER_ALIASES.get(tier.upper(), tier.lower())
    return f"{_FE_STATIC}/images/ranked-mini-crests/{key}.png"


# ----- position icons (champ select SVGs) -----

_POSITION_ALIASES = {
    "TOP": "top",
    "JUNGLE": "jungle",
    "MID": "middle",
    "MIDDLE": "middle",
    "BOT": "bottom",
    "BOTTOM": "bottom",
    "ADC": "bottom",
    "SUPPORT": "utility",
    "UTILITY": "utility",
}


def position_icon(position: str) -> str | None:
    key = _POSITION_ALIASES.get(position.upper() if position else "")
    if not key:
        return None
    return f"{_FE_CHAMP_SELECT}/svg/position-{key}.svg"


# ----- queue labels (static Chinese override for popular queues) -----

QUEUE_LABELS_ZH: dict[int, str] = {
    420: "单双排",
    430: "匹配",
    440: "灵活组排",
    450: "大乱斗",
    700: "冠军杯",
    830: "人机 - 入门",
    840: "人机 - 一般",
    850: "人机 - 高级",
    900: "无限火力",
    1020: "终极魔典",
    1300: "极地大乱斗 - 极速",
    1400: "终极魔法师",
    1700: "斗魂竞技场",
    1900: "无限火力 (旋转)",
    2300: "极限闪击",
    2000: "新手教程 1",
    2010: "新手教程 2",
    2020: "新手教程 3",
}


def queue_label(queue_id: int, fallback: str = "") -> str:
    return QUEUE_LABELS_ZH.get(queue_id, fallback or str(queue_id))
