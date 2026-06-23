"""Persistent app settings (JSON file under user config dir)."""
from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from platformdirs import user_config_dir

from app.common.config import APP_NAME
from app.common.logger import get_logger

log = get_logger(__name__)


@dataclass
class AutoActionSettings:
    auto_accept: bool = False
    auto_ban: bool = False
    auto_pick: bool = False
    send_team_winrate: bool = True
    ban_priority: list[int] = field(default_factory=list)
    pick_priority: list[int] = field(default_factory=list)


@dataclass
class OpggSettings:
    tier: str = "emerald_plus"
    region: str = "global"
    mode: str = "ranked"
    position: str = ""  # "" = auto


@dataclass
class WindowGeom:
    x: int = -1
    y: int = -1
    width: int = 1100
    height: int = 660


@dataclass
class AiSettings:
    """Match AI analysis config.

    Ships ON by default and routed through the free hosted relay (opgg-proxy),
    so end users need no API key — see bridge.py `_AI_PROXY_*`. The fields below
    stay for power users: writing a full custom OpenAI-compatible endpoint
    (api_key + base_url + model) into settings.json overrides the relay.
    """
    enabled: bool = True
    base_url: str = ""
    api_key: str = ""
    model: str = ""


@dataclass
class AppSettings:
    auto_actions: AutoActionSettings = field(default_factory=AutoActionSettings)
    opgg: OpggSettings = field(default_factory=OpggSettings)
    window: WindowGeom = field(default_factory=WindowGeom)
    ai: AiSettings = field(default_factory=AiSettings)
    dark_mode: str = "light"  # "light" / "dark" — first-launch default is light
    # Bumped whenever we need to migrate older saved settings. Don't roll back
    # — older clients ignore unknown fields, newer clients use this to decide
    # whether a one-shot upgrade has already run.
    schema_version: int = 3

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "AppSettings":
        aa_raw = raw.get("auto_actions") or {}
        op_raw = raw.get("opgg") or {}
        wnd_raw = raw.get("window") or {}
        ai_raw = raw.get("ai") or {}
        try:
            saved_height = int(wnd_raw.get("height") or 0)
        except (TypeError, ValueError):
            saved_height = 0
        if wnd_raw.get("width") == 1100 and wnd_raw.get("height") == 720:
            wnd_raw = dict(wnd_raw)
            wnd_raw["height"] = 660
        elif saved_height > 900:
            wnd_raw = dict(wnd_raw)
            wnd_raw["height"] = 660
        dark_mode = raw.get("dark_mode", "light")
        if dark_mode not in ("dark", "light"):
            dark_mode = "light"
        try:
            schema_version = int(raw.get("schema_version") or 0)
        except (TypeError, ValueError):
            schema_version = 0
        # v2 migration: send_team_winrate was effectively unreachable in v1
        # (buggy FluToggleSwitch wiring), so we ignore whatever the user has
        # saved and force the new default on. From v2 onwards the toggle
        # actually works, so a False value the user explicitly sets sticks.
        aa_filtered = {
            k: v
            for k, v in aa_raw.items()
            if k in AutoActionSettings.__dataclass_fields__
        }
        if schema_version < 2:
            aa_filtered["send_team_winrate"] = True
        ai_filtered = {k: v for k, v in ai_raw.items() if k in AiSettings.__dataclass_fields__}
        # v3 migration: AI match analysis became a free, zero-config hosted relay
        # (no user key needed), so enable it for everyone upgrading from <3 (the
        # old default was off + required a self-supplied key). Also clear any
        # stale custom endpoint so an old self-hosted base_url/key can't quietly
        # override the free relay. A user who later turns it off keeps that
        # choice on v3+.
        if schema_version < 3:
            ai_filtered["enabled"] = True
            ai_filtered["api_key"] = ""
            ai_filtered["base_url"] = ""
            ai_filtered["model"] = ""
        return cls(
            auto_actions=AutoActionSettings(**aa_filtered),
            opgg=OpggSettings(**{k: v for k, v in op_raw.items() if k in OpggSettings.__dataclass_fields__}),
            window=WindowGeom(**{k: v for k, v in wnd_raw.items() if k in WindowGeom.__dataclass_fields__}),
            ai=AiSettings(**ai_filtered),
            dark_mode=dark_mode,
            schema_version=max(schema_version, 3),
        )


def config_path() -> Path:
    d = Path(user_config_dir(APP_NAME, APP_NAME))
    d.mkdir(parents=True, exist_ok=True)
    return d / "settings.json"


def load_settings() -> AppSettings:
    p = config_path()
    if not p.exists():
        return AppSettings()
    try:
        raw = json.loads(p.read_text(encoding="utf-8"))
        settings = AppSettings.from_dict(raw)
        saved_version = int(raw.get("schema_version") or 0)
        if (
            raw.get("dark_mode") != settings.dark_mode
            or saved_version < settings.schema_version
        ):
            save_settings(settings)
        return settings
    except Exception as e:  # noqa: BLE001
        log.warning("failed to read settings %s: %s — using defaults", p, e)
        return AppSettings()


def save_settings(s: AppSettings) -> None:
    p = config_path()
    tmp = p.with_suffix(".json.tmp")
    try:
        tmp.write_text(json.dumps(s.to_dict(), indent=2, ensure_ascii=False), encoding="utf-8")
        os.replace(tmp, p)
    except Exception as e:  # noqa: BLE001
        log.warning("failed to save settings %s: %s", p, e)
        try:
            tmp.unlink(missing_ok=True)
        except Exception:  # noqa: BLE001
            pass
