import sys


def main() -> int:
    argv = sys.argv[1:]
    if argv and argv[0] == "--cli":
        from app.cli.debug import run_cli
        return run_cli(argv[1:])
    from app.view.app import run_gui
    return run_gui()


if __name__ == "__main__":
    sys.exit(main())
