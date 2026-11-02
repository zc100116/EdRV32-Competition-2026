#!/usr/bin/env python3
# File: pipeline_profile.py
# Spec: T-NPU-PROF; npu-spec 4, 4.1, 4.3.
# Description: Parse exclusive edge counters and compare unchanged NET-02 baselines.
# Clock domain: host (Python standard library only).
"""Write per-descriptor and whole-network CSV files from profiler logs."""
import argparse
import csv
from pathlib import Path
import re
import struct

CATEGORIES = ['mac', 'descriptor', 'model_first', 'model_later', 'input_first',
              'input_later', 'switch_fill', 'credit', 'residual', 'tail_pipeline',
              'fence', 'nonconv', 'quant_calendar', 'tail_write']


def read_descriptors(path):
    data = bytearray()
    for token in path.read_text().split():
        if not token.startswith('@'):
            data.extend(bytes.fromhex(token)[::-1])
    return [struct.unpack_from('<16I', data, n) for n in range(0, len(data), 64)]


def write_csv(path, rows):
    with path.open('w', newline='') as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    descriptors = read_descriptors(args.directory.parent / 'yolo/mem_desc.hex')
    totals = []
    all_rows = []
    for mode in ['zero', 'latency', 'bw']:
        baseline = (args.directory / f'{mode}_baseline.log').read_text()
        profile = (args.directory / f'{mode}_profile.log').read_text()
        for label, log in [('baseline', baseline), ('profile', profile)]:
            if 'PASS NB' not in log or 'FAIL' in log:
                raise ValueError(f'{mode} {label}: NET-02 comparison did not pass')
        base_perf = re.findall(r'PERF(\d+)=(\d+)', baseline)
        prof_perf = re.findall(r'PERF(\d+)=(\d+)', profile)
        if base_perf != prof_perf:
            raise ValueError(f'{mode}: observer changed PERF: {base_perf} != {prof_perf}')
        perf = {int(key): int(value) for key, value in prof_perf}
        records = re.findall(r'PROFILE d=(\d+) span=(\d+) work=(\d+) counts=([\d,]+)',
                             profile)
        rows = []
        for index, span, work, counts in records:
            d = int(index)
            words = descriptors[d]
            flags = words[0]
            op = flags & 15
            cin = 3 if flags & 256 else (words[10] & 63)*16
            cout = ((words[10] >> 8) & 15)*32 - (16 if flags & 512 else 0)
            width = words[9] & 4095
            height = (words[9] >> 16) & 4095
            values = [int(value) for value in counts.rstrip(',').split(',')]
            row = dict(mode=mode, index=d, op=op, width=width, height=height,
                       cin=cin, cout=cout if op == 0 else cin, start_done=int(span),
                       busy=sum(values), true_mac=int(work),
                       efficiency=int(work)/(values[0]*512) if values[0] else 0)
            row.update(zip(CATEGORIES, values))
            # Full spatial kernel includes padded image borders, but no padded channels.
            nominal = width*height*cin*cout*(9 if flags & 16 else 1) if op == 0 else 0
            row['boundary_mac'] = nominal-int(work)
            row['channel_padding_mac'] = values[0]*512-nominal if op == 0 else 0
            input_pixels = (words[8] & 4095)*((words[8] >> 16) & 4095)
            blocks = (words[10] >> 8) & 15
            read_bytes = input_pixels*(4 if flags & 256 else cin)+64
            write_bytes = width*height*(cout if op == 0 else cin)
            if op == 0:
                read_bytes += blocks*words[12]
                if flags & 512 and not flags & 256:
                    read_bytes -= words[12]//2
                read_bytes += blocks*(256+(256 if flags & 64 else 0))
                if flags & 128:
                    read_bytes += write_bytes
            row['read_bytes'] = read_bytes
            row['write_bytes'] = write_bytes
            # BW tokens can carry 64 bytes across a descriptor boundary.
            row['bw_payload_floor'] = max(0, (read_bytes+write_bytes-64)*150/1400)
            row['credit_save_cap'] = (min(values[7], max(0, row['busy']
                                      - row['bw_payload_floor'])) if mode == 'bw' else values[7])
            rows.append(row)
        if ([row['index'] for row in rows] != list(range(68))
                or sum(row['busy'] for row in rows) != perf[0]):
            raise ValueError(f'{mode}: descriptor count or exclusive sum != PERF0 {perf[0]}')
        if sum(row['mac'] for row in rows) != perf[1]:
            raise ValueError(f'{mode}: MAC sum != PERF1 {perf[1]}')
        all_rows.extend(rows)
        total = dict(mode=mode, perf0=perf[0], true_mac=sum(row['true_mac'] for row in rows))
        total.update({key: sum(row[key] for row in rows) for key in CATEGORIES})
        total.update({key+'_pct': total[key]*100/perf[0] for key in CATEGORIES})
        total['credit_save_cap'] = sum(row['credit_save_cap'] for row in rows)
        totals.append(total)
        print(f'{mode}: baseline/profile PERF identical; 68 descriptors; '
              f'classification={sum(total[key] for key in CATEGORIES)} PERF0={perf[0]}; '
              f'MAC={perf[1]}; byte comparison PASS')
    write_csv(args.directory / 'descriptors.csv', all_rows)
    write_csv(args.directory / 'totals.csv', totals)


if __name__ == '__main__':
    main()
