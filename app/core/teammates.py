"""Recent teammate aggregation + pre-group (premade) detection.

Takes the most recent N matches and extracts the other participants you
played alongside. Aggregates appearances by puuid (same team only) to
surface who you queue with most.

Pre-group detection (borrowed from rank-analysis): for each pair of players
you're inspecting during champ select, if they appeared on the *same* team
in 3+ of their recent shared games, they're flagged as premade.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from typing import Iterable


@dataclass
class TeammateEntry:
    puuid: str
    summoner_id: int
    display_name: str
    profile_icon_id: int = 0
    summoner_level: int = 0
    games_together: int = 0
    wins_together: int = 0
    champion_ids_seen: list[int] = field(default_factory=list)

    @property
    def win_rate(self) -> float:
        return round(self.wins_together / self.games_together, 3) if self.games_together else 0.0

    def to_dict(self) -> dict:
        return {
            "puuid": self.puuid,
            "summonerId": self.summoner_id,
            "displayName": self.display_name,
            "profileIconId": self.profile_icon_id,
            "summonerLevel": self.summoner_level,
            "gamesTogether": self.games_together,
            "winsTogether": self.wins_together,
            "winRate": self.win_rate,
            "championIdsSeen": self.champion_ids_seen[:5],
        }


def aggregate_teammates(detailed_games: Iterable[dict], my_puuid: str) -> list[TeammateEntry]:
    """detailed_games must come from /lol-match-history/v1/games/{id} (full payload)."""
    buckets: dict[str, TeammateEntry] = {}
    for g in detailed_games:
        parts = g.get("participants") or []
        idents = g.get("participantIdentities") or []
        me = _find_me(parts, idents, my_puuid)
        if me is None:
            continue
        my_team = me.get("teamId")
        my_win = bool(me.get("stats", {}).get("win"))
        for p, ident in zip(parts, idents):
            pl = ident.get("player", {})
            puuid = pl.get("puuid") or ""
            if not puuid or puuid == my_puuid:
                continue
            if p.get("teamId") != my_team:
                continue
            bucket = buckets.get(puuid)
            if bucket is None:
                bucket = TeammateEntry(
                    puuid=puuid,
                    summoner_id=pl.get("summonerId", 0),
                    display_name=pl.get("gameName") or pl.get("summonerName") or "",
                )
                buckets[puuid] = bucket
            bucket.games_together += 1
            if my_win:
                bucket.wins_together += 1
            bucket.champion_ids_seen.append(p.get("championId") or 0)
    return sorted(buckets.values(), key=lambda t: t.games_together, reverse=True)


def _find_me(parts: list[dict], idents: list[dict], my_puuid: str) -> dict | None:
    for p, ident in zip(parts, idents):
        if (ident.get("player") or {}).get("puuid") == my_puuid:
            return p
    return None


# ----- pre-group detection -----

@dataclass
class PreGroup:
    puuids: list[str]
    games_same_team: int
    color: str  # visual tag suggestion

_COLORS = ("#e06c75", "#e5c07b", "#98c379", "#61afef", "#c678dd", "#56b6c2")


def detect_pregroups(
    players: list[dict],
    *,
    threshold: int = 3,
) -> list[PreGroup]:
    """Given a list of player cards whose `recent` contain shared opponents,
    find subsets of 2+ players who appear together on the same team >= threshold times.

    Expects each player dict to have:
      * puuid
      * recent  -> list of {gameId, win, teamId?}  -- teamId stamped externally

    Runs a pairwise pass: O(N² × G).
    """
    index: dict[tuple[str, int], int] = {}
    for p in players:
        for m in p.get("recent") or []:
            key = (p["puuid"], m.get("gameId", 0))
            index[key] = m.get("teamId", 0)

    pair_counts: dict[tuple[str, str], int] = defaultdict(int)
    for i, a in enumerate(players):
        for b in players[i + 1:]:
            shared = 0
            a_games = {(m.get("gameId", 0)): index.get((a["puuid"], m.get("gameId", 0)), 0)
                       for m in a.get("recent") or []}
            for m in b.get("recent") or []:
                gid = m.get("gameId", 0)
                if gid in a_games and a_games[gid] == index.get((b["puuid"], gid), -1):
                    shared += 1
            if shared >= threshold:
                pair_counts[(a["puuid"], b["puuid"])] = shared

    # Greedy transitive grouping.
    groups: list[set[str]] = []
    for (p1, p2), _ in pair_counts.items():
        placed = False
        for g in groups:
            if p1 in g or p2 in g:
                g.update({p1, p2})
                placed = True
                break
        if not placed:
            groups.append({p1, p2})

    color_iter = iter(_COLORS)
    out: list[PreGroup] = []
    for g in groups:
        color = next(color_iter, _COLORS[-1])
        # Best pair count for display; take max shared across pairs in group.
        best = max(
            (shared for (a, b), shared in pair_counts.items() if a in g and b in g),
            default=0,
        )
        out.append(PreGroup(puuids=sorted(g), games_same_team=best, color=color))
    return out
