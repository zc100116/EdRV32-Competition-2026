#!/usr/bin/env python3
# File: test_trace_compare.py; cpu-plan C-V1 acceptance; clock: host.
# Convert real Spike logs to RTL events and check first-writeback corruption.
"""Check trace comparator acceptance using the built riscv-tests Spike logs."""
from pathlib import Path
from dataclasses import replace
import subprocess
import sys

from trace_compare import COUNTER_CSRS, spike_events

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/cpu/trace-compare'
COMPARE = Path(__file__).with_name('trace_compare.py')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    logs = sorted((ROOT / 'build/cpu/riscv-tests').glob('*/spike.log'))
    # Use a successful, built suite (ma_data is explicitly not applicable).
    logs = [path for path in logs if path.parent.name != 'rv32ui-p-ma_data']
    if not logs:
        raise RuntimeError('Build riscv-tests first: python3 tools/cpu/build_tests.py')
    for log in logs:
        events = list(spike_events(log))
        rtl = OUT / (log.parent.name + '.trace')
        rtl.write_text('\n'.join(map(str, events)) + '\n')
        subprocess.run([sys.executable, str(COMPARE), str(rtl), str(log)], check=True)
    log = ROOT / 'build/cpu/riscv-tests/rv32ui-p-add/spike.log'
    events = list(spike_events(log))
    index = next(i for i, event in enumerate(events) if event.rd)
    event = events[index]
    events[index] = replace(event, value=event.value ^ 1)
    bad = OUT / 'corrupt.trace'
    bad.write_text('\n'.join(map(str, events)) + '\n')
    result = subprocess.run([sys.executable, str(COMPARE), str(bad), str(log)],
                            capture_output=True, text=True)
    (OUT / 'corrupt.log').write_text(result.stdout + result.stderr)
    assert result.returncode == 1, result
    assert f'FAIL event {index + 1}' in result.stdout, result.stdout
    assert 'RTL:' in result.stdout and 'Spike:' in result.stdout, result.stdout
    log = ROOT / 'build/cpu/riscv-tests/rv32mi-p-instret_overflow/spike.log'
    events = list(spike_events(log))
    index = next(i for i, event in enumerate(events) if event.rd
                 and event.instr & 0x7F == 0x73
                 and event.instr >> 20 in COUNTER_CSRS)
    event = events[index]
    events[index] = replace(event, value=event.value ^ 1)
    counter = OUT / 'counter.trace'
    counter.write_text('\n'.join(map(str, events)) + '\n')
    subprocess.run([sys.executable, str(COMPARE), str(counter), str(log)], check=True)
    events[index] = replace(events[index], rd=event.rd % 31 + 1)
    counter.write_text('\n'.join(map(str, events)) + '\n')
    result = subprocess.run([sys.executable, str(COMPARE), str(counter), str(log)],
                            capture_output=True, text=True)
    (OUT / 'counter-rd.log').write_text(result.stdout + result.stderr)
    assert result.returncode == 1 and f'FAIL event {index + 1}' in result.stdout
    print(f'PASS: {len(logs)} self-conversions, writeback corruption, counter-value waiver '
          'and counter-rd corruption')


if __name__ == '__main__':
    main()
