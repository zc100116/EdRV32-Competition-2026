#!/usr/bin/env python3
# File: coverage_selftest.py
# Spec: cpu-spec 3.4, 7.1-7.2; cpu-testplan 4 (C-V5).
# Description: Verify collector decoding, IRQ arrival counting and report merging.
# Clock: none (host).
"""Exercise the coverage collector with synthetic public observations, not a core."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[4]


def main():
    out = ROOT / 'build/cpu-coverage-selftest'
    out.mkdir(parents=True, exist_ok=True)
    b1 = Path(__file__).resolve().parent
    with (out / 'compile.log').open('w') as log:
        subprocess.run(['verilator', '--binary', '--timing', '-Wall', '--top-module',
                        'edrv32_cpu_coverage_tb', '-j', '1',
                        '--Mdir', str(out / 'obj'), '-o', 'sim',
                        str(b1 / 'edrv32_cpu_coverage.sv'),
                        str(b1 / 'edrv32_cpu_coverage_tb.sv')],
                        cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    fixture = out / 'observations.json'
    with (out / 'run.log').open('w') as log:
        subprocess.run([str(out / 'obj/sim'), '+COVERAGE_FILE=' + str(fixture)],
                        cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    counts = json.loads(fixture.read_text())['counts']
    assert len(counts) == 86 and all(value > 0 for value in counts.values()), counts
    assert all(value == 1 for key, value in counts.items() if key.startswith('bypass.'))
    assert all(value == 1 for key, value in counts.items() if key.startswith('pair.'))
    assert all(value == 1 for key, value in counts.items() if key.startswith('exception.'))
    assert counts['redirect.e_direction'] == 3 and counts['redirect.e_target'] == 2
    assert counts['redirect.m'] == 1
    assert counts['redirect.exception'] == 14 and counts['redirect.interrupt'] == 1
    assert counts['stall.csr'] == 2 and counts['stall.multiply'] == 1
    assert counts['irq.normal'] == 1 and counts['irq.divide'] == 2
    assert counts['irq.device'] == counts['irq.dc_miss'] == counts['irq.branch_flush'] == 1
    report = ROOT / 'tools/cpu/coverage_report.py'
    merged = subprocess.run(['python3', str(report), str(fixture), str(fixture)],
                            capture_output=True, text=True, check=True)
    rows = [line.split('|') for line in merged.stdout.splitlines() if line.startswith('| ')][1:]
    assert len(rows) == 86, merged.stdout
    for row in rows:
        assert int(row[3]) == 2 * counts[row[1].strip()], row
        assert row[4].strip() == '已覆盖', row
    counts['bypass.w1.rs2.slot1'] = 0
    incomplete = out / 'incomplete.json'
    incomplete.write_text(json.dumps({'counts': counts}))
    result = subprocess.run(['python3', str(report), str(incomplete)],
                            capture_output=True, text=True)
    assert result.returncode == 1 and '未覆盖 1 项' in result.stdout, result
    print('PASS coverage decoding: 86 bins; IRQ hold and simultaneous arrivals')
    print('PASS report merging: exact sums, all-covered exit=0, uncovered exit=1')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
