#!/usr/bin/env python3
# File: cpu_calibrate.py
# Spec: T-CPU-N-T2BE section 0; CLAUDE.md 12.3.
# Description: Match PDS boundary pairs to XC7 proxy depths and fit observed slack.
# Clock domain: host measurement; source reports use clk_sys.
"""Read extracted PDS timing5000.rtr reports and cpu_levels XC7 JSON files."""
import argparse
from collections import Counter, defaultdict
import csv
import gzip
from graphlib import TopologicalSorter
import json
import math
from pathlib import Path
import re
import subprocess

from tools.synth.netlist_paths import analyze, is_lut, is_mux, is_carry


CARDS = {
    '56R1': ('20261104-56-cpu-l1-timing-probe', 'R1'),
    '56R2': ('20261104-56-cpu-l1-timing-probe', 'R2'),
    '59': ('20261105-59-cpu-v017-timing-probe', 'R1'),
    '60': ('20261105-60-cpu-v018-tournament-probe', 'R1'),
}


def extract_reports(directory):
    for card, (task, run) in CARDS.items():
        output = directory / ('pds' + card)
        output.mkdir(parents=True, exist_ok=True)
        names = ['native_reports/timing5000.rtr.gz', 'timing_setup_fail_all.txt']
        if card == '56R1':
            names += ['native_reports/lutram_btb.rtr.gz',
                      'native_reports/lutram_direction.rtr.gz']
        for name in names:
            data = subprocess.check_output([
                'git', 'show', f'origin/win/{task}:tasks/win/{task}/artifacts/{run}/{name}'])
            if name.endswith('.gz'):
                data = gzip.decompress(data)
            (output / Path(name).name.removesuffix('.gz')).write_bytes(data)


def read_pds(path, ram_cuts=False):
    block = []
    with path.open() as stream:
        for line in stream:
            if line.startswith('Startpoint'):
                block = [line]
            elif block:
                block.append(line)
                if re.match(r' Slack \(', line):
                    text = ''.join(block)
                    block = []
                    if ('max (slow corner)' not in text or
                            'Path Class  : sequential timing path' not in text):
                        continue
                    start = re.search(r'Startpoint\s*:\s*(\S+)', text)[1]
                    end = re.search(r'Endpoint\s*:\s*(\S+)', text)[1]
                    levels = int(re.search(r'Logic Levels:\s*(\d+)', text)[1])
                    slack = float(re.search(r'Slack \(\w+\)\s+([-\d.]+)', text)[1])
                    # Exclude launch/capture clock trees from the data fanout.
                    launch = re.search(r'^.*\btco\s+.*$', text, re.M)
                    data = text[launch.end():text.index(' Data arrival time')]
                    nets = re.findall(r'net \(fanout=(\d+)\)\s+[-\d.]+\s+[-\d.]+\s+(\S.*)', data)
                    fanout = max(int(n) for n, _ in nets)
                    first_net = re.sub(r'\s+', '', nets[0][1])
                    kind = ('DRM' if '/gopdrm_' in start else
                            'APM' if 'gopapm' in start else
                            'LUTRAM' if 'lutram' in start.lower() else 'FF')
                    if not ram_cuts:
                        yield dict(start=start, end=end, levels=levels, slack=slack,
                                   fanout=fanout, launch_net=first_net, category=kind)
                    else:
                        outputs = list(re.finditer(r'^.*\btd\s+.*ram64x1d/DO\s*$',
                                                   data, re.M))
                        if outputs:
                            tail = data[outputs[-1].end():]
                            levels = len(re.findall(r'^.*\btd\s+.*$', tail, re.M))
                            fanout = max(map(int, re.findall(r'net \(fanout=(\d+)\)', tail)))
                            yield dict(start=start, end=end, levels=levels, slack=slack,
                                       fanout=fanout, launch_net=first_net, category='LUTRAM')


def group(row):
    start, end = row['start'], row['end']
    if 'e_redirect_r' in start and 'ras_data_r' in end:
        return 'P10'
    if 'e_branch_' in start:
        return 'P1'
    if ('/u_dcache/' in start or '/addr_r' in start) and ('e_operand_' in end or 'e_branch_' in end):
        return 'P6'
    if 'e_operand_' in start and ('e_operand_' in end or 'e_branch_' in end):
        return 'P5'
    if 'early_' in end and ('/u_ib/' in start or '/u_dcache/' in start):
        return 'P4'
    if '/u_ib/' in start and '/u_core/e_' in end:
        return 'P3'
    if '/u_dcache/' in start:
        return 'P2'
    if '/u_icache/u_tag' in start and 'f1_pc' in end:
        return 'P7'
    if '/u_predictor/' in end and ('f1_' in start or '/u_frontend/' in start):
        return 'P8'
    if 'f1_pc' in start and 'f1_pc' in end:
        return 'P9'
    return None


def normalize(name):
    name = name.removeprefix('u_cpu/').replace('/', '.')
    # PDS appends physical replica identifiers after the original RTL bit.
    name = re.sub(r'_r_\d+_copy(?=\[)', '_r', name)
    return re.sub(r'(\[\d+\])_\d+(?=\.|$)', r'\1', name)


def solve(matrix, vector):
    size = len(vector)
    rows = [list(row) + [value] for row, value in zip(matrix, vector)]
    for col in range(size):
        pivot = max(range(col, size), key=lambda n: abs(rows[n][col]))
        rows[col], rows[pivot] = rows[pivot], rows[col]
        scale = rows[col][col]
        rows[col] = [value / scale for value in rows[col]]
        for index in range(size):
            if index != col:
                scale = rows[index][col]
                rows[index] = [a - scale * b for a, b in zip(rows[index], rows[col])]
    return [row[-1] for row in rows]


