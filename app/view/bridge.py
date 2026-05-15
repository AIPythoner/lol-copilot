"""QObject bridges exposed to QML.

LcuBridge owns the LCU stack (watcher, client, event stream) + persisted
settings, and re-emits state changes as Qt signals / properties.

Exposed to QML as context property `Lcu`. Read-only properties are camelCase;
slots are verbs. All long work is async — slots just kick tasks off.
"""
from __future__ import annotations

import asyncio
import json
import time
from typing import Any, Optional

import httpx

from PySide6.QtCore import (
    Property,
    QObject,
    Signal,
    Slot,
)
from PySide6.QtGui import QGuiApplication

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

MATCH_DETAIL_PRELOAD_COUNT = 10
MATCH_DETAIL_PRELOAD_CONCURRENCY = 4
MATCH_DETAIL_ICON_PRELOAD_COUNT = 4
MATCH_DETAIL_CACHE_LIMIT = 64
MATCH_DETAIL_MIN_SKELETON_MS = 180
MATCHES_DEFAULT_PAGE_SIZE = 20

AI_SYSTEM_PROMPT = (
    "你是一个 LOL 游戏分析师，擅长分析玩家战绩和给出游戏建议。"
    "请用简洁、专业、直接的中文回复。所有结论都必须绑定数据证据，避免空泛。"
)


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
    hextechChanged = Signal()
    settingsChanged = Signal()
    errorOccurred = Signal(str)
    notify = Signal(str, str)  # title, body
    navigationRequested = Signal(str)  # relative qml path for pages/… nav.push
    # AI match analysis stream: one session at a time.
    # started(gameId, mode) — fires when a stream begins (or a cache hit replays)
    # chunk(text) — append the delta to the on-screen buffer
    # done() / error(text) — terminal; UI flips back to idle
    aiAnalysisStarted = Signal(str, str)
    aiAnalysisChunk = Signal(str)
    aiAnalysisDone = Signal()
    aiAnalysisError = Signal(str)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._connected: bool = False
        self._summoner: dict[str, Any] = {}
        self._phase: str = ""
        self._matches: list[dict[str, Any]] = []
        self._matches_loading: bool = False
        self._matches_request_seq: int = 0
        self._matches_page_size: int = MATCHES_DEFAULT_PAGE_SIZE
        self._matches_has_more: bool = True
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
        # Bump on every game-data reload — cheap scalar lets QML icon bindings
        # re-eval when items.json arrives without subscribing to the whole dict.
        self._game_data_rev: int = 0
        self._match_detail_cache: dict[int, dict] = {}
        self._match_detail_order: list[int] = []
        self._match_detail_inflight: dict[int, asyncio.Task] = {}
        self._match_detail_preload_seq: int = 0
        self._match_detail_loading_started_at: float = 0.0
        self._match_detail_pending_game_id: int = 0
        # gameId is unreliable during champ-select on some patches (returns 0),
        # so we dedup on the sorted teammate-puuid fingerprint of the session.
        self._winrate_sent_fingerprints: set[str] = set()
        self._champion_pool: list[dict[str, Any]] = []
        self._teammates: list[dict[str, Any]] = []
        self._search_result: dict[str, Any] = {}
        self._aram_buffs: list[dict[str, Any]] = []
        self._in_game: dict[str, Any] = {}
        self._hextech: dict[str, Any] = {}
        # Session-scoped AI analysis cache, keyed by (gameId, mode, puuid).
        # Matches rank-analysis' sessionStorage strategy — same match replays
        # instantly without re-billing tokens.
        self._ai_cache: dict[tuple[int, str, str], str] = {}
        self._ai_task: Optional[asyncio.Task] = None
        # Background task polling for login completion. LCU's REST endpoints
        # can return "not logged in" for several seconds after the WS handshake
        # succeeds, so we keep retrying instead of giving up.
        self._login_wait_task: Optional[asyncio.Task] = None
        # Session-scoped puuid → primary rank cache. Match detail enriches
        # participant rows with ranks; the same puuid often appears across
        # adjacent matches so caching avoids redundant LCU calls.
        self._rank_cache: dict[str, dict] = {}

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

    @Property(bool, notify=matchesChanged)
    def matchesHasMore(self) -> bool:  # type: ignore[override]
        return self._matches_has_more

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

    @Property(int, notify=gameDataChanged)
    def gameDataRev(self) -> int:  # type: ignore[override]
        return self._game_data_rev

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
        # CDragon hosts every item icon under a stable /items/<id>.png path,
        # so we can serve a URL even if items.json hasn't finished loading
        # (otherwise rows render with empty slots until the user navigates away).
        return self._best_asset_url(icon_path, assets.item_icon(iid))

    @Slot(int, result=str)
    def itemName(self, iid: int) -> str:
        entry = self._items_by_id.get(str(iid))
        return entry.get("name", "") if entry else ""

    @Slot(int, result=str)
    def spellIcon(self, sid: int) -> str:
        if sid <= 0:
            return ""
        entry = self._spells_by_id.get(str(sid))
        icon_path = entry.get("iconPath", "") if entry else ""
        return self._best_asset_url(icon_path)

    @Slot(int, result=str)
    def spellName(self, sid: int) -> str:
        entry = self._spells_by_id.get(str(sid))
        return entry.get("name", "") if entry else ""

    @Slot(int, result=str)
    def perkIcon(self, pid: int) -> str:
        if pid <= 0:
            return ""
        entry = self._perks_by_id.get(str(pid))
        icon_path = entry.get("iconPath", "") if entry else ""
        return self._best_asset_url(icon_path)

    @Slot(int, result=str)
    def perkName(self, pid: int) -> str:
        entry = self._perks_by_id.get(str(pid))
        return entry.get("name", "") if entry else ""

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

    @Property("QVariant", notify=hextechChanged)
    def hextech(self) -> dict:  # type: ignore[override]
        return self._hextech

    @Property("QVariant", notify=settingsChanged)
    def settings(self) -> dict:  # type: ignore[override]
        return self._settings.to_dict()

    # ----- QML-callable slots: core -----

    @Slot()
    def refresh(self) -> None:
        self._spawn(self._refresh_all(), name="bridge-refresh")

    @Slot(int)
    def refreshMatches(self, count: int) -> None:
        self._spawn(self._load_matches(max(1, count), append=False), name="bridge-matches")

    @Slot()
    def loadMoreMatches(self) -> None:
        if self._matches_loading or not self._matches_has_more:
            return
        self._spawn(
            self._load_matches(self._matches_page_size, append=True),
            name="bridge-matches-more",
        )

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
        if cached is not None:
            # Skip the loading frame + MIN_SKELETON wait entirely — data is
            # already complete, so the page can render immediately.
            self._match_detail_pending_game_id = 0
            self._match_detail_loading_started_at = 0.0
            self._match_detail = cached
            self._preload_match_detail_icons(cached, priority=True, clear_pending=True)
            self.matchDetailChanged.emit()
            if not cached.get("_ranks_loaded"):
                self._spawn(
                    self._enrich_match_detail_ranks(gid),
                    name=f"bridge-match-ranks-{gid}",
                )
        else:
            self._set_match_detail_loading(gid)
            self._spawn(self._load_match_detail(gid))
        self.navigationRequested.emit("pages/MatchDetailPage.qml")

    @Slot()
    def refreshRanked(self) -> None:
        self._spawn(self._load_ranked(), name="bridge-ranked")

    @Slot()
    def refreshChampSelect(self) -> None:
        self._spawn(self._load_champ_select(), name="bridge-champ-select")

    @Slot()
    def sendAllWinrates(self) -> None:
        """Force-send a recent-winrate summary for every visible player.

        Unlike the auto-trigger this also includes the enemy team (when their
        info is visible) and ignores the once-per-fingerprint dedup so the
        user can re-broadcast on demand.
        """
        self._spawn(self._send_all_winrates(), name="bridge-send-all-winrates")

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

    @Slot(str)
    def copyToClipboard(self, text: str) -> None:
        if not text:
            return
        cb = QGuiApplication.clipboard()
        if cb is not None:
            cb.setText(text)
            self.notify.emit("已复制", text)

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

    # ----- QML-callable slots: Hextech loot -----

    @Slot()
    def refreshHextech(self) -> None:
        self._spawn(self._refresh_hextech(), name="bridge-hextech-refresh")

    @Slot()
    def openAllChests(self) -> None:
        self._spawn(
            self._tidy_hextech(open_chests=True, disenchant=False),
            name="bridge-hextech-open",
        )

    @Slot()
    def disenchantRedundantShards(self) -> None:
        self._spawn(
            self._tidy_hextech(open_chests=False, disenchant=True),
            name="bridge-hextech-disenchant",
        )

    @Slot()
    def tidyHextech(self) -> None:
        self._spawn(
            self._tidy_hextech(open_chests=True, disenchant=True),
            name="bridge-hextech-tidy",
        )

    # ----- QML-callable slots: replays -----

    @Slot(float)
    def watchReplay(self, game_id: float) -> None:
        self._spawn(self._watch_replay(int(game_id)), name="bridge-replay")

    # ----- QML-callable slots: AI match analysis -----

    @Slot(float, str, str)
    def analyzeMatch(self, game_id: float, mode: str, target_puuid: str) -> None:
        """Start (or replay from cache) an AI analysis of ``game_id``.

        ``mode`` is ``overview`` (full-team breakdown) or ``player`` (focus
        on ``target_puuid``). If another analysis is already streaming we
        cancel it first — the dialog can only host one session at a time.
        """
        gid = int(game_id)
        self._cancel_ai_task()
        self._ai_task = self._spawn(
            self._analyze_match(gid, mode or "overview", (target_puuid or "").strip()),
            name="bridge-ai-analyze",
        )

    @Slot()
    def cancelAnalysis(self) -> None:
        self._cancel_ai_task()

    @Slot("QVariant")
    def updateAiConfig(self, raw: Any) -> None:
        """raw: {enabled, base_url, api_key, model}"""
        if not isinstance(raw, dict):
            return
        ai = self._settings.ai
        if "enabled" in raw:
            ai.enabled = bool(raw["enabled"])
        for k in ("base_url", "api_key", "model"):
            if k in raw and isinstance(raw[k], str):
                setattr(ai, k, raw[k].strip())
        save_settings(self._settings)
        self.settingsChanged.emit()

    # ----- QML-callable slots: settings -----

    @Slot("QVariant")
    def updateAutoActions(self, raw: Any) -> None:
        """raw: {auto_accept, auto_ban, auto_pick, send_team_winrate, ban_priority, pick_priority}"""
        if not isinstance(raw, dict):
            return
        log.info("updateAutoActions called: %s", raw)
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

    @staticmethod
    def _perf_ms(start: float) -> int:
        return round((time.perf_counter() - start) * 1000)

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
            if self._login_wait_task is not None and not self._login_wait_task.done():
                self._login_wait_task.cancel()
                self._login_wait_task = None
            self._summoner = {}
            self._phase = ""
            self._matches = []
            self._set_matches_loading(False)
            self._ranked = {}
            self._champ_select = {}
            self._rank_cache.clear()
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
                    self._winrate_sent_fingerprints.clear()
                if new_phase in ("None", "Lobby") and self._in_game:
                    self._in_game = {}
                    self.inGameChanged.emit()

    async def _on_summoner_event(self, ev: LcuEvent) -> None:
        if isinstance(ev.data, dict):
            had_summoner = bool(self._summoner.get("puuid")) if self._summoner else False
            self._summoner = ev.data
            self.summonerChanged.emit()
            # If we hadn't loaded a summoner yet (client was sitting at the
            # login screen on startup), now's the moment to fetch matches /
            # ranked / etc. — the rest of _refresh_all bails on the "not
            # logged in" 404 until this event arrives. Cancel any in-flight
            # login-polling task so we don't double-fetch.
            if not had_summoner and ev.data.get("puuid"):
                if self._login_wait_task is not None and not self._login_wait_task.done():
                    self._login_wait_task.cancel()
                    self._login_wait_task = None
                self._spawn(self._refresh_all(), name="bridge-refresh-after-login")

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
        except LcuError as e:
            # LCU returns 404 RPC_ERROR "You are not logged in" when its REST
            # surface comes up before the user has finished signing in (this
            # is normal during startup and can persist for many seconds on
            # TENCENT). Poll in the background until it succeeds instead of
            # giving up — otherwise the profile page sits empty forever.
            if self._is_not_logged_in_error(e):
                self._start_login_wait()
                return
            log.exception("refresh failed: %s", e)
            self.errorOccurred.emit(str(e))
        except Exception as e:  # noqa: BLE001
            log.exception("refresh failed: %s", e)
            self.errorOccurred.emit(str(e))

    @staticmethod
    def _is_not_logged_in_error(e: LcuError) -> bool:
        if e.status != 404:
            return False
        payload = e.payload if isinstance(e.payload, dict) else {}
        return "not logged in" in str(payload.get("message", "")).lower()

    def _start_login_wait(self) -> None:
        if self._login_wait_task is not None and not self._login_wait_task.done():
            return
        log.info("refresh waiting for login (lcu not logged in yet) — polling")
        self._login_wait_task = self._spawn(self._wait_for_login(), name="bridge-login-wait")

    async def _wait_for_login(self) -> None:
        # Exponential-ish backoff capped at 10s — fast enough that the UI
        # populates within a couple of seconds of login completing, slow
        # enough that we don't hammer LCU.
        delays = [1.0, 2.0, 3.0, 5.0]
        idx = 0
        while self._client.is_connected():
            await asyncio.sleep(delays[min(idx, len(delays) - 1)])
            idx += 1
            try:
                me = await api.current_summoner(self._client)
            except NotConnectedError:
                return
            except LcuError as e:
                if self._is_not_logged_in_error(e):
                    continue
                log.warning("login wait got non-login error: %s", e)
                return
            except Exception as e:  # noqa: BLE001
                log.warning("login wait failed: %s", e)
                return
            self._summoner = me
            self.summonerChanged.emit()
            log.info("login detected — refreshing data")
            await self._refresh_all()
            return

    async def _load_matches(
        self,
        count: int,
        puuid: str | None = None,
        *,
        append: bool = False,
    ) -> None:
        if not self._client.is_connected():
            self._set_matches_loading(False)
            return
        self._matches_request_seq += 1
        request_seq = self._matches_request_seq
        begin_index = len(self._matches) if append else 0
        page_size = max(1, count)
        self._matches_page_size = page_size
        if not append:
            self._matches_has_more = True
        self._set_matches_loading(True)
        started_at = time.perf_counter()
        fetch_ms = 0
        project_ms = 0
        fetched_count = 0
        try:
            if not puuid:
                puuid = (self._summoner or {}).get("puuid") or ""
            if not puuid:
                me = await api.current_summoner(self._client)
                puuid = me["puuid"]
            games: list[dict[str, Any]] = []
            fetch_started_at = time.perf_counter()
            end_index = begin_index + page_size
            for begin in range(begin_index, end_index, 20):
                end = min(begin + 19, end_index - 1)
                raw = await api.match_history(self._client, puuid, begin, end)
                batch = raw.get("games", {}).get("games", [])
                games.extend(batch)
                fetched_count += len(batch)
                if request_seq != self._matches_request_seq or len(batch) < (end - begin + 1):
                    break
            fetch_ms = self._perf_ms(fetch_started_at)
            if request_seq != self._matches_request_seq:
                return
            project_started_at = time.perf_counter()
            projected = [self._project_match(g) for g in games]
            project_ms = self._perf_ms(project_started_at)
            if append:
                seen_ids = {m.get("gameId") for m in self._matches}
                self._matches.extend(m for m in projected if m.get("gameId") not in seen_ids)
            else:
                self._matches = projected
            self._matches_has_more = fetched_count >= page_size
            self.matchesChanged.emit()
            self._schedule_match_detail_preload(projected if append else self._matches, request_seq)
            log.info(
                "perf matches append=%s begin=%s requested=%s fetched=%s total=%s "
                "has_more=%s fetch_ms=%s project_ms=%s total_ms=%s",
                append,
                begin_index,
                page_size,
                fetched_count,
                len(self._matches),
                self._matches_has_more,
                fetch_ms,
                project_ms,
                self._perf_ms(started_at),
            )
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
            self._preload_match_detail_icons(cached, priority=True)
            await self._publish_match_detail(cached)
            if not cached.get("_ranks_loaded"):
                self._spawn(
                    self._enrich_match_detail_ranks(game_id),
                    name=f"bridge-match-ranks-{game_id}",
                )
            return
        current_gid = int((self._match_detail or {}).get("gameId") or -1)
        if current_gid != game_id or not bool((self._match_detail or {}).get("loading")):
            self._set_match_detail_loading(game_id)
        try:
            projected = await self._get_projected_match_detail(game_id)
            self._preload_match_detail_icons(projected, priority=True, clear_pending=True)
            await self._publish_match_detail(projected)
            self._spawn(
                self._enrich_match_detail_ranks(game_id),
                name=f"bridge-match-ranks-{game_id}",
            )
        except Exception as e:  # noqa: BLE001
            log.exception("match detail failed: %s", e)
            await self._publish_match_detail({"error": str(e), "gameId": game_id})
            self.errorOccurred.emit(str(e))

    async def _enrich_match_detail_ranks(self, game_id: int) -> None:
        detail = self._match_detail_cache.get(game_id)
        if not detail or detail.get("_ranks_loaded"):
            return
        participants = detail.get("participants") or []
        with_puuid = sum(1 for p in participants if p.get("puuid"))
        with_sid = sum(1 for p in participants if int(p.get("summonerId") or 0) > 0)
        log.info(
            "match_detail rank-enrich start game=%s participants=%s with_puuid=%s with_summonerId=%s",
            game_id, len(participants), with_puuid, with_sid,
        )
        # Resolve a puuid for every participant. TENCENT match-history payloads
        # often omit puuid and only carry summonerId, in which case we need an
        # extra hop through summoner_by_id before we can hit ranked-stats.
        missing: list[tuple[dict, int]] = [
            (p, int(p.get("summonerId") or 0))
            for p in participants
            if not p.get("puuid") and int(p.get("summonerId") or 0) > 0
        ]
        if missing:
            results = await asyncio.gather(
                *[api.summoner_by_id(self._client, sid) for _, sid in missing],
                return_exceptions=True,
            )
            for (p, _), s in zip(missing, results):
                if isinstance(s, dict) and s.get("puuid"):
                    p["puuid"] = s["puuid"]
        seen: set[str] = set()
        puuids: list[str] = []
        for p in participants:
            puuid = p.get("puuid")
            if puuid and puuid not in seen:
                seen.add(puuid)
                puuids.append(puuid)
        if not puuids:
            log.info("match_detail ranks game=%s: no puuids resolvable", game_id)
            detail["_ranks_loaded"] = True
            return
        to_fetch = [p for p in puuids if p not in self._rank_cache]
        ok = 0
        err = 0
        sample_dumped = False
        if to_fetch:
            results = await asyncio.gather(
                *[api.ranked_stats(self._client, p) for p in to_fetch],
                return_exceptions=True,
            )
            for puuid, raw in zip(to_fetch, results):
                if isinstance(raw, dict):
                    if not sample_dumped:
                        # One-shot dump so we can see if LCU on this patch
                        # uses queueMap, queues, or some other shape.
                        log.info("ranked_stats sample shape keys=%s", list(raw.keys()))
                        sample_dumped = True
                    primary = self._primary_rank(raw)
                    self._rank_cache[puuid] = primary or {}
                    if primary:
                        ok += 1
                else:
                    log.warning("ranked_stats fetch failed for %s: %r", puuid[:8], raw)
                    self._rank_cache[puuid] = {}
                    err += 1
        for p in participants:
            rank = self._rank_cache.get(p.get("puuid") or "")
            if rank:
                p["rank"] = rank
        detail["_ranks_loaded"] = True
        log.info(
            "match_detail ranks game=%s participants=%s puuids=%s fetched=%s ranked=%s errors=%s",
            game_id, len(participants), len(puuids), len(to_fetch), ok, err,
        )
        # Re-cache (LRU bump) + re-emit if the user is still on this detail
        self._cache_match_detail(game_id, detail)
        if int((self._match_detail or {}).get("gameId") or 0) == game_id:
            self._match_detail = detail
            self.matchDetailChanged.emit()

    @staticmethod
    def _primary_rank(raw: dict) -> dict | None:
        # LCU returns ranks in either of two shapes depending on the endpoint
        # / patch: `queues` (array) for the current user's stats, `queueMap`
        # (dict) for other puuids. Seraphine / rank-analysis both observe the
        # dict shape on per-puuid lookups, so we accept both.
        preferred = ("RANKED_SOLO_5x5", "RANKED_FLEX_SR")
        queue_map = raw.get("queueMap")
        if isinstance(queue_map, dict):
            for queue_type in preferred:
                q = queue_map.get(queue_type)
                if isinstance(q, dict) and q.get("tier"):
                    return {
                        "tier": q.get("tier"),
                        "division": "" if q.get("division") in (None, "NA") else q.get("division"),
                        "leaguePoints": q.get("leaguePoints", 0) or 0,
                        "queueType": queue_type,
                    }
        queues = raw.get("queues") or []
        for queue_type in preferred:
            q = next(
                (q for q in queues if q.get("queueType") == queue_type and q.get("tier")),
                None,
            )
            if q:
                division = q.get("division") or q.get("rank") or ""
                if division == "NA":
                    division = ""
                return {
                    "tier": q.get("tier"),
                    "division": division,
                    "leaguePoints": q.get("leaguePoints", 0) or 0,
                    "queueType": queue_type,
                }
        return None

    def _set_match_detail_loading(self, game_id: int) -> None:
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = asyncio.get_event_loop()
        self._match_detail_loading_started_at = loop.time()
        self._match_detail_pending_game_id = game_id
        self._match_detail = {"loading": True, "gameId": game_id}
        self.matchDetailChanged.emit()

    async def _publish_match_detail(self, payload: dict[str, Any]) -> None:
        gid = int(payload.get("gameId") or 0)
        if gid > 0 and self._match_detail_pending_game_id == gid:
            try:
                loop = asyncio.get_running_loop()
            except RuntimeError:
                loop = asyncio.get_event_loop()
            elapsed = loop.time() - self._match_detail_loading_started_at
            remaining = MATCH_DETAIL_MIN_SKELETON_MS / 1000.0 - elapsed
            if remaining > 0:
                await asyncio.sleep(remaining)
        if gid > 0 and self._match_detail_pending_game_id not in (0, gid):
            return
        self._match_detail = payload
        self.matchDetailChanged.emit()
        if gid > 0 and self._match_detail_pending_game_id == gid:
            self._match_detail_pending_game_id = 0
            self._match_detail_loading_started_at = 0.0

    def _schedule_match_detail_preload(self, matches: list[dict[str, Any]], request_seq: int) -> None:
        self._match_detail_preload_seq += 1
        preload_seq = self._match_detail_preload_seq
        game_ids: list[int] = []
        seen: set[int] = set()
        for match in matches:
            raw_gid = match.get("gameId") if isinstance(match, dict) else None
            try:
                gid = int(raw_gid)
            except (TypeError, ValueError):
                continue
            if gid <= 0 or gid in seen or gid in self._match_detail_cache:
                continue
            seen.add(gid)
            game_ids.append(gid)
            if len(game_ids) >= MATCH_DETAIL_PRELOAD_COUNT:
                break
        if game_ids:
            self._spawn(
                self._preload_match_details(game_ids, request_seq, preload_seq),
                name="bridge-match-detail-preload",
            )

    async def _preload_match_details(
        self,
        game_ids: list[int],
        request_seq: int,
        preload_seq: int,
    ) -> None:
        started_at = time.perf_counter()
        sem = asyncio.Semaphore(MATCH_DETAIL_PRELOAD_CONCURRENCY)

        async def one(gid: int, warm_icons: bool) -> None:
            if (
                request_seq != self._matches_request_seq
                or preload_seq != self._match_detail_preload_seq
            ):
                return
            if gid in self._match_detail_cache:
                if warm_icons:
                    self._preload_match_detail_icons(
                        self._match_detail_cache[gid],
                        priority=False,
                        clear_pending=False,
                    )
                return
            async with sem:
                try:
                    detail = await self._get_projected_match_detail(gid)
                    if warm_icons:
                        self._preload_match_detail_icons(
                            detail,
                            priority=False,
                            clear_pending=False,
                        )
                except Exception as e:  # noqa: BLE001
                    log.debug("match detail preload failed gid=%s: %s", gid, e)

        await asyncio.gather(
            *(
                one(gid, idx < MATCH_DETAIL_ICON_PRELOAD_COUNT)
                for idx, gid in enumerate(game_ids)
            )
        )
        log.info(
            "perf match_detail_preload count=%s concurrency=%s total_ms=%s",
            len(game_ids),
            MATCH_DETAIL_PRELOAD_CONCURRENCY,
            self._perf_ms(started_at),
        )

    async def _get_projected_match_detail(self, game_id: int) -> dict[str, Any]:
        cached = self._match_detail_cache.get(game_id)
        if cached is not None:
            return cached

        task = self._match_detail_inflight.get(game_id)
        if task is None:
            task = self._spawn(
                self._fetch_projected_match_detail(game_id),
                name=f"bridge-match-detail-{game_id}",
            )
            self._match_detail_inflight[game_id] = task
        try:
            return await task
        finally:
            if task.done() and self._match_detail_inflight.get(game_id) is task:
                self._match_detail_inflight.pop(game_id, None)

    async def _fetch_projected_match_detail(self, game_id: int) -> dict[str, Any]:
        started_at = time.perf_counter()
        g = await api.game_detail(self._client, game_id)
        fetch_ms = self._perf_ms(started_at)
        project_started_at = time.perf_counter()
        projected = self._project_match_detail(g)
        project_ms = self._perf_ms(project_started_at)
        self._cache_match_detail(game_id, projected)
        log.info(
            "perf match_detail game_id=%s participants=%s fetch_ms=%s project_ms=%s total_ms=%s",
            game_id,
            len(projected.get("participants") or []),
            fetch_ms,
            project_ms,
            self._perf_ms(started_at),
        )
        return projected

    def _cache_match_detail(self, game_id: int, detail: dict[str, Any]) -> None:
        self._match_detail_cache[game_id] = detail
        if game_id in self._match_detail_order:
            self._match_detail_order.remove(game_id)
        self._match_detail_order.append(game_id)
        while len(self._match_detail_order) > MATCH_DETAIL_CACHE_LIMIT:
            old = self._match_detail_order.pop(0)
            self._match_detail_cache.pop(old, None)

    def _preload_match_detail_icons(
        self,
        detail: dict[str, Any],
        *,
        priority: bool = False,
        clear_pending: bool = False,
    ) -> None:
        if self._image_provider is None or not hasattr(self._image_provider, "preload"):
            return

        core_paths: list[str] = []
        item_paths: list[str] = []
        seen: set[str] = set()
        uses_augments = detail.get("usesAugments") is True

        def add(bucket: list[str], path: str | None) -> None:
            if not path or not path.startswith("/lol-game-data/assets/") or path in seen:
                return
            seen.add(path)
            bucket.append(path)

        for p in detail.get("participants") or []:
            if not isinstance(p, dict):
                continue
            champion = self._champions_by_id.get(str(p.get("championId") or 0))
            add(core_paths, (champion or {}).get("squarePortraitPath") or (champion or {}).get("iconPath"))
            for sid in (p.get("spell1Id"), p.get("spell2Id")):
                add(core_paths, (self._spells_by_id.get(str(sid)) or {}).get("iconPath"))
            if uses_augments:
                for aid in p.get("augments") or []:
                    add(core_paths, (self._augments_by_id.get(str(aid)) or {}).get("iconPath"))
            else:
                perks = p.get("perks") or []
                add(core_paths, (self._perks_by_id.get(str(perks[0] if perks else 0)) or {}).get("iconPath"))
                add(core_paths, (self._perk_styles_by_id.get(str(p.get("subStyleId") or 0)) or {}).get("iconPath"))
            for iid in p.get("items") or []:
                add(item_paths, (self._items_by_id.get(str(iid)) or {}).get("iconPath"))

        try:
            self._image_provider.preload(
                core_paths + item_paths,
                priority=priority,
                clear_pending=clear_pending,
            )
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
                "tagLine": pl.get("tagLine") or "",
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

    # ----- hextech loot / replays -----

    async def _refresh_hextech(self) -> None:
        if not self._client.is_connected():
            return
        try:
            loot = await api.player_loot(self._client)
        except Exception as e:  # noqa: BLE001
            log.warning("player_loot failed: %s", e)
            self.errorOccurred.emit(str(e))
            return
        self._hextech = self._project_hextech(loot)
        self.hextechChanged.emit()

    @staticmethod
    def _project_hextech(loot: list[dict]) -> dict:
        """Collapse ``/lol-loot/v1/player-loot`` into the shape the UI needs.

        LCU returns every token, currency, shard, and chest in a flat list
        keyed by ``type`` (``CHEST``, ``CHAMPION_RENTAL``, ``SKIN_RENTAL``,
        ``CURRENCY``, ...). The client's own crafting UI does the equivalent
        bucketing client-side — there's no server-side summary endpoint.
        """
        wallet = {"blue": 0, "orange": 0, "mythic": 0, "keys": 0, "keyFragments": 0}
        chests: list[dict] = []
        shards: list[dict] = []
        for item in loot or []:
            if not isinstance(item, dict):
                continue
            t = item.get("type") or ""
            name = item.get("lootName") or ""
            count = int(item.get("count") or 0)
            if count <= 0:
                continue
            if t == "CURRENCY":
                if name == "CURRENCY_champion":
                    wallet["blue"] = count
                elif name == "CURRENCY_cosmetic":
                    wallet["orange"] = count
                elif name == "CURRENCY_mythic":
                    wallet["mythic"] = count
            elif name == "MATERIAL_key":
                wallet["keys"] = count
            elif name == "MATERIAL_key_fragment":
                wallet["keyFragments"] = count
            elif t == "CHEST":
                chests.append({
                    "lootId": item.get("lootId") or name,
                    "lootName": name,
                    "displayName": item.get("itemDesc") or name,
                    "count": count,
                })
            elif t in ("CHAMPION_RENTAL", "SKIN_RENTAL"):
                shards.append({
                    "lootId": item.get("lootId") or "",
                    "lootName": name,
                    "type": t,
                    "refId": item.get("refId") or item.get("storeItemId") or 0,
                    "count": count,
                    # `redundant` is LCU's own flag — true when the player already
                    # owns the underlying permanent, so disenchanting is lossless.
                    "redundant": bool(item.get("redundant")),
                    "disenchantValue": int(item.get("disenchantValue") or 0),
                    "displayName": item.get("itemDesc") or name,
                })

        redundant = [s for s in shards if s["redundant"]]
        redundant_be = sum(s["disenchantValue"] * s["count"] for s in redundant)
        return {
            "wallet": wallet,
            "chests": chests,
            "shards": shards,
            "redundantShards": redundant,
            "redundantBe": redundant_be,
            "totalChests": sum(c["count"] for c in chests),
            "totalShards": sum(s["count"] for s in shards),
        }

    async def _tidy_hextech(self, *, open_chests: bool, disenchant: bool) -> None:
        """Open every openable chest and/or disenchant every redundant shard.

        Each recipe call is isolated in try/except — one bad recipe name
        (e.g. an event chest whose ``_OPEN`` variant was renamed) won't stop
        the rest of the batch. Errors go to debug logs only.
        """
        if not self._client.is_connected():
            return

        try:
            loot = await api.player_loot(self._client)
        except Exception as e:  # noqa: BLE001
            self.errorOccurred.emit(str(e))
            return

        opened = 0
        disenchanted = 0
        be_gained = 0

        if open_chests:
            for item in loot or []:
                if not isinstance(item, dict) or item.get("type") != "CHEST":
                    continue
                name = item.get("lootName") or ""
                count = int(item.get("count") or 0)
                if count <= 0 or not name:
                    continue
                # Convention: chest recipes are ``{lootName}_OPEN``. The input
                # slot takes the lootName itself — chests are fungible so their
                # lootId == lootName. Unknown recipes yield 404; we skip them.
                recipe = f"{name}_OPEN"
                try:
                    await api.loot_craft(self._client, recipe, [name], repeat=count)
                    opened += count
                except Exception as e:  # noqa: BLE001
                    log.debug("open %s skipped: %s", name, e)

        if disenchant:
            # Shards are disenchanted by lootId (unique per shard instance),
            # through the generic ``CHAMPION_RENTAL_disenchant`` / ``SKIN_RENTAL_disenchant``
            # recipes.
            for item in loot or []:
                if not isinstance(item, dict):
                    continue
                t = item.get("type")
                if t not in ("CHAMPION_RENTAL", "SKIN_RENTAL"):
                    continue
                if not item.get("redundant"):
                    continue
                loot_id = item.get("lootId") or ""
                count = int(item.get("count") or 0)
                value = int(item.get("disenchantValue") or 0)
                if count <= 0 or not loot_id:
                    continue
                recipe = f"{t}_disenchant"
                try:
                    await api.loot_craft(self._client, recipe, [loot_id], repeat=count)
                    disenchanted += count
                    be_gained += value * count
                except Exception as e:  # noqa: BLE001
                    log.debug("disenchant %s skipped: %s", loot_id, e)

        # Always refresh so the summary counts reflect the new state.
        try:
            loot = await api.player_loot(self._client)
            self._hextech = self._project_hextech(loot)
            self.hextechChanged.emit()
        except Exception as e:  # noqa: BLE001
            log.debug("hextech post-refresh failed: %s", e)

        parts: list[str] = []
        if opened:
            parts.append(f"开启 {opened} 个宝箱")
        if disenchanted:
            parts.append(f"分解 {disenchanted} 个碎片  +{be_gained} BE")
        if parts:
            self.notify.emit("赫克斯科技", " · ".join(parts))
        else:
            self.notify.emit("赫克斯科技", "无可整理的内容")

    # ----- AI match analysis -----

    def _cancel_ai_task(self) -> None:
        task = self._ai_task
        self._ai_task = None
        if task is not None and not task.done():
            task.cancel()

    async def _analyze_match(self, game_id: int, mode: str, target_puuid: str) -> None:
        ai = self._settings.ai
        if not ai.enabled or not ai.api_key or not ai.base_url or not ai.model:
            self.aiAnalysisError.emit("请先在“设置”里启用 AI 并填写 base_url / api_key / model")
            return
        if game_id <= 0:
            self.aiAnalysisError.emit("无效的对局 ID")
            return
        mode = mode if mode in ("overview", "player") else "overview"
        if mode == "player" and not target_puuid:
            self.aiAnalysisError.emit("单人复盘需要指定玩家")
            return

        cache_key = (game_id, mode, target_puuid if mode == "player" else "")
        cached = self._ai_cache.get(cache_key)

        self.aiAnalysisStarted.emit(str(game_id), mode)
        if cached is not None:
            # Replay previously-streamed content as a single chunk. Cheaper
            # than re-billing tokens and matches how rank-analysis' session
            # cache behaves.
            self.aiAnalysisChunk.emit(cached)
            self.aiAnalysisDone.emit()
            return

        try:
            detail = await self._get_projected_match_detail(game_id)
        except asyncio.CancelledError:
            raise
        except Exception as e:  # noqa: BLE001
            self.aiAnalysisError.emit(f"加载对局失败: {e}")
            return

        snapshot = self._build_match_snapshot(detail, target_puuid)
        if mode == "player":
            target = next(
                (p for p in snapshot["players"] if p.get("puuid") == target_puuid),
                None,
            )
            if target is None:
                self.aiAnalysisError.emit("该玩家不在这场对局中")
                return
            user_prompt = self._prompt_match_player(snapshot, target)
        else:
            user_prompt = self._prompt_match_overview(snapshot)

        try:
            content = await self._stream_openai_compat(
                system_prompt=AI_SYSTEM_PROMPT,
                user_prompt=user_prompt,
                on_chunk=self.aiAnalysisChunk.emit,
            )
            self._ai_cache[cache_key] = content
            self.aiAnalysisDone.emit()
        except asyncio.CancelledError:
            # User closed the dialog or started a new analysis — swallow,
            # don't emit done/error; the UI has already reset.
            raise
        except Exception as e:  # noqa: BLE001
            log.warning("AI analysis failed: %s", e)
            self.aiAnalysisError.emit(f"AI 请求失败: {e}")

    async def _stream_openai_compat(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        on_chunk,
    ) -> str:
        """Stream an OpenAI-compatible ``chat/completions`` response.

        Works against OpenAI, DeepSeek, OpenRouter, One-API, local vLLM /
        LM Studio — anything that honours the reference SSE format. Returns
        the aggregated assistant content once the stream terminates so the
        caller can cache it.
        """
        ai = self._settings.ai
        url = ai.base_url.rstrip("/") + "/chat/completions"
        body = {
            "model": ai.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "stream": True,
            "temperature": 0.3,
        }
        headers = {
            "Authorization": f"Bearer {ai.api_key}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        }

        buffer: list[str] = []
        # Long timeout on read/stream — completions over slow models can take
        # a while; short connect timeout catches typos in base_url fast.
        timeout = httpx.Timeout(connect=10.0, read=120.0, write=30.0, pool=10.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            async with client.stream("POST", url, headers=headers, json=body) as resp:
                if resp.status_code != 200:
                    err_text = await resp.aread()
                    try:
                        err_json = json.loads(err_text)
                        msg = (err_json.get("error") or {}).get("message") or err_text.decode("utf-8", "replace")
                    except Exception:  # noqa: BLE001
                        msg = err_text.decode("utf-8", "replace") if err_text else f"HTTP {resp.status_code}"
                    raise RuntimeError(f"{resp.status_code}: {msg}")
                async for line in resp.aiter_lines():
                    if not line or not line.startswith("data:"):
                        continue
                    payload = line[5:].strip()
                    if payload == "[DONE]":
                        break
                    try:
                        data = json.loads(payload)
                    except json.JSONDecodeError:
                        continue
                    try:
                        delta = data["choices"][0].get("delta") or {}
                    except (KeyError, IndexError, TypeError):
                        continue
                    piece = delta.get("content") or ""
                    if piece:
                        buffer.append(piece)
                        on_chunk(piece)
        return "".join(buffer)

    def _build_match_snapshot(self, detail: dict, target_puuid: str = "") -> dict:
        """Dense, LLM-friendly projection of a match. Adds the shares /
        participation percentages that a model can't reliably compute.
        """
        participants = detail.get("participants") or []
        team_stats = detail.get("teamStats") or []
        my_puuid = (self._summoner or {}).get("puuid") or ""

        team_totals: dict[int, dict[str, int]] = {}
        for p in participants:
            tid = int(p.get("teamId") or 0)
            agg = team_totals.setdefault(tid, {"damage": 0, "taken": 0, "gold": 0, "kills": 0})
            agg["damage"] += int(p.get("damage") or 0)
            agg["taken"] += int(p.get("damageTaken") or 0)
            agg["gold"] += int(p.get("gold") or 0)
            agg["kills"] += int(p.get("kills") or 0)

        def pct(v: int, total: int) -> float:
            if total <= 0:
                return 0.0
            return round(v / total * 100, 1)

        players = []
        for p in participants:
            tid = int(p.get("teamId") or 0)
            totals = team_totals.get(tid) or {"damage": 0, "taken": 0, "gold": 0, "kills": 0}
            cid = str(p.get("championId") or 0)
            champion_name = (self._champions_by_id.get(cid) or {}).get("name") or f"champion_{cid}"
            puuid = p.get("puuid") or ""
            kills = int(p.get("kills") or 0)
            deaths = int(p.get("deaths") or 0)
            assists = int(p.get("assists") or 0)
            players.append({
                "participantId": p.get("participantId"),
                "teamId": tid,
                "name": p.get("summonerName") or "",
                "puuid": puuid,
                "champion": champion_name,
                "isMe": bool(my_puuid) and puuid == my_puuid,
                "isFocus": bool(target_puuid) and puuid == target_puuid,
                "win": bool(p.get("win")),
                "kda": round((kills + assists) / max(1, deaths), 2),
                "kills": kills,
                "deaths": deaths,
                "assists": assists,
                "gold": int(p.get("gold") or 0),
                "cs": int(p.get("cs") or 0),
                "damage": int(p.get("damage") or 0),
                "taken": int(p.get("damageTaken") or 0),
                "damageShare": pct(int(p.get("damage") or 0), totals["damage"]),
                "damageTakenShare": pct(int(p.get("damageTaken") or 0), totals["taken"]),
                "goldShare": pct(int(p.get("gold") or 0), totals["gold"]),
                "killParticipation": pct(kills + assists, max(1, totals["kills"])),
                "vision": int(p.get("vision") or 0),
                "wardsPlaced": int(p.get("wardsPlaced") or 0),
                "wardsKilled": int(p.get("wardsKilled") or 0),
                "perks": {
                    "primary": p.get("primaryStyleId") or 0,
                    "subStyle": p.get("subStyleId") or 0,
                },
                "augments": [a for a in (p.get("augments") or []) if a and a > 0],
                "position": p.get("position") or "",
                "score": p.get("score") or 0,
                "tags": list(p.get("tags") or []),
            })

        teams: list[dict] = []
        for t in team_stats:
            tid = int(t.get("teamId") or 0)
            team_players = [p for p in players if p["teamId"] == tid]
            teams.append({
                "teamId": tid,
                "result": "胜方" if t.get("win") else "败方",
                "totalKills": sum(p["kills"] for p in team_players),
                "totalDeaths": sum(p["deaths"] for p in team_players),
                "totalAssists": sum(p["assists"] for p in team_players),
                "totalDamage": sum(p["damage"] for p in team_players),
                "totalGold": sum(p["gold"] for p in team_players),
                "towerKills": int(t.get("towerKills") or 0),
                "dragonKills": int(t.get("dragonKills") or 0),
                "baronKills": int(t.get("baronKills") or 0),
                "firstBlood": bool(t.get("firstBlood")),
            })

        queue_id = detail.get("queueId")
        queue_entry = self._queues_by_id.get(str(queue_id)) or {}
        return {
            "gameId": detail.get("gameId"),
            "queueId": queue_id,
            "queueName": queue_entry.get("name") or detail.get("gameMode") or "",
            "gameMode": detail.get("gameMode"),
            "durationSeconds": int(detail.get("gameDuration") or 0),
            "augmentMode": bool(detail.get("usesAugments")),
            "players": players,
            "teams": teams,
        }

    @staticmethod
    def _prompt_match_overview(snapshot: dict) -> str:
        duration = int(snapshot.get("durationSeconds") or 0)
        mins = duration // 60
        secs = duration % 60
        queue_name = snapshot.get("queueName", "")
        queue_id = snapshot.get("queueId", "")
        game_mode = snapshot.get("gameMode", "")
        augment = "海克斯/强化局，优先看强化搭配" if snapshot.get("augmentMode") else "常规局，优先看符文与基础数据"
        snap_json = json.dumps(snapshot, ensure_ascii=False, indent=2)
        return f"""你是 LOL 单场复盘分析师。请只基于下面这场比赛的数据做结论，不要编造对线细节、团战时间点或装备效果。

【任务目标】
请你判断这场比赛里：
1. 谁最尽力
2. 谁最犯罪
3. 谁是被对位或被局势打爆的
4. 谁属于被队友连累
5. 胜负的核心原因是什么

【标签定义】
- 缚地灵：整场几乎不参与团战、只待在自己线上/野区刷资源；特征是低参团率、低助攻、低伤害占比，但补刀/经济未必低。

【硬性要求】
- 每个判断都必须引用至少 2 个具体数据证据（KDA、伤害占比、承伤占比、经济占比、参团率、推塔、死亡数）。
- 不要因为输了就默认某个人犯罪，也不要因为赢了就默认某个人尽力。
- “被连累”只给在败方里数据明显完成职责、但团队整体明显失衡的人。
- “被爆”优先看高死亡、低经济占比、低输出占比、低参团，或同队里明显拖后腿。
- 允许结论为“无人明显犯罪”或“多人都尽力”。
- 语气直接，但不要人身攻击。

【负面标签申辩机制】
判定某玩家为负面标签时，必须同时考虑以下申辩理由：
1. 位置因素：下路双人路天然容易被针对、上路长线容易被军训、打野被反野可能是因线上没线权。
2. 补位因素：若该玩家明显在玩非主玩位置，失误率高应给予理解。
3. 被针对因素：若死亡集中在前期、敌方打野/中单击杀中该玩家占比过高，说明被重点照顾。
4. 团队因素：若某路队友崩盘导致自己被连带。
5. 英雄克制：若存在明显的英雄劣势对线（短手打长手），KDA 差应部分归因于 BP。

【申辩权重】
- 主玩位置+非明显被针对：负面标签有效
- 补位/被明显针对/团队连累：降级为“情有可原”或改判为“被连累”
- 无法判断时优先选择较温和的表述

【对局信息】
模式：{queue_name}
队列ID：{queue_id}
游戏模式：{game_mode}
时长：{mins}分{secs}秒
构筑类型：{augment}

【全场数据快照】
{snap_json}

【输出格式】
请严格按这个结构输出：

## 总体结论
- 先用 2-3 句话总结胜负原因。

## 尽力榜
- 只列 1-2 人。
- 每人一行：名字 + 判定 + 证据。

## 犯罪榜
- 只列 1-2 人。
- 如果没有明显犯罪，明确写“本局无人明显犯罪”。

## 被爆点评
- 点出 1-2 个最明显的崩点。

## 被连累点评
- 如果有人属于被连累，说明他做到了什么、却被哪些队友问题拖垮。

## 关键证据
- 用 3-5 条 bullet 收尾，每条都带数字。"""

    @staticmethod
    def _prompt_match_player(snapshot: dict, target: dict) -> str:
        duration = int(snapshot.get("durationSeconds") or 0)
        mins = duration // 60
        secs = duration % 60
        queue_name = snapshot.get("queueName", "")
        augment = "海克斯/强化局" if snapshot.get("augmentMode") else "常规局"
        same_team = [p for p in snapshot["players"] if p["teamId"] == target["teamId"]]
        enemy = [p for p in snapshot["players"] if p["teamId"] != target["teamId"]]
        target_json = json.dumps(target, ensure_ascii=False, indent=2)
        same_json = json.dumps(same_team, ensure_ascii=False, indent=2)
        enemy_json = json.dumps(enemy, ensure_ascii=False, indent=2)
        return f"""你是 LOL 单人复盘分析师。请围绕指定玩家，判断他这局到底属于“尽力 / 犯罪 / 被爆 / 被连累 / 缚地灵 / 正常发挥”中的哪一类。

【标签定义】
- 缚地灵：整场几乎不参与团战、只待在自己线上/野区刷资源；特征是低参团率（低于团队平均 15% 以上）、低助攻、低伤害占比，但补刀/经济未必低。常见于“单机”型上单或刷子型打野。

【硬性要求】
- 必须先给出唯一主标签。
- 所有结论必须基于数据，至少引用 3 个具体指标。
- 要区分“自己打得差”和“队友整体拖垮”这两种情况。
- 如果是海克斯/强化模式，请结合强化数量和构筑方向判断是否成型。
- 不要空泛鼓励，不要写成攻略。

【负面标签申辩机制】
判定为“犯罪”“被爆”或“缚地灵”时，必须评估以下申辩：
1. 位置因素（下路易被 4 包 2、上路长线军训、打野被反野）。
2. 补位因素（非主玩位置应给予折扣）。
3. 被针对因素（死亡集中前期、敌方击杀占比集中在该玩家）。
4. 团队连累（某路队友崩盘导致被连带）。
5. 英雄克制（短手打长手、阵容缺保护/开团）。

【申辩判定】
- 满足 2 项以上申辩：改判为“被连累”或“情有可原的正常发挥”。
- 满足 1 项：负面标签保留，但备注申辩原因。
- 不满足：负面标签成立，给出直接批评。

【对局信息】
模式：{queue_name}
时长：{mins}分{secs}秒
构筑类型：{augment}

【目标玩家】
{target_json}

【同队玩家】
{same_json}

【敌方玩家】
{enemy_json}

【输出格式】
请严格按这个结构输出：

## 玩家判定
- 先写：名字 + 主标签（负面标签且通过申辩时，写“XXX（情有可原）”）。

## 为什么这么判
- 用 3-4 条 bullet 解释，必须带数字。

## 申辩评估（仅负面标签需要）
- 逐条评估 5 类申辩理由，写明：是否成立 + 简要依据。

## 他是怎么输/赢的
- 说明是自己打出来的、被针对的、还是被队友带飞/拖累。若有申辩理由成立，重点说明。

## 一句话锐评
- 允许直接，但不要辱骂。"""

    async def _watch_replay(self, game_id: int) -> None:
        if not self._client.is_connected() or game_id <= 0:
            return
        # Pre-flight download is harmless if the .rofl is already cached —
        # LCU returns an ack either way. Only the `watch` call is load-bearing.
        try:
            await api.replay_download(self._client, game_id)
        except Exception as e:  # noqa: BLE001
            log.debug("replay download pre-flight: %s", e)
        try:
            await api.replay_watch(self._client, game_id)
            self.notify.emit("回放", f"正在启动对局 #{game_id} 的回放")
        except Exception as e:  # noqa: BLE001
            # Most failures here mean the replay isn't available (too old,
            # different patch, custom game without recording).
            self.errorOccurred.emit(f"回放不可用: {e}")

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
        started_at = time.perf_counter()
        try:
            snapshot_started_at = time.perf_counter()
            snap: ChampSelectSnapshot = await snapshot_session(self._client, session)
            snapshot_ms = self._perf_ms(snapshot_started_at)
            data = snap.to_dict()
            # Compute pre-groups across all visible players.
            all_players = [*data.get("myTeam", []), *data.get("theirTeam", [])]
            # Stamp each recent match with the player's team so the detector can
            # recognise "same team in past games".
            for p in all_players:
                for m in p.get("recent") or []:
                    m["teamId"] = p.get("team_id") or 0
            try:
                pregroup_started_at = time.perf_counter()
                groups = detect_pregroups(all_players)
                pregroup_ms = self._perf_ms(pregroup_started_at)
                data["preGroups"] = [
                    {"puuids": g.puuids, "gamesSameTeam": g.games_same_team, "color": g.color}
                    for g in groups
                ]
            except Exception as e:  # noqa: BLE001
                pregroup_ms = 0
                log.warning("pregroup detect failed: %s", e)
                data["preGroups"] = []
            self._champ_select = data
            self.champSelectChanged.emit()
            self._spawn(self._maybe_send_team_winrates(data), name="bridge-team-winrates")
            log.info(
                "perf champ_select game_id=%s players=%s groups=%s snapshot_ms=%s "
                "pregroup_ms=%s total_ms=%s",
                data.get("gameId") or 0,
                len(all_players),
                len(data.get("preGroups") or []),
                snapshot_ms,
                pregroup_ms,
                self._perf_ms(started_at),
            )
        except Exception as e:  # noqa: BLE001
            log.exception("champ select snapshot failed: %s", e)

    async def _maybe_send_team_winrates(self, data: dict[str, Any]) -> None:
        log.info(
            "team-winrate check: enabled=%s connected=%s myTeam=%s",
            self._settings.auto_actions.send_team_winrate,
            self._client.is_connected(),
            len(data.get("myTeam") or []),
        )
        if not self._settings.auto_actions.send_team_winrate:
            return
        if not self._client.is_connected():
            log.info("team-winrate skip: lcu not connected")
            return
        my_team_all = [p for p in (data.get("myTeam") or []) if isinstance(p, dict)]
        # Fingerprint covers the whole composition (including me) so we resend
        # if anyone swaps. gameId is 0 in champ select on some patches.
        puuids = sorted(p.get("puuid") or "" for p in my_team_all if p.get("puuid"))
        if not puuids:
            log.info(
                "team-winrate skip: no puuids yet (myTeam=%s)",
                len(my_team_all),
            )
            return
        fingerprint = "|".join(puuids)
        if fingerprint in self._winrate_sent_fingerprints:
            return
        # Sort: me first, then alphabetical for stability.
        my_team_all.sort(key=lambda p: (0 if (p.get("is_me") or p.get("isMe")) else 1,
                                        p.get("display_name") or ""))
        lines = self._format_winrate_lines(my_team_all)
        if not lines:
            return
        message = "我方近期胜率：\n" + "\n".join(lines)
        try:
            conversations = await api.chat_conversations(self._client)
            # Surface what conversation types are actually present so we can
            # match a new shape if Riot ever renames "championSelect".
            types_seen = [
                (c.get("id"), c.get("type"))
                for c in conversations or []
                if isinstance(c, dict)
            ]
            conversation = next(
                (
                    c for c in conversations or []
                    if isinstance(c, dict)
                    and (
                        str(c.get("type", "")).lower() in ("championselect", "champion-select")
                        or "champion-select" in str(c.get("id", "")).lower()
                        or "champ-select" in str(c.get("id", "")).lower()
                    )
                ),
                None,
            )
            if not conversation:
                log.info("team-winrate: no champ-select conversation yet, types=%s", types_seen)
                return
            conversation_id = conversation.get("id") or ""
            if not conversation_id:
                log.info("team-winrate: conversation missing id, conv=%s", conversation)
                return
            log.info("team-winrate sending via %s msg=%s", conversation_id, message)
            await api.send_chat_message(self._client, str(conversation_id), message)
            self._winrate_sent_fingerprints.add(fingerprint)
            self.notify.emit("选人胜率", "已发送队友最近战绩胜率")
        except Exception as e:  # noqa: BLE001
            log.warning("send team winrates failed: %s", e)

    async def _send_all_winrates(self) -> None:
        if not self._client.is_connected():
            self.notify.emit("发送胜率", "未连接客户端")
            return
        # Prefer the live champ-select snapshot (both teams visible). Fall
        # back to the frozen in-game snapshot so the user can still trigger
        # this once the game has started.
        snapshot = self._champ_select or self._in_game or {}
        my_team = [p for p in (snapshot.get("myTeam") or []) if isinstance(p, dict)]
        their_team = [p for p in (snapshot.get("theirTeam") or []) if isinstance(p, dict)]
        if not my_team and not their_team:
            self.notify.emit("发送胜率", "未在选人/对局中，没有可发送的玩家")
            return
        # me first within my team, alphabetical otherwise
        my_team.sort(key=lambda p: (0 if (p.get("is_me") or p.get("isMe")) else 1,
                                    p.get("display_name") or ""))
        ally_lines = self._format_winrate_lines(my_team)
        enemy_lines = self._format_winrate_lines(their_team)
        if not ally_lines and not enemy_lines:
            self.notify.emit("发送胜率", "暂无可统计的对手/队友数据")
            return
        try:
            conversations = await api.chat_conversations(self._client)
            conversation = next(
                (
                    c for c in conversations or []
                    if isinstance(c, dict)
                    and (
                        str(c.get("type", "")).lower() in ("championselect", "champion-select")
                        or "champion-select" in str(c.get("id", "")).lower()
                        or "champ-select" in str(c.get("id", "")).lower()
                    )
                ),
                None,
            )
            if not conversation:
                self.notify.emit("发送胜率", "未找到选人聊天会话")
                return
            conversation_id = str(conversation.get("id") or "")
            if not conversation_id:
                self.notify.emit("发送胜率", "聊天会话缺少 id")
                return
            sent = 0
            if ally_lines:
                await api.send_chat_message(
                    self._client, conversation_id, "我方近期胜率：\n" + "\n".join(ally_lines)
                )
                sent += 1
            if enemy_lines:
                await api.send_chat_message(
                    self._client, conversation_id, "敌方近期胜率：\n" + "\n".join(enemy_lines)
                )
                sent += 1
            self.notify.emit("发送胜率", f"已发送 {sent} 条")
        except Exception as e:  # noqa: BLE001
            log.warning("send all winrates failed: %s", e)
            self.notify.emit("发送胜率", f"失败: {e}")

    @staticmethod
    def _format_winrate_lines(players: list[dict]) -> list[str]:
        out: list[str] = []
        for p in players:
            name = p.get("display_name") or p.get("displayName") or "?"
            if name == "???":
                continue
            rate = p.get("recent_win_rate", p.get("recentWinRate", 0))
            recent = p.get("recent") or []
            if recent:
                wins = sum(1 for m in recent if m.get("win"))
                line = (
                    f"{name} - 近{len(recent)}场 "
                    f"{round(float(rate) * 100)}% ({wins}胜{len(recent) - wins}负)"
                )
            else:
                line = f"{name} - 无近期战绩"
            out.append(line)
        return out

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
        started_at = time.perf_counter()
        fetch_ms = 0
        aggregate_ms = 0
        try:
            puuid: str = (self._summoner or {}).get("puuid") or ""
            if not puuid:
                me = await api.current_summoner(self._client)
                puuid = me["puuid"]
            # Match history endpoint paginates at 20 per request — fetch in chunks.
            games: list[dict[str, Any]] = []
            fetch_started_at = time.perf_counter()
            for begin in range(0, count, 20):
                end = min(begin + 19, count - 1)
                chunk = await api.match_history(self._client, puuid, begin, end)
                batch = (chunk.get("games", {}).get("games") or [])
                if not batch:
                    break
                games.extend(batch)
                if len(batch) < (end - begin + 1):
                    break
            fetch_ms = self._perf_ms(fetch_started_at)
            aggregate_started_at = time.perf_counter()
            self._champion_pool = [s.to_dict() for s in aggregate_champions(games)]
            aggregate_ms = self._perf_ms(aggregate_started_at)
            self.championPoolChanged.emit()
            log.info(
                "perf champion_pool requested=%s games=%s champions=%s fetch_ms=%s "
                "aggregate_ms=%s total_ms=%s",
                count,
                len(games),
                len(self._champion_pool),
                fetch_ms,
                aggregate_ms,
                self._perf_ms(started_at),
            )
        except Exception as e:  # noqa: BLE001
            log.warning("champion pool failed: %s", e)
            self.errorOccurred.emit(str(e))

    async def _load_teammates(self, count: int) -> None:
        if not self._client.is_connected():
            return
        started_at = time.perf_counter()
        history_ms = 0
        details_ms = 0
        aggregate_ms = 0
        profile_ms = 0
        try:
            puuid: str = (self._summoner or {}).get("puuid") or ""
            if not puuid:
                me = await api.current_summoner(self._client)
                puuid = me["puuid"]
            games: list[dict[str, Any]] = []
            history_started_at = time.perf_counter()
            for begin in range(0, count, 20):
                end = min(begin + 19, count - 1)
                chunk = await api.match_history(self._client, puuid, begin, end)
                batch = (chunk.get("games", {}).get("games") or [])
                if not batch:
                    break
                games.extend(batch)
                if len(batch) < (end - begin + 1):
                    break
            history_ms = self._perf_ms(history_started_at)
            game_ids = [g.get("gameId") for g in games if g.get("gameId")]
            # Fetch details with bounded concurrency.
            sem = asyncio.Semaphore(5)

            async def one(gid: int) -> dict | None:
                async with sem:
                    try:
                        return await api.game_detail(self._client, gid)
                    except Exception:  # noqa: BLE001
                        return None

            details_started_at = time.perf_counter()
            details = await asyncio.gather(*(one(gid) for gid in game_ids))
            details = [d for d in details if d]
            details_ms = self._perf_ms(details_started_at)
            aggregate_started_at = time.perf_counter()
            teammates = aggregate_teammates(details, puuid)
            aggregate_ms = self._perf_ms(aggregate_started_at)
            if teammates:
                profile_started_at = time.perf_counter()
                summary_by_puuid: dict[str, dict[str, Any]] = {}
                teammate_puuids = [t.puuid for t in teammates if t.puuid]
                for start in range(0, len(teammate_puuids), 50):
                    batch = teammate_puuids[start:start + 50]
                    try:
                        summaries = await api.summoners_by_puuids(self._client, batch)
                    except Exception as e:  # noqa: BLE001
                        log.debug("teammate profile resolve failed: %s", e)
                        continue
                    if isinstance(summaries, dict):
                        summaries = summaries.get("summoners") or []
                    for summary in summaries or []:
                        if not isinstance(summary, dict):
                            continue
                        resolved_puuid = summary.get("puuid") or ""
                        if resolved_puuid:
                            summary_by_puuid[resolved_puuid] = summary
                missing_puuids = [
                    teammate.puuid for teammate in teammates
                    if teammate.puuid and teammate.puuid not in summary_by_puuid
                ]
                if missing_puuids:
                    sem_profile = asyncio.Semaphore(5)

                    async def resolve_one(profile_puuid: str) -> tuple[str, dict[str, Any] | None]:
                        async with sem_profile:
                            try:
                                data = await api.summoner_by_puuid(self._client, profile_puuid)
                                return profile_puuid, data if isinstance(data, dict) else None
                            except Exception as e:  # noqa: BLE001
                                log.debug("teammate profile resolve by puuid failed puuid=%s: %s", profile_puuid, e)
                                return profile_puuid, None

                    resolved_profiles = await asyncio.gather(
                        *(resolve_one(profile_puuid) for profile_puuid in missing_puuids)
                    )
                    for resolved_puuid, summary in resolved_profiles:
                        if summary:
                            summary_by_puuid[resolved_puuid] = summary
                profile_ms = self._perf_ms(profile_started_at)
                for teammate in teammates:
                    summary = summary_by_puuid.get(teammate.puuid) or {}
                    teammate.profile_icon_id = int(summary.get("profileIconId") or 0)
                    teammate.summoner_level = int(summary.get("summonerLevel") or 0)
                    game_name = (summary.get("gameName") or summary.get("displayName") or "").strip()
                    tag_line = (summary.get("tagLine") or "").strip()
                    if game_name:
                        teammate.display_name = f"{game_name}#{tag_line}" if tag_line else game_name
            self._teammates = [t.to_dict() for t in teammates]
            self.teammatesChanged.emit()
            log.info(
                "perf teammates requested=%s games=%s details=%s teammates=%s "
                "history_ms=%s details_ms=%s aggregate_ms=%s profile_ms=%s total_ms=%s",
                count,
                len(games),
                len(details),
                len(self._teammates),
                history_ms,
                details_ms,
                aggregate_ms,
                profile_ms,
                self._perf_ms(started_at),
            )
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

        self._game_data_rev += 1
        self.gameDataChanged.emit()
        self.championsChanged.emit()

    def _resolve_opgg_alias(self, query: str) -> str | None:
        """Map a user-entered champion string (中文 / English / partial) to
        the English alias OP.GG uses in its URL slugs. Returns None when no
        confident match is found — caller will fall back to the raw input."""
        if not query:
            return None
        q = query.strip().lower()
        if not q:
            return None
        # 1) exact match on alias — already in the right form
        for c in self._champions:
            alias = (c.get("alias") or "").lower()
            if alias == q:
                return c.get("alias")
        # 2) exact match on display name (Chinese on TENCENT)
        for c in self._champions:
            if (c.get("name") or "") == query.strip():
                return c.get("alias") or c.get("name")
        # 3) substring match — name or alias contains the query
        for c in self._champions:
            name = c.get("name") or ""
            alias = (c.get("alias") or "").lower()
            if q in alias or q in name.lower():
                return c.get("alias") or c.get("name")
        return None

    async def _load_opgg(self, champion: str, mode: str, position: str) -> None:
        try:
            # OP.GG slugs are English aliases ("yasuo"), so a Chinese name like
            # "疾风剑豪" must be mapped through the champion table first.
            lookup_name = self._resolve_opgg_alias(champion) or champion
            build = await opgg.fetch_build(
                lookup_name,
                mode=mode or self._settings.opgg.mode,
                position=position or None,
                tier=self._settings.opgg.tier,
                region=self._settings.opgg.region,
            )
            # Preserve the user-facing name on the result so the QML header
            # shows "疾风剑豪" rather than "Yasuo" after a successful fetch.
            if champion and champion != lookup_name:
                build.champion = champion
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
