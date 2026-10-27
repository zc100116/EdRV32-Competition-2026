#!/usr/bin/env python3
# File: run.py
# Spec: npu-spec 2, 5; npu-testplan OP-01..10, CP and SQ.
# Description: Generate independent reference images and test each serial operator in isolation.
# Clock: host tool.
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files

OUT = ROOT / 'build/npu_ctrl/operators'
PYTHON = Path.home() / '.local/opt/edrv32-py/bin/python'


def execute(args, **kw):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True, **kw)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--nonconv', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / ('sim_nonconv' if args.nonconv else 'sim_conv')
    target.mkdir(exist_ok=True)
    directory = 'npu_nonconv' if args.nonconv else 'npu_conv'
    sources = expand_files(ROOT / 'verif/unit' / directory / 'files.f')
    with (target / 'compile.log').open('w') as log:
        execute(['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                 '+define+SIM_MODE', '--top-module', 'tb_npu_operator',
                 "-GNONCONV=1'b"+str(int(args.nonconv)), '--Mdir', target, '-o', 'sim']
                + sources, stdout=log, stderr=subprocess.STDOUT)
    if args.nonconv:
        layers = [dict(op='pool', in_w=20, in_h=12, cin=48),
                  dict(op='upsample', in_w=2, in_h=3, cin=16),
                  dict(op='upsample', in_w=40, in_h=4, cin=32)]
    else:
        layers = [dict(op='conv', in_w=12, in_h=7, cin=48, cout=80, k=3, lut=True, res=True),
                  dict(op='conv', in_w=16, in_h=9, cin=3, cout=16, k=3, s=2, in_c4=True,
                       lut=True, res=True),
                  dict(op='conv', in_w=80, in_h=7, cin=16, cout=80, s=2),
                  dict(op='conv', in_w=80, in_h=4, cin=16, cout=16, res=True)]
    env = {**os.environ, 'OPENBLAS_NUM_THREADS': '1', 'OMP_NUM_THREADS': '1'}
    for number, layer in enumerate(layers):
        path = OUT / f'{layer["op"]}_{number}'
        path.mkdir(exist_ok=True)
        config = path / 'config.json'
        layer.update(in_from='input', in_offset=0x1e0, out_offset=0xfe0,
                     in_plane_stride=0x4000, out_plane_stride=0x6000,
                     quant=dict(bias=37, mult=-3, shift=10, out_zp=-7))
        config.write_text(json.dumps({'layers': [layer]}))
        execute([PYTHON, ROOT/'tools/npu/gen_case.py', '--config', config,
                 '--seed', str(number+17), '--out', path], env=env)
        execute([PYTHON, ROOT/'tools/npu/ref/npu_ref.py', path], env=env)
        memory = {}
        for image in path.glob('mem_*.hex'):
            addr = 0
            for token in image.read_text().split():
                if token.startswith('@'):
                    addr = int(token[1:], 16)
                else:
                    memory[addr] = int(token, 16)
                    addr += 1
        regs = dict((name, int(value, 16)) for name, value in
                    (line.split() for line in (path/'regs.txt').read_text().splitlines()))
        desc = memory[regs['DESC_BASE']//32] | memory[regs['DESC_BASE']//32+1] << 256
        words = [(desc >> (32*i)) & 0xffffffff for i in range(16)]
        flags = words[0]
        bases = [regs[key+'_BASE'] for key in ('MODEL', 'WORK', 'INPUT', 'OUTPUT')]
        meta = words+[bases[flags >> 12 & 3]+words[1], bases[flags >> 14 & 3]+words[3],
                      bases[flags >> 16 & 3]+words[5], regs['MODEL_BASE']+words[6],
                      regs['MODEL_BASE']+words[7]]
        (path/'operator_meta.hex').write_text(''.join(f'{word:08x}\n' for word in meta))
        with (path/'run.log').open('w') as log:
            execute([target/'sim', '+CASE_DIR='+str(path), '+MEM_MODE=bw', '+MEM_B_DELAY=200'],
                    stdout=log, stderr=subprocess.STDOUT)
        print((path/'run.log').read_text(), end='')


if __name__ == '__main__':
    main()
