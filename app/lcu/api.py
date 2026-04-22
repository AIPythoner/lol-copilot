"""High-level LCU endpoint wrappers.

Grouped by domain; each function is a thin convenience around LcuClient.
Return shapes are Riot JSON — we pass through, consumers handle projection.

Endpoints compiled from the reference projects (Seraphine, frank, rank-analysis).
"""
from __future__ import annotations

from typing import Any

from app.lcu.client import LcuClient


# ---------- summoner ----------

async def current_summoner(c: LcuClient) -> dict:
    return await c.get("/lol-summoner/v1/current-summoner")


async def summoner_by_id(c: LcuClient, summoner_id: int) -> dict:
    return await c.get(f"/lol-summoner/v1/summoners/{summoner_id}")


async def summoner_by_puuid(c: LcuClient, puuid: str) -> dict:
    return await c.get(f"/lol-summoner/v2/summoners/puuid/{puuid}")


async def summoner_by_name(c: LcuClient, name: str) -> dict:
    return await c.get("/lol-summoner/v1/summoners", params={"name": name})


async def summoners_by_puuids(c: LcuClient, puuids: list[str]) -> list[dict]:
    if not puuids:
        return []
    return await c.get("/lol-summoner/v2/summoners", params={"puuids": puuids})


# ---------- ranked ----------

async def ranked_stats(c: LcuClient, puuid: str) -> dict:
    return await c.get(f"/lol-ranked/v1/ranked-stats/{puuid}")


async def my_ranked_stats(c: LcuClient) -> dict:
    return await c.get("/lol-ranked/v1/current-ranked-stats")


# ---------- match history ----------

async def match_history(c: LcuClient, puuid: str, begin: int = 0, end: int = 19) -> dict:
    return await c.get(
        f"/lol-match-history/v1/products/lol/{puuid}/matches",
        params={"begIndex": begin, "endIndex": end},
    )


async def game_detail(c: LcuClient, game_id: int) -> dict:
    return await c.get(f"/lol-match-history/v1/games/{game_id}")


# ---------- gameflow ----------

async def gameflow_phase(c: LcuClient) -> str:
    return await c.get("/lol-gameflow/v1/gameflow-phase")


async def gameflow_session(c: LcuClient) -> dict:
    return await c.get("/lol-gameflow/v1/session")


# ---------- matchmaking / ready-check ----------

async def ready_check_accept(c: LcuClient) -> None:
    await c.post("/lol-matchmaking/v1/ready-check/accept")


async def ready_check_decline(c: LcuClient) -> None:
    await c.post("/lol-matchmaking/v1/ready-check/decline")


# ---------- lobby ----------

async def get_lobby(c: LcuClient) -> dict:
    return await c.get("/lol-lobby/v2/lobby")


async def dodge_lobby(c: LcuClient) -> None:
    await c.post("/lol-lobby/v2/lobby/custom/dodge")


# ---------- champ select ----------

async def champ_select_session(c: LcuClient) -> dict:
    return await c.get("/lol-champ-select/v1/session")


async def champ_select_my_selection(c: LcuClient) -> dict:
    return await c.get("/lol-champ-select/v1/current-champion")


async def champ_select_pickable(c: LcuClient) -> list[int]:
    return await c.get("/lol-champ-select/v1/pickable-champion-ids")


async def champ_select_bannable(c: LcuClient) -> list[int]:
    return await c.get("/lol-champ-select/v1/bannable-champion-ids")


async def champ_select_patch_action(
    c: LcuClient, action_id: int, *, champion_id: int, completed: bool = False
) -> None:
    await c.patch(
        f"/lol-champ-select/v1/session/actions/{action_id}",
        json={"championId": champion_id, "completed": completed},
    )


# ---------- game data ----------

async def game_data_champions(c: LcuClient) -> list[dict]:
    return await c.get("/lol-game-data/assets/v1/champion-summary.json")


