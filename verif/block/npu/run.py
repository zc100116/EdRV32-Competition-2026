#!/usr/bin/env python3
# File: run.py
# Spec: npu-testplan 2, 3.2-3.7 and 6; CLAUDE.md 9.1.
# Description: Prepare cases, build once with one compiler job, and run serially.
#              A selftest checks both successful comparison and deliberate corruption.
# Clock domain: none (host orchestration).
"""NB regression entry point; source ~/.local/opt/edrv32/env.sh first."""
import argparse
import csv
import re
from pathlib import Path
import subprocess
import sys

from cases import TIERS
from prepare import BUILD, ROOT, manual_selftest, prepare_network, prepare_small

sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402

HERE = Path(__file__).resolve().parent


def build(selftest):
    target = BUILD / ('sim_selftest' if selftest else 'sim_dut')
    target.mkdir(parents=True, exist_ok=True)
    sources = expand_files(HERE / 'sources.f')
    if not selftest:
        sources += expand_files(HERE / 'dut.f')
    args = ['verilator', '--binary', '--timing', '-Wall', '--top-module', 'tb_npu',
            '-j', '1', '+define+SIM_MODE', '--Mdir', str(target), '-o', 'sim',
            "-GSELFTEST=1'b"+str(int(selftest))] + sources
    with (target / 'compile.log').open('w') as output:
        result = subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print((target / 'compile.log').read_text())
        raise subprocess.CalledProcessError(result.returncode, args)
    return target / 'sim'


def simulate(executable, path, args, label):
    log = path / (label+'.log')
    with log.open('w') as output:
        result = subprocess.run([str(executable), f'+CASE_DIR={path}']+args,
                                cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                timeout=1200)
    return result.returncode, log.read_text(), log


def performance_rows(runs):
    """Record historical N-E2 estimates alongside observations; deviation is informational."""
    sys.path.insert(0, str(ROOT/'tools/npu/eval'))
    from legacy_plan import analysis
    from datapath_model import C0, network
    rows = analysis(ROOT/'third_party/ultralytics/ultralytics/cfg/models/v8/yolov8.yaml')
    result = []
    for mode, output in runs:
        perf = dict((int(n), int(value)) for n, value in re.findall(r'PERF(\d+)=(\d+)', output))
        values = dict((key, int(value)) for key, value in re.findall(r'(\w+)=(\d+)', output))
        latency = 0 if mode == 'zero' else 94
        bandwidth = 1.4 if mode == 'bw' else 4.0
        estimate = sum(layer['cycles'] for layer in
                       network(rows, latency, bandwidth, C0+('D2', 'D3b')))
        row = dict(mode=mode, model_latency=latency, model_bandwidth_gbps=bandwidth,
                   model_cycles=round(estimate), rtl_cycles=perf[0],
                   delta_pct=(perf[0]/estimate-1)*100,
                   doorbell_irq_cycles=values['doorbell_irq_cycles'],
                   read_beats=values['read_beats'], write_beats=values['write_beats'],
                   mem_cycles=values['mem_cycles'],
                   mem_avg_mbps=(values['read_beats']+values['write_beats'])*32*125/
                   values['mem_cycles'])
        row.update({f'PERF{n}': perf[n] for n in range(16)})
        result.append(row)
    path = BUILD/'net_02_perf.csv'
    with path.open('w', newline='') as output:
        writer = csv.DictWriter(output, fieldnames=list(result[0]))
        writer.writeheader()
        writer.writerows(result)
    print(f'PERFORMANCE {path}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', choices=['SELFTEST']+list(TIERS), required=True)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    if args.test == 'SELFTEST':
        path = manual_selftest()
        if args.prepare_only:
            print(path)
            return
        executable = build(True)
        code, output, log = simulate(executable, path, ['+TEST_ID=SELFTEST'], 'positive')
        if code or 'PASS NB' not in output or 'FAIL' in output:
            raise RuntimeError(f'selftest positive failed: {log}\n{output}')
        code, output, log = simulate(executable, path,
            ['+TEST_ID=SELFTEST', '+SELFTEST_CORRUPT'], 'corrupt')
        diagnostic = ['FAIL desc=0', 'addr=05000000', 'expected=03 actual=02', 'time=']
        if code == 0 or any(field not in output for field in diagnostic):
            raise RuntimeError(f'selftest corruption was not diagnosed: {log}\n{output}')
        print(f'PASS selftest: 96 output bytes matched; corruption rejected; logs: {path}')
        return
    prepared = (prepare_network(args.test) if args.test.startswith('NET')
                else prepare_small(args.test))
    if args.prepare_only:
        for path, plusargs in prepared:
            print(path, ' '.join(plusargs))
        return
    executable = build(False)
    performance = []
    for index, (path, plusargs) in enumerate(prepared):
        code, output, log = simulate(executable, path, plusargs, f'run_{index}')
        if code or 'PASS NB' not in output or 'FAIL' in output:
            raise RuntimeError(f'{args.test} failed: {log}\n{output}')
        print(f'PASS {args.test} {path.name} ({log})')
        if args.test == 'NET-02':
            mode = next(arg.split('=', 1)[1] for arg in plusargs if arg.startswith('+MEM_MODE='))
            performance.append((mode, output))
    if performance:
        performance_rows(performance)


if __name__ == '__main__':
    main()