def fit(rows):
    x = [[1., row['levels'], math.log2(row['fanout'])] for row in rows]
    y = [row['slack'] for row in rows]
    coeff = solve([[sum(v[i] * v[j] for v in x) for j in range(3)]
                   for i in range(3)], [sum(v[i] * s for v, s in zip(x, y)) for i in range(3)])
    errors = [s - sum(a * b for a, b in zip(v, coeff)) for v, s in zip(x, y)]
    mean = sum(y) / len(y)
    r2 = 1 - sum(e * e for e in errors) / sum((s - mean) ** 2 for s in y)
    typical = sorted(r['fanout'] for r in rows)[len(rows)//2]
    limits = {str(mhz): (coeff[0] + coeff[2] * math.log2(typical) +
                        1000 / mhz - 1000 / 150) / -coeff[1] for mhz in [150, 135]}
    return dict(n=len(rows), coefficients=coeff, r2=r2,
                rmse=math.sqrt(sum(e * e for e in errors) / len(errors)),
                min_residual=min(errors), typical_fanout=typical, mean_zero_slack_levels=limits)


def compare(design, rows):
    graph, logic, roots, endpoints, loads, _ = analyze(design, graph_only=True)
    module = design['modules']['edrv32_cpu_subsys']
    aliases = defaultdict(set)
    for name, net in module['netnames'].items():
        for index, bit in enumerate(net['bits']):
            if isinstance(bit, int):
                label = name + (f'[{index + net.get("offset", 0)}]'
                                if len(net['bits']) > 1 else '')
                aliases[label].add(bit)
    by_q = defaultdict(list)
    for point in endpoints:
        cell_name, pin = point['pin'].rsplit('.', 1) if '.' in point['pin'] else ('', '')
        if cell_name in module['cells'] and 'Q' in module['cells'][cell_name]['connections']:
            by_q[module['cells'][cell_name]['connections']['Q'][0]].append(point)
    order = list(TopologicalSorter(graph).static_order())
    cache = {}
    samples = Counter()
    for row in rows:
        family = group(row)
        if family is None or samples[family] >= 6:
            continue
        start_name = normalize(row['start'].split('/opit')[0])
        if '/u_ip/' in row['start']:
            start_name = normalize(row['launch_net'])
        start_bits = aliases.get(start_name, set()) & roots.keys()
        end_name = normalize(row['end'].split('/opit')[0])
        ends = [point for bit in aliases.get(end_name, set()) for point in by_q[bit]]
        if not start_bits or not ends:
            continue
        for root in start_bits:
            if root not in cache:
                depth = {root: (0, len(loads[root]))}
                for bit in order:
                    if bit in roots:
                        continue
                    values = [depth[p] for p in graph[bit] if p in depth]
                    if values:
                        level, fanout = max(values)
                        kind = logic[bit][1]
                        depth[bit] = (level + int(is_lut(kind) or is_mux(kind) or is_carry(kind)),
                                      max(fanout, len(loads[bit])))
                cache[root] = depth
        candidates = [cache[root][end['bit']] for root in start_bits for end in ends
                      if end['bit'] in cache[root]]
        if not candidates:
            continue
        level, fanout = max(candidates)
        samples[family] += 1
        yield dict(row, group=family, proxy_levels=level, proxy_fanout=fanout,
                   delta=row['levels']-level, normalized_start=start_name,
                   normalized_end=end_name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path,
                        help='contains 59/xc7.json, 60/xc7.json and pds*/timing5000.rtr')
    args = parser.parse_args()
    extract_reports(args.directory)
    all_rows, comparison = [], []
    for card in ['56R1', '56R2', '59', '60']:
        rows = list(read_pds(args.directory / ('pds' + card) / 'timing5000.rtr'))
        all_rows.extend(dict(row, card=card) for row in rows)
        all_rows.extend(dict(row, card=card) for row in read_pds(
            args.directory / ('pds' + card) / 'timing5000.rtr', ram_cuts=True))
        if card in ['59', '60']:
            design = json.loads((args.directory / card / 'xc7.json').read_text())
            text = (args.directory / ('pds' + card) / 'timing_setup_fail_all.txt').read_text()
            listed = {(row['startpoint'], row['endpoint']): int(row['logic_levels'])
                      for row in csv.DictReader(text[text.index('source\t'):].splitlines(),
                                                delimiter='\t')}
            selected = [dict(row, levels=listed[row['start'], row['end']]) for row in rows
                        if (row['start'], row['end']) in listed]
            comparison.extend(dict(row, card=card) for row in compare(design, selected))
    with (args.directory / 'calibration.tsv').open('w') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(comparison[0]), delimiter='\t')
        writer.writeheader()
        writer.writerows(comparison)
    for name in ['lutram_btb.rtr', 'lutram_direction.rtr']:
        all_rows.extend(read_pds(args.directory / 'pds56R1' / name, ram_cuts=True))
    fits = {kind: fit([r for r in all_rows if r['category'] == kind])
            for kind in ['FF', 'LUTRAM', 'DRM'] if any(r['category'] == kind for r in all_rows)}
    (args.directory / 'fit.json').write_text(json.dumps(fits, indent=2)+'\n')
    print('Samples:', Counter(r['group'] for r in comparison))
    print('PDS minus proxy:', sorted(Counter(r['delta'] for r in comparison).items()))
    for family in sorted({r['group'] for r in comparison}):
        print(family, sorted(Counter(r['delta'] for r in comparison
                                    if r['group'] == family).items()))
    print(json.dumps(fits, indent=2))


if __name__ == '__main__':
    main()
