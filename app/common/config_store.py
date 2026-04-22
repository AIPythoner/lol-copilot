"""Persistent app settings (JSON file under user config dir)."""
from __future__ import annotations

import json
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
    height: int = 720


@dataclass
class AppSettings:
    auto_actions: AutoActionSettings = field(default_factory=AutoActionSettings)
    opgg: OpggSettings = field(default_factory=OpggSettings)
    window: WindowGeom = field(default_factory=WindowGeom)
    dark_mode: str = "dark"  # "system" / "light" / "dark"

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "AppSettings":
        aa_raw = raw.get("auto_actions") or {}
        op_raw = raw.get("opgg") or {}
        wnd_raw = raw.get("window") or {}
        return cls(
            auto_actions=AutoActionSettings(**{k: v for k, v in aa_raw.items() if k in AutoActionSettings.__dataclass_fields__}),
            opgg=OpggSettings(**{k: v for k, v in op_raw.items() if k in OpggSettings.__dataclass_fields__}),
            window=WindowGeom(**{k: v for k, v in wnd_raw.items() if k in WindowGeom.__dataclass_fields__}),
            dark_mode=raw.get("dark_mode", "system"),
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
        return AppSettings.from_dict(raw)
    except Exception as e:  # noqa: BLE001
        log.warning("failed to read settings %s: %s — using defaults", p, e)
        return AppSettings()


def save_settings(s: AppSettings) -> None:
    p = config_path()
    try:
        p.write_text(json.dumps(s.to_dict(), indent=2, ensure_ascii=False), encoding="utf-8")
    except Exception as e:  # noqa: BLE001
        log.warning("failed to save settings %s: %s", p, e)
