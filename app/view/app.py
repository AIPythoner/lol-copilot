"""GUI bootstrap — wires qasync, FluentUI, QML engine, and LcuBridge."""
from __future__ import annotations

import asyncio
import ctypes
import os
import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow, QSGRendererInterface
from PySide6.QtWidgets import QApplication

from app.common.config import APP_NAME
from app.common.logger import get_logger, setup_logging
from app.view.bridge import LcuBridge
from app.view.icons import app_icon
from app.view.image_provider import LcuImageProvider
from app.view.tray import AppTray

log = get_logger(__name__)


def _set_windows_app_id() -> None:
    if sys.platform != "win32":
        return
    try:
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("lol-agent.desktop")
    except Exception as e:  # noqa: BLE001
        log.debug("failed to set Windows app id: %s", e)


def run_gui() -> int:
    setup_logging()
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    QQuickWindow.setGraphicsApi(QSGRendererInterface.GraphicsApi.OpenGL)
    _set_windows_app_id()

    QGuiApplication.setOrganizationName("lol-agent")
    QGuiApplication.setApplicationName(APP_NAME)
    # QApplication (not QGuiApplication) is required for QSystemTrayIcon.
    app = QApplication(sys.argv)
    icon = app_icon()
    app.setWindowIcon(icon)
    app.setQuitOnLastWindowClosed(False)

    # qasync integrates asyncio with Qt's event loop — required for our async LCU stack.
    import qasync

    loop = qasync.QEventLoop(app)
    asyncio.set_event_loop(loop)

    engine = QQmlApplicationEngine()

    # Serve LCU icons through a custom image provider so Image { source: "image://lcu/..." }
    # hits localhost HTTPS with the right auth instead of going to CDragon.
    image_provider = LcuImageProvider()
    engine.addImageProvider("lcu", image_provider)

    bridge = LcuBridge()
    bridge.set_image_provider(image_provider)
    engine.rootContext().setContextProperty("Lcu", bridge)

    try:
        import FluentUI  # type: ignore
        FluentUI.init(engine)
    except Exception as e:  # noqa: BLE001
        log.error("FluentUI import failed: %s — install PySide6-FluentUI-QML", e)
        return 3

    qml_dir = Path(__file__).parent / "qml"
    engine.addImportPath(str(qml_dir))
    engine.load(QUrl.fromLocalFile(str(qml_dir / "Main.qml")))
    if not engine.rootObjects():
        log.error("QML failed to load")
        return 4

    window = engine.rootObjects()[0]
    try:
        window.setIcon(icon)
    except Exception as e:  # noqa: BLE001
        log.debug("failed to set QML window icon: %s", e)

    def _show_window() -> None:
        window.show()
        window.raise_()
        window.requestActivate()

    tray = AppTray(
        parent=app,
        icon=icon,
        on_show=_show_window,
        on_toggle_pause=bridge.toggleAutoPause,
        is_paused=bridge.autoPaused,
        on_quit=app.quit,
    )
    if not tray.install():
        log.warning("system tray unavailable; close button will quit the app")
        app.setQuitOnLastWindowClosed(True)

    close_event = asyncio.Event()
    app.aboutToQuit.connect(close_event.set)
    app.aboutToQuit.connect(engine.deleteLater)

    with loop:
        loop.call_soon(bridge.start)
        loop.run_until_complete(close_event.wait())
        loop.run_until_complete(bridge.shutdown())
    return 0
