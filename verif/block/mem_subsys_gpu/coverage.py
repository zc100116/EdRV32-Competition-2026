#!/usr/bin/env python3
# File: coverage.py
# Spec: mem-subsys-testplan 5-6.
# Description: Merge functional COVER observations across the MB full regression logs.
# Clock domain: host tool.
"""Report the GPU memory subsystem protocol and fixed-policy coverage union."""
from pathlib import Path
import sys


def main():
    root = Path(sys.argv[1])
    hits = set()
    peaks = {}
    for log in root.rglob('run.log'):
        output = log.read_text()
        if 'PASS mem_subsys' not in output:
            continue
        for line in output.splitlines():
            if not line.startswith('COVER '):
                continue
            words = line.split()
            pairs = dict(word.split('=', 1) for word in words if '=' in word)
            if words[1] == 'GW':
                if int(pairs.get('hits', pairs.get('hit', '0'))) != 0:
                    key = ' '.join(word for word in words[1:]
                                   if not word.startswith(('hits=', 'hit=')))
                    hits.add(key)
            elif words[1] == 'schedule':
                if 'rule' in pairs and int(pairs['hits']) != 0:
                    hits.add('rule ' + pairs['rule'])
            elif words[1] == 'flow':
                if 'port' in pairs:
                    for direction in ('rd', 'wr'):
                        key = direction + pairs['port']
                        peaks[key] = max(peaks.get(key, 0), int(pairs[direction + '_peak']))
                elif pairs.get('credit_full') == '1':
                    hits.add('credit_full')
                if 'global_peak' in pairs:
                    peaks['global'] = max(peaks.get('global', 0), int(pairs['global_peak']))
            elif words[1] == 'violation' and pairs['hit'] == '1':
                hits.add(' '.join(word for word in words[1:] if not word.startswith('hit=')))
    expected = set()
    for kind in range(2):
        for window in range(2):
            for direction in range(2):
                expected.add(f'GW legal={kind} window={window} dir={direction}')
    for size in range(4):
        for offset in range(0, 32, 1 << size):
            expected.add(f'GW size={size} offset={offset}')
    for index in range(10):
        expected.add(f'GW illegal={index}')
    for index in range(3):
        expected.add(f'rule {index+1}')
    expected.add('credit_full')
    for kind in range(2):
        for direction in range(2):
            expected.add(f'violation kind={kind} dir={direction}')
    caps = {'global': 8}
    for port, (read, write) in enumerate(zip((4, 1, 1, 4, 2),
                                            (0, 0, 1, 2, 2))):
        if read:
            caps['rd' + str(port)] = read
        if write:
            caps['wr' + str(port)] = write
    missing = sorted(expected-hits)
    missing += [f'{key} peak >= {value}, actual {peaks.get(key, 0)}'
                for key, value in caps.items() if peaks.get(key, 0) < value]
    print(f'MB coverage: {len(expected & hits)}/{len(expected)} bins; '
          f'{sum(peaks.get(k, 0) >= v for k, v in caps.items())}/{len(caps)} limits')
    for key in missing:
        print('MISS ' + key)
    return int(bool(missing))


if __name__ == '__main__':
    sys.exit(main())
