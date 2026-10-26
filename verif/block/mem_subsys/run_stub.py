#!/usr/bin/env python3
# File: run_stub.py
# Spec: task M-V1 acceptance, compilation stub and component self-tests.
# Compile once, then run every registered MB case/seed to its expected stub failure.
# Clock domain: host tool.
"""Run M-V1 acceptance without real RTL; this does not pass the functional MB tests."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
BASE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tools import regress  # noqa: E402


def main():
    for name in ('model_selftest', 'checker_selftest', 'master_selftest'):
        path = BASE / name / 'test.yaml'
        if not regress.run_test(path, regress.read_test(path), 'verilator', 'smoke'):
            return 1
    out = ROOT / 'build/mem_mb_stub'
    out.mkdir(parents=True, exist_ok=True)
    args = ['verilator', '--binary', '--timing', '-j', '1',
            '--output-split', '10000', '--output-split-cfuncs', '100',
            '-CFLAGS', '-O0', '--top-module', 'edrv32_mem_subsys_tb', '-GCASE=0',
            '--Mdir', str(out / 'obj'), '-o', 'sim', '+define+SIM_MODE']
    args += regress.expand_files(BASE / 'files.f')
    with (out / 'compile.log').open('w') as log:
        subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    failures = 0
    cases = 0
    for path in sorted(BASE.rglob('test.yaml')):
        fields = regress.read_test(path)
        if fields['top'] != 'edrv32_mem_subsys_tb':
            continue
        parameters = dict(item.split('=') for item in fields['parameters'].split())
        name = path.parent.relative_to(BASE)
        log_dir = out / name
        log_dir.mkdir(parents=True, exist_ok=True)
        case = int(parameters['CASE'])
        deadline = 5000 if case in (205, 206, 301, 302, 303, 304, 306, 307, 401) else 100000
        args = [str(out / 'obj/sim'), '+CASE=' + parameters['CASE'],
                '+SEED=' + parameters['SEED'], f'+MAX_CYCLES={deadline}']
        with (log_dir / 'run.log').open('w') as log:
            result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=60)
        output = (log_dir / 'run.log').read_text()
        # The empty-response stub either times out or reaches a functional comparison.
        expected = result.returncode != 0 and re.search(
            r'FAIL (forwarded transaction count|gateway BRESP|GW read|GW second AR blocked|'
            r'GW second AW blocked|P2 token rate|zero-weight port served|'
            r'DRR grants present|per-port RD cap reached|per-port WR cap reached|'
            r'read credit exhausted|RRESP|APB slot=|'
            r'MB timeout|local data)', output)
        cases += 1
        if not expected:
            failures += 1
        print(f'{"EXPECTED_FAIL" if expected else "UNEXPECTED_RESULT"} {name}', flush=True)
    print(f'{"PASS" if failures == 0 else "FAIL"} stub acceptance: '
          f'{cases-failures}/{cases} expected failures; functional MB remains unverified')
    return int(failures != 0)


if __name__ == '__main__':
    sys.exit(main())
