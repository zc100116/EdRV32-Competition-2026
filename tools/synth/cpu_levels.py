#!/usr/bin/env python3
# File: cpu_levels.py
# Spec: T-CPU-N-T2BE section 0; CLAUDE.md 12.3.
# Description: Synthesize CPU+L1 and enumerate maximum mapped depth per boundary pair.
# Clock domain: host tool; RTL uses clk_sys.
"""XC7 proxy levels (one per LUT/MUXF/CARRY), without a physical timing claim."""
import argparse
import csv
from graphlib import TopologicalSorter
import json
from pathlib import Path
import re
import subprocess

from tools.synth.netlist_paths import analyze, is_lut, is_mux, is_carry

ROOT = Path(__file__).resolve().parents[2]


def synthesize(output, commit):
    source = ROOT
    if commit != 'worktree':
        source = output / 'source'
        source.mkdir(parents=True, exist_ok=True)
        archive = subprocess.check_output(['git', 'archive', commit, 'rtl'])
        subprocess.run(['tar', '-x', '-C', str(source)], input=archive, check=True)
    files, includes = [], set()

    def filelist(path):
        for raw in path.read_text().splitlines():
            line = raw.split('//')[0].strip()
            if line.startswith('-f '):
                filelist(path.parent / line[3:])
            elif line.startswith('+incdir+'):
                includes.add(str((path.parent / line[8:]).resolve()))
            elif line:
                files.append(str((path.parent / line).resolve()))

    filelist(source / 'rtl/filelists/cpu_subsys.f')
    files.append(str(ROOT / 'tools/synth/ip_stubs.v'))
    script = output / 'synth.ys'
    script.write_text('\n'.join([
        'read_verilog -D FPGA_MODE ' + ' '.join('-I' + p for p in sorted(includes)) +
        ' ' + ' '.join(dict.fromkeys(files)),
        'hierarchy -top edrv32_cpu_subsys', 'proc', 'flatten',
        'setattr -set keep 1 w:*_r w:*_r[[]* w:*_r_copy*',
        'setattr -set keep 1 a:keep %ci1', 'select *',
        'synth_xilinx -top edrv32_cpu_subsys -family xc7 -flatten -noiopad -noclkbuf -nobram',
        'opt_clean', f'write_json {output}/xc7.json', 'stat',
    ]) + '\n')
    with (output / 'synth.log').open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-s', str(script)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    netlist = output / 'xc7.json'
    netlist.write_text(netlist.read_text().replace(str(source) + '/', ''))
    (output / 'version.txt').write_text(subprocess.check_output(['yosys', '-V'], text=True))
    (output / 'commit.txt').write_text(subprocess.check_output(
        ['git', 'rev-parse', 'HEAD' if commit == 'worktree' else commit], text=True))
    return netlist


def category(point):
    kind = point['boundary']
    if kind == 'FF':
        return 'FF'
    if 'lutram' in kind or kind.startswith(('RAM', 'SRL')):
        return 'LUTRAM'
    if kind.startswith('ip_ram') or kind.startswith('ip_rom'):
        return 'DRM'
    if kind == 'ip_mul_s33x33':
        return 'APM'
    return kind


def carry_chain_links(design, logic):
    top, = [m for m in design['modules'].values()
            if int(m.get('attributes', {}).get('top', '0'), 2)]
    # Only a native carry output into the next cell's CI/CYINIT continues a chain.
    # A sum feeding S/DI, or a LUT between adders, starts a separate two-level chain.
    carry_outputs = {bit for cell in top['cells'].values() if is_carry(cell['type'])
                     for bit in cell['connections'].get('CO', [])}
    links = {}
    for bit, (name, kind, _) in logic.items():
        if is_carry(kind):
            conn = top['cells'][name]['connections']
            links[bit] = {prev for p in ('CI', 'CYINIT') for prev in conn.get(p, [])
                                if prev in carry_outputs}
    return links


