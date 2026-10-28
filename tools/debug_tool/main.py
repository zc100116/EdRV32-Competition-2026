#!/usr/bin/env python3
"""EdRV32 调试工具 -- entry point.

  python main.py                     # GUI + embedded REST API (default)
  python main.py --headless          # no GUI: engine + REST API only
  python main.py --api-port 9000     # change the API listen port
  python main.py --no-api            # GUI only, do not expose the API
  python main.py --connect COM7 --baud 115200   # auto-connect on start

The REST API is the single control surface for terminal (cli.py) and
AI agents: every GUI action maps to an endpoint.
"""

import argparse
import sys


def main():
    parser = argparse.ArgumentParser(description="EdRV32 调试工具")
    parser.add_argument("--headless", action="store_true",
                        help="run engine + REST API without the GUI")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--api-port", type=int, default=8765)
    parser.add_argument("--no-api", action="store_true")
    parser.add_argument("--connect", metavar="PORT",
                        help="open this serial port on startup")
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()

    from core.engine import SerialEngine
    engine = SerialEngine()

    api = None
    if not args.no_api:
        from core.api import ApiServer
        api = ApiServer(engine, args.host, args.api_port)
        try:
            url = api.start()
            print(f"[api] REST API listening on {url}")
        except OSError as exc:
            print(f"[api] failed to bind {args.host}:{args.api_port}: {exc}")
            api = None

    if args.connect:
        try:
            engine.connect(args.connect, args.baud)
            print(f"[serial] connected {args.connect} @ {args.baud}")
        except Exception as exc:
            print(f"[serial] connect failed: {exc}")

    if args.headless:
        print("[headless] Ctrl+C to stop")
        try:
            import threading
            threading.Event().wait()
        except KeyboardInterrupt:
            pass
        finally:
            engine.ethernet.stop_receive()
            engine.disconnect(silent=True)
            if api:
                api.stop()
        return 0

    from PySide6.QtGui import QFont
    from PySide6.QtWidgets import QApplication
    from gui.app import MainWindow

    app = QApplication(sys.argv)
    app.setApplicationName("EdRV32 调试工具")
    # crisp text on Windows: force the UI font with antialiasing preferred
    font = QFont("Microsoft YaHei UI", 9)
    font.setStyleStrategy(QFont.PreferAntialias)
    app.setFont(font)
    window = MainWindow(engine)
    window.show()
    code = app.exec()
    engine.ethernet.stop_receive()
    engine.disconnect(silent=True)
    if api:
        api.stop()
    return code


if __name__ == "__main__":
    sys.exit(main())
