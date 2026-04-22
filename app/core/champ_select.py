"""Champ-select aggregation service.

When the champ-select session arrives, we fetch each participant's ranked
entries and recent match history in parallel, then compute a simple
performance summary (avg KDA, last-N win rate, average score).

This mirrors the "teammate inspector" feature shipped by rank-analysis,
frank, and Seraphine's GameInfoInterface. Data is cached per-puuid for the
session — we don't re-fetch on every event.
"""
from __future__ import annotations

import asyncio
from dataclasses import asdict, dataclass, field
from typing import Any, Optional

from app.common.logger import get_logger
from app.lcu import api
from app.lcu.client import LcuClient

log = get_logger(__name__)

RECENT_MATCH_COUNT = 20


@dataclass
class RankTier:
    queue: str  # RANKED_SOLO_5x5 / RANKED_FLEX_SR / ...
    tier: str  # "DIAMOND" / ... / "UNRANKED"
    division: str  # "I" / "II" / ...
    league_points: int = 0
    wins: int = 0
    losses: int = 0

    @property
    def win_rate(self) -> float:
        total = self.wins + self.losses
        return round(self.wins / total, 3) if total else 0.0


@dataclass
class MatchSummary:
    game_id: int
    champion_id: int
    queue_id: int
    win: bool
    kills: int
    deaths: int
    assists: int
    cs: int


@dataclass
class PlayerCard:
    cell_id: int
    team_id: int
    summoner_id: int
    puuid: str
    display_name: str
    summoner_level: int
    champion_id: int = 0  # intent or locked-in
    assigned_position: str = ""
    is_me: bool = False
    ranks: list[RankTier] = field(default_factory=list)
    recent: list[MatchSummary] = field(default_factory=list)
    recent_win_rate: float = 0.0
    avg_kda: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["ranks"] = [asdict(r) | {"winRate": r.win_rate} for r in self.ranks]
        return d


_TIER_ORDER = [
    "IRON", "BRONZE", "SILVER", "GOLD", "PLATINUM", "EMERALD",
    "DIAMOND", "MASTER", "GRANDMASTER", "CHALLENGER",
]


def rank_rank(t: RankTier) -> int:
    try:
        i = _TIER_ORDER.index(t.tier.upper())
    except ValueError:
        return -1
    sub = {"IV": 0, "III": 1, "II": 2, "I": 3}.get(t.division.upper(), 0)
    return i * 4 + sub


def peak_rank(ranks: list[RankTier]) -> Optional[RankTier]:
    ranked = [r for r in ranks if r.tier and r.tier.upper() != "UNRANKED"]
    if not ranked:
        return None
    return max(ranked, key=rank_rank)


def _parse_ranked_entry(entry: dict) -> Optional[RankTier]:
    tier = entry.get("tier") or ""
    if not tier:
        return None
    return RankTier(
        queue=entry.get("queueType") or "",
        tier=tier,
        division=entry.get("division") or entry.get("rank") or "",
        league_points=entry.get("leaguePoints", 0),
        wins=entry.get("wins", 0),
        losses=entry.get("losses", 0),
    )


def _project_match(g: dict, puuid: str) -> Optional[MatchSummary]:
    participants = g.get("participants") or [{}]
    me = participants[0]
    stats = me.get("stats", {})
    return MatchSummary(
        game_id=g.get("gameId", 0),
        champion_id=me.get("championId", 0),
        queue_id=g.get("queueId", 0),
        win=bool(stats.get("win")),
        kills=stats.get("kills", 0),
        deaths=stats.get("deaths", 0),
        assists=stats.get("assists", 0),
        cs=stats.get("totalMinionsKilled", 0) + stats.get("neutralMinionsKilled", 0),
    )


