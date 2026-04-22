"""Application icon assets."""
from __future__ import annotations

from pathlib import Path

ASSET_DIR = Path(__file__).resolve().parent / "assets"
APP_ICON_ICO = ASSET_DIR / "app-icon.ico"
APP_ICON_PNG = ASSET_DIR / "app-icon-64.png"


def app_icon():
    from PySide6.QtGui import QIcon

    icon = QIcon(str(APP_ICON_ICO))
    if icon.isNull():
        icon = QIcon(str(APP_ICON_PNG))
    return icon
