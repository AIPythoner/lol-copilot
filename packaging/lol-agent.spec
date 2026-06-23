# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files

ROOT = Path.cwd()

datas = [
    (str(ROOT / "app" / "view" / "qml"), "app/view/qml"),
    (str(ROOT / "app" / "view" / "assets"), "app/view/assets"),
]
datas += collect_data_files("FluentUI", includes=["qml/**/*"])


a = Analysis(
    [str(ROOT / "app.py")],
    pathex=[str(ROOT)],
    binaries=[],
    datas=datas,
    hiddenimports=["qasync", "FluentUI"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "_refs",
        # Qt modules this QML/FluentUI app never imports — keep PyInstaller from
        # following them (the matching DLLs are pruned post-COLLECT below).
        "PySide6.QtWebEngineCore", "PySide6.QtWebEngineWidgets", "PySide6.QtWebEngineQuick",
        "PySide6.QtMultimedia", "PySide6.QtMultimediaWidgets", "PySide6.QtCharts",
        "PySide6.QtPdf", "PySide6.QtPdfWidgets", "PySide6.QtQuick3D", "PySide6.Qt3DCore",
        "PySide6.QtDataVisualization", "PySide6.QtGraphs", "PySide6.QtLocation",
        "PySide6.QtPositioning", "PySide6.QtSensors", "PySide6.QtTest", "PySide6.QtSql",
        "PySide6.QtBluetooth", "PySide6.QtNfc", "PySide6.QtSerialPort",
        "PySide6.QtWebSockets", "PySide6.QtWebChannel", "PySide6.QtTextToSpeech",
        "PySide6.QtRemoteObjects", "PySide6.QtScxml",
        "tkinter", "unittest", "pydoc", "test",
    ],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="lol-copilot",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    icon=str(ROOT / "app" / "view" / "assets" / "app-icon.ico"),
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[
        "libssl-3-x64.dll",
        "libssl-3.dll",
        "libcrypto-3-x64.dll",
        "libcrypto-3.dll",
        "Qt6*.dll",
        "vcruntime*.dll",
    ],
    name="lol-copilot",
)

# Mirror the OpenSSL DLLs next to the EXE. Windows' default DLL search
# order is (app dir > System32 > ... ) and _ssl.pyd does a plain
# LoadLibrary("libssl-3-x64.dll") at import time — so if these DLLs only
# live under _internal/, Windows skips them and falls through to system32
# where older OpenSSL builds (missing OPENSSL_LH_set_thunks etc) cause
# launch errors like "无法定位程序输入点 OPENSSL_LH_set_thunks".
import shutil

_dist_root = ROOT / "dist" / "lol-copilot"
_internal = _dist_root / "_internal"
for _dll in (
    "libssl-3-x64.dll",
    "libssl-3.dll",
    "libcrypto-3-x64.dll",
    "libcrypto-3.dll",
):
    _src = _internal / _dll
    if _src.exists():
        shutil.copy2(_src, _dist_root / _dll)

# ---------------------------------------------------------------------------
# Slim the Qt deployment. PySide6 bundles the full Qt — but this app is a pure
# QML/FluentUI client that only needs the core QtQuick / Controls(Basic) /
# Layouts / Window stack plus Qt5Compat (for the frosted-glass GraphicalEffects)
# and Qt Network + the TLS plugin (QML loads remote champion icons over HTTPS).
# Everything below is verified-unused against app/view/qml imports. WebEngine's
# embedded Chromium alone is ~200 MB. A launch smoke-test guards the result.
# ---------------------------------------------------------------------------
_pyside = _internal / "PySide6"


def _rm(p):
    try:
        if p.is_dir():
            shutil.rmtree(p, ignore_errors=True)
        elif p.exists():
            p.unlink()
    except Exception as _e:  # noqa: BLE001
        print("prune: skip", p, _e)


def _dir_size(p):
    return sum(f.stat().st_size for f in p.rglob("*") if f.is_file()) if p.exists() else 0


