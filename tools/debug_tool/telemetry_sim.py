#!/usr/bin/env python3
"""telemetry_sim.py — B2 design 3.5 synthetic UDP sender; host clock domain.

Generate v1 records at 100 Hz in batches of 16, without any GUI imports.
Run beside main.py: python3 telemetry_sim.py --seconds 10 --port 6000
"""

import argparse
import math
import socket
import struct
import time
from core.ethernet import packets, HEADER, unpack
from core.video import VIDEO_HEADER, DETECTION_HEADER, DETECTION, Block
from core.yolo import INPUT_BYTES, OUTPUT_BYTES
from core.telemetry import FIELDS, encode


def periodic(seq, tick, hz):
    record = dict.fromkeys(FIELDS, 0)
    record.update(version=1, type=1, seq=seq, scene=1 if tick < hz * 5 else 2,
                  mtime=int((tick + 1) * 100e6 / hz), window_cyc=int(125e6 / hz),
                  clk_sys_hz=100_000_000, clk_npu_hz=150_000_000)
    record['ds_busy'] = int(record['window_cyc'] * (.46 + .12 * math.sin(tick / hz)))
    for p in range(7):
        scale = (1 + .18 * math.sin(tick / hz * 2 + p))
        record[f'p{p}_rd_beat'] = int((p + 1) * 700000 / hz * scale)
        record[f'p{p}_wr_beat'] = int((7 - p) * 500000 / hz * scale) if p else 0
        record[f'p{p}_rd_txn'] = record[f'p{p}_rd_beat'] // 8
        record[f'p{p}_wr_txn'] = record[f'p{p}_wr_beat'] // 8
        record[f'p{p}_wait_sum'] = (p + 3) * (record[f'p{p}_rd_txn'] +
                                                        record[f'p{p}_wr_txn'])
        record[f'p{p}_wait_max'] = (p + 1) * 15
        record[f'p{p}_urg_cnt'] = int(p == 0 and tick % 101 == 0)
    record.update(npu_completed=int(tick % 5 == 0), npu_cycles=6_450_000,
                  post_cycles=1_470_000, boxes=8 + tick % 5,
                  vid_skip=int(tick > 0 and tick % hz == 0))
    return record


def histogram(seq, tick, hz):
    record = dict.fromkeys(FIELDS, 0)
    record.update(version=1, type=2, seq=seq, scene=1 if tick < hz * 5 else 2,
                  mtime=int((tick + 1) * 100e6 / hz), clk_sys_hz=100_000_000,
                  hist_width=16, read_cnt=1200, lat_min=17, lat_max=251, lat_sum=63000)
    for i in range(16):
        record[f'hist{i}'] = int(300 * math.exp(-((i - 3) / 2.5) ** 2))
    return record


def run(host, port, seconds, hz):
    seq = 0
    batch = bytearray()
    started = time.monotonic()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        for tick in range(int(seconds * hz)):
            batch.extend(encode(periodic(seq, tick, hz)))
            seq = (seq + 1) & 0xffffffff
            if (tick + 1) % hz == 0:
                batch.extend(encode(histogram(seq, tick, hz)))
                seq = (seq + 1) & 0xffffffff
            while len(batch) >= 16 * 320:
                for packet in packets(batch[:16 * 320], 3, 0):
                    sock.sendto(packet, (host, port))
                del batch[:16 * 320]
            if tick == int(seconds * hz) - 1 and batch:
                for packet in packets(batch, 3, 0):
                    sock.sendto(packet, (host, port))
                batch.clear()
            delay = started + (tick + 1) / hz - time.monotonic()
            if delay > 0:
                time.sleep(delay)



def demo_pixels():
    """A reproducible 720p road scene, built without image or GUI dependencies."""
    width, height = 1280, 720
    pixels = bytearray(width * height * 2)

    def rectangle(x0, y0, x1, y1, color):
        row = struct.pack('<H', color) * (x1 - x0)
        for y in range(y0, y1):
            pixels[(y * width + x0) * 2:(y * width + x1) * 2] = row

    rectangle(0, 0, width, 330, 0x64f7)
    rectangle(0, 300, width, height, 0x424a)
    rectangle(0, 270, width, 350, 0x328b)
    for x, h in [(30, 180), (190, 250), (410, 150), (700, 210), (1010, 240), (1170, 170)]:
        rectangle(x, 300 - h, min(x + 125, width), 300, 0x3aaf)
        for y in range(320 - h, 270, 30):
            rectangle(x + 15, y, min(x + 105, width), y + 9, 0x8e18)
    for x in (210, 640, 1070):
        rectangle(x, 350, x + 8, 435, 0xadd5)
        rectangle(x, 480, x + 12, 580, 0xadd5)
        rectangle(x, 650, x + 18, 720, 0xadd5)
    # Car, bus and pedestrian silhouettes correspond to the EDDT demo boxes.
    rectangle(360, 370, 565, 515, 0x167b)
    rectangle(388, 338, 535, 410, 0x167b)
    rectangle(400, 349, 524, 393, 0x9e7b)
    rectangle(374, 490, 411, 531, 0x10a3)
    rectangle(513, 490, 550, 531, 0x10a3)
    rectangle(790, 288, 1122, 483, 0xdd66)
    rectangle(806, 305, 1105, 375, 0x9518)
    rectangle(816, 461, 867, 505, 0x10a3)
    rectangle(1044, 461, 1095, 505, 0x10a3)
    rectangle(170, 391, 206, 430, 0xded9)
    rectangle(157, 430, 218, 510, 0xd148)
    rectangle(165, 510, 182, 578, 0x18e5)
    rectangle(194, 510, 211, 578, 0x18e5)
    return bytes(pixels)


