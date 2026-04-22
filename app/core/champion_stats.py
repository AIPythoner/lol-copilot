"""Aggregate a match list into per-champion stats.

Source is the summarised games returned by LCU /lol-match-history — each
game has exactly one participant (the summoner we're querying). We group
by championId and compute totals.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, asdict
from typing import Iterable


@dataclass
class ChampionStat:
    champion_id: int
    games: int = 0
    wins: int = 0
    losses: int = 0
    kills: int = 0
    deaths: int = 0
    assists: int = 0
    cs: int = 0
    gold: int = 0

    @property
    def win_rate(self) -> float:
        return round(self.wins / self.games, 3) if self.games else 0.0

    @property
    def kda(self) -> float:
        return round((self.kills + self.assists) / max(1, self.deaths), 2)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["winRate"] = self.win_rate
        d["kda"] = self.kda
        d["avgKills"] = round(self.kills / max(1, self.games), 1)
        d["avgDeaths"] = round(self.deaths / max(1, self.games), 1)
        d["avgAssists"] = round(self.assists / max(1, self.games), 1)
        d["avgCs"] = round(self.cs / max(1, self.games), 0)
        return d


def aggregate(games: Iterable[dict]) -> list[ChampionStat]:
    buckets: dict[int, ChampionStat] = defaultdict(lambda: ChampionStat(0))
    for g in games:
        participants = g.get("participants") or []
        if not participants:
            continue
        p = participants[0]
        stats = p.get("stats") or {}
        champ_id = p.get("championId") or 0
        bucket = buckets[champ_id]
        bucket.champion_id = champ_id
        bucket.games += 1
        if stats.get("win"):
            bucket.wins += 1
        else:
            bucket.losses += 1
        bucket.kills += stats.get("kills", 0)
        bucket.deaths += stats.get("deaths", 0)
        bucket.assists += stats.get("assists", 0)
        bucket.cs += stats.get("totalMinionsKilled", 0) + stats.get("neutralMinionsKilled", 0)
        bucket.gold += stats.get("goldEarned", 0)
    return sorted(buckets.values(), key=lambda s: (s.games, s.wins), reverse=True)
