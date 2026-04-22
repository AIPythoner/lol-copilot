"""Launcher — run this file directly to start the GUI (no args needed)."""
import sys


def main() -> int:
    # Defer to the package so behaviour stays identical to `python -m app`.
    # Keep this as an explicit import; PyInstaller cannot reliably discover
    # dynamic runpy execution of app.__main__.
    from app.__main__ import main as package_main

    return package_main()


if __name__ == "__main__":
    sys.exit(main())
