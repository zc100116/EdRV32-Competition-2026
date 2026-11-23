#!/usr/bin/env python3
"""performance.py: gpu-spec 7; measure public command cycles and judge GT-25.
Host postprocessor, no clock domain; default DDR settings are supplied by run.py.
"""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path[:0] = [str(ROOT), str(ROOT/'verif/block/gpu')]
from tools.gpu.scene import unpack
from scene import WORKLOADS


def measure(root):
    outputs = [root/name for name in json.loads((root/'runs.json').read_text())]
    report = ['GT-25: clk_gpu=180 MHz; default DDR delay; cycles include APB observation.']
    failures = []
    for name, out in zip(WORKLOADS, outputs):
        data = (out/'commands.bin').read_bytes()
        commands = [data[i:i+32] for i in range(0, len(data), 32)]
        timing = [line.split() for line in (out/'timing.txt').read_text().splitlines()]
        assert len(timing) == len(commands), f'{name}: missing per-command timing'
        cycles = [int(row[3])-int(row[2]) for row in timing]
        for index, row in enumerate(timing):
            assert int(row[1]) == 1 and int(row[4], 16) == 1, f'{name}: command {index}'
            report.append(f'{name} command {index+1}: {cycles[index]} cycles')
        if name == 'resolve':
            total = sum(cycles[i] for i, command in enumerate(commands) if command[0] == 0x40)
            report.append(f'AA RESOLVE 640x360: {total} cycles, {total/180000:.6f} ms; '
                          f'limit=90000 cycles; {"PASS" if total <= 90000 else "FAIL"}')
            if total > 90000:
                failures.append('AA RESOLVE > 90000 cycles')
            continue
        opcode = 0x21 if name == 'quad' else 0x22 if name == 'objects' else 0x20
        layout = {0x21: 'CMD_DRAW_QUAD', 0x22: 'CMD_OBJ_STEP', 0x20: 'CMD_DRAW_TRI'}[opcode]
        indices = [i for i, command in enumerate(commands) if command[0] == opcode]
        empty, loaded = indices
        count = unpack(layout, commands[loaded])['COUNT']
        elapsed = cycles[loaded]-cycles[empty]
        assert elapsed > 0, f'{name}: non-positive measured work cycles {elapsed}'
        regs = json.loads((out/'expected.regs.json').read_text())
        units = count*3 if name == 'vertex' else regs['PERF[4]'] if name in (
            'nearest', 'bilinear', 'trilinear', 'palette_i4', 'palette_i8') else count
        rate = units/elapsed
        report.append(f'{name}: total={cycles[loaded]}, fixed={cycles[empty]}, '
                      f'net={elapsed}, units={units}, cycles/unit={elapsed/units:.6f}, '
                      f'units/cycle={rate:.6f}')
        if name == 'quad':
            passed = elapsed/count <= 80
            report.append(f'quad <=80 cycles/object: {"PASS" if passed else "FAIL"}')
            if not passed:
                failures.append('quad > 80 cycles/object')
        elif name in ['nearest', 'bilinear', 'trilinear']:
            target = {'nearest': 4, 'bilinear': 2, 'trilinear': 1}[name]
            report.append(f'{name}: internal steady target={target} pixels/cycle; report only')
        elif name == 'vertex':
            report.append('vertex: internal steady target=0.5 vertices/cycle; report only')
        elif name == 'setup':
            report.append('setup: internal steady target=0.125 triangles/cycle; report only')
        elif name == 'objects':
            report.append('objects: internal steady target=1 object/cycle; report only')
        else:
            report.append('palette preload: internal limit=264 cycles; command total above; '
                          'internal preload interval requires unit test')
    report.append('Resource targets: DRM about 195, LUT <=60000, APM about 180; PDS required.')
    (root/'performance.txt').write_text('\n'.join(report)+'\n')
    print('\n'.join(report))
    assert not failures, '; '.join(failures)
    print('PASS GT-25 performance')


if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'rtl'
    subprocess.run([sys.executable, str(ROOT/'verif/block/gpu/run.py'), mode, 'gt25'],
                   cwd=ROOT, check=True)
    if mode in ['rtl', 'compare']:
        measure(ROOT/'build/gpu/block/gt25')
    else:
        print('GT-25 model generation only: no timing or performance verdict')
