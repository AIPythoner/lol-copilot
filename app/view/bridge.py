"""QObject bridges exposed to QML.

LcuBridge owns the LCU stack (watcher, client, event stream) + persisted
settings, and re-emits state changes as Qt signals / properties.

Exposed to QML as context property `Lcu`. Read-only properties are camelCase;
slots are verbs. All long work is async — slots just kick tasks off.
"""
from __future__ import annotations

import asyncio
from typing import Any, Optional

from PySide6.QtCore import (
    Property,
    QObject,
    Signal,
    Slot,
)

from app.common.config_store import (
    AppSettings,
    load_settings,
    save_settings,
)
from app.common.logger import get_logger
from app.core.auto_actions import AutoActions, AutoActionsConfig
from app.core.champ_select import ChampSelectSnapshot, snapshot_session
from app.core.champion_stats import aggregate as aggregate_champions
from app.core.teammates import aggregate_teammates, detect_pregroups
from app.core import scoring
from app.lcu import api
from app.lcu.client import LcuClient, LcuError, NotConnectedError
from app.lcu.connector import ConnectorWatcher, LcuCredentials
from app.lcu.events import LcuEvent, LcuEventStream
from app.services import aram_buff, assets, opgg

log = get_logger(__name__)


class LcuBridge(QObject):
    connectedChanged = Signal()
    summonerChanged = Signal()
    phaseChanged = Signal()
    matchesChanged = Signal()
    matchesLoadingChanged = Signal()
    rankedChanged = Signal()
    champSelectChanged = Signal()
    matchDetailChanged = Signal()
    opggBuildChanged = Signal()
    championsChanged = Signal()
    gameDataChanged = Signal()
    championPoolChanged = Signal()
    teammatesChanged = Signal()
    searchResultChanged = Signal()
    aramBuffsChanged = Signal()
    inGameChanged = Signal()
    settingsChanged = Signal()
    errorOccurred = Signal(str)
    notify = Signal(str, str)  # title, body
    navigationRequested = Signal(str)  # relative qml path for pages/… nav.push

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._connected: bool = False
        self._summoner: dict[str, Any] = {}
        self._phase: str = ""
        self._matches: list[dict[str, Any]] = []
        self._matches_loading: bool = False
        self._matches_request_seq: int = 0
        self._ranked: dict[str, Any] = {}
        self._champ_select: dict[str, Any] = {}
        self._match_detail: dict[str, Any] = {}
        self._opgg_build: dict[str, Any] = {}
        self._champions: list[dict[str, Any]] = []
        self._champions_by_id: dict[str, Any] = {}
        self._items_by_id: dict[str, Any] = {}
        self._spells_by_id: dict[str, Any] = {}
        self._perks_by_id: dict[str, Any] = {}
        self._perk_styles_by_id: dict[str, Any] = {}
        self._queues_by_id: dict[str, Any] = {}
        self._augments_by_id: dict[str, Any] = {}
        self._match_detail_cache: dict[int, dict] = {}
        self._match_detail_order: list[int] = []
        self._winrate_sent_game_ids: set[int] = set()
        self._champion_pool: list[dict[str, Any]] = []
        self._teammates: list[dict[str, Any]] = []
        self._search_result: dict[str, Any] = {}
        self._aram_buffs: list[dict[str, Any]] = []
        self._in_game: dict[str, Any] = {}

        self._settings: AppSettings = load_settings()
        self._client = LcuClient()
        self._watcher = ConnectorWatcher()
        self._events = LcuEventStream()
        # Forward auto-action events into QML via the notify signal.
        self._auto = AutoActions(
            self._client,
            self._events,
            notifier=lambda title, body: self.notify.emit(title, body),
        )
        self._image_provider: Any = None  # set by app bootstrap
        self._apply_settings_to_auto()

        self._watcher.on_change(self._on_creds_change)
        self._events.subscribe(api.EVENT_GAMEFLOW_PHASE, self._on_phase_event)
        self._events.subscribe(api.EVENT_CURRENT_SUMMONER, self._on_summoner_event)
        self._events.subscribe(api.EVENT_CHAMP_SELECT, self._on_champ_select_event)

    # ----- lifecycle -----

    @staticmethod
    def _spawn(coro, *, name: str | None = None):
        """Schedule a coroutine on whichever asyncio loop is available.

        Slots fire from Qt signals regardless of whether the asyncio loop is
        already running (e.g. a QML binding evaluating before run_until_complete
        starts). asyncio.create_task strictly requires a running loop, so we
        fall back to `loop.create_task` on the current/new loop.
        """
        try:
            return asyncio.create_task(coro, name=name)
        except RuntimeError:
            loop = asyncio.get_event_loop()
            return loop.create_task(coro, name=name)

    def start(self) -> None:
        self._watcher.start()

    def set_image_provider(self, provider: Any) -> None:
        """Inject the QQuickImageProvider so we can refresh its LCU auth."""
        self._image_provider = provider

    async def shutdown(self) -> None:
        await self._watcher.stop()
        await self._events.stop()
        await self._client.close()

    # ----- properties -----

    @Property(bool, notify=connectedChanged)
    def connected(self) -> bool:  # type: ignore[override]
        return self._connected

    @Property("QVariant", notify=summonerChanged)
    def summoner(self) -> dict:  # type: ignore[override]
        return self._summoner

    @Property(str, notify=phaseChanged)
    def phase(self) -> str:  # type: ignore[override]
        return self._phase

    @Property("QVariant", notify=matchesChanged)
    def matches(self) -> list:  # type: ignore[override]
        return self._matches

    @Property(bool, notify=matchesLoadingChanged)
    def matchesLoading(self) -> bool:  # type: ignore[override]
        return self._matches_loading

    @Property("QVariant", notify=rankedChanged)
    def ranked(self) -> dict:  # type: ignore[override]
        return self._ranked

    @Property("QVariant", notify=champSelectChanged)
    def champSelect(self) -> dict:  # type: ignore[override]
        return self._champ_select

    @Property("QVariant", notify=matchDetailChanged)
    def matchDetail(self) -> dict:  # type: ignore[override]
        return self._match_detail

    @Property("QVariant", notify=opggBuildChanged)
    def opggBuild(self) -> dict:  # type: ignore[override]
        return self._opgg_build

    @Property("QVariant", notify=championsChanged)
    def champions(self) -> list:  # type: ignore[override]
        return self._champions

    @Property("QVariant", notify=gameDataChanged)
    def championsById(self) -> dict:  # type: ignore[override]
        return self._champions_by_id

    @Property("QVariant", notify=gameDataChanged)
    def itemsById(self) -> dict:  # type: ignore[override]
        return self._items_by_id

    @Property("QVariant", notify=gameDataChanged)
    def spellsById(self) -> dict:  # type: ignore[override]
        return self._spells_by_id

    @Property("QVariant", notify=gameDataChanged)
    def perksById(self) -> dict:  # type: ignore[override]
        return self._perks_by_id

    @Property("QVariant", notify=gameDataChanged)
    def perkStylesById(self) -> dict:  # type: ignore[override]
        return self._perk_styles_by_id

    @Property("QVariant", notify=gameDataChanged)
    def queuesById(self) -> dict:  # type: ignore[override]
        return self._queues_by_id

    def _best_asset_url(self, icon_path: str, cdragon_fallback: str = "") -> str:
        """Return ``image://lcu/...`` when connected (localhost, ~5 ms), else CDragon.

        When connected, Qt's LCU image provider downloads from the game client
        directly — much faster than going out to CDragon and more reliable on
        restricted networks.
        """
        if icon_path:
            if self._connected:
                return "image://lcu" + (icon_path if icon_path.startswith("/") else "/" + icon_path)
            return assets.cdragon_url(icon_path)
        return cdragon_fallback

    @Slot(int, result=str)
    def championIcon(self, cid: int) -> str:
        if cid <= 0:
            return ""
        entry = self._champions_by_id.get(str(cid))
        icon_path = entry.get("squarePortraitPath", "") if entry else ""
        return self._best_asset_url(icon_path, assets.champion_icon(cid))

    @Slot(int, result=str)
    def championName(self, cid: int) -> str:
        entry = self._champions_by_id.get(str(cid))
        return entry.get("name", "") if entry else ""

    @Slot(int, result=str)
    def itemIcon(self, iid: int) -> str:
        if iid <= 0:
            return ""
        entry = self._items_by_id.get(str(iid))
        icon_path = entry.get("iconPath", "") if entry else ""
        return self._best_asset_url(icon_path)

    @Slot(int, result=str)
    def spellIcon(self, sid: int) -> str:
        if sid <= 0:
            return ""
        entry = self._spells_by_id.get(str(sid))
        icon_path = entry.get("iconPath", "") if entry else ""
        return self._best_asset_url(icon_path)

    @Slot(int, result=str)
    def perkIcon(self, pid: int) -> str:
        if pid <= 0:
            return ""
        entry = self._perks_by_id.get(str(pid))
        icon_path = entry.get("iconPath", "") if entry else ""
        return self._best_asset_url(icon_path)

    @Slot(int, result=str)
    def augmentIcon(self, aid: int) -> str:
        if aid <= 0:
            return ""
        entry = self._augments_by_id.get(str(aid))
        icon_path = entry.get("iconPath", "") if entry else ""
        return self._best_asset_url(icon_path)

    @Slot(int, result=str)
    def augmentName(self, aid: int) -> str:
        entry = self._augments_by_id.get(str(aid))
        return entry.get("name", "") if entry else ""

    @Slot(int, result=str)
    def augmentRarity(self, aid: int) -> str:
        entry = self._augments_by_id.get(str(aid))
        return entry.get("rarity", "") if entry else ""

    @Slot(int, result=str)
    def perkStyleIcon(self, pid: int) -> str:
        if pid <= 0:
            return ""
        entry = self._perk_styles_by_id.get(str(pid))
        icon_path = entry.get("iconPath", "") if entry else ""
        return self._best_asset_url(icon_path)

    @Slot(str, result=str)
    def tierEmblem(self, tier: str) -> str:
        return assets.tier_emblem(tier or "unranked")

    @Slot(str, result=str)
    def positionIcon(self, pos: str) -> str:
        return assets.position_icon(pos) or ""

    @Slot(int, result=str)
    def queueName(self, qid: int) -> str:
        entry = self._queues_by_id.get(str(qid))
        if entry:
            return entry.get("name") or assets.queue_label(qid, entry.get("shortName", ""))
        return assets.queue_label(qid, str(qid))

    @Slot(int, result=str)
    def profileIcon(self, iid: int) -> str:
        return assets.profile_icon(iid)

    @Property("QVariant", notify=championPoolChanged)
    def championPool(self) -> list:  # type: ignore[override]
        return self._champion_pool

    @Property("QVariant", notify=teammatesChanged)
    def teammates(self) -> list:  # type: ignore[override]
        return self._teammates

    @Property("QVariant", notify=searchResultChanged)
    def searchResult(self) -> dict:  # type: ignore[override]
        return self._search_result

    @Property("QVariant", notify=aramBuffsChanged)
    def aramBuffs(self) -> list:  # type: ignore[override]
        return self._aram_buffs

    @Property("QVariant", notify=inGameChanged)
    def inGame(self) -> dict:  # type: ignore[override]
        return self._in_game

    @Property("QVariant", notify=settingsChanged)
    def settings(self) -> dict:  # type: ignore[override]
        return self._settings.to_dict()

    # ----- QML-callable slots: core -----

    @Slot()
    def refresh(self) -> None:
        self._spawn(self._refresh_all(), name="bridge-refresh")

    @Slot(int)
    def refreshMatches(self, count: int) -> None:
        self._spawn(self._load_matches(max(1, count)), name="bridge-matches")

    @Slot(float)
    def loadMatchDetail(self, game_id: float) -> None:
        self._spawn(self._load_match_detail(int(game_id)))

    @Slot(float)
    def openMatchDetail(self, game_id: float) -> None:
        """Trigger both a detail fetch and navigation in one call from QML.

        Critically: synchronously reset ``matchDetail`` to the new gameId BEFORE
        navigation — the freshly-pushed page's Component.onCompleted snapshot
        would otherwise latch onto the *previous* match's gameId and never
        accept the new payload.
        """
        gid = int(game_id)
        cached = self._match_detail_cache.get(gid)
        self._match_detail = cached if cached is not None else {"loading": True, "gameId": gid}
        self.matchDetailChanged.emit()
        self._spawn(self._load_match_detail(gid))
        self.navigationRequested.emit("pages/MatchDetailPage.qml")

    @Slot()
    def refreshRanked(self) -> None:
        self._spawn(self._load_ranked(), name="bridge-ranked")

    @Slot()
    def refreshChampSelect(self) -> None:
        self._spawn(self._load_champ_select(), name="bridge-champ-select")

    # ----- QML-callable slots: matchmaking actions -----

    @Slot()
    def acceptReady(self) -> None:
        self._spawn(self._safe_call(api.ready_check_accept(self._client)))

    @Slot()
    def declineReady(self) -> None:
        self._spawn(self._safe_call(api.ready_check_decline(self._client)))

    @Slot()
    def dodgeLobby(self) -> None:
        self._spawn(self._safe_call(api.dodge_lobby(self._client)))

    # ----- QML-callable slots: opgg -----

    @Slot(str, str, str)
    def loadOpggBuild(self, champion: str, mode: str, position: str) -> None:
        self._spawn(self._load_opgg(champion, mode, position))

    @Slot()
    def applyCurrentRunePage(self) -> None:
        self._spawn(self._apply_rune_page())

    # ----- QML-callable slots: summoner / champion pool / teammates -----

    @Slot(str)
    def searchSummoner(self, query: str) -> None:
        self._spawn(self._search_summoner(query.strip()))

    @Slot(str)
    def openSummonerProfile(self, query: str) -> None:
        """Text-search entry point — name / Riot ID / alias. Falls back across
        several LCU endpoints since ``summoner-by-name`` is deprecated."""
        if not query or not query.strip():
            return
        query = query.strip()
        self._search_result = {"loading": True, "query": query}
        self.searchResultChanged.emit()
        self._spawn(self._search_summoner(query))
        self.navigationRequested.emit("pages/SummonerProfilePage.qml")

    @Slot(str)
    def openSummonerProfileByPuuid(self, puuid: str) -> None:
        """Click-from-match entry point — we already know the puuid, which
        is the only identifier the modern client reliably resolves."""
        if not puuid:
            return
        # Sync-reset so the new page snapshot sees the correct puuid.
        self._search_result = {"loading": True, "puuid": puuid}
        self.searchResultChanged.emit()
        self._spawn(self._load_profile_by_puuid(puuid))
        self.navigationRequested.emit("pages/SummonerProfilePage.qml")

    @Slot(int)
    def loadChampionPool(self, count: int) -> None:
        self._spawn(self._load_champion_pool(max(20, count)))

    @Slot(int)
    def loadTeammates(self, count: int) -> None:
        self._spawn(self._load_teammates(max(10, count)))

    @Slot()
    def loadAramBuffs(self) -> None:
        self._spawn(self._load_aram_buffs())

    @Slot(float)
    def spectateBySummonerId(self, summoner_id: float) -> None:
        self._spawn(self._spectate(int(summoner_id)))

    @Slot(str)
    def setStatusMessage(self, msg: str) -> None:
        self._spawn(self._safe_call(api.set_status_message(self._client, msg)))

    @Slot(int)
    def setBackgroundSkin(self, skin_id: int) -> None:
        self._spawn(self._safe_call(api.set_background_skin(self._client, skin_id)))

    # ----- QML-callable slots: lobbies -----

    @Slot(str, str)
    def createPracticeLobby(self, name: str, password: str) -> None:
        self._spawn(self._create_practice(name, password))

    @Slot(str, str)
    def createCustom5v5(self, name: str, password: str) -> None:
        self._spawn(self._create_custom(
            name, password, queue_id=3100, game_mode="CLASSIC", map_id=11, team_size=5
        ))

    @Slot(str, str)
    def createCustomAram(self, name: str, password: str) -> None:
        self._spawn(self._create_custom(
            name, password, queue_id=3200, game_mode="ARAM", map_id=12, team_size=5
        ))

    @Slot(int)
    def createQueueLobby(self, queue_id: int) -> None:
        async def run():
            try:
                await api.create_queue_lobby(self._client, queue_id)
                self.notify.emit("创建房间", f"已进入队列 {queue_id}")
            except Exception as e:  # noqa: BLE001
                self.errorOccurred.emit(str(e))
        self._spawn(run())

    # ----- QML-callable slots: profile tools -----

    @Slot(int)
    def applyProfileIcon(self, icon_id: int) -> None:
        async def run():
            try:
                await api.set_profile_icon(self._client, icon_id)
                self.notify.emit("头像", f"已应用头像 #{icon_id}")
            except Exception as e:  # noqa: BLE001
                self.errorOccurred.emit(str(e))
        self._spawn(run())

    @Slot()
    def removePrestigeCrest(self) -> None:
        async def run():
            try:
                await api.remove_prestige_crest(self._client)
                self.notify.emit("个人资料", "已移除荣耀水晶框")
            except Exception as e:  # noqa: BLE001
                self.errorOccurred.emit(str(e))
        self._spawn(run())

    @Slot(str)
    def applyAvailability(self, availability: str) -> None:
        async def run():
            try:
                await api.set_availability(self._client, availability)
                self.notify.emit("在线状态", f"已切换到 {availability}")
            except Exception as e:  # noqa: BLE001
                self.errorOccurred.emit(str(e))
        self._spawn(run())

    # ----- QML-callable slots: settings -----

    @Slot("QVariant")
    def updateAutoActions(self, raw: Any) -> None:
        """raw: {auto_accept, auto_ban, auto_pick, send_team_winrate, ban_priority, pick_priority}"""
        if not isinstance(raw, dict):
            return
        aa = self._settings.auto_actions
        for k in ("auto_accept", "auto_ban", "auto_pick", "send_team_winrate"):
            if k in raw:
                setattr(aa, k, bool(raw[k]))
        for k in ("ban_priority", "pick_priority"):
            if k in raw and isinstance(raw[k], list):
                setattr(aa, k, [int(x) for x in raw[k] if isinstance(x, (int, float, str)) and str(x).isdigit()])
        save_settings(self._settings)
        self._apply_settings_to_auto()
        self.settingsChanged.emit()

    @Slot("QVariant")
    def updateOpggPrefs(self, raw: Any) -> None:
        if not isinstance(raw, dict):
            return
        op = self._settings.opgg
        for k in ("tier", "region", "mode", "position"):
            if k in raw and isinstance(raw[k], str):
                setattr(op, k, raw[k])
        save_settings(self._settings)
        self.settingsChanged.emit()

    @Slot(str)
    def setDarkMode(self, mode: str) -> None:
        if mode in ("system", "light", "dark"):
            self._settings.dark_mode = mode
            save_settings(self._settings)
            self.settingsChanged.emit()

    @Slot(result=bool)
    def autoPaused(self) -> bool:
        return self._auto.paused

    @Slot()
    def toggleAutoPause(self) -> None:
        self._auto.paused = not self._auto.paused
        if self._auto.paused:
            self.notify.emit("自动动作", "已暂停")
        else:
            self.notify.emit("自动动作", "已恢复")

    @Slot(int, int, int, int)
    def saveWindowGeometry(self, x: int, y: int, w: int, h: int) -> None:
        self._settings.window.x = int(x)
        self._settings.window.y = int(y)
        self._settings.window.width = max(400, int(w))
        self._settings.window.height = max(300, int(h))
        save_settings(self._settings)

    # ----- internal handlers -----

    def _apply_settings_to_auto(self) -> None:
        s = self._settings.auto_actions
        self._auto.config = AutoActionsConfig(
            auto_accept=s.auto_accept,
            auto_ban=s.auto_ban,
            auto_pick=s.auto_pick,
            ban_priority=list(s.ban_priority),
            pick_priority=list(s.pick_priority),
        )

    def _set_matches_loading(self, loading: bool) -> None:
        if self._matches_loading != loading:
            self._matches_loading = loading
            self.matchesLoadingChanged.emit()

    async def _on_creds_change(self, creds: Optional[LcuCredentials]) -> None:
        await self._client.set_credentials(creds)
        await self._events.set_credentials(creds)
        if self._image_provider is not None:
            if creds:
                self._image_provider.set_credentials(creds.port, creds.token)
            else:
                self._image_provider.set_credentials(0, "")
        new_connected = creds is not None
        if new_connected != self._connected:
            self._connected = new_connected
            self.connectedChanged.emit()
        if new_connected:
            # Load static game data (icons) in parallel with user data — the
            # match list needs champion icons the moment it renders.
            await asyncio.gather(
                self._load_champions(),
                self._refresh_all(),
                return_exceptions=True,
            )
        else:
            self._summoner = {}
            self._phase = ""
            self._matches = []
            self._set_matches_loading(False)
            self._ranked = {}
            self._champ_select = {}
            for sig in (
                self.summonerChanged,
                self.phaseChanged,
                self.matchesChanged,
                self.rankedChanged,
                self.champSelectChanged,
            ):
                sig.emit()

    async def _on_phase_event(self, ev: LcuEvent) -> None:
        new_phase = ev.data if isinstance(ev.data, str) else ""
        if new_phase != self._phase:
            prev = self._phase
            self._phase = new_phase
            self.phaseChanged.emit()
            if new_phase == "ChampSelect":
                await self._load_champ_select()
            elif new_phase in ("GameStart", "InProgress"):
                # Freeze the current champ-select snapshot so GameflowPage can
                # keep showing the team composition during the game.
                if prev == "ChampSelect" and self._champ_select:
                    self._in_game = dict(self._champ_select)
                    self.inGameChanged.emit()
            elif new_phase in ("None", "Lobby", "Matchmaking", "EndOfGame", "PreEndOfGame"):
                if self._champ_select:
                    self._champ_select = {}
                    self.champSelectChanged.emit()
                if new_phase in ("None", "Lobby"):
                    self._winrate_sent_game_ids.clear()
                if new_phase in ("None", "Lobby") and self._in_game:
                    self._in_game = {}
                    self.inGameChanged.emit()

    async def _on_summoner_event(self, ev: LcuEvent) -> None:
        if isinstance(ev.data, dict):
            self._summoner = ev.data
            self.summonerChanged.emit()

    async def _on_champ_select_event(self, ev: LcuEvent) -> None:
        if ev.event_type == "Delete":
            if self._champ_select:
                self._champ_select = {}
                self.champSelectChanged.emit()
            return
        # Throttle: only refresh when session composition changes
        if not isinstance(ev.data, dict):
            return
        await self._refresh_champ_select_from(ev.data)

    # ----- fetchers -----

    async def _refresh_all(self) -> None:
        if not self._client.is_connected():
            return
        try:
            me = await api.current_summoner(self._client)
            self._summoner = me
            self.summonerChanged.emit()
            try:
                self._phase = await api.gameflow_phase(self._client) or ""
                self.phaseChanged.emit()
            except LcuError:
                pass
            await asyncio.gather(
                self._load_matches(20, me.get("puuid")),
                self._load_ranked(me.get("puuid")),
                return_exceptions=True,
            )
        except NotConnectedError:
            pass
        except Exception as e:  # noqa: BLE001
            log.exception("refresh failed: %s", e)
            self.errorOccurred.emit(str(e))

    async def _load_matches(self, count: int, puuid: str | None = None) -> None:
        if not self._client.is_connected():
            self._set_matches_loading(False)
            return
        self._matches_request_seq += 1
        request_seq = self._matches_request_seq
        self._set_matches_loading(True)
        try:
            if not puuid:
                puuid = (self._summoner or {}).get("puuid") or ""
            if not puuid:
                me = await api.current_summoner(self._client)
                puuid = me["puuid"]
            games: list[dict[str, Any]] = []
            for begin in range(0, count, 20):
                end = min(begin + 19, count - 1)
                raw = await api.match_history(self._client, puuid, begin, end)
                batch = raw.get("games", {}).get("games", [])
                games.extend(batch)
                if request_seq != self._matches_request_seq or len(batch) < (end - begin + 1):
                    break
            if request_seq != self._matches_request_seq:
                return
            self._matches = [self._project_match(g) for g in games]
            self.matchesChanged.emit()
        except Exception as e:  # noqa: BLE001
            log.exception("load matches failed: %s", e)
            self.errorOccurred.emit(str(e))
        finally:
            if request_seq == self._matches_request_seq:
                self._set_matches_loading(False)

    async def _load_ranked(self, puuid: str | None = None) -> None:
        if not self._client.is_connected():
            return
        try:
            if not puuid:
                puuid = (self._summoner or {}).get("puuid") or ""
            if not puuid:
                return
            data = await api.ranked_stats(self._client, puuid)
            self._ranked = self._project_ranked(data)
            self.rankedChanged.emit()
        except Exception as e:  # noqa: BLE001
            log.warning("ranked load failed: %s", e)

    async def _load_match_detail(self, game_id: int) -> None:
        if not self._client.is_connected():
            return
        # Serve from cache on repeat clicks — near-instant back/forward.
        cached = self._match_detail_cache.get(game_id)
        if cached is not None:
            self._match_detail = cached
            self.matchDetailChanged.emit()
            return
        self._match_detail = {"loading": True, "gameId": game_id}
        self.matchDetailChanged.emit()
        try:
            g = await api.game_detail(self._client, game_id)
            projected = self._project_match_detail(g)
            self._preload_match_detail_icons(projected)
            self._match_detail = projected
            # LRU: keep last 64 details
            self._match_detail_cache[game_id] = projected
            self._match_detail_order.append(game_id)
            while len(self._match_detail_order) > 64:
                old = self._match_detail_order.pop(0)
                self._match_detail_cache.pop(old, None)
            self.matchDetailChanged.emit()
        except Exception as e:  # noqa: BLE001
            log.exception("match detail failed: %s", e)
            self._match_detail = {"error": str(e), "gameId": game_id}
            self.matchDetailChanged.emit()
            self.errorOccurred.emit(str(e))

    def _preload_match_detail_icons(self, detail: dict[str, Any]) -> None:
        if self._image_provider is None or not hasattr(self._image_provider, "preload"):
            return

        paths: set[str] = set()

        def add(path: str | None) -> None:
            if path and path.startswith("/lol-game-data/assets/"):
                paths.add(path)

        for p in detail.get("participants") or []:
            if not isinstance(p, dict):
                continue
            champion = self._champions_by_id.get(str(p.get("championId") or 0))
            add((champion or {}).get("squarePortraitPath") or (champion or {}).get("iconPath"))
            for iid in p.get("items") or []:
                add((self._items_by_id.get(str(iid)) or {}).get("iconPath"))
            for sid in (p.get("spell1Id"), p.get("spell2Id")):
                add((self._spells_by_id.get(str(sid)) or {}).get("iconPath"))
            for pid in p.get("perks") or []:
                add((self._perks_by_id.get(str(pid)) or {}).get("iconPath"))
            add((self._perk_styles_by_id.get(str(p.get("subStyleId") or 0)) or {}).get("iconPath"))
            for aid in p.get("augments") or []:
                add((self._augments_by_id.get(str(aid)) or {}).get("iconPath"))

        try:
            self._image_provider.preload(paths)
        except Exception as e:  # noqa: BLE001
            log.debug("match detail icon preload failed: %s", e)

    @staticmethod
    def _project_match_detail(g: dict) -> dict:
        scores = {
            s.participant_id: {"score": s.score, "tags": list(s.tags)}
            for s in scoring.score_game(g)
        }
        participants: list[dict] = []
        team_kills: dict[int, int] = {}
        team_damage: dict[int, int] = {}
        for p in g.get("participants") or []:
            pid = p.get("participantId")
            stats = p.get("stats", {})
            team_id = p.get("teamId", 0)
            team_kills[team_id] = team_kills.get(team_id, 0) + stats.get("kills", 0)
            team_damage[team_id] = team_damage.get(team_id, 0) + stats.get("totalDamageDealtToChampions", 0)
            ident = next(
                (i for i in (g.get("participantIdentities") or []) if i.get("participantId") == pid),
                {},
            )
            pl = ident.get("player", {})
            participants.append({
                "participantId": pid,
                "teamId": team_id,
                "championId": p.get("championId"),
                "summonerName": pl.get("gameName") or pl.get("summonerName") or "",
                "puuid": pl.get("puuid") or "",
                "summonerId": pl.get("summonerId") or 0,
                "win": bool(stats.get("win")),
                "kills": stats.get("kills", 0),
                "deaths": stats.get("deaths", 0),
                "assists": stats.get("assists", 0),
                "cs": stats.get("totalMinionsKilled", 0) + stats.get("neutralMinionsKilled", 0),
                "gold": stats.get("goldEarned", 0),
                "damage": stats.get("totalDamageDealtToChampions", 0),
                "damagePhysical": stats.get("physicalDamageDealtToChampions", 0),
                "damageMagic": stats.get("magicDamageDealtToChampions", 0),
                "damageTrue": stats.get("trueDamageDealtToChampions", 0),
                "damageTaken": stats.get("totalDamageTaken", 0),
                "vision": stats.get("visionScore", 0),
                "wardsPlaced": stats.get("wardsPlaced", 0),
                "wardsKilled": stats.get("wardsKilled", 0),
                "items": [stats.get(f"item{i}", 0) for i in range(7)],
                "spell1Id": p.get("spell1Id", 0),
                "spell2Id": p.get("spell2Id", 0),
                "primaryStyleId": stats.get("perkPrimaryStyle", 0),
                "subStyleId": stats.get("perkSubStyle", 0),
                "perks": [stats.get(f"perk{i}", 0) for i in range(6)],
                "statPerks": [
                    stats.get("statPerk0", 0),
                    stats.get("statPerk1", 0),
                    stats.get("statPerk2", 0),
                ],
                # Arena / Hexakill modes store augment IDs in these slots.
                "augments": [stats.get(f"playerAugment{i}", 0) for i in range(1, 7)],
                "position": (p.get("timeline", {}) or {}).get("lane", ""),
                "role": (p.get("timeline", {}) or {}).get("role", ""),
                "score": scores.get(pid, {}).get("score", 0),
                "tags": scores.get(pid, {}).get("tags", []),
            })

        # Team aggregates
        teams_raw = g.get("teams") or []
        team_stats: list[dict] = []
        for t in teams_raw:
            tid = t.get("teamId", 0)
            team_stats.append({
                "teamId": tid,
                "win": t.get("win") == "Win" if isinstance(t.get("win"), str) else bool(t.get("win")),
                "kills": team_kills.get(tid, 0),
                "damage": team_damage.get(tid, 0),
                "gold": sum(p["gold"] for p in participants if p["teamId"] == tid),
                "towerKills": t.get("towerKills", 0),
                "dragonKills": t.get("dragonKills", 0),
                "baronKills": t.get("baronKills", 0),
                "inhibitorKills": t.get("inhibitorKills", 0),
                "riftHeraldKills": t.get("riftHeraldKills", 0),
                "firstBlood": bool(t.get("firstBlood")),
                "firstDragon": bool(t.get("firstDragon")),
                "firstBaron": bool(t.get("firstBaron")),
                "firstTower": bool(t.get("firstTower")),
                "firstInhibitor": bool(t.get("firstInhibitor")),
            })

        # Relative damage share (for DamageBar widths)
        if participants:
            max_dmg_per_team: dict[int, int] = {}
            for p in participants:
                max_dmg_per_team[p["teamId"]] = max(max_dmg_per_team.get(p["teamId"], 0), p["damage"])
            for p in participants:
                peak = max(1, max_dmg_per_team.get(p["teamId"], 1))
                p["damageShare"] = round(p["damage"] / peak, 3)

        queue_id = g.get("queueId", 0)
        uses_augments = queue_id in (1700, 2400) and any(
            any(a > 0 for a in p.get("augments", [])) for p in participants
        )

        return {
            "gameId": g.get("gameId"),
            "queueId": queue_id,
            "gameMode": g.get("gameMode"),
            "gameType": g.get("gameType"),
            "mapId": g.get("mapId"),
            "gameCreation": g.get("gameCreation"),
            "gameDuration": g.get("gameDuration"),
            "participants": participants,
            "teamStats": team_stats,
            "usesAugments": uses_augments,
        }

    async def _load_champ_select(self) -> None:
        if not self._client.is_connected():
            return
        try:
            session = await api.champ_select_session(self._client)
        except LcuError as e:
            if e.status == 404:
                return
            raise
        await self._refresh_champ_select_from(session)

    async def _refresh_champ_select_from(self, session: dict) -> None:
        try:
            snap: ChampSelectSnapshot = await snapshot_session(self._client, session)
            data = snap.to_dict()
            # Compute pre-groups across all visible players.
            all_players = [*data.get("myTeam", []), *data.get("theirTeam", [])]
            # Stamp each recent match with the player's team so the detector can
            # recognise "same team in past games".
            for p in all_players:
                for m in p.get("recent") or []:
                    m["teamId"] = p.get("team_id") or 0
            try:
                groups = detect_pregroups(all_players)
                data["preGroups"] = [
                    {"puuids": g.puuids, "gamesSameTeam": g.games_same_team, "color": g.color}
                    for g in groups
                ]
            except Exception as e:  # noqa: BLE001
                log.warning("pregroup detect failed: %s", e)
                data["preGroups"] = []
            self._champ_select = data
            self.champSelectChanged.emit()
            self._spawn(self._maybe_send_team_winrates(data), name="bridge-team-winrates")
        except Exception as e:  # noqa: BLE001
            log.exception("champ select snapshot failed: %s", e)

    async def _maybe_send_team_winrates(self, data: dict[str, Any]) -> None:
        if not self._settings.auto_actions.send_team_winrate or not self._client.is_connected():
            return
        game_id = int(data.get("gameId") or 0)
        if game_id <= 0 or game_id in self._winrate_sent_game_ids:
            return
        teammates = [
            p for p in (data.get("myTeam") or [])
            if isinstance(p, dict) and not p.get("is_me") and not p.get("isMe")
        ]
        lines: list[str] = []
        for p in teammates:
            name = p.get("display_name") or p.get("displayName") or "队友"
            rate = p.get("recent_win_rate", p.get("recentWinRate", 0))
            recent = p.get("recent") or []
            if recent:
                lines.append(f"{name}: 近{len(recent)}场 {round(float(rate) * 100)}%")
            else:
                lines.append(f"{name}: 无最近战绩")
        if not lines:
            return
        message = "队友胜率 | " + " | ".join(lines)
        try:
            conversations = await api.chat_conversations(self._client)
            conversation = next(
                (
                    c for c in conversations or []
                    if isinstance(c, dict)
                    and (
                        str(c.get("type", "")).lower() in ("championselect", "champion-select")
                        or "champion" in str(c.get("id", "")).lower()
                    )
                ),
                None,
            )
            conversation_id = (conversation or {}).get("id") or "championSelect"
            await api.send_chat_message(self._client, str(conversation_id), message)
            self._winrate_sent_game_ids.add(game_id)
            self.notify.emit("选人胜率", "已发送队友最近战绩胜率")
        except Exception as e:  # noqa: BLE001
            log.warning("send team winrates failed: %s", e)

    # ----- new fetchers -----

    async def _resolve_puuid(self, query: str) -> str | None:
        """Try several endpoints to turn a user-entered string into a puuid."""
        # Riot ID (Name#TAG) — preferred
        if "#" in query:
            name, tag = query.split("#", 1)
            try:
                r = await api.summoner_by_riot_id(self._client, name, tag)
                if isinstance(r, dict) and r.get("puuid"):
                    return r["puuid"]
            except LcuError:
                pass
        # Legacy name endpoint — works on some patches, fails silently otherwise
        try:
            r = await api.summoner_by_name(self._client, query)
            if isinstance(r, dict) and r.get("puuid"):
                return r["puuid"]
        except LcuError:
            pass
        # Riot global alias lookup
        try:
            alias = await api.search_alias(self._client, query)
            if isinstance(alias, list):
                for entry in alias:
                    if isinstance(entry, dict) and entry.get("puuid"):
                        return entry["puuid"]
            elif isinstance(alias, dict):
                if alias.get("puuid"):
                    return alias["puuid"]
                inner = alias.get("alias") or alias.get("data") or []
                if isinstance(inner, list):
                    for entry in inner:
                        if isinstance(entry, dict) and entry.get("puuid"):
                            return entry["puuid"]
        except LcuError:
            pass
        return None

    async def _load_profile_by_puuid(self, puuid: str) -> None:
        if not puuid or not self._client.is_connected():
            return
        self._search_result = {"loading": True, "puuid": puuid}
        self.searchResultChanged.emit()
        try:
            summoner, ranked, mh = await asyncio.gather(
                api.summoner_by_puuid(self._client, puuid),
                api.ranked_stats(self._client, puuid),
                api.match_history(self._client, puuid, 0, 19),
                return_exceptions=True,
            )
            if isinstance(summoner, Exception):
                raise summoner
            result = dict(summoner) if isinstance(summoner, dict) else {}
            result["_ranked"] = self._project_ranked(ranked) if isinstance(ranked, dict) else {}
            if isinstance(mh, dict):
                games = (mh.get("games", {}) or {}).get("games", []) or []
                result["_matches"] = [self._project_match(g) for g in games]
            else:
                result["_matches"] = []
            self._search_result = result or {"error": "not-found"}
            self.searchResultChanged.emit()
        except Exception as e:  # noqa: BLE001
            log.warning("profile-by-puuid failed: %s", e)
            self._search_result = {"error": str(e)}
            self.searchResultChanged.emit()

    async def _search_summoner(self, query: str) -> None:
        if not query or not self._client.is_connected():
            return
        self._search_result = {"loading": True, "query": query}
        self.searchResultChanged.emit()
        puuid = await self._resolve_puuid(query)
        if not puuid:
            self._search_result = {"error": f"未找到 {query}", "query": query}
            self.searchResultChanged.emit()
            return
        await self._load_profile_by_puuid(puuid)

    async def _load_champion_pool(self, count: int) -> None:
        if not self._client.is_connected():
            return
        try:
            puuid: str = (self._summoner or {}).get("puuid") or ""
            if not puuid:
                me = await api.current_summoner(self._client)
                puuid = me["puuid"]
            # Match history endpoint paginates at 20 per request — fetch in chunks.
            games: list[dict[str, Any]] = []
            for begin in range(0, count, 20):
                end = min(begin + 19, count - 1)
                chunk = await api.match_history(self._client, puuid, begin, end)
                batch = (chunk.get("games", {}).get("games") or [])
                if not batch:
                    break
                games.extend(batch)
                if len(batch) < (end - begin + 1):
                    break
            self._champion_pool = [s.to_dict() for s in aggregate_champions(games)]
            self.championPoolChanged.emit()
        except Exception as e:  # noqa: BLE001
            log.warning("champion pool failed: %s", e)
            self.errorOccurred.emit(str(e))

    async def _load_teammates(self, count: int) -> None:
        if not self._client.is_connected():
            return
        try:
            puuid: str = (self._summoner or {}).get("puuid") or ""
            if not puuid:
                me = await api.current_summoner(self._client)
                puuid = me["puuid"]
            mh = await api.match_history(self._client, puuid, 0, max(0, count - 1))
            game_ids = [g.get("gameId") for g in (mh.get("games", {}).get("games") or []) if g.get("gameId")]
            # Fetch details with bounded concurrency.
            sem = asyncio.Semaphore(5)

            async def one(gid: int) -> dict | None:
                async with sem:
                    try:
                        return await api.game_detail(self._client, gid)
                    except Exception:  # noqa: BLE001
                        return None

            details = await asyncio.gather(*(one(gid) for gid in game_ids))
            details = [d for d in details if d]
            self._teammates = [t.to_dict() for t in aggregate_teammates(details, puuid)]
            self.teammatesChanged.emit()
        except Exception as e:  # noqa: BLE001
            log.warning("teammates failed: %s", e)
            self.errorOccurred.emit(str(e))

    async def _load_aram_buffs(self) -> None:
        try:
            data = await aram_buff.fetch_aram()
            self._aram_buffs = sorted(data.values(), key=lambda x: x["championId"])
            self.aramBuffsChanged.emit()
        except Exception as e:  # noqa: BLE001
            log.warning("aram buff fetch failed: %s", e)
            self.errorOccurred.emit("ARAM 增益数据加载失败，请稍后重试")

    def _lobby_name(self, user_input: str, default: str) -> str:
        name = (user_input or "").strip()
        return name if len(name) >= 2 else default

    async def _create_practice(self, name: str, password: str) -> None:
        try:
            await api.create_custom_lobby(
                self._client,
                queue_id=3140,
                game_mode="PRACTICETOOL",
                map_id=11,
                lobby_name=self._lobby_name(name, "训练房间"),
                password=password,
                team_size=5,
            )
            self.notify.emit("创建房间", "已创建 5v5 训练房间")
        except Exception as e:  # noqa: BLE001
            self.errorOccurred.emit(str(e))

    async def _create_custom(
        self,
        name: str,
        password: str,
        *,
        queue_id: int,
        game_mode: str,
        map_id: int,
        team_size: int,
    ) -> None:
        try:
            await api.create_custom_lobby(
                self._client,
                queue_id=queue_id,
                game_mode=game_mode,
                map_id=map_id,
                lobby_name=self._lobby_name(name, "自定义房间"),
                password=password,
                team_size=team_size,
            )
            label = "5v5 自定义" if game_mode == "CLASSIC" else "大乱斗自定义"
            self.notify.emit("创建房间", f"已创建 {label}")
        except Exception as e:  # noqa: BLE001
            self.errorOccurred.emit(str(e))

    async def _spectate(self, summoner_id: int) -> None:
        try:
            summoner = await api.summoner_by_id(self._client, summoner_id)
            await api.spectate_summoner(self._client, summoner.get("puuid") or "")
            self.notify.emit("观战", "已发送观战请求")
        except Exception as e:  # noqa: BLE001
            log.warning("spectate failed: %s", e)
            self.errorOccurred.emit(str(e))

    async def _load_champions(self) -> None:
        """Load all static game data (champions/items/spells/perks/queues).

        Each entry gets an ``iconUrl`` field holding a CDragon mirror URL so
        QML can bind directly to ``Image.source``.
        """
        try:
            tasks = [
                api.game_data_champions(self._client),
                api.game_data_items(self._client),
                api.game_data_summoner_spells(self._client),
                api.game_data_runes(self._client),
                api.game_data_rune_styles(self._client),
                api.game_data_queues(self._client),
                api.game_data_cherry_augments(self._client),
            ]
            champs, items, spells, perks, perk_styles, queues, augments = await asyncio.gather(
                *tasks, return_exceptions=True
            )
        except Exception as e:  # noqa: BLE001
            log.warning("game data batch load failed: %s", e)
            return

        def _index(raw: Any, *, path_keys: tuple[str, ...] = ("iconPath",)) -> dict[str, dict]:
            if not isinstance(raw, list):
                return {}
            out: dict[str, dict] = {}
            for item in raw:
                iid = item.get("id")
                if iid is None or iid == -1:
                    continue
                entry = dict(item)
                for key in path_keys:
                    val = item.get(key)
                    if val:
                        entry["iconUrl"] = assets.cdragon_url(val)
                        break
                else:
                    entry["iconUrl"] = ""
                out[str(iid)] = entry
            return out

        # champion-summary.json uses ``squarePortraitPath`` (not iconPath).
        self._champions_by_id = _index(champs, path_keys=("squarePortraitPath", "iconPath"))
        self._champions = [
            {"id": c.get("id"), "name": c.get("name"), "alias": c.get("alias")}
            for c in (champs or [])
            if isinstance(c, dict) and c.get("id") and c.get("id") != -1
        ] if isinstance(champs, list) else []
        self._items_by_id = _index(items)
        self._spells_by_id = _index(spells)
        self._perks_by_id = _index(perks)

        # perkstyles has a nested shape: {"styles":[...]}
        if isinstance(perk_styles, dict):
            styles = perk_styles.get("styles") or []
        elif isinstance(perk_styles, list):
            styles = perk_styles
        else:
            styles = []
        self._perk_styles_by_id = _index(styles)

        # cherry-augments use "augmentSmallIconPath" + "nameTRA" instead of standard names.
        if isinstance(augments, list):
            self._augments_by_id = {
                str(a.get("id")): {
                    "id": a.get("id"),
                    "name": a.get("nameTRA") or a.get("name") or "",
                    "rarity": (a.get("rarity") or "").replace("k", "").lower() or "unknown",
                    "iconUrl": assets.cdragon_url(
                        a.get("augmentSmallIconPath")
                        or a.get("iconLargePath")
                        or a.get("augmentLargeIconPath")
                        or ""
                    ),
                    "iconPath": a.get("augmentSmallIconPath")
                    or a.get("iconLargePath")
                    or a.get("augmentLargeIconPath")
                    or "",
                }
                for a in augments
                if isinstance(a, dict) and a.get("id")
            }
        else:
            self._augments_by_id = {}

        # queues.json entries: {id, name, shortName, description, mapId}
        if isinstance(queues, list):
            self._queues_by_id = {
                str(q.get("id")): {
                    "id": q.get("id"),
                    "name": q.get("description") or q.get("name") or "",
                    "shortName": q.get("shortName") or "",
                    "mapId": q.get("mapId"),
                }
                for q in queues
                if isinstance(q, dict) and q.get("id") is not None
            }
        else:
            self._queues_by_id = {}

        self.gameDataChanged.emit()
        self.championsChanged.emit()

    async def _load_opgg(self, champion: str, mode: str, position: str) -> None:
        try:
            build = await opgg.fetch_build(
                champion,
                mode=mode or self._settings.opgg.mode,
                position=position or None,
                tier=self._settings.opgg.tier,
                region=self._settings.opgg.region,
            )
            self._opgg_build = {
                "champion": build.champion,
                "mode": build.mode,
                "patch": build.patch or "",
                "position": build.position or "",
                "variants": [
                    {
                        "name": v.name,
                        "items_start": v.items_start,
                        "items_core": v.items_core,
                        "items_boots": v.items_boots,
                        "items_situational": v.items_situational,
                        "summoner_spells": v.summoner_spells,
                        "runePage": None if v.rune_page is None else {
                            "primary": v.rune_page.primary_style_id,
                            "sub": v.rune_page.sub_style_id,
                            "perks": v.rune_page.selected_perk_ids,
                        },
                    }
                    for v in build.variants
                ],
            }
            self.opggBuildChanged.emit()
        except Exception as e:  # noqa: BLE001
            log.warning("opgg fetch failed: %s", e)
            self.errorOccurred.emit(f"OP.GG: {e}")

    async def _apply_rune_page(self) -> None:
        build = self._opgg_build
        if not build or not build.get("variants"):
            self.errorOccurred.emit("No OP.GG build loaded")
            return
        v = build["variants"][0]
        rp = v.get("runePage")
        if not rp:
            self.errorOccurred.emit("Loaded build has no rune page")
            return
        try:
            existing = await api.list_rune_pages(self._client)
            for page in existing or []:
                if page.get("name", "").startswith("OPGG "):
                    try:
                        await api.delete_rune_page(self._client, page["id"])
                    except Exception:  # noqa: BLE001
                        pass
            payload = {
                "name": f"OPGG {build.get('champion')}",
                "primaryStyleId": rp["primary"],
                "subStyleId": rp["sub"],
                "selectedPerkIds": rp["perks"],
                "current": True,
            }
            await api.create_rune_page(self._client, payload)
            self.notify.emit("符文页", f"已应用 {build.get('champion')} OP.GG 符文页")
        except Exception as e:  # noqa: BLE001
            log.warning("apply rune page failed: %s", e)
            self.errorOccurred.emit(str(e))

    # ----- projections -----

    @staticmethod
    def _project_match(g: dict) -> dict:
        participants = g.get("participants") or [{}]
        me = participants[0]
        stats = me.get("stats", {})
        return {
            "gameId": g.get("gameId"),
            "queueId": g.get("queueId"),
            "gameMode": g.get("gameMode", ""),
            "gameCreation": g.get("gameCreation", 0),
            "gameDuration": g.get("gameDuration", 0),
            "championId": me.get("championId"),
            "win": bool(stats.get("win")),
            "kills": stats.get("kills", 0),
            "deaths": stats.get("deaths", 0),
            "assists": stats.get("assists", 0),
            "cs": stats.get("totalMinionsKilled", 0) + stats.get("neutralMinionsKilled", 0),
            "gold": stats.get("goldEarned", 0),
        }

    @staticmethod
    def _project_ranked(data: dict) -> dict:
        queues = data.get("queues") or []
        out: dict[str, Any] = {"queues": []}
        for q in queues:
            tier = q.get("tier") or "UNRANKED"
            out["queues"].append({
                "queueType": q.get("queueType", ""),
                "tier": tier,
                "division": q.get("division") or q.get("rank") or "",
                "leaguePoints": q.get("leaguePoints", 0),
                "wins": q.get("wins", 0),
                "losses": q.get("losses", 0),
            })
        hr = data.get("highestRankedEntry") or data.get("highestCurrentSeasonReachedTierSR")
        if hr:
            out["highest"] = hr
        return out

    async def _safe_call(self, coro) -> None:
        try:
            await coro
        except Exception as e:  # noqa: BLE001
            log.warning("action failed: %s", e)
            self.errorOccurred.emit(str(e))
