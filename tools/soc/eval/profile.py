#!/usr/bin/env python3
"""Print S-1 hierarchy comparison and observed timing/fanout; read-only, stdlib."""
import csv
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GPU_REF = '96fd08ecee9c771f840f1ccad75a62bcb55d54fc'
GPU_DIR = 'tasks/win/20261124-107-gpu-board/artifacts/round11/'
VISION_DIR = ROOT / 'tasks/win/20261114-75-soc-fan2-post/artifacts'


def gpu_file(name):
    return subprocess.check_output(
        ['git', 'show', f'{GPU_REF}:{GPU_DIR}{name}'], cwd=ROOT, text=True)


def hierarchy(source, gpu):
    result = {}
    stack = []
    for line in source.splitlines():
        if gpu:
            match = re.match(
                r'\s*\d+\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)(   .*)$',
                line)
            if not match:
                continue
            field = match[6]
            values = tuple(float(match[i]) for i in (1, 2, 3, 5))
        else:
            fields = line.split('|')
            if len(fields) < 8 or not fields[2].strip().isdigit():
                continue
            field = fields[1]
            values = tuple(float(fields[i]) for i in (2, 3, 4, 6))
        if '+' not in field:
            continue
        depth = field.index('+')
        name = field.split('+')[1].strip()
        while stack and stack[-1][0] >= depth:
            stack.pop()
        stack.append((depth, name))
        path = '/'.join(item[1] for item in stack).removeprefix('u_soc/')
        result[path] = values
    return result


def selected(path):
    name = path.split('/')[-1]
    if 'reset' in name or name.startswith('g_'):
        return False
    return (path.split('/')[0] in ('u_mem', 'u_sys', 'u_eth', 'u_disp', 'u_aud')
            and path.count('/') <= 1 or path in (
                'u_mem/u_xbar/u_rbuf', 'u_mem/u_xbar/u_regs', 'u_mem/u_xbar/u_sched',
                'u_mem/u_gw/u_bridge', 'u_gpu/u_core/u_regs', 'u_gpu/u_axi_async',
                'u_gpu/u_apb_async'))


def counts(value):
    return ' / '.join(f'{number:g}' for number in value)


def main():
    gpu = hierarchy(gpu_file('resource_hier.txt'), True)
    vision = hierarchy((VISION_DIR / 'resource_hier.txt').read_text(), False)
    print('| 层次 | GPU LUT / FF / LUTRAM / DRM36K | 视觉 LUT / FF / LUTRAM / DRM36K |')
    print('|---|---:|---:|')
    for path in sorted(set(gpu) | set(vision)):
        if selected(path):
            print(f'| `{path}` | {counts(gpu[path]) if path in gpu else "—"} | '
                  f'{counts(vision[path]) if path in vision else "—"} |')
    for label, data, totals in [('GPU', gpu, (98023, 143393)),
                                ('视觉', vision, (89046, 109700))]:
        paths = ['u_mem', 'u_sys', 'u_eth', 'u_disp']
        if label == 'GPU':
            paths += ['u_aud', 'u_gpu/u_core/u_regs', 'u_gpu/u_axi_async',
                      'u_gpu/u_apb_async']
        sums = [sum(data[path][i] for path in paths) for i in range(4)]
        print(label, counts(sums), 'LUT/FF %',
              *(f'{100*sums[i]/totals[i]:.3f}' for i in range(2)))
    print('\nGPU 高扇出（所选层次，含复位/使能等；非关键路径排名）：')
    rows = set()
    for line in gpu_file('high_fanout.txt').splitlines():
        fields = [part.strip() for part in line.split('|')[1:] if part.strip()]
        if len(fields) == 3 and fields[2].isdigit():
            path = fields[0].removeprefix('u_soc/')
            if any(path.startswith(prefix + '/') for prefix in (
                    'u_mem', 'u_sys', 'u_eth', 'u_disp', 'u_aud', 'u_gpu/u_core/u_regs')):
                rows.add((int(fields[2]), fields[0]))
    for count, path in sorted(rows, reverse=True)[:20]:
        print(count, path)
    print('\nGPU clk_mem top200 按终点归类（仅导出样本）：')
    groups = {}
    for line in gpu_file('setup_top200_clk_mem.txt').splitlines():
        match = re.match(r'\s*(\d+) \|\s*([\d.-]+) \|\s*(\d+) \| (.*)', line)
        if match:
            endpoint = match[4].split(' -> ')[1]
            group = '/'.join(endpoint.split('/')[:3])
            if '/u_rbuf/' in endpoint:
                group += '/u_rbuf'
            groups.setdefault(group, []).append(float(match[2]))
    for group, slacks in sorted(groups.items(), key=lambda item: min(item[1])):
        print(group, len(slacks), min(slacks))
    print('\n视觉 slow 已导出路径，各模块最差（非全路径覆盖）：')
    worst = {}
    with (VISION_DIR / 'timing_selected_modules_le_0p5.csv').open() as stream:
        for row in csv.DictReader(stream):
            if row['corner'] != 'slow' or not row['module'].startswith(
                    ('u_mem/', 'u_sys/', 'u_eth/', 'u_disp/')):
                continue
            key = row['module']
            if key not in worst or float(row['slack_ns']) < float(worst[key]['slack_ns']):
                worst[key] = row
    for key, row in sorted(worst.items()):
        print(key, row['slack_ns'], row['startpoint'], '->', row['endpoint'])


if __name__ == '__main__':
    main()
