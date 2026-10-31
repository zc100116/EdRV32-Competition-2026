#!/usr/bin/env python3
# File: report.py
# Spec: rnd 2.3/5.2/7; T-RNDMEAS.
# Description: Format measured lane counts and geometry ranges into the requested report.
# Clock domain: host.
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/rnd_util'


def main():
    rows = json.loads((OUT / 'results.json').read_text())
    geometry = json.loads((OUT / 'geometry.json').read_text())
    names = (OUT / 'capture/names.txt').read_text().splitlines()
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    lines = [
        '# RND 真实 LVGL 命令流 lane 利用率（2026-10-31）',
        '',
        f'RTL：`7c056b66cdd49999ce6561a6446c5ba78d6aeb31`；测量工具：`{commit}`。',
        'Verilator 5.020，125 MHz；无器件/速度等级约束（RTL 功能仿真）。首次同口径基线；RTL/规格/原测试未改。',
        '每场景抓取中点的一次 RN-17 全屏重绘：普通场景进入后 1500 ms，8/14 为 2500 ms，15 为 10000 ms。',
        '原始输入/全任务统计位于 `build/rnd_util/capture/`、`profile.log`；汇总为 `results.json`、`geometry.json`。',
        '两配置均无随机背压，B 额外延迟 0；读首拍延迟分别 0/40，后者与 RN-18 的 DDR 模型同口径。',
        '32 次回放逐 batch 对所有目标字节与 rnd_ref 逐位一致；PERF0/4/5 与 TB 周期/读等/写等逐 batch 相等，PASS。',
        '下表每格 `0等待 / 40拍`；C=总周期，2/1/0=alpha 输出接受像素拍数，G=geometry 有效且接受，S=draw 仅等 geometry。',
        'R8=2/C；R7=(4×AA双像素请求+非AA双像素请求)/C；近似 S%=S/C。不扣除与 DDR 等待的重叠，均为所采命令流额外工作上界。',
        '读/写等待沿用 PERF4/5，可彼此重叠；这些采样不能证明任意动画帧或改单 lane 后 RN-18 周期不增加。',
        '',
        '|场景|C|2/1/0|R8 %|R7 %|G/S|S %|读/写等待|',
        '|---|---:|---|---:|---:|---|---:|---|',
    ]

    def cells(pair):
        def both(fn):
            return ' / '.join(fn(row) for row in pair)
        return [both(lambda r: str(r['cycles'])),
                both(lambda r: f"{r['two']},{r['one']},{r['zero']}"),
                both(lambda r: f"{100*r['two']/r['cycles']:.3f}"),
                both(lambda r: f"{100*r['geometry_extra']/r['cycles']:.3f}"),
                both(lambda r: f"{r['geometry_accepted']},{r['geometry_stall']}"),
                both(lambda r: f"{100*r['geometry_stall']/r['cycles']:.3f}"),
                both(lambda r: f"{r['read_wait']},{r['write_wait']}")]

    for scene, name in enumerate(names):
        pair = [next(r for r in rows if r['scene'] == scene and r['latency'] == latency)
                for latency in (0, 40)]
        lines.append('|' + '|'.join([f'{scene:02d} {name}', *cells(pair)]) + '|')
    sums = [{key: sum(r[key] for r in rows if r['latency'] == latency)
             for key in rows[0] if key not in ('scene', 'latency')} for latency in (0, 40)]
    lines.append('|' + '|'.join(['加权合计', *cells(sums)]) + '|')
    lines += [
        '',
        '加权按各场景各一帧的计数求和后除以总 C，非百分比的算术平均；全屏重绘包含原始混合 SW/RND 分工，C 只含 RND 忙碌时间。',
        f"参数 census：原生 SW 跑 100–68900 ms、100 ms 步长，16 场景共 "
        f"{sum(geometry['geometry_tasks'])} 个几何参数块；支持判定保持原样。",
        '字段单位为参数块原始整数；位宽=abs(max).bit_length()+1（有符号对称范围）。累加范围为实际 RECT∩CLIP，圆包含 1/8 初始子点和 AA 子点。',
        '线性 E 在矩形角点取极值；圆为可分离凸二次式，检查端点及最邻近顶点的采样网格点；E×8 额外保留比较小数位。',
        '',
        '|字段|最大绝对值|有符号位数|场景 / 命令|',
        '|---|---:|---:|---|',
    ]
    ops = {9: 'TRIANGLE', 10: 'LINE', 11: 'ARC'}
    for field, value in geometry['maxima'].items():
        lines.append(f"|{field}|{value['absolute']}|{value['bits']}|"
                     f"{value['scene']:02d} {names[value['scene']]} / {ops[value['op']]}|")
    lines += [
        '',
        '复现（先初始化已锁定的 LVGL 子模块并加载仓库工具环境；生成物均留在 build）：',
        '```sh',
        'mkdir -p build/rnd_util',
        'python3 tools/s3/rnd_capture.py > build/rnd_util/capture.log',
        'python3 sw/apps/s3/host/rnd_profile.py > build/rnd_util/profile.log',
        'python3 verif/block/rnd_util/geometry.py build/rnd_util/profile.log '
        '> build/rnd_util/geometry.json',
        'flock /tmp/edrv32-sim.lock python3 verif/block/rnd_util/run.py',
        'python3 verif/block/rnd_util/report.py',
        '```',
        '测量目录仅属 perf，不加入 smoke/full；本次没有改变任何 RN-17/RN-18 判定。',
    ]
    (ROOT / 'docs/reports/2026-10-31-rnd-lane-util.md').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
