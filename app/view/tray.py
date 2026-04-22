"""System tray icon with context menu.

Provides quick access to:
* 显示主窗口 — show/raise the main window
* 暂停 / 恢复自动动作 — toggle AutoActions.paused without losing config
* 退出 — quit the app (close button minimises instead)
"""
from __future__ import annotations

from typing import Callable, Optional

from PySide6.QtCore import QObject, Qt
from PySide6.QtGui import QAction, QColor, QIcon, QPainter, QPixmap
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

from app.common.config import APP_NAME


def _default_icon() -> QIcon:
    """Paint a simple gold circle icon — good enough for a tray badge."""
    pix = QPixmap(64, 64)
    pix.fill(Qt.transparent)
    painter = QPainter(pix)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setBrush(QColor("#d4a04a"))
    painter.setPen(Qt.NoPen)
    painter.drawEllipse(4, 4, 56, 56)
    painter.setPen(QColor("#1a1a1a"))
    font = painter.font()
    font.setBold(True)
    font.setPixelSize(26)
    painter.setFont(font)
    painter.drawText(pix.rect(), Qt.AlignCenter, "L")
    painter.end()
    return QIcon(pix)


class AppTray(QObject):
    def __init__(
        self,
        *,
        parent: Optional[QObject] = None,
        icon: Optional[QIcon] = None,
        on_show: Callable[[], None],
        on_toggle_pause: Callable[[], None],
        is_paused: Callable[[], bool],
        on_quit: Callable[[], None],
    ) -> None:
        super().__init__(parent)
        self._on_show = on_show
        self._icon = icon
        self._on_toggle_pause = on_toggle_pause
        self._is_paused = is_paused
        self._on_quit = on_quit
        self._tray: Optional[QSystemTrayIcon] = None
        self._pause_action: Optional[QAction] = None

    def install(self) -> bool:
        if not QSystemTrayIcon.isSystemTrayAvailable():
            return False
        icon = self._icon if self._icon is not None and not self._icon.isNull() else _default_icon()
        self._tray = QSystemTrayIcon(icon)
        self._tray.setToolTip(APP_NAME)

        menu = QMenu()

        show_action = QAction("显示主窗口", menu)
        show_action.triggered.connect(self._on_show)
        menu.addAction(show_action)

        self._pause_action = QAction(self._pause_label(), menu)
        self._pause_action.triggered.connect(self._handle_pause)
        menu.addAction(self._pause_action)

        menu.addSeparator()

        quit_action = QAction("退出", menu)
        quit_action.triggered.connect(self._on_quit)
        menu.addAction(quit_action)

        self._tray.setContextMenu(menu)
        self._tray.activated.connect(self._on_activated)
        self._tray.show()
        return True

    def _pause_label(self) -> str:
        return "恢复自动动作" if self._is_paused() else "暂停自动动作"

    def _handle_pause(self) -> None:
        self._on_toggle_pause()
        if self._pause_action:
            self._pause_action.setText(self._pause_label())

    def _on_activated(self, reason: QSystemTrayIcon.ActivationReason) -> None:
        if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick):
            self._on_show()

    def show_message(self, title: str, body: str) -> None:
        if self._tray is not None:
            self._tray.showMessage(title, body, QSystemTrayIcon.Information, 3000)