def demo_detections(frame_id):
    boxes = [(352, 329, 572, 540, 2, 942), (780, 279, 1133, 514, 5, 908),
             (148, 383, 229, 587, 0, 876)]
    return (DETECTION_HEADER.pack(b'EDDT', 1, len(boxes), frame_id, 0) +
            b''.join(DETECTION.pack(*box) for box in boxes))


def send_block(sock, destination, data, window, offset=0, notify=True):
    for index, packet in enumerate(packets(data, window, offset)):
        if not notify:
            packet = packet[:1] + b'\0' + packet[2:]
        sock.sendto(packet, destination)
        # PC loopback still traverses the actual socket receive thread and file writes.
        if index % 4 == 3:
            time.sleep(.001)


def run_video(host, port, seconds, fps, scene=1):
    pixels = demo_pixels()
    started = time.monotonic()
    destination = host, port
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        for frame_id in range(int(seconds * fps)):
            send_block(sock, destination, demo_detections(frame_id), 2)
            header = VIDEO_HEADER.pack(b'EDVF', 1, 1, 1280, 720, 2560,
                                       frame_id, int(frame_id * 100e6 / fps), scene)
            send_block(sock, destination, header, 0, notify=False)
            send_block(sock, destination, pixels, 0, offset=32)
            record = periodic(frame_id, frame_id, fps)
            record['scene'] = scene
            if scene == 2:
                for field in ('npu_completed', 'npu_cycles', 'post_cycles', 'boxes'):
                    record[field] = 0
            send_block(sock, destination, encode(record), 3)
            delay = started + (frame_id + 1) / fps - time.monotonic()
            if delay > 0:
                time.sleep(delay)


def run_yolo(host, port, ch2=None, output=None):
    """Synthetic raw returns by default; explicit files exercise real model comparisons."""
    from pathlib import Path
    inputs = bytes(INPUT_BYTES) if ch2 is None else Path(ch2).read_bytes()
    outputs = bytes(OUTPUT_BYTES) if output is None else Path(output).read_bytes()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        destination = host, port
        send_block(sock, destination, inputs, 0, notify=False)
        send_block(sock, destination, outputs, 1, notify=False)
        send_block(sock, destination, demo_detections(42), 2)


def run_b3n(sock, model, quant_params, frames):
    """T-NETN host board: receive CH2 and return reference OUTPUT/EDDT over real UDP."""
    from core.yolo import reference_output, reference_detections
    for frame_id in range(frames):
        block = Block()
        while True:
            packet, peer = sock.recvfrom(65535)
            window, notify, offset, data = unpack(packet)
            if window not in (0, 1):
                continue
            block.receive(offset, data, notify)
            if notify:
                if not block.complete(INPUT_BYTES):
                    raise ValueError('B3N simulator: incomplete CH2 tensor')
                break
        output = reference_output(model, block.data(INPUT_BYTES))
        boxes = reference_detections(output, quant_params)
        detections = DETECTION_HEADER.pack(b'EDDT', 1, len(boxes), frame_id, 0)
        detections += b''.join(DETECTION.pack(*box) for box in boxes)
        send_block(sock, peer, output, 1, notify=False)
        send_block(sock, peer, detections, 2)
        print(f'B3N frame_id={frame_id} WIN{window} CH2={INPUT_BYTES} '
              f'OUTPUT={len(output)} detections={len(boxes)}', flush=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=6000)
    parser.add_argument('--seconds', type=float, default=60)
    parser.add_argument('--hz', type=int, choices=range(10, 1001), default=100, metavar='10..1000')
    parser.add_argument('--mode', choices=['telemetry', 'video', 'yolo', 'b3n'], default='telemetry')
    parser.add_argument('--fps', type=int, choices=range(1, 61), default=10, metavar='1..60')
    parser.add_argument('--ch2', help='YOLO mode: raw CH2 input file')
    parser.add_argument('--output', help='YOLO mode: raw NPU OUTPUT file')
    parser.add_argument('--model', help='B3N: compiled NPU model directory')
    parser.add_argument('--quant', help='B3N: quantization JSON')
    parser.add_argument('--frames', type=int, default=1, help='B3N: image count')
    args = parser.parse_args()
    if args.mode == 'telemetry':
        run(args.host, args.port, args.seconds, args.hz)
    elif args.mode == 'video':
        run_video(args.host, args.port, args.seconds, args.fps)
    elif args.mode == 'yolo':
        run_yolo(args.host, args.port, args.ch2, args.output)
    else:
        import json
        from pathlib import Path
        parameters = json.loads(Path(args.quant).read_text())
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind((args.host, args.port))
            print(f'B3N listening {sock.getsockname()}', flush=True)
            run_b3n(sock, args.model, parameters, args.frames)


if __name__ == '__main__':
    main()
