"""Auto-action state machine.

Subscribes to LCU events and triggers:
  * Auto-accept ready check.
  * Auto-ban the first available champion from a configured priority list,
    in champ select ban phase.
  * Auto-pick similarly during pick phase.

Guarantees:
  * Each action runs at most once per session (tracked by session id + phase).
  * Bans never hit a teammate's intent or an already-banned champion.
  * Failure to act is logged, never raises.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Optional

from app.common.logger import get_logger
from app.lcu import api
from app.lcu.client import LcuClient
from app.lcu.events import LcuEvent, LcuEventStream

log = get_logger(__name__)

Notifier = Callable[[str, str], None]


@dataclass
class AutoActionsConfig:
    auto_accept: bool = False
    auto_ban: bool = False
    auto_pick: bool = False
    ban_priority: list[int] = field(default_factory=list)
    pick_priority: list[int] = field(default_factory=list)


class AutoActions:
    def __init__(
        self,
        client: LcuClient,
        events: LcuEventStream,
        notifier: Optional[Notifier] = None,
    ) -> None:
        self._client = client
        self._events = events
        self._notifier = notifier
        self.config = AutoActionsConfig()
        self.paused = False
        self._acted_banned = False
        self._acted_picked = False
        self._last_session_id: Optional[int] = None

        events.subscribe(api.EVENT_MATCHMAKING_READY_CHECK, self._on_ready_check)
        events.subscribe(api.EVENT_CHAMP_SELECT, self._on_champ_select)

    def _notify(self, title: str, body: str) -> None:
        if self._notifier:
            try:
                self._notifier(title, body)
            except Exception:  # noqa: BLE001
                pass

    # ----- ready check -----

    async def _on_ready_check(self, ev: LcuEvent) -> None:
        if self.paused or not self.config.auto_accept:
            return
        data = ev.data
        if not isinstance(data, dict):
            return
        if data.get("state") != "InProgress":
            return
        if data.get("playerResponse") in ("Accepted", "Declined"):
            return
        try:
            await api.ready_check_accept(self._client)
            log.info("auto-accepted ready check")
            self._notify("自动接受", "已自动接受对局")
        except Exception as e:  # noqa: BLE001
            log.warning("auto-accept failed: %s", e)
            self._notify("自动接受失败", str(e))

    # ----- champ select -----

    async def _on_champ_select(self, ev: LcuEvent) -> None:
        data = ev.data
        if not isinstance(data, dict):
            return
        if ev.event_type == "Delete":
            self._reset_session()
            return
        if self.paused:
            return
        session_id = data.get("gameId")
        if session_id != self._last_session_id:
            self._reset_session()
            self._last_session_id = session_id

        me_id = data.get("localPlayerCellId")
        actions = data.get("actions") or []
        bans = data.get("bans") or {}
        banned_ids = set(
            (bans.get("myTeamBans") or []) + (bans.get("theirTeamBans") or [])
        )
        teammate_intents = {
            p.get("championPickIntent")
            for p in (data.get("myTeam") or [])
            if p.get("cellId") != me_id and p.get("championPickIntent")
        }

        for group in actions:
            for action in group:
                if action.get("actorCellId") != me_id:
                    continue
                if action.get("isInProgress") is not True:
                    continue
                if action.get("completed"):
                    continue
                atype = action.get("type")
                if atype == "ban" and self.config.auto_ban and not self._acted_banned:
                    await self._lock_first_available(
                        action["id"],
                        self.config.ban_priority,
                        banned_ids | teammate_intents,
                        kind="禁用",
                    )
                    self._acted_banned = True
                elif atype == "pick" and self.config.auto_pick and not self._acted_picked:
                    await self._lock_first_available(
                        action["id"],
                        self.config.pick_priority,
                        banned_ids,
                        kind="选择",
                    )
                    self._acted_picked = True

    async def _lock_first_available(
        self,
        action_id: int,
        priority: list[int],
        forbidden: set[int],
        *,
        kind: str,
    ) -> None:
        candidates = [cid for cid in priority if cid not in forbidden]
        if not candidates:
            log.info("auto-action: no candidate usable (all banned/picked)")
            self._notify(f"自动{kind}", "优先级列表里的英雄都已被禁用或选走")
            return
        champion_id = candidates[0]
        try:
            await api.champ_select_patch_action(
                self._client, action_id, champion_id=champion_id, completed=True
            )
            log.info("auto-locked champion %s via action %s", champion_id, action_id)
            self._notify(f"自动{kind}", f"已{kind}英雄 #{champion_id}")
        except Exception as e:  # noqa: BLE001
            log.warning("auto-action lock failed: %s", e)
            self._notify(f"自动{kind}失败", str(e))

    def _reset_session(self) -> None:
        self._acted_banned = False
        self._acted_picked = False
