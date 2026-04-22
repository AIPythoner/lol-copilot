"""Command-line LCU debugger.

Examples
--------
    python -m app --cli status
    python -m app --cli me
    python -m app --cli phase
    python -m app --cli history --count 20
    python -m app --cli raw GET /lol-gameflow/v1/gameflow-phase
    python -m app --cli watch
"""
from __future__ import annotations

import argparse
import asyncio
import json
from typing import Any

from app.common.logger import get_logger, setup_logging
from app.lcu import api
from app.lcu.client import LcuClient, NotConnectedError
from app.lcu.connector import find_credentials
from app.lcu.events import LcuEvent, LcuEventStream

log = get_logger(__name__)


def _pp(obj: Any) -> None:
    if isinstance(obj, (dict, list)):
        print(json.dumps(obj, indent=2, ensure_ascii=False))
    else:
        print(obj)


async def _with_client() -> LcuClient:
    creds = find_credentials()
    if creds is None:
        raise NotConnectedError("League client not running — start it and retry.")
    print(f"[ok] connected pid={creds.pid} port={creds.port} region={creds.region}")
    client = LcuClient()
    await client.set_credentials(creds)
    return client


async def _cmd_status(_: argparse.Namespace) -> None:
    creds = find_credentials()
    if creds is None:
        print("[-] not connected")
        return
    print(f"[+] pid={creds.pid} port={creds.port} token={creds.token[:6]}… region={creds.region} install_dir={creds.install_dir}")


async def _cmd_me(_: argparse.Namespace) -> None:
    c = await _with_client()
    try:
        _pp(await api.current_summoner(c))
    finally:
        await c.close()


async def _cmd_phase(_: argparse.Namespace) -> None:
    c = await _with_client()
    try:
        _pp(await api.gameflow_phase(c))
    finally:
        await c.close()


async def _cmd_history(ns: argparse.Namespace) -> None:
    c = await _with_client()
    try:
        me = await api.current_summoner(c)
        puuid = me["puuid"]
        end = max(0, ns.count - 1)
        mh = await api.match_history(c, puuid, 0, end)
        games = mh.get("games", {}).get("games", [])
        print(f"[+] {len(games)} games for {me.get('displayName') or me.get('gameName')}")
        for g in games:
            p = g.get("participants", [{}])[0]
            stats = p.get("stats", {})
            print(
                f"  {g.get('gameId')} q={g.get('queueId'):<4} "
                f"{'W' if stats.get('win') else 'L'} "
                f"{stats.get('kills',0)}/{stats.get('deaths',0)}/{stats.get('assists',0)} "
                f"champ={p.get('championId')}"
            )
    finally:
        await c.close()


async def _cmd_raw(ns: argparse.Namespace) -> None:
    c = await _with_client()
    try:
        method = ns.method.upper()
        body = json.loads(ns.body) if ns.body else None
        _pp(await c.request(method, ns.uri, json=body))
    finally:
        await c.close()


async def _cmd_watch(_: argparse.Namespace) -> None:
    creds = find_credentials()
    if creds is None:
        print("[-] not connected")
        return
    stream = LcuEventStream()

    async def printer(ev: LcuEvent) -> None:
        uri = ev.uri
        if isinstance(ev.data, (dict, list)):
            preview = json.dumps(ev.data, ensure_ascii=False)[:160]
        else:
            preview = str(ev.data)[:160]
        print(f"[{ev.event_type}] {uri} -> {preview}")

    for prefix in (
        api.EVENT_GAMEFLOW_PHASE,
        api.EVENT_CHAMP_SELECT,
        api.EVENT_MATCHMAKING_READY_CHECK,
        api.EVENT_LOBBY,
    ):
        stream.subscribe(prefix, printer)

    await stream.set_credentials(creds)
    print("[+] watching events (Ctrl+C to exit)")
    try:
        await asyncio.Event().wait()
    except (asyncio.CancelledError, KeyboardInterrupt):
        pass
    finally:
        await stream.stop()


_COMMANDS = {
    "status": _cmd_status,
    "me": _cmd_me,
    "phase": _cmd_phase,
    "history": _cmd_history,
    "raw": _cmd_raw,
    "watch": _cmd_watch,
}


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="lol-agent --cli")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    sub.add_parser("me")
    sub.add_parser("phase")
    ph = sub.add_parser("history")
    ph.add_argument("--count", type=int, default=20)
    pr = sub.add_parser("raw")
    pr.add_argument("method")
    pr.add_argument("uri")
    pr.add_argument("--body", default=None)
    sub.add_parser("watch")
    return p


def run_cli(argv: list[str]) -> int:
    setup_logging()
    ns = _build_parser().parse_args(argv)
    handler = _COMMANDS[ns.cmd]
    try:
        asyncio.run(handler(ns))
    except NotConnectedError as e:
        print(f"[-] {e}")
        return 2
    except KeyboardInterrupt:
        return 130
    return 0
