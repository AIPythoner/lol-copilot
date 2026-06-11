"""Async HTTP client over the LCU self-signed HTTPS endpoint."""
from __future__ import annotations

import asyncio
from typing import Any, Optional

import httpx

from app.common.config import LCU_REQUEST_TIMEOUT_SEC
from app.common.logger import get_logger
from app.lcu.connector import LcuCredentials

log = get_logger(__name__)

LCU_MAX_CONCURRENT_REQUESTS = 8


class LcuError(RuntimeError):
    def __init__(self, status: int, uri: str, payload: Any | None = None) -> None:
        super().__init__(f"LCU {status} {uri}: {payload!r}")
        self.status = status
        self.uri = uri
        self.payload = payload


class NotConnectedError(RuntimeError):
    pass


class LcuClient:
    """Thin async wrapper around httpx.AsyncClient for LCU endpoints.

    Auth credentials can be updated at runtime (when the client disconnects
    and reconnects on a new port). Self-signed certs are accepted — LCU uses
    a per-install cert that's not in any trust store.
    """

    def __init__(self) -> None:
        self._client: Optional[httpx.AsyncClient] = None
        self._creds: Optional[LcuCredentials] = None
        self._request_sem = asyncio.Semaphore(LCU_MAX_CONCURRENT_REQUESTS)
        self._swap_lock = asyncio.Lock()

    def is_connected(self) -> bool:
        return self._client is not None and self._creds is not None

    @property
    def credentials(self) -> Optional[LcuCredentials]:
        return self._creds

    async def set_credentials(self, creds: Optional[LcuCredentials]) -> None:
        async with self._swap_lock:
            if creds == self._creds:
                return
            old_client = self._client
            self._client = None
            self._creds = creds
            if old_client is not None:
                try:
                    await old_client.aclose()
                except Exception as e:  # noqa: BLE001
                    log.debug("failed to close old lcu client: %s", e)
            if creds is None:
                return
            self._client = httpx.AsyncClient(
                base_url=creds.base_url,
                auth=("riot", creds.token),
                verify=False,  # LCU uses a self-signed riotgames.pem
                timeout=LCU_REQUEST_TIMEOUT_SEC,
                headers={"Accept": "application/json"},
            )
            log.debug("lcu client bound to %s", creds.base_url)

    async def close(self) -> None:
        await self.set_credentials(None)

    def _require(self) -> httpx.AsyncClient:
        if self._client is None:
            raise NotConnectedError("LCU client not connected")
        return self._client

    async def _snapshot_client(self) -> httpx.AsyncClient:
        async with self._swap_lock:
            return self._require()

    async def _send_once(
        self,
        client: httpx.AsyncClient,
        method: str,
        uri: str,
        *,
        json: Any | None,
        params: dict | None,
    ) -> httpx.Response:
        if method.upper() == "GET":
            async with self._request_sem:
                return await client.request(method, uri, json=json, params=params)
        return await client.request(method, uri, json=json, params=params)

    async def request(
        self,
        method: str,
        uri: str,
        *,
        json: Any | None = None,
        params: dict | None = None,
        raw: bool = False,
    ) -> Any:
        client = await self._snapshot_client()
        try:
            resp = await self._send_once(client, method, uri, json=json, params=params)
        except RuntimeError as e:
            if "closed" not in str(e).lower():
                raise
            client = await self._snapshot_client()
            resp = await self._send_once(client, method, uri, json=json, params=params)
        if resp.status_code >= 400:
            try:
                payload = resp.json()
            except Exception:  # noqa: BLE001
                payload = resp.text
            raise LcuError(resp.status_code, uri, payload)
        if raw:
            return resp.content
        if resp.status_code == 204 or not resp.content:
            return None
        ctype = resp.headers.get("content-type", "")
        if "json" in ctype:
            return resp.json()
        return resp.text

    async def get(self, uri: str, **kw: Any) -> Any:
        return await self.request("GET", uri, **kw)

    async def post(self, uri: str, **kw: Any) -> Any:
        return await self.request("POST", uri, **kw)

    async def put(self, uri: str, **kw: Any) -> Any:
        return await self.request("PUT", uri, **kw)

    async def patch(self, uri: str, **kw: Any) -> Any:
        return await self.request("PATCH", uri, **kw)

    async def delete(self, uri: str, **kw: Any) -> Any:
        return await self.request("DELETE", uri, **kw)
