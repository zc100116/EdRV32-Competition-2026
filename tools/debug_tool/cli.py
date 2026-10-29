#!/usr/bin/env python3
"""Terminal client for EdRV32 调试工具.

Talks to the REST API of a running instance (GUI or --headless), so the
terminal and the desktop window always see the same serial session.
AI agents can use this CLI or plain HTTP (curl) interchangeably.

Examples:
  python cli.py ports                      # list COM ports
  python cli.py status                     # connection state + counters
  python cli.py connect COM7 --baud 115200
  python cli.py send "hello"               # default line ending: \\r
  python cli.py tail                       # print the buffer, -f to follow
  python cli.py clear
  python cli.py save [path]
  python cli.py cmd list
  python cli.py cmd run coremark           # fire a stored command by id
  python cli.py cmd add "CoreMark" "6" --ending cr --id coremark
  python cli.py cmd del coremark
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_URL = os.environ.get("SERIAL2_URL", "http://127.0.0.1:8765")


def request(method, path, body=None, timeout=5):
    url = BASE + path
    data = None
    headers = {"Content-Type": "application/json"}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers,
                                 method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        try:
            detail = json.loads(detail).get("error", detail)
        except json.JSONDecodeError:
            pass
        raise SystemExit(f"HTTP {exc.code}: {detail}")
    except urllib.error.URLError:
        raise SystemExit(f"cannot reach {BASE} -- is the console running?")


def fmt_line(entry):
    from datetime import datetime
    ms = entry["ts"]
    stamp = datetime.fromtimestamp(ms / 1000.0).strftime("%H:%M:%S")
    stamp += f".{ms % 1000:03d}"
    return f"[{stamp}][{entry['dir'].upper():>2}] {entry['text']}"


def print_json(obj):
    print(json.dumps(obj, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default=DEFAULT_URL,
                        help="API base URL (env SERIAL2_URL)")
    parser.add_argument("--json", action="store_true",
                        help="print raw JSON responses")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("ports")
    sub.add_parser("status")
    p = sub.add_parser("connect")
    p.add_argument("port")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--data-bits", type=int, default=8)
    p.add_argument("--parity", default="none",
                   choices=["none", "even", "odd", "mark", "space"])
    p.add_argument("--stop-bits", default="1", choices=["1", "1.5", "2"])
    sub.add_parser("disconnect")

    p = sub.add_parser("program", help="program SRAM .bin or load and run ELF through BIOS")
    p.add_argument("path")
    p.add_argument("--elf", action="store_true")
    p.add_argument("--baud", type=int, choices=(115200, 921600, 2000000), default=2000000)

    p = sub.add_parser("send")
    p.add_argument("text")
    p.add_argument("--ending", default="cr",
                   choices=["none", "cr", "lf", "crlf"])
    p.add_argument("--hex", action="store_true",
                   help="interpret text as hex bytes (e.g. '01 03 FF')")

    p = sub.add_parser("sendfile")
    p.add_argument("path", nargs="?")
    p.add_argument("--echo", action="store_true",
                   help="also log the file bytes into the console buffer")
    p.add_argument("--cancel", action="store_true",
                   help="cancel the running transfer instead of starting one")

    p = sub.add_parser("modem")
    p.add_argument("--dtr", choices=["on", "off"])
    p.add_argument("--rts", choices=["on", "off"])

    p = sub.add_parser("config")
    p.add_argument("--encoding", choices=["utf-8", "gbk", "ascii"])

    p = sub.add_parser("tail")
    p.add_argument("-f", "--follow", action="store_true")
    p.add_argument("--dir", choices=["rx", "tx", "sys"])
    sub.add_parser("clear")

    p = sub.add_parser("save")
    p.add_argument("path", nargs="?")

    p = sub.add_parser("cmd")
    cmd_sub = p.add_subparsers(dest="subcmd", required=True)
    cmd_sub.add_parser("list")
    p_run = cmd_sub.add_parser("run")
    p_run.add_argument("id")
    p_add = cmd_sub.add_parser("add")
    p_add.add_argument("label")
    p_add.add_argument("payload")
    p_add.add_argument("--ending", default="cr",
                       choices=["none", "cr", "lf", "crlf"])
    p_add.add_argument("--id")
    p_del = cmd_sub.add_parser("del")
    p_del.add_argument("id")
    p_exp = cmd_sub.add_parser("export")
    p_exp.add_argument("path")
    p_imp = cmd_sub.add_parser("import")
    p_imp.add_argument("path")

    p = sub.add_parser("rules")
    rule_sub = p.add_subparsers(dest="subcmd", required=True)
    rule_sub.add_parser("list")
    p_radd = rule_sub.add_parser("add")
    p_radd.add_argument("name")
    p_radd.add_argument("pattern")
    p_radd.add_argument("--id")
    p_radd.add_argument("--key-group", type=int, default=0)
    p_radd.add_argument("--value-group", type=int, default=1)
    p_radd.add_argument("--base", type=int, default=10, choices=[10, 16])
    p_radd.add_argument("--scale", type=float, default=1.0)
    p_radd.add_argument("--unit", default="")
    p_radd.add_argument("--disabled", action="store_true")
    p_rset = rule_sub.add_parser("set")
    p_rset.add_argument("id")
    p_rset.add_argument("--name")
    p_rset.add_argument("--pattern")
    p_rset.add_argument("--key-group", type=int)
    p_rset.add_argument("--value-group", type=int)
    p_rset.add_argument("--base", type=int, choices=[10, 16])
    p_rset.add_argument("--scale", type=float)
    p_rset.add_argument("--unit")
    p_rset.add_argument("--on", dest="enabled", action="store_true",
                        default=None)
    p_rset.add_argument("--off", dest="enabled", action="store_false")
    p_rdel = rule_sub.add_parser("del")
    p_rdel.add_argument("id")

    p = sub.add_parser("params")
    p.add_argument("--clear", action="store_true")

    p = sub.add_parser("telemetry", help="latest DDR measurements and CSV")
    p.add_argument("action", choices=["latest", "export", "replay", "clear"])
    p.add_argument("path", nargs="?")
    p = sub.add_parser("yolo", help="send compiler output or RGB565 test image")
    p.add_argument("kind", choices=["model", "image"])
    p.add_argument("path")
    p.add_argument("--board-ip", default="192.168.1.10")
    p.add_argument("--board-port", type=int, default=5000)
    p.add_argument("--local-port", type=int, default=6000)
    p.add_argument("--window", type=int, choices=[0, 1], default=0)
    p = sub.add_parser("scene")
    p.add_argument("name")
    p.add_argument("--rate", type=int, default=100)
    p = sub.add_parser("listen", help="start the shared UDP listener")
    p.add_argument("--port", type=int, default=6000)
    p.add_argument("--directory")
    p.add_argument("--mode", choices=["files", "yolo", "video"], default="files")

    args = parser.parse_args()
    global BASE
    BASE = args.url.rstrip("/")

    if args.cmd == "telemetry":
        if args.action == "latest":
            print_json(request("GET", "/api/telemetry"))
        else:
            print_json(request("POST", "/api/telemetry/" + args.action,
                               {"path": os.path.abspath(args.path)} if args.path else {}))
    elif args.cmd == "listen":
        print_json(request("POST", "/api/ethernet/receive/start",
                           {"localPort": args.port, "directory": args.directory, "mode": args.mode}))
    elif args.cmd == "scene":
        print_json(request("POST", "/api/scenes/send", {"name": args.name, "rate": args.rate}))
    elif args.cmd == "yolo":
        body = {"path": os.path.abspath(args.path), "boardIp": args.board_ip,
                "boardPort": args.board_port, "localPort": args.local_port}
        if args.kind == "image":
            body["window"] = args.window
        request("POST", "/api/yolo/" + args.kind, body)
        while True:
            state = request("GET", "/api/ethernet/status")["tx"]
            if not state["active"]:
                print_json(state)
                if state["error"]:
                    raise SystemExit(1)
                break
            time.sleep(0.2)
    elif args.cmd == "ports":
        ports = request("GET", "/api/ports")["ports"]
        if args.json:
            print_json(ports)
        elif not ports:
            print("(no serial ports found)")
        else:
            for p_ in ports:
                print(f"{p_['device']:<8} {p_['description']}")
    elif args.cmd == "status":
        st = request("GET", "/api/status")
        if args.json:
            print_json(st)
        else:
            cfg = st["config"]
            link = f"{cfg['port']} @ {cfg['baud']}" if st["connected"] \
                else "disconnected"
            print(f"link   : {link}")
            print(f"rx/tx  : {st['rxBytes']} / {st['txBytes']} bytes")
            print(f"lastSeq: {st['lastSeq']}")
    elif args.cmd == "connect":
        print_json(request("POST", "/api/connect", {
            "port": args.port, "baud": args.baud,
            "dataBits": args.data_bits, "parity": args.parity,
            "stopBits": args.stop_bits}))
    elif args.cmd == "disconnect":
        print_json(request("POST", "/api/disconnect", {}))
    elif args.cmd == "program":
        request("POST", "/api/program", {"path": os.path.abspath(args.path),
                                          "elf": args.elf, "baud": args.baud})
        print("按住 KEY1 按复位；等待 BIOS menu", flush=True)
        while True:
            st = request("GET", "/api/program/status")
            print(f"\r{st['phase']}: {st['sent']}/{st['total']} B", end="", flush=True)
            if not st["active"]:
                print()
                print_json(st)
                if st["error"] or (st["result"] and "FAIL" in st["result"]):
                    raise SystemExit(1)
                break
            time.sleep(0.2)
    elif args.cmd == "send":
        request("POST", "/api/send", {"text": args.text,
                                      "ending": args.ending,
                                      "hex": args.hex})
        print("sent.")
    elif args.cmd == "sendfile":
        if args.cancel:
            request("POST", "/api/file/cancel", {})
            print("cancel requested.")
        else:
            if not args.path:
                raise SystemExit("sendfile requires a file path")
            request("POST", "/api/file/send", {"path": args.path,
                                               "echo": args.echo})
            while True:
                st = request("GET", "/api/file/status")
                if not st.get("active"):
                    if st.get("error"):
                        raise SystemExit(f"transfer failed: {st['error']}")
                    if st.get("cancelled"):
                        print(f"cancelled at {st.get('sent', 0)} B")
                    else:
                        print(f"sent {st.get('sent', 0)} B: "
                              f"{st.get('name', '')}")
                    break
                total = st.get("total") or 1
                pct = 100.0 * st.get("sent", 0) / total
                print(f"\r{st.get('sent', 0)}/{total} B ({pct:.1f}%)",
                      end="", flush=True)
                time.sleep(0.2)
            print()
    elif args.cmd == "modem":
        body = {}
        if args.dtr is not None:
            body["dtr"] = args.dtr == "on"
        if args.rts is not None:
            body["rts"] = args.rts == "on"
        if not body:
            raise SystemExit("nothing to set: pass --dtr/--rts on|off")
        print_json(request("POST", "/api/modem", body))
    elif args.cmd == "config":
        if args.encoding:
            request("POST", "/api/options", {"encoding": args.encoding})
        st = request("GET", "/api/status")
        print(f"encoding: {st.get('encoding')}  dtr: {st.get('dtr')}  "
              f"rts: {st.get('rts')}")
    elif args.cmd == "tail":
        since = 0
        while True:
            data = request("GET", "/api/buffer?" + urllib.parse.urlencode(
                {"since": since, "dir": args.dir or "", "limit": 1000}))
            for entry in data["entries"]:
                print(fmt_line(entry))
            since = data["lastSeq"]
            if not args.follow:
                break
            time.sleep(0.4)
    elif args.cmd == "clear":
        request("POST", "/api/clear", {})
        print("cleared.")
    elif args.cmd == "save":
        result = request("POST", "/api/save",
                         {"path": args.path} if args.path else {})
        print(f"saved {result['lines']} lines -> {result['path']}")
    elif args.cmd == "cmd":
        if args.subcmd == "list":
            commands = request("GET", "/api/commands")["commands"]
            if args.json:
                print_json(commands)
            else:
                for c in commands:
                    print(f"{c['id']:<12} {c['label']:<16} "
                          f"payload={c['payload']!r} ending={c['ending']}")
        elif args.subcmd == "run":
            request("POST", f"/api/commands/{args.id}/send", {})
            print("sent.")
        elif args.subcmd == "add":
            body = {"label": args.label, "payload": args.payload,
                    "ending": args.ending}
            if args.id:
                body["id"] = args.id
            print_json(request("POST", "/api/commands", body))
        elif args.subcmd == "del":
            request("DELETE", f"/api/commands/{args.id}")
            print("deleted.")
        elif args.subcmd == "export":
            commands = request("GET", "/api/commands")["commands"]
            with open(args.path, "w", encoding="utf-8") as fh:
                json.dump(commands, fh, ensure_ascii=False, indent=2)
            print(f"exported {len(commands)} commands -> {args.path}")
        elif args.subcmd == "import":
            with open(args.path, "r", encoding="utf-8") as fh:
                commands = json.load(fh)
            result = request("POST", "/api/commands/replace",
                             {"commands": commands})
            print(f"imported {len(result['commands'])} commands "
                  f"(replaced the whole list)")
    elif args.cmd == "rules":
        if args.subcmd == "list":
            rules = request("GET", "/api/rules")["rules"]
            if args.json:
                print_json(rules)
            elif not rules:
                print("(no match rules)")
            else:
                for r in rules:
                    state = "on " if r.get("enabled", True) else "off"
                    print(f"{r['id']:<14} [{state}] {r['name']:<16} "
                          f"/{r['pattern']}/ key:{r.get('keyGroup',0)} "
                          f"val:{r.get('valueGroup',1)} base{r.get('base',10)}"
                          f" x{r.get('scale',1)} {r.get('unit','')}")
        elif args.subcmd == "add":
            body = {"name": args.name, "pattern": args.pattern,
                    "keyGroup": args.key_group, "valueGroup": args.value_group,
                    "base": args.base, "scale": args.scale,
                    "unit": args.unit, "enabled": not args.disabled}
            if args.id:
                body["id"] = args.id
            print_json(request("POST", "/api/rules", body))
        elif args.subcmd == "set":
            body = {}
            for field, arg in (("name", args.name), ("pattern", args.pattern),
                               ("keyGroup", args.key_group),
                               ("valueGroup", args.value_group),
                               ("base", args.base), ("scale", args.scale),
                               ("unit", args.unit),
                               ("enabled", args.enabled)):
                if arg is not None:
                    body[field] = arg
            print_json(request("PUT", f"/api/rules/{args.id}", body))
        elif args.subcmd == "del":
            request("DELETE", f"/api/rules/{args.id}")
            print("deleted.")
    elif args.cmd == "params":
        if args.clear:
            request("POST", "/api/params/clear", {})
            print("cleared.")
        else:
            params = request("GET", "/api/params")["params"]
            if args.json:
                print_json(params)
            elif not params:
                print("(no parameters captured yet)")
            else:
                for p in params:
                    print(f"{p['name']:<28} {p['value']:>14.6g} "
                          f"{p['unit']:<4} (raw {p['raw']}, "
                          f"x{p['count']})")


if __name__ == "__main__":
    main()