async def game_data_items(c: LcuClient) -> list[dict]:
    return await c.get("/lol-game-data/assets/v1/items.json")


async def game_data_runes(c: LcuClient) -> list[dict]:
    return await c.get("/lol-game-data/assets/v1/perks.json")


async def game_data_rune_styles(c: LcuClient) -> dict:
    return await c.get("/lol-game-data/assets/v1/perkstyles.json")


async def game_data_summoner_spells(c: LcuClient) -> list[dict]:
    return await c.get("/lol-game-data/assets/v1/summoner-spells.json")


async def game_data_queues(c: LcuClient) -> list[dict]:
    return await c.get("/lol-game-data/assets/v1/queues.json")


async def game_data_cherry_augments(c: LcuClient) -> list[dict]:
    """Arena / 斗魂竞技场 augments (海克斯强化)."""
    return await c.get("/lol-game-data/assets/v1/cherry-augments.json")


# ---------- champion mastery ----------

async def champion_mastery(c: LcuClient, puuid: str) -> list[dict]:
    return await c.get(f"/lol-champion-mastery/v1/{puuid}/champion-mastery")


# ---------- perks (rune pages) ----------

async def list_rune_pages(c: LcuClient) -> list[dict]:
    return await c.get("/lol-perks/v1/pages")


async def current_rune_page(c: LcuClient) -> dict:
    return await c.get("/lol-perks/v1/currentpage")


async def create_rune_page(c: LcuClient, page: dict) -> dict:
    return await c.post("/lol-perks/v1/pages", json=page)


async def delete_rune_page(c: LcuClient, page_id: int) -> None:
    await c.delete(f"/lol-perks/v1/pages/{page_id}")


# ---------- chat presence ----------

async def my_presence(c: LcuClient) -> dict:
    return await c.get("/lol-chat/v1/me")


async def set_presence(c: LcuClient, *, availability: str | None = None, status_message: str | None = None) -> dict:
    body: dict[str, Any] = {}
    if availability is not None:
        body["availability"] = availability
    if status_message is not None:
        body["statusMessage"] = status_message
    return await c.put("/lol-chat/v1/me", json=body)


async def friends(c: LcuClient) -> list[dict]:
    return await c.get("/lol-chat/v1/friends")


# ---------- summoner search (Riot ID) ----------

async def summoner_by_riot_id(c: LcuClient, game_name: str, tag_line: str) -> dict:
    return await c.get(
        f"/lol-summoner/v1/summoners-by-name/{game_name}#{tag_line}"
    )


async def search_alias(c: LcuClient, query: str) -> dict:
    """Riot client's global alias lookup (works for name#tag and plain names)."""
    return await c.get("/player-account/aliases/v1/lookup", params={"query": query})


# ---------- lobby creation ----------

async def create_custom_lobby(
    c: LcuClient,
    *,
    queue_id: int,
    game_mode: str,
    map_id: int,
    lobby_name: str,
    password: str = "",
    team_size: int = 5,
    spectator_policy: str = "AllAllowed",
    mutator_id: int = 1,
) -> dict:
    """Create a custom / practice lobby.

    ``queue_id`` is **required** by ``LolLobbyLobbyChangeGameDto``; empty
    / missing → 400 INVALID_REQUEST. Common 腾讯区 ids:

    * ``3140`` PRACTICETOOL / mapId 11 → 单人训练模式
    * ``3100`` CLASSIC / mapId 11 → 5v5 召唤师峡谷自定义（征召）
    * ``3200`` ARAM / mapId 12 → 大乱斗自定义（征召）
    """
    body = {
        "queueId": queue_id,
        "customGameLobby": {
            "configuration": {
                "gameMode": game_mode,
                "gameMutator": "",
                "gameServerRegion": "",
                "mapId": map_id,
                "mutators": {"id": mutator_id},
                "spectatorPolicy": spectator_policy,
                "teamSize": team_size,
            },
            "lobbyName": lobby_name,
            "lobbyPassword": password,
        },
    }
    return await c.post("/lol-lobby/v2/lobby", json=body)


