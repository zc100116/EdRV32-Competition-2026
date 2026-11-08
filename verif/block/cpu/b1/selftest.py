#!/usr/bin/env python3
# File: selftest.py
# Spec: cpu-testplan 2.3; C-V2 acceptance
# Description: Run B1 stub scenarios and verify protocol failures return nonzero.
# Clock: none (host).
"""Compile B1 with strict lint and exercise configuration and negative cases.

Run from the repository with the edrv32 tool environment sourced:
    python3 verif/block/cpu/b1/selftest.py

The smoke manifest runs the default stress scenario. This script also checks hits,
error injection, PC-triggered interrupts, ordered retirement text, and nonzero exits.
Artifacts are build/cpu-b1/{compile.log,<scenario>.log,<scenario>.trace,<scenario>.coverage.json}.

For real-core integration, replace the stub and self-test harness in files.f with
an integration top. Reuse the explicit model/checker/trace connections in the TB;
connect m_enter_i to the real pipeline advance, and trace inputs hierarchically.
Supply +MEM_HEX=<byte hex with absolute @addresses> and +TOHOST_ADDR=<ELF symbol>
from C-V1. The self-test uses SRAM tohost 10001000 and APB test registers 40007000.

IC/DC_MISS_PCT and IC/DC_READY_LOW_PCT are percentages; IC/DC_DELAY_MIN/MAX are
cycles (model defaults 0% miss, 0% ready-low, 5-40 cycles). IC/DC_ERROR_ADDR is hex.
DC_WB_EVENT_CYCLE emits one dirty-writeback pulse and wb_event_count records it.
MEIP/MSIP/MTIP_CYCLE or _PC selects an interrupt start, _DURATION sets high cycles.
TRACE_FILE selects output text; COVERAGE_FILE selects coverage JSON (default
build/cpu-coverage.json from repo root). The self-test defaults inject misses,
backpressure, three interrupt pulses and one writeback pulse; plusargs override these.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools'))
import regress


def main():
    out = ROOT / 'build/cpu-b1'
    out.mkdir(parents=True, exist_ok=True)
    sources = regress.expand_files(Path(__file__).with_name('files.f'))
    with (out / 'compile.log').open('w') as log:
        subprocess.run(['verilator', '--binary', '--timing', '-Wall', '-j', '1', '--top-module',
                        'edrv32_cpu_b1_tb', '--Mdir', str(out / 'obj'), '-o', 'sim'] + sources,
                       cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    cases = [
        ('stress', [], None),
        ('hits', ['+IC_MISS_PCT=0', '+DC_MISS_PCT=0', '+IC_READY_LOW_PCT=0',
                  '+DC_READY_LOW_PCT=0'], None),
        ('fetch_error', ['+IC_ERROR_ADDR=00000000'], None),
        ('cached_error', ['+DC_ERROR_ADDR=10000000'], None),
        ('device_error', ['+DC_ERROR_ADDR=40007000'], None),
        ('pc_interrupt', ['+MEIP_PC=00000000', '+MSIP_PC=00000004',
                          '+MTIP_CYCLE=1', '+MEIP_DURATION=3'], None),
        ('bad_alignment', ['+VIOLATION=1'], 'unaligned I$ address'),
        ('early_device', ['+VIOLATION=2'], 'device execution before commit'),
        ('no_m_entry', ['+VIOLATION=3'], 'D$ request without entering M'),
    ]
    for name, args, expected_error in cases:
        trace = out / (name + '.trace')
        result = subprocess.run([str(out / 'obj/sim'),
                                 '+MEM_HEX=' + str(Path(__file__).with_name('program.hex')),
                                 '+TRACE_FILE=' + str(trace),
                                 '+COVERAGE_FILE=' + str(out / (name + '.coverage.json'))]
                                + args,
                                cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=30)
        (out / (name + '.log')).write_text(result.stdout)
        if expected_error:
            assert result.returncode != 0 and expected_error in result.stdout, result.stdout
        else:
            assert result.returncode == 0 and 'PASS B1' in result.stdout, result.stdout
            assert trace.read_text().splitlines() == [
                '00000000 00100093 01 00000001',
                '00000004 00200113 02 00000002',
                '00000010 00000013 00 00000000',
                'trap 8000000b',
            ], trace.read_text()
        print(f'PASS {name}: exit={result.returncode}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
