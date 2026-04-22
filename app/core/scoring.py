"""Match performance scoring.

Inspired by frank's per-game stat scoring: combines KDA, damage share, CS,
gold, and vision into a 0–100 score, with an MVP/ACE tag for the top/bottom
player on each team.

The raw scores are tuned to feel reasonable on ranked 5v5; tweak weights
as calibration improves.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable


@dataclass(frozen=True)
class ParticipantScore:
    participant_id: int
    team_id: int
    score: float
    win: bool
    tags: tuple[str, ...]


def _safe_ratio(num: float, denom: float) -> float:
    return num / denom if denom else 0.0


def _score_participant(p: dict, team_total_kills: int, team_total_damage: int) -> float:
    stats = p.get("stats", {})
    kills = stats.get("kills", 0)
    deaths = stats.get("deaths", 0)
    assists = stats.get("assists", 0)
    damage = stats.get("totalDamageDealtToChampions", 0)
    cs = stats.get("totalMinionsKilled", 0) + stats.get("neutralMinionsKilled", 0)
    gold = stats.get("goldEarned", 0)
    vision = stats.get("visionScore", 0)

    kda = (kills + assists) / max(1, deaths)
    kill_part = _safe_ratio(kills + assists, max(1, team_total_kills))
    dmg_part = _safe_ratio(damage, max(1, team_total_damage))

    # Weighted mix. KDA/kill-participation dominate, damage/CS/gold/vision shape edges.
    score = (
        kda * 6.0
        + kill_part * 30.0
        + dmg_part * 30.0
        + min(cs, 300) * 0.04
        + min(gold, 25000) * 0.0005
        + min(vision, 100) * 0.1
    )
    return round(min(100.0, max(0.0, score)), 2)


def score_game(game: dict) -> list[ParticipantScore]:
    """Return a score per participant for a /lol-match-history/v1/games/{id} payload."""
    participants = game.get("participants") or []
    teams: dict[int, list[dict]] = {}
    for p in participants:
        teams.setdefault(p.get("teamId", 0), []).append(p)

    team_kills = {
        tid: sum((p.get("stats", {}).get("kills", 0)) for p in ps)
        for tid, ps in teams.items()
    }
    team_damage = {
        tid: sum((p.get("stats", {}).get("totalDamageDealtToChampions", 0)) for p in ps)
        for tid, ps in teams.items()
    }

    raw = []
    for p in participants:
        tid = p.get("teamId", 0)
        s = _score_participant(p, team_kills.get(tid, 0), team_damage.get(tid, 0))
        raw.append((p, s))

    # Tag MVP per winning team and ACE per losing team.
    tagged: list[ParticipantScore] = []
    for tid in teams:
        team_scores = [(p, s) for (p, s) in raw if p.get("teamId") == tid]
        team_scores.sort(key=lambda t: t[1], reverse=True)
        if not team_scores:
            continue
        won = bool(team_scores[0][0].get("stats", {}).get("win"))
        for idx, (p, s) in enumerate(team_scores):
            tags: list[str] = []
            if idx == 0:
                tags.append("MVP" if won else "ACE")
            tagged.append(
                ParticipantScore(
                    participant_id=p.get("participantId", 0),
                    team_id=tid,
                    score=s,
                    win=bool(p.get("stats", {}).get("win")),
                    tags=tuple(tags),
                )
            )
    return tagged


def average_score(scores: Iterable[float]) -> float:
    values = list(scores)
    if not values:
        return 0.0
    return round(sum(values) / len(values), 2)
