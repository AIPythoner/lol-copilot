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
    upx_exclude=[],
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
