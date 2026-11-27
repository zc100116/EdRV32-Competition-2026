#!/usr/bin/env python3
# File: calibrate_v2_timing.py; Spec: C2-I slow-corner path calibration; Clock: host.
# Summarize data arcs from cards 56/59/75; exclude clock-tree and fast-corner arcs.
# Critical-path samples are not an unbiased device delay distribution.
"""python3 tools/cpu/eval/calibrate_v2_timing.py; no generated inputs required."""
from pathlib import Path
import re
from statistics import median
import subprocess


def archived(card, name):
    task = '20261104-56-cpu-l1-timing-probe' if card == 56 else '20261105-59-cpu-v017-timing-probe'
    return subprocess.check_output(
        ['git', 'show', f'archive/win/{task}:tasks/win/{task}/artifacts/{name}/'
         'timing_setup_top20_detail.txt'], text=True)


def summarize(report):
    values = dict(ff_tco=[], drm_tco=[], clm_y_td=[], route=[], small_route=[])
    paths = 0
    for block in report.split('Startpoint')[1:]:
        if not re.search(r'Path Group\s*:\s*clk_sys\s', block) or (
                'max (slow corner)' not in block):
            continue
        paths += 1
        data = block[re.search(r'^.*\btco\s', block, re.M).start():]
        data = data.split('Data arrival time')[0]
        for line in data.splitlines():
            if match := re.search(r'\btco\s+([\d.]+)', line):
                values['drm_tco' if line.lstrip().startswith('DRM_') else 'ff_tco'].append(
                    float(match[1]))
            if re.search(r'^\s*CLM[AS]_\S+/Y\d', line):
                if match := re.search(r'\btd\s+([\d.]+)', line):
                    values['clm_y_td'].append(float(match[1]))
        for fanout, delay in re.findall(r'net \(fanout=(\d+)\)\s+([\d.]+)', data):
            values['route'].append(float(delay))
            if int(fanout) <= 16:
                values['small_route'].append(float(delay))
    return paths, values


def main():
    reports = {'56-R1': archived(56, 'R1'), '59-R1': archived(59, 'R1'),
               '75': Path('tasks/win/20261114-75-soc-fan2-post/artifacts/'
                          'timing_setup_top20_detail.txt').read_text()}
    print('| 卡/慢角sys路径数 | 弧类 | 弧数 | min / median / max ns |')
    print('|---|---|---:|---|')
    for name, report in reports.items():
        paths, values = summarize(report)
        for kind, samples in values.items():
            if samples:
                print(f'| {name} / {paths} | {kind} | {len(samples)} | '
                      f'{min(samples):.3f} / {median(samples):.3f} / {max(samples):.3f} |')


if __name__ == '__main__':
    main()