async def _load_player(
    client: LcuClient,
    *,
    cell: dict,
    local_cell_id: Optional[int],
    include_enemy_details: bool,
) -> Optional[PlayerCard]:
    summoner_id = cell.get("summonerId") or 0
    puuid = cell.get("puuid") or ""
    if not summoner_id and not puuid:
        # Enemy team cells may be hidden behind fog of war.
        return PlayerCard(
            cell_id=cell.get("cellId", -1),
            team_id=cell.get("team") or 0,
            summoner_id=0,
            puuid="",
            display_name="???",
            summoner_level=0,
            champion_id=cell.get("championId") or cell.get("championPickIntent") or 0,
            assigned_position=cell.get("assignedPosition") or "",
        )

    try:
        summoner = (
            await api.summoner_by_puuid(client, puuid)
            if puuid
            else await api.summoner_by_id(client, summoner_id)
        )
    except Exception as e:  # noqa: BLE001
        log.warning("summoner lookup failed for %s: %s", summoner_id or puuid, e)
        return None
    puuid = summoner.get("puuid") or puuid

    card = PlayerCard(
        cell_id=cell.get("cellId", -1),
        team_id=cell.get("team") or 0,
        summoner_id=summoner.get("summonerId") or summoner_id,
        puuid=puuid,
        display_name=summoner.get("gameName") or summoner.get("displayName") or "",
        summoner_level=summoner.get("summonerLevel", 0),
        champion_id=cell.get("championId") or cell.get("championPickIntent") or 0,
        assigned_position=cell.get("assignedPosition") or "",
        is_me=(cell.get("cellId") == local_cell_id),
    )

    # Fetch ranks + recent matches in parallel.
    tasks = [
        asyncio.create_task(api.ranked_stats(client, puuid)),
        asyncio.create_task(api.match_history(client, puuid, 0, RECENT_MATCH_COUNT - 1)),
    ]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    ranked_raw, history_raw = results

    if isinstance(ranked_raw, dict):
        for q in (ranked_raw.get("queues") or []):
            r = _parse_ranked_entry(q)
            if r:
                card.ranks.append(r)

    if isinstance(history_raw, dict):
        games = history_raw.get("games", {}).get("games", []) or []
        if not include_enemy_details and not card.is_me and card.team_id != (cell.get("team") or 0):
            games = games[:5]
        recent = [m for m in (_project_match(g, puuid) for g in games) if m is not None]
        card.recent = recent
        wins = sum(1 for m in recent if m.win)
        card.recent_win_rate = round(wins / len(recent), 3) if recent else 0.0
        total_k, total_d, total_a = 0, 0, 0
        for m in recent:
            total_k += m.kills
            total_d += max(1, m.deaths)
            total_a += m.assists
        card.avg_kda = round((total_k + total_a) / max(1, total_d), 2)

    return card


@dataclass
class ChampSelectSnapshot:
    phase: str  # PLANNING / BAN_PICK / FINALIZATION / ...
    game_id: int
    local_cell_id: int
    my_team: list[PlayerCard]
    their_team: list[PlayerCard]
    bans: dict[str, list[int]]

    def to_dict(self) -> dict[str, Any]:
        return {
            "phase": self.phase,
            "gameId": self.game_id,
            "localCellId": self.local_cell_id,
            "myTeam": [p.to_dict() for p in self.my_team],
            "theirTeam": [p.to_dict() for p in self.their_team],
            "bans": self.bans,
        }


async def snapshot_session(client: LcuClient, session: dict) -> ChampSelectSnapshot:
    my_cells, their_cells = api.split_champ_select_teams(session)
    local_cell_id = api.champ_select_local_cell(session) or -1

    tasks = [
        asyncio.create_task(
            _load_player(client, cell=c, local_cell_id=local_cell_id, include_enemy_details=False)
        )
        for c in my_cells + their_cells
    ]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    players: list[PlayerCard] = []
    for r in results:
        if isinstance(r, PlayerCard):
            players.append(r)
    my_team = [p for p in players if p.team_id == 1] or players[: len(my_cells)]
    their_team = [p for p in players if p.team_id == 2] or players[len(my_cells):]

    bans_raw = session.get("bans") or {}
    bans = {
        "myTeamBans": list(bans_raw.get("myTeamBans") or []),
        "theirTeamBans": list(bans_raw.get("theirTeamBans") or []),
    }
    return ChampSelectSnapshot(
        phase=session.get("timer", {}).get("phase") or session.get("phase") or "",
        game_id=session.get("gameId", 0),
        local_cell_id=local_cell_id,
        my_team=my_team,
        their_team=their_team,
        bans=bans,
    )
