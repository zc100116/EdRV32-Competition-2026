#!/usr/bin/env python3
# File: run.py
# Spec: T-NPU-PROF; CLAUDE.md 9.1.
# Description: Run unchanged NET-02 with and without a read-only wrapper.
# Clock domain: host.
"""Run under flock /tmp/edrv32-sim.lock after sourcing the project environment."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'verif/block/npu'))
from prepare import prepare_network
from run import build
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files

OUT = ROOT / 'build/npu/prof'


def command(args, log):
    with log.open('w') as output:
        subprocess.run([str(arg) for arg in args], cwd=ROOT, stdout=output,
                       stderr=subprocess.STDOUT, check=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    prepared = prepare_network('NET-02')
    baseline = build(False)
    sources = expand_files(ROOT / 'verif/block/npu/sources.f')
    sources += expand_files(ROOT / 'verif/block/npu/dut.f')
    sources += [str(Path(__file__).with_name('tb_npu_prof.sv'))]
    common = ['--timing', '-Wall', '+define+SIM_MODE', '--top-module', 'tb_npu_prof']
    command(['verilator', '--lint-only'] + common + sources, OUT / 'lint.log')
    command(['verilator', '--binary', '-j', '1', '--Mdir', OUT / 'obj', '-o', 'sim']
            + common + sources, OUT / 'compile.log')
    for path, plusargs in prepared:
        mode = next(arg.split('=')[1] for arg in plusargs if arg.startswith('+MEM_MODE='))
        for label, executable in [('baseline', baseline), ('profile', OUT / 'obj/sim')]:
            command([executable, f'+CASE_DIR={path}'] + plusargs,
                    OUT / f'{mode}_{label}.log')
    command(['python3', 'tools/npu/pipeline_profile.py', OUT], OUT / 'analysis.log')
    print((OUT / 'analysis.log').read_text())


if __name__ == '__main__':
    main()