if _pyside.exists():
    _before = _dir_size(_dist_root)

    # 1) Unused module DLLs + Python bindings (.pyd) + WebEngine resources.
    _drop_globs = [
        "Qt6WebEngine*", "QtWebEngine*", "QtWebEngineProcess.exe",
        "qtwebengine_*", "*.pak", "icudtl.dat",
        "Qt6Pdf*", "QtPdf*",
        "Qt6Quick3D*", "QtQuick3D*",
        "Qt63D*", "Qt3D*",
        "Qt6Graphs*", "QtGraphs*",
        "Qt6Charts*", "QtCharts*",
        "Qt6DataVisualization*", "QtDataVisualization*",
        "Qt6Multimedia*", "QtMultimedia*", "Qt6SpatialAudio*", "QtSpatialAudio*",
        "Qt6Location*", "QtLocation*", "Qt6Positioning*", "QtPositioning*",
        "Qt6Sensors*", "QtSensors*",
        "Qt6TextToSpeech*", "QtTextToSpeech*",
        "Qt6RemoteObjects*", "QtRemoteObjects*",
        "Qt6Scxml*", "QtScxml*", "Qt6StateMachine*",
        "Qt6SerialPort*", "QtSerialPort*", "Qt6SerialBus*", "QtSerialBus*",
        "Qt6Bluetooth*", "QtBluetooth*", "Qt6Nfc*", "QtNfc*",
        "Qt6WebSockets*", "QtWebSockets*", "Qt6WebChannel*", "QtWebChannel*",
        "Qt6WebView*", "QtWebView*",
        "Qt6Test*", "QtTest*",
        "Qt6Sql*", "QtSql*",
        "Qt6NetworkAuth*", "QtNetworkAuth*",
        "Qt6Help*", "QtHelp*", "Qt6Designer*", "QtDesigner*", "Qt6UiTools*", "QtUiTools*",
        "Qt6QuickControls2Material*", "Qt6QuickControls2Universal*",
        "Qt6QuickControls2Fusion*", "Qt6QuickControls2Imagine*",
        "Qt6QuickTimeline*", "QtQuickTimeline*",
        "Qt6QuickDialogs2*",
        # NB: keep QtOpenGL — QtQuick hard-imports it via shiboken at startup.
    ]
    for _pat in _drop_globs:
        for _f in _pyside.glob(_pat):
            _rm(_f)
    _rm(_pyside / "resources")  # WebEngine .pak / devtools resources

    # 2) Unused QML modules.
    _qml = _pyside / "qml"
    for _sub in ["QtWebEngine", "QtQuick3D", "Qt3D", "QtGraphs", "QtCharts",
                 "QtDataVisualization", "QtMultimedia", "QtSpatialAudio", "QtLocation",
                 "QtPositioning", "QtSensors", "QtTextToSpeech", "QtWebSockets",
                 "QtWebChannel", "QtScxml", "QtNfc", "QtBluetooth", "QtTest",
                 "QtRemoteObjects", "QtSerialPort", "QtWebView", "QtSql"]:
        _rm(_qml / _sub)
    _qq = _qml / "QtQuick"
    for _sub in ["Dialogs", "Particles", "Scene2D", "Scene3D", "Timeline", "VirtualKeyboard"]:
        _rm(_qq / _sub)
    for _style in ["Material", "Universal", "Fusion", "Imagine"]:
        _rm(_qq / "Controls" / _style)

    # 3) Unused Qt plugins (keep platforms / imageformats / iconengines / tls /
    #    networkinformation / styles / platforminputcontexts).
    _plugins = _pyside / "plugins"
    for _sub in ["multimedia", "sqldrivers", "position", "sensors", "webview",
                 "qmltooling", "texttospeech", "assetimporters", "sceneparsers",
                 "renderers", "renderplugins", "geometryloaders", "scxmldatamodel"]:
        _rm(_plugins / _sub)

    # 4) Trim Qt's own translations to Chinese (the app ships its own strings).
    _tr = _pyside / "translations"
    if _tr.exists():
        for _qm in _tr.glob("*.qm"):
            if "zh_CN" not in _qm.name:
                _rm(_qm)
        _rm(_tr / "qtwebengine_locales")

    _after = _dir_size(_dist_root)
    print("prune: dist %.0f MB -> %.0f MB (saved %.0f MB)" % (
        _before / 1e6, _after / 1e6, (_before - _after) / 1e6))
