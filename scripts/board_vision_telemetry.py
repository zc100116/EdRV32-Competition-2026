#!/usr/bin/env python3
"""Decode the standalone stereo/HDMI board's G,hex,... UART records."""

import argparse
import re
import sys
import threading
import time


FIELDS = (
    "mode", "source", "drop", "start", "ok", "error", "flip",
    "scan", "underflow", "total", "prep", "fetch", "sample",
    "drain", "read_ar", "read_beats", "read_ar_stall", "read_wait",
    "write_aw_stall", "write_w_stall", "write_b_wait", "config",
    "writer_tail", "live_phase", "live_cycles", "cam0_raw", "cam1_raw",
    "pixel_output", "source_replaced", "input_stall", "output_stall",
    "camera_w_stall", "geometry_owner_wait", "geometry_downstream_wait",
    "mux_eof", "unpack_eof", "point_eof", "spatial_eof",
    "mux_error", "pixel_cfg_pending", "writer_active",
    "mux_valid_cycles", "pixel_valid_cycles",
    "cam0_overflow", "cam1_overflow", "writer_error", "active_camera",
)

PHASES = {
    0: "idle/setup", 1: "block-prep", 2: "DDR-fetch",
    3: "bilinear", 4: "band-drain", 5: "config", 6: "writer-tail",
}


def decode(line):
    parts = line.strip().split(",")
    if len(parts) != len(FIELDS) + 1 or parts[0] != "G":
        raise ValueError("expected G followed by 47 hex fields")
    if any(len(part) != 8 for part in parts[1:]):
        raise ValueError("each field must have eight hex digits")
    return dict(zip(FIELDS, (int(part, 16) for part in parts[1:])))


def format_record(values, clock_hz):
    ms = lambda name: values[name] * 1000.0 / clock_hz
    phase = PHASES.get(values["live_phase"], "unknown")
    return (
        f"mode={values['mode']}  FPS/s: cam0_raw={values['cam0_raw']} "
        f"cam1_raw={values['cam1_raw']} pixel={values['pixel_output']} "
        f"camera_to_DDR={values['source']} "
        f"geometry={values['ok']} display_flip={values['flip']} "
        f"DDR_scan={values['scan']}  "
        f"writer_drops={values['drop']} scheduler_replaced={values['source_replaced']} "
        f"errors={values['error']} "
        f"underflows={values['underflow']}\n"
        f"  last completed geometry frame (ms): total={ms('total'):.3f} "
        f"config={ms('config'):.3f} prep={ms('prep'):.3f} "
        f"fetch={ms('fetch'):.3f} bilinear={ms('sample'):.3f} "
        f"drain={ms('drain'):.3f} writer_tail={ms('writer_tail'):.3f}\n"
        f"  last frame DDR: read_AR={values['read_ar']} "
        f"requested_256b_beats={values['read_beats']} "
        f"AR_stall={ms('read_ar_stall'):.3f}ms "
        f"R_wait={ms('read_wait'):.3f}ms "
        f"AW_stall={ms('write_aw_stall'):.3f}ms "
        f"W_stall={ms('write_w_stall'):.3f}ms "
        f"(owner={ms('geometry_owner_wait'):.3f}ms "
        f"downstream={ms('geometry_downstream_wait'):.3f}ms) "
        f"camera_W_stall={ms('camera_w_stall'):.3f}ms "
        f"B_wait={ms('write_b_wait'):.3f}ms\n"
        f"  stream stalls/s: camera_to_pixel={ms('input_stall'):.3f}ms "
        f"pixel_to_writer={ms('output_stall'):.3f}ms\n"
        f"  EOF/s: mux={values['mux_eof']} unpack={values['unpack_eof']} "
        f"point={values['point_eof']} spatial={values['spatial_eof']} "
        f"packed={values['pixel_output']}  "
        f"valid_time/s: mux={ms('mux_valid_cycles'):.3f}ms "
        f"pixel={ms('pixel_valid_cycles'):.3f}ms  "
        f"flags: mux_error={values['mux_error']} "
        f"cfg_pending={values['pixel_cfg_pending']} "
        f"writer_active={values['writer_active']} "
        f"cam0_overflow={values['cam0_overflow']} "
        f"cam1_overflow={values['cam1_overflow']} "
        f"writer_error={values['writer_error']} "
        f"selected_camera={values['active_camera']}\n"
        f"  current geometry: phase={phase} "
        f"elapsed={ms('live_cycles'):.3f}ms"
    )


def send_command(port, command):
    command = command.strip().upper()
    if not re.fullmatch(r"(?:M\d{1,2}|P\d|R\d{1,3}|X\d{1,4}|Y\d{1,4}|A|S)", command):
        raise ValueError("use M0..M31, P0..P7, R0..R359, X640..X2560, Y360..Y1440, A, or S")
    limits = {"M": (0, 31), "P": (0, 7), "R": (0, 359),
              "X": (640, 2560), "Y": (360, 1440)}
    if command[0] in limits:
        lower, upper = limits[command[0]]
        if not lower <= int(command[1:]) <= upper:
            raise ValueError(f"{command[0]} value must be {lower}..{upper}")
    # The FPGA no longer requires LF, but it remains a useful separator for
    # several --command arguments sent back-to-back.
    port.write(command.encode("ascii") + b"\n")
    print(f"sent {command}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Windows serial port, e.g. COM3")
    parser.add_argument("--wait-port", action="store_true",
                        help="wait for another program to release the port")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--clock-hz", type=int, default=125000000)
    parser.add_argument("--command", action="append", default=[],
                        help="send M/P/R/X/Y, A or S after opening")
    parser.add_argument("--interactive", action="store_true",
                        help="read additional commands from the console")
    args = parser.parse_args()
    if args.clock_hz <= 0:
        parser.error("--clock-hz must be positive")
    if not args.port and (args.command or args.interactive):
        parser.error("sending commands requires --port")

    if args.port:
        try:
            import serial
        except ImportError as exc:
            raise SystemExit("Install pyserial: python -m pip install pyserial") from exc
        waiting = False
        while True:
            try:
                source = serial.Serial(args.port, args.baud, timeout=2)
                print(f"Monitoring {args.port} at {args.baud} baud", flush=True)
                break
            except serial.SerialException as exc:
                if not args.wait_port:
                    raise SystemExit(f"Cannot open {args.port}: {exc}") from exc
                if not waiting:
                    print(f"Waiting for {args.port} to become available...",
                          flush=True)
                    waiting = True
                time.sleep(2)
    else:
        source = sys.stdin.buffer

    if args.port:
        if args.command:
            # CP210x TX can lose the first byte immediately after open.
            time.sleep(1.0)
        for command in args.command:
            send_command(source, command)
        if args.interactive:
            def read_commands():
                for line in sys.stdin:
                    try:
                        send_command(source, line)
                    except ValueError as exc:
                        print(exc, file=sys.stderr)

            threading.Thread(target=read_commands, daemon=True).start()

    try:
        while True:
            raw = source.readline()
            if not raw:
                if args.port:
                    continue
                break
            try:
                values = decode(raw.decode("ascii"))
            except (UnicodeDecodeError, ValueError) as exc:
                print(f"skip malformed telemetry: {exc}", file=sys.stderr)
                continue
            print(format_record(values, args.clock_hz), flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        if args.port:
            source.close()


if __name__ == "__main__":
    main()
