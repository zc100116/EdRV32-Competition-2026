#!/usr/bin/env python3
# File: coverage_report.py
# Spec: cpu-testplan 4; cpu-spec 3.4, 7.1-7.2 (C-V5).
# Description: Merge B1 functional counters and report every required coverage bin.
# Clock: none (host).
"""Merge B1 coverage JSON files; exit 1 if any required bin has zero hits."""
import argparse
import json
from pathlib import Path


def requirements():
    """Yield stable bin IDs, requirements."""
    for suffix, label in (
        ('dual', '双发射（双退休见证成功配对）'),
        ('normal', '双发射不互换'), ('swap', '双发射互换'),
        ('raw', '配对失败：组内 RAW（HPM 5）'),
        ('structure', '配对失败：结构冲突（HPM 6）'),
        ('slot1_type', '配对失败：管线能力或双控制转移（HPM 7）'),
        ('ib_single', '配对失败：IB 只有 1 条（HPM 8）'),
    ):
        yield f'pair.{suffix}', f'配对结果：{label}'
    for source in ('e0', 'e1', 'm0', 'm1', 'w0', 'w1'):
        for operand in (1, 2):
            for slot in (0, 1):
                yield (f'bypass.{source}.rs{operand}.slot{slot}',
                        f'旁路源：{source.upper()} → 槽 {slot} rs{operand}')
    for cause, label in (
        (0, '指令地址不对齐（无 C 扩展）'), (1, '取指访问错误'),
        (2, '非法指令'), (3, 'EBREAK'), (4, 'load 地址不对齐'),
        (5, 'load 访问错误'), (6, 'store 地址不对齐'),
        (7, 'store 访问错误'), (11, 'M 模式 ECALL'),
    ):
        yield f'exception.{cause}.slot0', f'异常原因 × 槽位：cause {cause} {label} × 槽 0'
    for cause in (0, 4, 5, 6, 7):
        yield f'exception.{cause}.slot1', f'异常原因 × 槽位：cause {cause} × 槽 1'
    for kind in ('e_direction', 'e_target', 'd'):
        for slot in (0, 1):
            yield f'redirect.{kind}.slot{slot}', f'{kind} 重定向 × 槽 {slot}'
    for suffix, label in (
        ('e_direction', 'E 级方向误预测'),
        ('e_target', 'E 级目标误预测'),
        ('d', 'D 级'), ('m', 'M 级 load 比较分支'), ('exception', '异常'), ('interrupt', '中断'),
        ('mret', 'MRET'), ('fence_i', 'FENCE.I'),
    ):
        yield f'redirect.{suffix}', f'重定向类型：{label}'
    yield 'early.bypass.e0', '提前 load 的 E0 旁路（编码 1）'
    for suffix in ('older_slot', 'e', 'm_alu', 'm_load', 'm_csr',
                   'multiply', 'w', 'x0', 'register_file'):
        yield f'early.condition.{suffix}', f'提前地址条件：{suffix}'
    for suffix in ('port', 'miss', 'device', 'write_buffer', 'accepted_store'):
        yield f'early.failure.{suffix}', f'提前访问失败：{suffix}'
    for suffix, label in (
        ('load_use', 'load-use'),
        ('multiply', '乘法'),
        ('divide', '除法'), ('csr', 'CSR'),
        ('ic_miss', 'I$ 缺失'), ('dc_miss', 'D$ 缺失'), ('device', '设备访问'),
    ):
        yield f'stall.{suffix}', f'停顿类型：{label}'
    for suffix, label in (
        ('normal', '普通执行'), ('divide', '除法进行中'), ('device', '设备访问进行中'),
        ('dc_miss', 'D$ 缺失中'), ('branch_flush', '分支误预测冲刷同拍'),
    ):
        yield f'irq.{suffix}', f'中断到达时刻：{label}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', type=Path, nargs='+', help='B1 coverage JSON files')
    args = parser.parse_args()
    bins = list(requirements())
    totals = {key: 0 for key, _ in bins}
    for path in args.files:
        counts = json.loads(path.read_text())['counts']
        for key in totals:
            # Missing required fields are input errors, never silently zero-filled.
            totals[key] += counts[key]
    print(f'CPU 功能覆盖报告（cpu-testplan §4；合并 {len(args.files)} 次仿真）')
    print()
    print('| 覆盖项 | 要求（每项 ≥1 次） | 命中次数 | 是否覆盖 |')
    print('|---|---|---:|---|')
    for key, requirement in bins:
        hits = totals[key]
        print(f'| {key} | {requirement} | {hits} | {"已覆盖" if hits > 0 else "未覆盖"} |')
    covered = sum(totals[key] > 0 for key in totals)
    print(f'\n覆盖 {covered}/{len(bins)} 项；未覆盖 {len(bins) - covered} 项。')
    print('\n互换组不可达：E0 ALU、E1 load/乘法（管线能力限制）；'
          '不计为缺失。P-03 另检查 E1 ALU、E0 JALR链接、M0 load、W0乘法的可达互换场景。')
    return 0 if covered == len(bins) else 1


if __name__ == '__main__':
    raise SystemExit(main())