async def create_queue_lobby(c: LcuClient, queue_id: int) -> dict:
    """Create a matchmaking lobby for the given queueId (单双排 420 / 匹配 430 / …)."""
    return await c.post("/lol-lobby/v2/lobby", json={"queueId": queue_id})


# ---------- profile customization ----------

async def set_profile_icon(c: LcuClient, icon_id: int) -> dict:
    return await c.put(
        "/lol-summoner/v1/current-summoner/icon",
        json={"profileIconId": icon_id},
    )


async def current_regalia(c: LcuClient) -> dict:
    return await c.get("/lol-regalia/v2/current-summoner/regalia")


async def remove_prestige_crest(c: LcuClient) -> dict:
    ref = await current_regalia(c)
    banner = ref.get("preferredBannerType") if isinstance(ref, dict) else None
    body = {
        "preferredCrestType": "prestige",
        "preferredBannerType": banner,
        "selectedPrestigeCrest": 22,
    }
    return await c.put("/lol-regalia/v2/current-summoner/regalia", json=body)


# ---------- spectator ----------

async def spectate_summoner(c: LcuClient, puuid: str) -> None:
    await c.post(
        "/lol-spectator/v1/spectate/launch",
        json={
            "allowObserveMode": "ALL",
            "dropInSpectateGameId": "",
            "gameQueueType": "",
            "puuid": puuid,
        },
    )


async def spectator_status(c: LcuClient, summoner_id: int) -> dict:
    return await c.get(f"/lol-spectator/v1/spectate/config/{summoner_id}")


# ---------- profile customization (Seraphine features) ----------

async def set_status_message(c: LcuClient, message: str) -> dict:
    return await c.put("/lol-chat/v1/me", json={"statusMessage": message})


async def set_availability(c: LcuClient, availability: str) -> dict:
    """availability: 'chat' | 'away' | 'offline' | 'mobile' | 'dnd'"""
    return await c.put("/lol-chat/v1/me", json={"availability": availability})


async def set_background_skin(c: LcuClient, skin_id: int) -> dict:
    return await c.post(
        "/lol-summoner/v1/current-summoner/summoner-profile",
        json={"key": "backgroundSkinId", "value": skin_id},
    )


async def my_profile(c: LcuClient) -> dict:
    return await c.get("/lol-summoner/v1/current-summoner/summoner-profile")


# ---------- ranked history (season archives) ----------

async def ranked_highest_tier(c: LcuClient, puuid: str) -> dict:
    return await c.get(f"/lol-ranked/v1/ranked-stats/{puuid}/highest-ranked-entry")


async def ranked_signatures(c: LcuClient, puuid: str) -> dict:
    return await c.get(f"/lol-ranked/v1/signatures/{puuid}")


# ---------- champ-select helpers ----------

def split_champ_select_teams(session: dict) -> tuple[list[dict], list[dict]]:
    """Return (myTeam, theirTeam) from a champ-select session payload."""
    return list(session.get("myTeam") or []), list(session.get("theirTeam") or [])


def champ_select_local_cell(session: dict) -> int | None:
    return session.get("localPlayerCellId")


# ---------- event URIs (for LcuEventStream subscribe prefixes) ----------

EVENT_GAMEFLOW_PHASE = "/lol-gameflow/v1/gameflow-phase"
EVENT_GAMEFLOW_SESSION = "/lol-gameflow/v1/session"
EVENT_CHAMP_SELECT = "/lol-champ-select/v1/session"
EVENT_MATCHMAKING_READY_CHECK = "/lol-matchmaking/v1/ready-check"
EVENT_LOBBY = "/lol-lobby/v2/lobby"
EVENT_CURRENT_SUMMONER = "/lol-summoner/v1/current-summoner"
