# Build lol-copilot with Nuitka (standalone, MSVC, no console window).
# Usage: powershell -ExecutionPolicy Bypass -File .\packaging\build_nuitka.ps1
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$python = Join-Path $repo '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) { throw "venv python not found: $python" }

$outDir = Join-Path $repo 'dist-nuitka'
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }

$args = @(
    '-m', 'nuitka',
    '--standalone',
    '--assume-yes-for-downloads',
    '--msvc=latest',
    '--windows-console-mode=disable',
    '--enable-plugin=pyside6',
    '--include-qt-plugins=qml',
    '--include-package=FluentUI',
    '--include-package-data=FluentUI',
    '--include-data-files=.venv/Lib/site-packages/FluentUI/qml/FluentUI/fluentuiplugin.dll=FluentUI/qml/FluentUI/fluentuiplugin.dll',
    '--include-package=qasync',
    '--include-package=selectolax',
    '--include-package=websockets',
    '--include-data-dir=app/view/qml=app/view/qml',
    '--include-data-dir=app/view/assets=app/view/assets',
    '--windows-icon-from-ico=app/view/assets/app-icon.ico',
    '--company-name=lol-agent',
    '--product-name=lol-copilot',
    '--file-description=LoL Copilot',
    '--file-version=0.1.0',
    '--product-version=0.1.0',
    "--output-dir=$outDir",
    '--output-filename=lol-copilot.exe',
    '--remove-output',
    'app.py'
)

Write-Host "[nuitka] python  = $python"
Write-Host "[nuitka] outDir  = $outDir"
Write-Host "[nuitka] running ..." -ForegroundColor Cyan
& $python @args
if ($LASTEXITCODE -ne 0) { throw "Nuitka build failed (exit $LASTEXITCODE)" }

Write-Host "[nuitka] done. Product at: $outDir\app.dist\lol-copilot.exe" -ForegroundColor Green
