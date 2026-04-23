"""QQuickImageProvider that serves LCU asset paths over the local HTTPS socket.

QML binds ``Image.source`` to ``image://lcu/lol-game-data/assets/...``. Qt calls
``requestPixmap`` on a non-GUI thread, so a sync HTTP client here is safe.
Localhost round-trips are ~5 ms each — vastly faster than CDragon for the
100+ icons a match detail page needs.

Falls back to returning an empty pixmap if credentials aren't set; callers
should bind to ``Lcu.connected`` and pick a CDragon URL in that case.
"""
from __future__ import annotations

import threading
from typing import Optional

import httpx
from PySide6.QtCore import QSize
from PySide6.QtGui import QImage, QPixmap
from PySide6.QtQuick import QQuickImageProvider

from app.common.logger import get_logger

log = get_logger(__name__)

# Match detail pages can enqueue 100+ localhost asset fetches at once. Keep a
# slightly wider pool so visible icons don't trickle in a few at a time.
PRELOAD_WORKER_COUNT = 8


class LcuImageProvider(QQuickImageProvider):
    def __init__(self, cache_limit: int = 2048) -> None:
        super().__init__(QQuickImageProvider.Pixmap)
        self._lock = threading.Lock()
        self._client: Optional[httpx.Client] = None
        # Qt already caches pixmaps by URL for displayed Images, but repeated
        # bursts (e.g. navigating back/forward between match details) still
        # re-enter requestPixmap. Caching raw bytes here means the second
        # visit to any asset is <1 ms regardless of Qt's internal cache state.
        self._cache_limit = cache_limit
        self._cache: dict[str, QPixmap] = {}
        self._cache_order: list[str] = []
        self._inflight: dict[str, threading.Event] = {}
        self._preload_queue: list[str] = []
        self._preload_queued: set[str] = set()
        self._preload_workers: list[threading.Thread] = []

    def set_credentials(self, port: int, token: str) -> None:
        with self._lock:
            old = self._client
            self._client = None
            # Invalidate cache on port change — LCU rolls port each launch.
            self._cache.clear()
            self._cache_order.clear()
            self._inflight.clear()
            self._preload_queue.clear()
            self._preload_queued.clear()
            if port and token:
                self._client = httpx.Client(
                    base_url=f"https://127.0.0.1:{port}",
                    auth=("riot", token),
                    verify=False,
                    timeout=5.0,
                )
        if old is not None:
            try:
                old.close()
            except Exception:  # noqa: BLE001
                pass

    def _store_cache_locked(self, key: str, pix: QPixmap) -> None:
        self._cache[key] = pix
        if key in self._cache_order:
            self._cache_order.remove(key)
        self._cache_order.append(key)
        while len(self._cache_order) > self._cache_limit:
            old_key = self._cache_order.pop(0)
            self._cache.pop(old_key, None)

    def _fetch_pixmap(self, key: str) -> QPixmap:
        with self._lock:
            cached = self._cache.get(key)
            if cached is not None:
                return cached
            event = self._inflight.get(key)
            if event is None:
                event = threading.Event()
                self._inflight[key] = event
                owner = True
            else:
                owner = False
            client = self._client

        if not owner:
            event.wait(timeout=5.0)
            with self._lock:
                return self._cache.get(key, QPixmap())

        pix = QPixmap()
        try:
            if client is not None:
                resp = client.get("/" + key)
                if resp.status_code == 200 and resp.content:
                    img = QImage.fromData(resp.content)
                    if not img.isNull():
                        pix = QPixmap.fromImage(img)
        except Exception as e:  # noqa: BLE001
            log.debug("lcu image fetch failed %s: %s", key, e)
        finally:
            with self._lock:
                if not pix.isNull():
                    self._store_cache_locked(key, pix)
                done = self._inflight.pop(key, None)
                if done is not None:
                    done.set()
        return pix

    def preload(
        self,
        paths: list[str] | set[str],
        *,
        priority: bool = False,
        clear_pending: bool = False,
    ) -> None:
        keys: list[str] = []
        seen: set[str] = set()
        for path in paths:
            key = path.lstrip("/") if path else ""
            if not key or key in seen:
                continue
            seen.add(key)
            keys.append(key)
        if not keys:
            return

        workers_to_start: list[threading.Thread] = []
        with self._lock:
            if clear_pending:
                self._preload_queue.clear()
                self._preload_queued.clear()
            pending: list[str] = []
            for key in keys:
                if key in self._cache or key in self._preload_queued:
                    continue
                pending.append(key)
                self._preload_queued.add(key)
            if priority:
                self._preload_queue = pending + self._preload_queue
            else:
                self._preload_queue.extend(pending)
            self._preload_workers = [w for w in self._preload_workers if w.is_alive()]
            missing = PRELOAD_WORKER_COUNT - len(self._preload_workers)
            for idx in range(min(missing, len(self._preload_queue))):
                worker = threading.Thread(
                    target=self._run_preload_queue,
                    name=f"lcu-image-preload-{idx + 1}",
                    daemon=True,
                )
                self._preload_workers.append(worker)
                workers_to_start.append(worker)

        for worker in workers_to_start:
            worker.start()

    def _run_preload_queue(self) -> None:
        while True:
            with self._lock:
                if not self._preload_queue:
                    return
                key = self._preload_queue.pop(0)
                self._preload_queued.discard(key)
            self._fetch_pixmap(key)

    def requestPixmap(self, id: str, size: QSize, requested: QSize) -> QPixmap:
        """id is the LCU path sans leading slash, e.g.
        ``lol-game-data/assets/v1/champion-icons/266.png``."""
        key = id.lstrip("/")
        if not key:
            return QPixmap()
        return self._fetch_pixmap(key)
