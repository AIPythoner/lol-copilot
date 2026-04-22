"""Locate a running LeagueClientUx process and extract LCU credentials.

The LoL client is launched with --remoting-auth-token=... and --app-port=...
on its command line. We read those via psutil — works for both Tencent (国服)
and international clients, since both spawn LeagueClientUx.exe.
"""
from __future__ import annotations

import asyncio
import re
from dataclasses import dataclass
from typing import Awaitable, Callable, Optional

import psutil

from app.common.config import CLIENT_PROCESS_NAMES, LCU_POLL_INTERVAL_SEC
from app.common.logger import get_logger

log = get_logger(__name__)

_ARG_RE = re.compile(r'--([a-zA-Z0-9\-]+)=(?:"([^"]*)"|(\S+))')


@dataclass(frozen=True)
class LcuCredentials:
    pid: int
    port: int
    token: str
    install_dir: Optional[str] = None
    region: Optional[str] = None
    locale: Optional[str] = None

    @property
    def base_url(self) -> str:
        return f"https://127.0.0.1:{self.port}"

    @property
    def ws_url(self) -> str:
        return f"wss://127.0.0.1:{self.port}"


def _parse_cmdline(args: list[str]) -> dict[str, str]:
    joined = " ".join(args)
    out: dict[str, str] = {}
    for m in _ARG_RE.finditer(joined):
        key = m.group(1)
        val = m.group(2) if m.group(2) is not None else m.group(3)
        out[key] = val
    return out


def _iter_client_processes() -> list[psutil.Process]:
    targets = {name.lower() for name in CLIENT_PROCESS_NAMES}
    found: list[psutil.Process] = []
    for proc in psutil.process_iter(["name"]):
        try:
            name = (proc.info.get("name") or "").lower()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
        if name in targets or name.rstrip(".exe") in {t.rstrip(".exe") for t in targets}:
            found.append(proc)
    return found


def find_credentials() -> Optional[LcuCredentials]:
    """Return credentials of the first valid League client process, or None."""
    for proc in _iter_client_processes():
        try:
            args = proc.cmdline()
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue
        if not args:
            continue
        params = _parse_cmdline(args)
        token = params.get("remoting-auth-token")
        port = params.get("app-port")
        if not token or not port:
            continue
        try:
            port_int = int(port)
        except ValueError:
            continue
        return LcuCredentials(
            pid=proc.pid,
            port=port_int,
            token=token,
            install_dir=params.get("install-directory"),
            region=params.get("region"),
            locale=params.get("locale"),
        )
    return None


CredsCallback = Callable[[Optional[LcuCredentials]], Awaitable[None]]


class ConnectorWatcher:
    """Polls for client presence and invokes callbacks on connect/disconnect."""

    def __init__(self, poll_interval: float = LCU_POLL_INTERVAL_SEC) -> None:
        self._interval = poll_interval
        self._task: Optional[asyncio.Task] = None
        self._current: Optional[LcuCredentials] = None
        self._on_change: Optional[CredsCallback] = None

    @property
    def current(self) -> Optional[LcuCredentials]:
        return self._current

    def on_change(self, cb: CredsCallback) -> None:
        self._on_change = cb

    def start(self) -> None:
        if self._task and not self._task.done():
            return
        self._task = asyncio.create_task(self._run(), name="lcu-connector-watcher")

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):
                pass
            self._task = None

    async def _run(self) -> None:
        log.info("connector watcher started")
        while True:
            try:
                creds = find_credentials()
                if creds != self._current:
                    prev = self._current
                    self._current = creds
                    if creds:
                        log.info("lcu detected pid=%s port=%s region=%s", creds.pid, creds.port, creds.region)
                    elif prev:
                        log.info("lcu disconnected")
                    if self._on_change:
                        await self._on_change(creds)
            except Exception as e:  # noqa: BLE001 - keep polling loop alive
                log.exception("connector watcher error: %s", e)
            await asyncio.sleep(self._interval)
