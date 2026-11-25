#!/usr/bin/env python3
"""tech 3/4: compare PC/Spike 60-frame summaries and report per-frame instret.

The mode's completion result is printed verbatim as END; a matching replay can
end in an upgrade menu or defeat. Mode acceptance separately requires victory.
"""
import argparse
from pathlib import Path


def compare(pc_path, spike_path):
    pc = pc_path.read_text().splitlines()
    spike = spike_path.read_text().splitlines()
    pc_run = next(line for line in pc if line.startswith('RUN,'))
    spike_run = next(line for line in spike if line.startswith('RUN,'))
    assert pc_run == spike_run, f'RUN mismatch: {pc_run}; {spike_run}'
    pc_end = next(line for line in pc if line.startswith('END,'))
    spike_end = next(line for line in spike if line.startswith('END,'))
    assert pc_end == spike_end, f'END mismatch: PC {pc_end}; Spike {spike_end}'
    frames = int(pc_end.split(',')[1])
    pc_states = [line for line in pc if line.startswith('STATE,')]
    spike_states = [line for line in spike if line.startswith('STATE,')]
    assert len(pc_states) == frames // 60, f'PC summary count {len(pc_states)}, frames {frames}'
    assert len(spike_states) == len(pc_states), (
        f'Spike summary count {len(spike_states)}, PC {len(pc_states)}')
    for index, (actual, expected) in enumerate(zip(pc_states, spike_states), 1):
        frame = int(actual.split()[0].split('=')[1])
        assert frame == index * 60, f'Summary frame {frame}, expected {index * 60}'
        assert actual == expected, f'Frame {frame} mismatch:\nPC {actual}\nSpike {expected}'
    rows = [list(map(int, line.split(',')[1:])) for line in spike
            if line.startswith('INST,') and not line.startswith('INST,frame')]
    assert len(rows) == frames, f'INST row count {len(rows)}, frames {frames}'
    for index, row in enumerate(rows, 1):
        assert row[0] == index, f'INST frame {row[0]}, expected {index}'
        assert len(row) == 7 and row[4] == sum(row[1:4]), f'Incomplete INST frame {index}'
    print(f'PASS PC/Spike summaries: {len(pc_states)}; input frames: {frames}')
    print(pc_end)
    for column, name, budget in [(1, 'simulation', 1200000), (2, 'presentation', 500000),
                                 (3, 'audio', 150000), (4, 'total', 1850000)]:
        values = [row[column] for row in rows]
        average = sum(values) / frames
        maximum = max(values)
        print(f'{name}: mean {average:.4f}, max {maximum} instret; '
              f'CPI1.3 mean {average * 1.3:.4f}, max {maximum * 1.3:.1f} cycles; '
              f'budget {budget}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pc_log', type=Path)
    parser.add_argument('spike_log', type=Path)
    args = parser.parse_args()
    compare(args.pc_log, args.spike_log)


if __name__ == '__main__':
    main()