def pairs(design, start=None, end=None, carry_chain_two=False):
    graph, logic, roots, endpoints, loads, _ = analyze(design, graph_only=True)
    order = list(TopologicalSorter(graph).static_order())
    carry_links = carry_chain_links(design, logic)
    chosen = [point for point in endpoints if not end or
              re.search(end, point['signal'] + ' ' + point['pin'])]
    # Each start is propagated independently; unlike global longest-path ranking,
    # a shorter path from another start remains observable for that pair.
    for root, point in sorted(roots.items()):
        if start and not re.search(start, point['signal'] + ' ' + point['pin']):
            continue
        state = {root: (0, len(loads[root]))}
        for bit in order:
            if bit in roots:
                continue
            kind = logic[bit][1]
            weight = int(is_lut(kind) or is_mux(kind) or is_carry(kind))
            candidates = []
            for prev in graph[bit]:
                if prev in state:
                    cost = weight
                    if carry_chain_two and is_carry(kind):
                        cost = 0 if prev in carry_links[bit] else 2
                    depth, fanout = state[prev]
                    candidates.append((depth + cost, max(fanout, len(loads[bit]))))
            if candidates:
                state[bit] = max(candidates)
        for endpoint in chosen:
            if endpoint['bit'] in state:
                depth, fanout = state[endpoint['bit']]
                yield (point['signal'], point['pin'], category(point), endpoint['signal'],
                       endpoint['pin'], depth, fanout)


def worst(design, start=None, end=None, carry_chain_two=False):
    """Compute each launch category's global maximum using the same mapped graph.

    The full pair enumeration remains the default; this equivalent reduction is
    useful for comparing candidate netlists without writing every pair again.
    """
    graph, logic, roots, endpoints, loads, _ = analyze(design, graph_only=True)
    order = list(TopologicalSorter(graph).static_order())
    carry_links = carry_chain_links(design, logic)
    chosen = [point for point in endpoints if not end or
              re.search(end, point['signal'] + ' ' + point['pin'])]
    selected = {bit: point for bit, point in roots.items() if not start or
                re.search(start, point['signal'] + ' ' + point['pin'])}
    result = {}
    for kind in sorted({category(point) for point in selected.values()}):
        state = {bit: (0, len(loads[bit]), bit) for bit, point in selected.items()
                 if category(point) == kind}
        for bit in order:
            if bit in roots:
                continue
            typ = logic[bit][1]
            weight = int(is_lut(typ) or is_mux(typ) or is_carry(typ))
            candidates = []
            for prev in graph[bit]:
                if prev in state:
                    cost = weight
                    if carry_chain_two and is_carry(typ):
                        cost = 0 if prev in carry_links[bit] else 2
                    depth, fanout, root = state[prev]
                    candidates.append((depth + cost, max(fanout, len(loads[bit])), root))
            if candidates:
                state[bit] = max(candidates, key=lambda value: value[:2])
        reached = [point for point in chosen if point['bit'] in state]
        if reached:
            endpoint = max(reached, key=lambda point: state[point['bit']][:2])
            depth, fanout, root = state[endpoint['bit']]
            result[kind] = dict(start=roots[root]['signal'], start_pin=roots[root]['pin'],
                                end=endpoint['signal'], end_pin=endpoint['pin'],
                                levels=depth, max_fanout=fanout)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--commit', default='worktree')
    parser.add_argument('--netlist', type=Path, help='reuse a synthesized XC7 JSON')
    parser.add_argument('--carry-chain-two', action='store_true',
                        help='count each continuous native carry chain as two levels')
    parser.add_argument('--start', help='start register/IP signal or pin regex')
    parser.add_argument('--end', help='end register/IP signal or pin regex')
    parser.add_argument('--worst-only', action='store_true',
                        help='write equivalent global maxima per category instead of all pairs')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    netlist = args.netlist or synthesize(output, args.commit)
    design = json.loads(netlist.read_text())
    if args.worst_only:
        summary = output / 'worst.json'
        summary.write_text(json.dumps(worst(design, args.start, args.end, args.carry_chain_two), indent=2) + '\n')
        print(summary)
        return
    with (output / 'pairs.tsv').open('w') as stream:
        writer = csv.writer(stream, delimiter='\t')
        writer.writerow(['start', 'start_pin', 'category', 'end', 'end_pin',
                         'levels', 'max_fanout'])
        writer.writerows(pairs(design, args.start, args.end, args.carry_chain_two))
    print(output / 'pairs.tsv')


if __name__ == '__main__':
    main()
