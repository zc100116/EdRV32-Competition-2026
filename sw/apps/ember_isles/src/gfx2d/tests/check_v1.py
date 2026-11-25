#!/usr/bin/env python3
"""V1 measured logs: exact state comparisons and per-wave software GPU statistics.
Columns are actual fixed/stream occupancy, unique visible frame payload, uploaded
32-byte lines, stored/visible particles, number objects and direction coverage.
"""
import argparse
import collections
import pathlib
import re
import statistics


def states(path):
    result = {}
    for line in pathlib.Path(path).read_text().splitlines():
        if line.startswith('STATE,'):
            result[int(re.search(r'frame=(\d+)', line)[1])] = line
    return result


def compare(before, after, sparse=False):
    a, b = states(before), states(after)
    if sparse:
        assert b and all(frame % 60 == 0 for frame in b)
        assert len(b) == max(a) // 60
        assert all(a[frame] == value for frame, value in b.items())
    else:
        assert a.keys() == b.keys(), (len(a), len(b))
        assert all(a[frame] == b[frame] for frame in a)
    final = b[max(b)]
    assert 'phase=3 ' in final and 'wave=10 ' in final and 'mode=0 stage=0 ' in final
    print(f'PASS STATE {len(b)} frames: {before} = {after}; real coast victory')


def measure(path):
    waves = collections.defaultdict(list)
    inst = []
    for line in pathlib.Path(path).read_text().splitlines():
        if line.startswith('GFX,'):
            fields = list(map(int, line.split(',')[1:]))
            waves[fields[1]].append(fields)
        elif line.startswith('INST,') and line.split(',')[1].isdigit():
            row = list(map(int, line.split(',')[1:]))
            assert row[1] + row[2] + row[3] == row[4]
            inst.append(row)
    if waves:
        print('wave,fixed_B,stream_B,visible_native_B,TEX_LOAD_B,particle_stored,particle_visible,number_objects,mean_us,p99_us,max_us,facing_mask,dir16_mask,elites,heads,bosses')
        for wave, rows in sorted(waves.items()):
            times = sorted(row[10] for row in rows)
            maximum = lambda column: max(row[column] for row in rows)
            values = [wave, maximum(2), maximum(3), maximum(4), maximum(5), maximum(6),
                      maximum(11), maximum(13), round(statistics.fmean(times)),
                      times[(len(times) - 1) * 99 // 100], max(times),
                      maximum(14), maximum(15), maximum(16), maximum(17), maximum(18)]
            print(','.join(map(str, values)))
    if inst:
        print('component,mean_instret,max_instret,estimated_mean_cycles_CPI1.3,estimated_max_cycles_CPI1.3')
        for column, name in enumerate(('sim', 'gfx', 'audio', 'total'), 1):
            mean = statistics.fmean(row[column] for row in inst)
            maximum = max(row[column] for row in inst)
            print(f'{name},{mean:.1f},{maximum},{mean * 1.3:.1f},{maximum * 1.3:.1f}')
        print('INST frames=' + str(len(inst)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before')
    parser.add_argument('--after')
    parser.add_argument('--spike', action='store_true')
    parser.add_argument('--measure')
    args = parser.parse_args()
    if args.before:
        compare(args.before, args.after, args.spike)
    if args.measure:
        measure(args.measure)


if __name__ == '__main__':
    main()
