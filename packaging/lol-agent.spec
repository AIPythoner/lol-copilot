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
    excludes=["_refs"],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="lol-agent",
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
    upx_exclude=[],
    name="lol-agent",
)
