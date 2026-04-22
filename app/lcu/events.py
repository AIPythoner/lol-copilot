"""LCU WebSocket event stream.

Subscribes to OnJsonApiEvent and dispatches events by URI prefix to
registered async callbacks. Reconnects on failure while credentials are valid.
"""
from __future__ import annotations

import asyncio
import base64
import json
import ssl
from dataclasses import dataclass
from typing import Any, Awaitable, Callable, Optional

import websockets
from websockets.client import WebSocketClientProtocol

from app.common.config import WS_RECONNECT_INTERVAL_SEC, WS_SUBSCRIBE_EVENT
from app.common.logger import get_logger
from app.lcu.connector import LcuCredentials

log = get_logger(__name__)

# LCU wamp opcodes
_OP_SUBSCRIBE = 5
_OP_EVENT = 8


@dataclass
class LcuEvent:
    uri: str
    event_type: str  # Create / Update / Delete
    data: Any


EventHandler = Callable[[LcuEvent], Awaitable[None]]


class LcuEventStream:
    """Single persistent WS connection, dispatches events by URI prefix."""

    def __init__(self) -> None:
        self._creds: Optional[LcuCredentials] = None
        self._task: Optional[asyncio.Task] = None
        self._ws: Optional[WebSocketClientProtocol] = None
        self._handlers: list[tuple[str, EventHandler]] = []
        self._stop = asyncio.Event()

    def subscribe(self, uri_prefix: str, handler: EventHandler) -> None:
        """Register handler for events whose URI starts with uri_prefix."""
        self._handlers.append((uri_prefix, handler))

    async def set_credentials(self, creds: Optional[LcuCredentials]) -> None:
        self._creds = creds
        await self._restart()

    async def start(self) -> None:
        await self._restart()

    async def stop(self) -> None:
        self._stop.set()
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):
                pass
            self._task = None

    async def _restart(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):
                pass
            self._task = None
        if self._creds is None:
            return
        self._stop.clear()
        self._task = asyncio.create_task(self._run(), name="lcu-event-stream")

    async def _run(self) -> None:
        creds = self._creds
        if creds is None:
            return
        ssl_ctx = ssl.create_default_context()
        ssl_ctx.check_hostname = False
        ssl_ctx.verify_mode = ssl.CERT_NONE
        auth = base64.b64encode(f"riot:{creds.token}".encode()).decode()
        headers = {"Authorization": f"Basic {auth}"}
        url = creds.ws_url
        while not self._stop.is_set():
            try:
                async with websockets.connect(
                    url,
                    ssl=ssl_ctx,
                    additional_headers=headers,
                    subprotocols=["wamp"],
                    max_size=2**23,
                    ping_interval=None,
                ) as ws:
                    self._ws = ws
                    await ws.send(json.dumps([_OP_SUBSCRIBE, WS_SUBSCRIBE_EVENT]))
                    log.info("lcu ws connected %s", url)
                    async for raw in ws:
                        await self._dispatch(raw)
            except asyncio.CancelledError:
                raise
            except Exception as e:  # noqa: BLE001
                log.warning("lcu ws error: %s — reconnecting", e)
            finally:
                self._ws = None
            if self._stop.is_set():
                break
            await asyncio.sleep(WS_RECONNECT_INTERVAL_SEC)

    async def _dispatch(self, raw: str | bytes) -> None:
        try:
            msg = json.loads(raw)
        except Exception:  # noqa: BLE001
            return
        if not isinstance(msg, list) or len(msg) < 3:
            return
        if msg[0] != _OP_EVENT:
            return
        payload = msg[2]
        if not isinstance(payload, dict):
            return
        uri = payload.get("uri") or ""
        event = LcuEvent(
            uri=uri,
            event_type=payload.get("eventType", ""),
            data=payload.get("data"),
        )
        for prefix, handler in self._handlers:
            if uri.startswith(prefix):
                try:
                    await handler(event)
                except Exception as e:  # noqa: BLE001
                    log.exception("event handler error for %s: %s", uri, e)
