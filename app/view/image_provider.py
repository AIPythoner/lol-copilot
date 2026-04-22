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


class LcuImageProvider(QQuickImageProvider):
    def __init__(self, cache_limit: int = 512) -> None:
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

    def set_credentials(self, port: int, token: str) -> None:
        with self._lock:
            old = self._client
            self._client = None
            # Invalidate cache on port change — LCU rolls port each launch.
            self._cache.clear()
            self._cache_order.clear()
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

    def requestPixmap(self, id: str, size: QSize, requested: QSize) -> QPixmap:
        """id is the LCU path sans leading slash, e.g.
        ``lol-game-data/assets/v1/champion-icons/266.png``."""
        key = id.lstrip("/")
        with self._lock:
            cached = self._cache.get(key)
            if cached is not None:
                return cached
            client = self._client
        if client is None or not id:
            return QPixmap()
        try:
            resp = client.get("/" + key)
        except Exception as e:  # noqa: BLE001
            log.debug("lcu image fetch failed %s: %s", id, e)
            return QPixmap()
        if resp.status_code != 200 or not resp.content:
            return QPixmap()
        img = QImage.fromData(resp.content)
        if img.isNull():
            return QPixmap()
        pix = QPixmap.fromImage(img)
        with self._lock:
            self._cache[key] = pix
            self._cache_order.append(key)
            while len(self._cache_order) > self._cache_limit:
                old_key = self._cache_order.pop(0)
                self._cache.pop(old_key, None)
        return pix
