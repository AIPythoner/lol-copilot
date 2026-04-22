"""Launcher — run this file directly to start the GUI (no args needed)."""
import runpy
import sys


def main() -> int:
    # Defer to the package so behaviour stays identical to `python -m app`.
    # Any CLI args still flow through (e.g. `python app.py --cli status`).
    sys.argv[0] = sys.argv[0]
    runpy.run_module("app", run_name="__main__", alter_sys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
