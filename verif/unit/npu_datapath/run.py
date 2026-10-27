#!/usr/bin/env python3
# File: run.py
# Spec: npu-spec 2.1-2.3, 5.4; npu-testplan OP-01..08.
# Description: Generate independent reference cases and run one serial RTL simulation.
# Clock domain: host tool.
"""Generate CONV images using the public tools, then exercise the frozen datapath port."""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files

TEST = ROOT / 'verif/unit/npu_datapath'
OUT = ROOT / 'build/npu_datapath'
PYTHON = Path.home() / '.local/opt/edrv32-py/bin/python'


def read_hex(path):
    data = {}
    address = 0
    for token in path.read_text().split():
        if token.startswith('@'):
            address = int(token[1:], 16)
        else:
            data[address] = int(token, 16)
            address += 1
    return data


def dump(path, values, digits):
    path.write_text(''.join(f'{value:0{digits}x}\n' for value in values))


def prepare(name, layer, seed, stall=0, cancel=0):
    case = OUT / name
    case.mkdir(parents=True, exist_ok=True)
    config = case / 'config.json'
    config.write_text(json.dumps({'layers': [dict(op='conv', in_from='input', **layer)]}))
    environment = {**os.environ, 'PYTHONPYCACHEPREFIX': str(OUT / 'pycache'),
                   'OPENBLAS_NUM_THREADS': '1'}
    subprocess.run([str(PYTHON), str(ROOT / 'tools/npu/gen_case.py'), '--config',
                    str(config), '--seed', str(seed), '--out', str(case)], check=True,
                   env=environment)
    subprocess.run([str(PYTHON), str(ROOT / 'tools/npu/ref/npu_ref.py'), str(case)],
                   check=True, env=environment)
    memory = {}
    for path in sorted(case.glob('mem_*.hex')):
        memory.update(read_hex(path))
    regs = dict((n, int(v, 16)) for n, v in
                (line.split() for line in (case / 'regs.txt').read_text().splitlines()))
    desc = memory[regs['DESC_BASE'] // 32] | memory[regs['DESC_BASE'] // 32 + 1] << 256
    words = [(desc >> (32*i)) & 0xffffffff for i in range(16)]
    iw, ih = words[8] & 4095, words[8] >> 16
    ow, oh = words[9] & 4095, words[9] >> 16
    flags = words[0]
    cb = words[10] & 63
    blocks = words[10] >> 8 & 15
    half = bool(flags & 512)
    c4 = bool(flags & 256)
    bases = [regs[n + '_BASE'] for n in ['MODEL', 'WORK', 'INPUT', 'OUTPUT']]
    input_base = bases[flags >> 12 & 3] + words[1]
    residual_base = bases[flags >> 16 & 3] + words[5]
    weights = (blocks - 1) * words[12] + words[12] // (2 if half and not c4 else 1)
    quant = regs['MODEL_BASE'] + words[7]
    wbase = regs['MODEL_BASE'] + words[6]
    planes = 2 * blocks - half
    dump(case / 'meta.hex', words + [weights // 32, planes, stall, cancel], 8)
    dump(case / 'weights.hex', (memory[(wbase + i) // 32] for i in range(0, weights, 32)), 64)
    dump(case / 'params.hex', ((memory[(quant + b*512 + c*8) // 32]
                               >> (64*(c % 4))) & ((1 << 64) - 1)
                              for b in range(blocks) for c in range(32)), 16)
    dump(case / 'lut.hex', ((memory[(quant + b*512 + 256 + c) // 32]
                            >> (8*(c % 32))) & 255
                           for b in range(blocks) for c in range(256)), 2)
    inputs = []
    for p in range(1 if c4 else cb):
        for y in range(ih):
            for x in range(iw // (8 if c4 else 2)):
                address = input_base + p*words[2] + (y*iw//(8 if c4 else 2) + x)*32
                inputs.append(memory[address // 32])
    dump(case / 'inputs.hex', inputs, 64)
    refs = read_hex(case / 'ref_out.hex')
    obase = bases[flags >> 14 & 3] + words[3]
    dump(case / 'expected.hex', (refs[(obase + p*words[4]) // 32 + j]
                                for p in range(planes) for j in range(ow*oh//2)), 64)
    dump(case / 'residual.hex', (memory[(residual_base + p*words[4]) // 32 + j]
                                if flags & 128 else 0
                                for p in range(planes) for j in range(ow*oh//2)), 64)
    return case


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Ordinary K=2/4/6 and D2 K=1 exercise the quantizer calendar across command changes.
    cases = []
    definitions = [
        ('k1_c16', dict(in_w=8, in_h=2, cin=16, cout=32), 1, 0, 1),
        ('k1_c32', dict(in_w=12, in_h=2, cin=32, cout=64, lut=True,
                         quant=dict(bias=37, mult=1, shift=8, out_zp=-13)), 2, 0, 0),
        ('k1_c48', dict(in_w=8, in_h=2, cin=48, cout=96), 3, 0, 0),
        ('k3_s1', dict(in_w=12, in_h=4, cin=16, cout=80, k=3, lut=True,
                        quant=dict(bias=-251, mult=3, shift=12, out_zp=7)), 4, 0, 0),
        ('k3_s2', dict(in_w=12, in_h=5, cin=32, cout=32, k=3, s=2,
                        quant=dict(bias=0, mult=-1, shift=10, out_zp=-5)), 5, 0, 0),
        ('c4_full', dict(in_w=16, in_h=5, cin=3, cout=32, k=3, s=2, in_c4=True), 6, 0, 0),
        ('c4_half', dict(in_w=16, in_h=5, cin=3, cout=16, k=3, s=2, in_c4=True,
                         lut=True, res=True), 7, 0, 0),
        ('d2_res', dict(in_w=40, in_h=2, cin=16, cout=16, res=True,
                         quant=dict(bias=117, mult=-3, shift=10, out_zp=-27)), 8, 0, 0),
        ('d2_transition', dict(in_w=8, in_h=2, cin=16, cout=80, res=True, lut=True), 9, 0, 0),
        ('backpressure', dict(in_w=80, in_h=2, cin=16, cout=80, lut=True), 10, 800, 0),
        ('k1_s2', dict(in_w=16, in_h=2, cin=32, cout=32, s=2, res=True), 11, 0, 0),
        ('quant_limits', dict(in_w=8, in_h=2, cin=16, cout=32,
                             quant=dict(bias=[2147483647, -2147483648]+[0]*30,
                                        mult=[32767, -32768, 0, -1]+[1]*28,
                                        shift=[0,47,1,46]+[8]*28, out_zp=-17)), 12, 0, 0),
    ]
    for definition in definitions:
        cases.append(prepare(*definition))
    compile_args = ['verilator', '--binary', '--timing', '-Wall', '-DSIM_MODE', '-j', '1',
                    '--top-module', 'tb_npu_datapath', '--Mdir', str(OUT / 'obj'), '-o', 'sim']
    with (OUT / 'compile.log').open('w') as log:
        subprocess.run(compile_args + expand_files(TEST / 'files.f'), cwd=ROOT,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    for case in cases:
        print('CASE', case.name, flush=True)
        subprocess.run([str(OUT / 'obj/sim'), '+CASE=' + str(case)], cwd=ROOT, check=True)
    print('PASS npu_datapath: 12 generated/reference cases')


if __name__ == '__main__':
    main()
