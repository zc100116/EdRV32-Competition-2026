#!/usr/bin/env python3
# File: run.py
# Spec: rnd 2.6/5.2/7; T-RNDMEAS.
# Description: Compile and replay captured benchmark batches at two DDR latencies.
# Clock domain: host, simulated clk_mem 125 MHz.
import gzip
import json
from pathlib import Path
import pickle
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/rnd_util'
sys.path.insert(0, str(ROOT / 'tools'))
from regress import expand_files


def prepare(scene):
    batches = []
    with gzip.open(OUT / f'capture/{scene:02d}.pkl.gz', 'rb') as source:
        batch = pickle.load(source)
        while batch is not None:
            batches.append(batch)
            batch = pickle.load(source)
    path = OUT / f'{scene:02d}.bin'
    # SV $fread scalar headers are big endian; payloads retain wire byte order.
    def word(value):
        return struct.pack('>I', value)

    with path.open('wb') as target:
        target.write(word(len(batches)))
        for packed, pages, targets in batches:
            descriptors = packed + bytes((-len(packed)) % 4096)
            pages.update({1 + k // 4096: descriptors[k:k + 4096]
                          for k in range(0, len(descriptors), 4096)})
            target.write(word(len(packed) // 64) + word(len(pages)))
            for page, data in pages.items():
                target.write(word(page) + data)
            target.write(word(len(targets)))
            for address, data in targets:
                target.write(word(address) + word(len(data)) + data)
    return path


def compile_sim():
    obj = OUT / 'obj'
    obj.mkdir(parents=True, exist_ok=True)
    command = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
               '--timescale', '1ns/1ps', '--top-module', 'edrv32_rnd_util_tb',
               '--Mdir', str(obj), '-o', 'sim', '+define+SIM_MODE',
               *expand_files(HERE / 'files.f')]
    with (obj / 'compile.log').open('w') as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    return obj / 'sim'


def measure(scene, latency, path, sim):
    log_path = OUT / f'{scene:02d}-{latency}.log'
    with log_path.open('w') as log:
        subprocess.run([str(sim), f'+INPUT={path}', f'+LATENCY={latency}'],
                       stdout=log, stderr=subprocess.STDOUT, check=True, cwd=ROOT)
    output = log_path.read_text()
    assert 'PASS' in output, output
    values = next(row for row in output.splitlines() if row.startswith('UTIL '))
    keys = ('cycles', 'two', 'one', 'zero', 'geometry_accepted', 'geometry_stall',
            'geometry_extra', 'read_wait', 'write_wait')
    row = dict(zip(keys, map(int, values.split()[1:])))
    row.update(scene=scene, latency=latency)
    return row


def main():
    sim = compile_sim()
    results = []
    for scene in range(16):
        path = prepare(scene)
        for latency in (0, 40):
            row = measure(scene, latency, path, sim)
            results.append(row)
            (OUT / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
            print(f'PASS scene={scene:02d} latency={latency}: {row}', flush=True)
        path.unlink()
    print('PASS 32 real LVGL replays, target bytes equal rnd_ref')


if __name__ == '__main__':
    main()
