#!/usr/bin/env python3
# File: net_latency.py
# Spec: npu-testplan NET-02; npu-spec 2.6, 5.6.
# Description: Run the real 68-descriptor network with post disabled/enabled at latency94.
# Clock domain: host; DUT clk_npu=180 MHz, clk_mem=125 MHz.
"""Run under flock /tmp/edrv32-sim.lock after preparing build/npu/yolo."""
import json
from pathlib import Path
import re
import struct
import subprocess

from run import BUILD, ROOT, build, network_raw
from fixtures import BASE, write_hex, write_regs
from prepare import Image, regs
from tools.npu.yolo_post_ref import decode_candidates


def main():
    network = BUILD / 'yolo'
    config = regs(network)
    memory = Image(network)
    raw = network_raw(network)
    heads = json.loads((ROOT / 'sw/lib/yolo_tables.json').read_text())
    candidates = decode_candidates(raw, heads)
    expected = {anchor: (tuple(box), prob, cls, anchor)
                for box, prob, cls, anchor in candidates}
    executable = build()
    rows = []
    for enabled in (0, 1):
        path = BUILD / 'post' / 'net_02' / f'en{enabled}_latency94'
        path.mkdir(parents=True, exist_ok=True)
        write_hex(path / 'mem_state.hex', memory.data)
        values = {**config, **{key: value for key, value in BASE.items()
                               if key.startswith('POST_')}}
        # Retain raw cls in EN=1 so the final raw B marks the complete core.
        values['POST_CTRL'] = 3 if enabled else 0
        write_regs(path, values)
        count = len(candidates) if enabled else 0
        (path / 'expected.txt').write_text(f'{count} {enabled}\n')
        reference = {}
        for head in heads:
            for key, planes in [('box_offset', 4), ('class_offset', 5)]:
                start = head[key]
                reference.update(enumerate(raw[start:start + planes * head['plane_stride']],
                                           values['OUTPUT_BASE'] + start))
        write_hex(path / 'ref_out.hex', reference)
        log_path = path / 'run.log'
        with log_path.open('w') as log:
            subprocess.run([str(executable), f'+CASE_DIR={path}', '+TEST_ID=NET-02',
                            '+MEM_MODE=latency', '+MEM_LAT=94'], cwd=ROOT, stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=1200)
        output = log_path.read_text()
        assert 'PASS POST' in output, log_path
        packed = bytes.fromhex((path / 'actual_candidates.hex').read_text())
        assert packed[count * 24:] == bytes((-count * 24) % 32)
        observed = []
        for x0, y0, x1, y1, prob, cls, anchor in struct.iter_unpack('<4iIHH', packed[:count*24]):
            record = ((x0, y0, x1, y1), prob, cls, anchor)
            assert record == expected[anchor], (record, expected[anchor])
            observed.append(anchor)
        # Each final cls plane closes its head in row/pair order; derive head order
        # from public descriptors, independently of the oracle's traversal order.
        order = []
        if enabled:
            for n in range(config['DESC_COUNT']):
                tag = memory.word(config['DESC_BASE'] + n * 64 + 52)
                if tag & 3 == 2:
                    head = tag >> 2 & 3
                    base, size = ((0, 3840), (3840, 960), (4800, 240))[head]
                    order.extend(anchor for anchor in range(base, base + size) if anchor in expected)
        assert observed == order, (observed, order)
        row = dict(enabled=enabled, count=count)
        row.update({key: int(value) for key, value in re.findall(r'(\w+)=(-?\d+)', output)})
        if not enabled:
            row.update(table_last=0, drain_gather=0, tail_cycles=0)
        rows.append(row)
        print(f'PASS NET-02 EN={enabled} latency94: {row}', flush=True)
    target = BUILD / 'post' / 'net_02' / 'performance.json'
    target.write_text(json.dumps(rows, indent=2) + '\n')


if __name__ == '__main__':
    main()
