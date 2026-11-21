"""Reproduce N-E2 CSV tables and measurement/estimate report; standard library."""

import importlib.util
import subprocess

from datapath_model import (CASES, COMBINATIONS, breakdown, network,
                            resident_weights, summarize)
from legacy_plan import BUILD, ROOT, analysis, write_csv
import npu_model

REFERENCE = '267690880519638fbdf621d4167781567a2f0755'
OUT = BUILD / 'ne2'
REPORT = ROOT / 'docs/reports/2026-10-26-perf-npu-datapath.md'
PHASE_NAMES = {'useful_mac': 'MAC 有效折算', 'padding_mac': 'MAC 通道填充',
               'control': '命令/输出块控制', 'quant': '量化装载与逐项配置',
               'weight': '权重装载', 'feature': '缺失输入行装载阻塞',
               'write_drain': '行尾 W 数据排空', 'write_response': '行尾 B/本地完成等待',
               'patch_pipeline': 'patch/流水填充及背压', 'row_prepare': '行准备/切换',
               'nonconv': '非卷积算子', 'payload_wait': '共享 R/W 载荷下限增量'}


def table(headers, rows):
    return ('| '+' | '.join(headers)+' |\n| '+' | '.join(['---']*len(headers))+' |\n'+
            ''.join('| '+' | '.join(map(str, row))+' |\n' for row in rows)+'\n')


def metrics(rows):
    return table(['场景', '周期', 'ms', 'fps', '+4.15ms fps', 'DDR读 B', 'DDR写 B',
                  '总 B/帧', '平均 GB/s', '最忙命令平均 GB/s'],
                 [(r['case'], f"{r['cycles']:,.0f}", f"{r['ms']:.4f}",
                   f"{r['fps']:.4f}", f"{r['fps_with_post']:.4f}",
                   f"{r['ddr_read']:,.0f}", f"{r['ddr_write']:,.0f}",
                   f"{r['ddr_bytes']:,.0f}", f"{r['avg_GBps']:.4f}",
                   f"{r['max_command_avg_GBps']:.4f}") for r in rows])


def reference_comparison(rows):
    # Recompute the historical program from git, without RTL or stored RTL logs.
    path = OUT / 'ne1_reference.py'
    path.write_bytes(subprocess.check_output(
        ['git', 'show', f'{REFERENCE}:tools/npu/eval/npu_model.py'], cwd=ROOT))
    spec = importlib.util.spec_from_file_location('ne1_reference', path)
    reference = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reference)
    commands, totals = [], []
    measured = (9393301, 10886701, 14606057, 21229893, 12492918, 14430820)
    for (latency, bw), rtl in zip(npu_model.MEASUREMENTS, measured):
        before = reference.network(rows, latency, bw)
        after = npu_model.network(rows, latency, bw)
        for a, b in zip(before, after):
            commands.append(dict(latency=latency, bandwidth=bw, index=a['index'],
                                 name=a['name'], before=a['cycles'], after=b['cycles'],
                                 delta=b['cycles']-a['cycles']))
        old, new = sum(c['cycles'] for c in before), sum(c['cycles'] for c in after)
        totals.append(dict(latency=latency, bandwidth=bw, rtl=rtl, before=old,
                           after=new, delta=new-old,
                           commands_changed=sum(a['cycles'] != b['cycles']
                                                for a, b in zip(before, after)),
                           error_pct=(new/rtl-1)*100))
    write_csv(OUT/'calibration_commands.csv', commands)
    write_csv(OUT/'calibration.csv', totals)
    before, after = reference.scenarios(rows, 94, 4), npu_model.scenarios(rows, 94, 4)
    diff = [dict(case=a['case'], before_cycles=a['cycles'], after_cycles=b['cycles'],
                 changed_fields=sum(a[k] != b[k] for k in a)) for a, b in zip(before, after)]
    write_csv(OUT/'ne1_scenarios.csv', diff)
    return totals, diff


def quant_throttle(rows, changes, pair_clocks):
    if 'D3b' not in changes:
        return 0
    total = 0
    for c in rows:
        if c['kind'] != 'conv':
            continue
        k = (9 if 'W5' in changes and c['index'] == 0 else
             c['cin_blocks']*2*(9 if c['kernel3'] else 1))
        for block in range(c['output_blocks']):
            half = ('D2' in changes and c['index'] != 0 and
                    c['last_c16_only'] and block == c['output_blocks']-1)
            step = k//2 if half else k
            total += c['output_height']*c['output_width_pairs']*max(0, pair_clocks-step)
    return total


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = analysis()
    summaries, commands, phases, models = [], [], [], {}
    for name, changes in CASES:
        model = network(rows, changes=changes)
        models[name] = model
        summaries.append(summarize(name, model, 4))
        commands += [dict(case=name, bandwidth=4.0) | r for r in model]
        phases.append(dict(case=name, bandwidth=4.0) | breakdown(rows, model))
    sensitivity, limited = [], []
    for bw in (1.0, 1.4):
        for name, changes in COMBINATIONS[-2:]:
            model = network(rows, bandwidth=bw, changes=changes)
            sensitivity.append(summarize(name, model, bw))
            commands += [dict(case=name, bandwidth=bw) | r for r in model]
            phases.append(dict(case=name, bandwidth=bw) | breakdown(rows, model))
            base = {r['index']: r for r in models[name]}
            for r in model:
                if r['payload_limited']:
                    limited.append(dict(case=name, bandwidth=bw, index=r['index'],
                                        name=r['name'], ddr_bytes=r['ddr_bytes'],
                                        schedule_cycles=r['schedule_cycles'],
                                        payload_cycles=r['payload_cycles'],
                                        demand_GBps=r['demand_GBps'],
                                        demand_at_4GBps=base[r['index']]['demand_GBps'],
                                        cycles=r['cycles']))
    quant = []
    for name, changes in COMBINATIONS:
        wide = network(rows, changes=changes+('Q32',))
        original = models[name]
        quant.append(dict(case=name, narrow_wait=quant_throttle(rows, changes, 4),
                          wide_wait=quant_throttle(rows, changes, 2),
                          recovered_cycles=sum(r['cycles'] for r in original)-
                          sum(r['cycles'] for r in wide),
                          wide_fps=summarize(name, wide, 4)['fps']))
    weights = resident_weights(rows)
    write_csv(OUT/'scenarios.csv', summaries)
    write_csv(OUT/'sensitivity.csv', sensitivity)
    write_csv(OUT/'commands.csv', commands)
    write_csv(OUT/'phases.csv', phases)
    write_csv(OUT/'bandwidth_limited.csv', limited)
    write_csv(OUT/'quant_throughput.csv', quant)
    write_csv(OUT/'resident_weights.csv', weights)
    calibration, old_scenarios = reference_comparison(rows)
    text = INTRO
    text += '\n## 单项叠加旧基线（模型估算）\n\n'+metrics(summaries[:10])
    text += ('\n## W4b 组合（模型估算）\n\n'
             'C0 = W1+W2+W3+W4b+W5+W6；所有组合均使用W4b。\n\n'+metrics(summaries[10:]))
    text += ('最忙命令均值为 `max(命令DDR字节/命令时间)`，不是单拍峰值；'
             '全部单项和组合仍为 512 MAC、150 MHz。'
             'DDR 字节包含 74 命令；后处理列只增加 4.15 ms，后处理流量未取得。\n\n')
    combo_phases = [p for p in phases if p['case'] in dict(COMBINATIONS) and p['bandwidth'] == 4]
    text += table(['互斥周期类别']+[p['case'] for p in combo_phases],
                  [(label, *[f'{p[key]:,.1f}' for p in combo_phases])
                   for key, label in PHASE_NAMES.items()])
    text += ('`payload_wait=max(0,总字节/(带宽/150MHz)−其余阶段和)`，'
             '单独归为共享端口载荷等待，使阶段和严格等于命令周期；'
             '没有把载荷下限重复加到输入或 MAC 阶段。'
             '互斥分类沿用 N-E1，并显式增加这一项；各单项和低带宽阶段值见 `phases.csv`。\n\n')
    for bw in (1.0, 1.4):
        text += f'\n## 可用带宽 {bw:.1f} GB/s（模型估算）\n\n'
        text += metrics([r for r in sensitivity if r['bandwidth'] == bw])
        text += table(['组合', '# 命令', '载荷 B', '未钳位调度周期', '载荷下限周期',
                       '本带宽下需求 GB/s', '4GB/s调度下需求 GB/s'],
                      [(r['case'], f"{r['index']} {r['name']}", f"{r['ddr_bytes']:,.0f}",
                        f"{r['schedule_cycles']:,.1f}", f"{r['payload_cycles']:,.1f}",
                        f"{r['demand_GBps']:.4f}", f"{r['demand_at_4GBps']:.4f}")
                       for r in limited if r['bandwidth'] == bw])
    text += BANDWIDTH
    text += '\n## 量化吞吐敏感性（协调者补充项）\n\n'
    text += table(['组合', '4拍量化显式等待', '2拍量化显式等待', '可收回整网周期', '32lane fps'],
                  [(r['case'], r['narrow_wait'], r['wide_wait'],
                    f"{r['recovered_cycles']:,.0f}", f"{r['wide_fps']:.4f}") for r in quant])
    text += ('固定计划全部普通 1×1 层 K≥4，D2 的最小半块 K=5，W5 首层 K=9；'
             '因此没有 K<4 的命令，这批形状中加宽量化收回 0 拍。'
             '旧 chunk 调度的 10T 已含间隙，不能再额外添加量化等待；'
             'D3b 才显式计算 `P×max(0,4−K)`，其定向小层 K=2 的等待由 24 拍变为 0 拍。'
             '32lane 估算只改变持续吞吐，保留每行 14 拍流水，未估算其新算术资源。\n\n')
    text += STORAGE+'\n'
    text += table(['# 命令', '权重 B', 'C32块', '每bank深度', '权重 DRM', '参数 B',
                   '16份LUT B'],
                  [(f"{r['index']} {r['name']}", r['weight_bytes'], r['blocks'],
                    r['bank_depth'], r['weight_drm'], r['params_bytes'], r['lut_bytes'])
                   for r in weights])
    text += RESOURCES
    resource_specs = [('W1', 0, '中：预取调度、五行标签/生命周期，1×1 使用两个行槽'),
                      ('W2', 0, '低：B计数跨行保留，命令末统一等待'),
                      ('W3', 48, '中：双bank与预取、16路参数/LUT选择'),
                      ('W4b', 80, '高：循环重排、整层权重寻址、量化bank常驻'),
                      ('W5', 0, '中：C3专用输入打包和地址生成'),
                      ('W6', 4, '中：shortcut读DMA、双缓冲、量化结果对齐'),
                      ('D2', 0, '高：权重重排、256位激活、部分和合并'),
                      ('D3a', 0, '中：跨行chunk描述符和双半区所有权；依赖W1'),
                      ('D3b', -8, '高：连续窗口寻址、行缓存直连、全链路背压')]
    by_name = {r['case']: r for r in summaries}
    exchange = []
    for name, drm, complexity in resource_specs:
        gain = by_name[name]['fps']-by_name['baseline']['fps']
        ratio = f'{gain/drm:.5f}' if drm > 0 else '不适用（净增0）' if drm == 0 else '不适用（节省8）'
        exchange.append(dict(item=name, net_drm=drm, fps_gain=gain,
                             fps_per_added_drm=ratio, complexity=complexity))
    write_csv(OUT/'resource_exchange.csv', exchange)
    text += table(['单项', '净增 DRM', '相对旧基线 Δfps', 'Δfps/新增DRM', '实现复杂度（估算）'],
                  [(r['item'], r['net_drm'], f"{r['fps_gain']:.5f}",
                    r['fps_per_added_drm'], r['complexity']) for r in exchange])
    text += ('D3a 单项没有 W1，故单项收益为零；C0 上加 D3a 的增益为 '
             f"{by_name['C0+D3a']['fps']-by_name['C0']['fps']:.5f} fps，净增0 DRM。"
             'D2 在 C0 上的增益为 '
             f"{by_name['C0+D2']['fps']-by_name['C0']['fps']:.5f} fps，净增0 DRM；"
             'D3b 在 C0 上的增益为 '
             f"{by_name['C0+D3b']['fps']-by_name['C0']['fps']:.5f} fps，节省8 DRM。"
             '零/负分母不定义 fps/新增 DRM，不能解释成无限收益。\n\n')
    text += '\n## 与 N-E1 对照和校准不变性\n\n'
    text += table(['L / GB/s', '旧RTL CY（N-E1）', '修改前模型 CY', '修改后模型 CY',
                   '逐命令改变数', '总差值', '模型/RTL误差'],
                  [(f"{r['latency']} / {r['bandwidth']:g}", f"{r['rtl']:,}",
                    f"{r['before']:,.3f}", f"{r['after']:,.3f}", r['commands_changed'],
                    r['delta'], f"{r['error_pct']:+.4f}%") for r in calibration])
    text += (f'六点合计 444 条逐命令周期逐位相同；N-E1 的 {len(old_scenarios)} 个场景'
             f"中变动字段共 {sum(r['changed_fields'] for r in old_scenarios)} 个，"
             '见 `calibration_commands.csv` 和 `ne1_scenarios.csv`。'
             '旧 RTL 周期引用 N-E1 报告，不重新运行仿真；历史模型由上述 git commit 导出后执行。\n\n'
             'N-E1 的 W1–W6 是 W4a 组合（8,643,476 拍，17.3541 fps）；'
             '本报告 C0 使用 W4b（8,318,316 拍），W1 可使用行内全部 C32 块的计算窗口，'
             '两者不能混用。单项 W1/W2/W3/W4b/W5/W6 与 N-E1 对应行相同。'
             'D2 移除 197,222,400 个填充 MAC，即 385,200 个 MAC 阵列拍；'
             '其时间收益另受填充缩短、合并流水和重叠窗口变化影响。'
             'D3b 基线收益不是直接删除 1,461,864 拍：仍保留每行14拍和writer背压，'
             '并用新的结果到达时刻重算 W/B 尾部。\n\n')
    text += REPRODUCE
    REPORT.write_text(text)
    for r in summaries+sensitivity:
        print(f"{r['case']} B={r['bandwidth']:g}: {r['cycles']:.0f} cycles, {r['fps']:.5f} fps")
    print(f'Report: {REPORT}')


INTRO = '''# NPU 512 MAC 数据通路与调度评估（N-E2）

日期：2026-10-26。本文记录 Python 阶段模型及片上资源估算，不含改造后 RTL 实测或设计选型结论。

## 输入与环境

- 输入/旧模型 commit：`267690880519638fbdf621d4167781567a2f0755`；评估工具与本文随 N-E2 提交。
  旧校准来源：[N-E1](2026-10-26-perf-npu-legacy.md)。Python 3.12.3，仅标准库，Linux x86_64，3核/8GB；单进程，不运行 RTL 仿真。
- PG2L200H，器件速度等级与实现时序本次未测。独立 `clk_npu=150 MHz`，512 MAC/拍，256 APM 阵列。
  640×384 YOLOv8n：74命令，63conv/6add/3pool/2up，沿用 `legacy_plan.analysis()` 的固定计划及其 YAML 输入路径。
- 板测等效服务点 `L=94` 拍、R/W共享载荷上限4.0 GB/s；不将等效 L 当作 DDR tRCD。
  1.0/1.4 GB/s 只改变服务带宽，固定L、150MHz和512 MAC；重新计算 burst、writer、非卷积和重叠窗口。
- MB/GB为十进制，KiB=1024 B，DRM每块36 Kibit。周期总量由未取整阶段相加，表格最后取整；fps由未取整周期计算。
  真实 MAC/512 包含空间边界零填充，通道填充单列。
- 依据只读旧 `conv_layer`、`patch_gen`、`conv_tile`、`line_cache`、`tile_store`、`result_quant`，
  以及旧2026-09-23 YOLO架构文档、SoC规格6.4–6.5、7.4–7.5、8.9、9.1/9.3和DDR带宽分析。
  任务书的“规格7.6”在当前版本不存在，协调者确认引用6.4/9.1和带宽分析第4节。

## 阶段假设

定义 B=ceil(Cout/32)，H=输出高，P=输出像素对/行，T=ceil(P/tile_pairs)，
K=2×CinBlocks×kernel²；W5首层K=9。旧每行MAC=P×K，非MAC patch项为
首chunk的 `min(P,tile_pairs)×K + 10T + 14`，再加writer阻塞。DDR burst、响应和非卷积模型均沿用N-E1。

| 项 | 隐藏/改变的阶段 | 前提与残留 |
| --- | --- | --- |
| W1 | 后续输入行装载与行执行重叠，隐藏量=min(可预取服务量,行执行窗口) | 首遍3×3两行或1×1一行保留；行执行窗口=MAC+patch+W排空的(H−1)/H，W4b使用该行全部C32块；容量/双口见下文 |
| W2 | 每行外部B等待移至命令边界 | 保留每行3拍本地完成及命令最后B；未去掉W载荷，沿用旧writer四个B credit，不等同于新SoC默认写在途2的完整DMA仿真 |
| W3 | 后续C32块的权重与量化配置隐藏于前块执行 | 保留第一块装载，阶段除以B；保留N-E1的充分重叠假设；不建模重写DMA的配置争用或跨命令预取 |
| W4b | 外层输出行、内层输出块，共享五行输入缓存，只读一遍输入 | 全层权重/参数/LUT常驻；第一行可与W3逐块装入，后续行复用；不使用W4a的720KiB缓存，不改变权重DDR字节 |
| W5 | 首层紧凑C3输入，空间核每位置发一次，K从18到9 | 输入3,932,160→737,280 B，权重4,608→2,304 B；不对该首层再叠D2，不假设达到真实MAC极限 |
| W6 | 量化后残差融合到生产者写回，取消add临时结果读/写 | shortcut读仍保留，按载荷+每16beat一次L串行收取于前一conv；全帧少1,290,240 B；pool/up依赖保留 |
| D2 | 非首层末C16输出块切换16输出×16输入×2像素；配对同一C16内的两个C8，块K减半 | 权重预重排/加载重排，2048位读总线不加宽；不压缩DDR填充记录，不降低配置/输入读量；activation同容量变256位；每chunk固定多1拍合并流水，D3b下每行多1拍 |
| D3a | W1保证下一行输入已就绪时，前行末chunk MAC覆盖后行首chunk填充 | 每输出块跨H−1次行界，各隐藏min(首chunk填充,末chunk MAC)；首行填充、尾chunk不足差额、10T+14、writer阻塞保留；无W1时独立D3a收益为0 |
| D3b | 行缓存直接滑窗供MAC，取消activation RAM和chunk重启 | 普通模式每行非MAC固定14拍，D2半块15拍；有效pair间隔max(K,4)，原16lane量化每对需4拍；writer阻塞/W/B尾部用新到达时刻重算；输入行等待仍由W1模型计入 |

D3a/D3b互斥。D3a是有条件的跨行重叠上界：W1不但需足够平均窗口，还需在末chunk开始前完成下一行输入；
本阶段模型不逐拍证明其截止时刻。表中W1减去隐藏服务量后仍有的阻塞必须保留；D3a不能据此宣称任意低带宽都完全隐藏。
所有D项先改变MAC/patch/writer到达时刻，再重算W1窗口，不能把各单项节省拍直接相加。
新结构没有RTL校准，未计布局布线、端口冲突以外的实现停顿，14/1拍是经协调者确认的估算参数。

## D3b 滑动窗口供数、端口与形状

每拍只处理一个(ky,kx,C16组,8通道半块)，同时服务两个输出像素；不是每拍取整个3×3窗口。
普通模式送阵列 `2像素×8通道×1B=16 B/拍`；D2半块送32 B/拍，两个部分和再合并。
行缓存维持两个物理bank，每bank一个256位同步读口和一个256位写口，读延迟1拍；总共2R+2W物理端口，
DMA逻辑上每拍最多写一个bank（32 B/拍），读侧最多两个256位不同beat（64 B/拍，9.6 GB/s@150MHz），
同一beat的两个像素只读一次（32 B/拍），边界补零可能不读。64 B是片上毛读量，不是DDR带宽；
普通模式毛读后抽C8，D2抽完整C16，均无需增加读口或复制行缓存。

对输出像素对p，x0=2p×stride+kx−pad，x1=x0+stride，y=输出y×stride+ky−pad；
3×3时ky/kx=0..2、pad=1，1×1时ky=kx=pad=0。地址沿用
`bank=(x>>1)&1; addr=row_slot_base[ky]+cblock×(input_width/4)+(x>>2)`，
用x[0]选beat内像素、channel_half选其低/高C8；D2不遍历channel_half，直接取C16。
循环顺序为pair→ky→kx→C16→C8半块，DDR的C16平面布局保持不变。
3×3 stride1两像素相邻，同bank时必为同beat；stride2两像素相隔2，必为不同bank，因而一个读口/bank即可。
1×1 stride1/2同式，边界由有效位输出零；D3b依旧需描述符、同步RAM读、局部扇出寄存、MAC/量化尾流水，
模型合并保留14拍/输出行，连续pair间无chunk填充。

本评估只覆盖偶数输出宽、输入宽为4的倍数、Cin按C16分组、stride1/2、1×1/3×3。
3×3要求`5×CinBlocks×input_width/4≤1024`，W1的1×1双行要求
`2×CinBlocks×input_width/4≤1024`；固定计划最大值分别800和480，均在范围内。
奇数宽、其他stride、未填充通道不在本组织/模型中；D3b取消原`tile_pairs×K≤1024`的activation容量限制，
没有声称取消行缓存容量和bank约束。W5的C3紧凑DDR行先解包到同一行缓存格式（有效3字节、其余零），
不会为紧凑C3强套C16字节地址。
'''

BANDWIDTH = '''“受带宽限制”严格指总命令时间由共享载荷下限决定（payload_wait>0），上表列全。
需求=该命令总字节÷该带宽下、未加共享载荷下限前的调度时间；该时间已经包含更慢的读服务、writer和W1残留等待。
另列4GB/s调度下的需求供比较；两者都不是突发瞬时峰值。即使平均需求低于上限，命令仍可能受事务延迟影响。

1.4 GB/s依据当前[SoC规格6.4、9.1](../spec/edrv32-soc-spec.md)与
[DDR分析第3–4节](../design/2026-10-25-ddr-bandwidth-analysis.md)：2.6GB/s规划有效带宽×0.75=1.95GB/s准入量，
扣除S1其余约0.55GB/s后约余1.4GB/s；这是流量规划上限，未实测NPU保底/峰值可用带宽。
此处仍用N-E1的四读/四写响应模型及等效L，不是新mem_xbar仲裁和CDC的替代验收。
'''

STORAGE = '''
## 片上存储估算（未综合）

依据[Logos2 DRM用户指南UG040002 V1.2表9-1](https://www.pangomicro.com/en/uploads/49630285_1729131726.pdf)：
36K模式可用SDP 512×64/72、1024×32/36、4096×8/9；本文数据通路选二次幂字宽，未使用奇偶校验位。
DRM数量用`Σ ceil(逻辑宽/原语宽)×ceil(逻辑深/原语深)`逐bank计算，绝不只用总bit数除36K。
下述SDP均为1W+1R独立端口，同拍可以写预取行/另一缓冲、读当前行/当前缓冲；数据不进行复位。
16路LUT的地址彼此独立，按每路一整块DRM 4096×8的明确保守映射估算，未假设浅存储可随意合并为一块。
该映射的容量浪费有意计入；不是PDS自动映射实测，也不是所有可选映射中的最小值。

| 存储/改进 | 逻辑容量和宽度×深度 | 读写端口/每拍峰值 | 采用原语组合与DRM估算 |
| --- | --- | --- | --- |
| W1行缓存，D3a/D3b共用 | 64KiB，2bank×1024×256；3×3五行、1×1双行 | 每bank1R256+1W256；逻辑读≤64B、DMA写≤32B | 2×8个1024×32 SDP=16；相对旧缓存净增0 |
| activation旧/D3a | 32KiB，2048×128，两半各1024项 | 1R128+1W128；计算/patch访问不同半区 | 2路宽×4段深的512×64 SDP=8；D3a净增0 |
| D2 activation | 同32KiB，1024×256，两半各512项；块K减半故chunk字节不变 | 1R256+1W256，patch一拍同时写两个C8 | 4路宽×2段深的512×64 SDP=8；净增0；混合模式需同RAM重解释地址/字使能 |
| D3b activation | 0 | 无；由行缓存读口直送 | 取消8 DRM；行缓存仍16 DRM |
| 旧权重tile | 128KiB，8bank×512×256，合计读2048bit | 每bank1R256+1W256，DMA逻辑每拍只写1bank | 8×4个512×64 SDP=32 |
| W3额外权重bank | 额外128KiB，同上；最大实际C32块73,728B | 活动bank读、预取bank写 | +32 DRM；固定深度沿用N-E1，不按实际较小块降低估算 |
| W3额外量化参数 | 32×64bit=256B预算（RTL字段有效54bit/通道） | 配置写1通道；量化16通道并行读 | 沿用旧FF数组，额外约2K FF预算，0 DRM；若强制分16个宽64浅RAM需16个512×64，本文未采用 |
| W3额外LUT | 16份×256×8bit=4096B | 16个独立8bit读地址，配置广播写 | 每路4096×8 SDP一块，+16 DRM；复制含独立配置bank选择 |
| W3额外记录暂存 | 16×256bit=512B | DMA写256bit，配置读选64bit/8bit | 沿用旧FF记录数组，+4096 FF，0 DRM；若强制RAM为4个512×64，本文未采用 |
| W4b常驻权重最大 | 294,912B=288KiB，8bank×1152×256 | 每拍总读2048bit；DMA写256bit | 每bank3段×4路512×64：96 DRM，相对旧32净增64；物理数据分配384KiB |
| W4b全块参数最大 | 8块×32×64bit=2048B预算 | 选中块16通道读，配置写1通道 | 沿用FF/分布式参数，0 DRM，较旧增1792B（≤14,336 FF预算） |
| W4b全块LUT最大 | 8块×16份×256B=32KiB | 每路按block和8bit索引读，配置广播写 | 16bank×4096×8 SDP=16 DRM；逻辑深2048，物理分配64KiB；替换旧RTL的LUT数组 |
| W4b记录暂存 | 复用一份512B DMA记录 | 只在装载当前块时使用 | FF布局，0 DRM；无需为每块永久保留已解码的原始记录 |
| W6 shortcut读路径 | 2bank×16beat×32B=1024B | 逻辑1W256预取/1R256消费，可并行、按bank轮换 | 合为32×256、4个512×64 SDP=4 DRM，独立读写地址跨两个16深半区；写回沿用旧2KiB缓冲 |

W3额外逻辑存储131072+256+4096+512=135936B（与N-E1相同）；选择以上端口映射后增48 DRM，
其余参数/记录约6144bit放FF。W4b对每层常驻容量/每bank深度如下；权重DRM下界32来自2048bit读宽，
不是每层真实权重都消耗128KiB逻辑数据。量化参数按每块256B、LUT按每块4096B预算。
'''

RESOURCES = '''权重最大层为#25 L7：8个C32块、294,912B；其中每块36,864B（K=144），
8块共同深度1152；全网最大单块则为#68 D2.box.cv0的73,728B（K=288）。
W4b参数/LUT最大逻辑量与N-E1一致；不同于N-E1按总容量未计算映射，本报告显式计入宽深与读端口碎片。

W3与W4b组合复用常驻池：第一行把后续C32块预取到其最终槽位，故不再额外叠加W3的32块固定权重bank；
W3的量化双bank也置于同一16路LUT存储的不同block地址。记录可用两份FF512B满足W3，但不会新增DRM。
因此本映射下C0净增`64权重+16LUT+4残差=84 DRM`，总量按旧79估为163/415；
C0+D2、C0+D3a、C0+D2+D3a仍163/415；带D3b取消8块activation，估155/415。
这些加法只表示上述存储替换对旧网表的近似增量，未包含新的SoC CDC/DMA FIFO或PDS重映射。
这里按旧LUT数组未占DRM作增量核算；未取得PDS量化器层级映射，若旧LUT已占DRM，需从163/155中扣除被替换的块数。
因此该总量是本映射和旧LUT计数假设下的保守估算，不是已验证的新网表净增。
W1行缓存没有扩容；D2与W5新增局部寄存/重排逻辑，无额外DRM。

## 资源量级与 fps/DRM 交换（估算）

旧工程基线来自[2026-09-23执行记录](../../legacy/doc/architecture/2026-09-23-yolo-v8n-exec.md)：
APM 289/740、DRM 79/415；后处理首轮Device Map LUT 45,253/159,800（约45K）。
三者来自该文不同迭代，不能声称是同一次收敛网表；旧文还有150MHz负裕量记录，本任务未测新时序。
256 APM MAC阵列规模保持；D2部分和合并可用LUT进位链，无新增乘法器，整体APM按旧289作参照而非新实现保证。

LUT/FF只给量级，不作综合资源结论：W1/W2/W3/W4b的控制/计数/寻址是百至数千LUT量级估算，
W3参数和记录直接位数预算额外约6144 FF，W4b全参数较旧最多增加14336bit FF预算；
D2两像素×16通道的32个32bit合并加法器与寄存为约千级LUT/FF，加上权重/激活选择网络；
D3a双行描述符为百级FF和控制LUT；D3b沿用旧patch地址流水并加入连续有效/背压为百至数千LUT量级，
删除activation RAM及其地址/半区控制；W5打包和W6对齐/饱和加法为百至数千LUT量级。
这些粗量级来自RTL寄存宽度、加法器数量/宽度和控制规模，没有取得可分摊的旧PDS层级资源表；
约45K旧顶层数只作为对照，不能精确推算新顶层LUT。没有使用Yosys结果。
'''

REPRODUCE = '''
## 复现、原始数据与验证

在本提交的仓库根目录执行（不需要Verilator/PDS，不启动RTL仿真）：

```sh
python3 tools/npu/eval/test_npu_model.py
python3 tools/npu/eval/write_datapath_report.py
git diff --check
python3 tools/check/verilog_style.py tools/npu/eval
```

`legacy_plan.py`沿用N-E1的YAML默认路径
`/home/workspace/Projects/EdRV32-Competition-2026/thirdparty/ultralytics/ultralytics/cfg/models/v8/yolov8.yaml`；
复现环境需具备该输入文件。报告生成命令直接导入固定计划，不读取RTL仿真日志。
历史模型直接由git导出输入commit；不计算哈希、不增加门禁或回退路径。

原始CSV均在`build/npu_eval/ne2/`，生成物不入库：

- `scenarios.csv`：基线、九单项、六组合；`sensitivity.csv`：四个低带宽结果。
- `commands.csv`：上述场景的全部逐命令阶段/DDR读写、调度下限与需求；`phases.csv`：互斥汇总。
- `bandwidth_limited.csv`：全部由载荷下限决定时间的命令及两种需求口径。
- `resident_weights.csv`：63层权重/参数/LUT与DRM映射；`resource_exchange.csv`：单项fps/DRM、复杂度。
- `quant_throughput.csv`：原16lane与32lane吞吐敏感性。
- `calibration.csv`、`calibration_commands.csv`：六个旧校准点总量与444条命令对比；
  `ne1_scenarios.csv`：N-E1全部场景字段差异；`ne1_reference.py`：从记录commit导出的旧模型。

验证结果：11项Python定向测试通过；保留原5项，新增D2、D3a、D3b、尾chunk不足、D2逐行固定合并和量化吞吐用例，
测试注释写出手算周期。六个历史校准点周期逐位不变，全部旧场景字段不变。
本次没有改RTL，Verilog风格扫描归属目录为0个RTL文件；RTL lint/综合/布局布线不适用。
'''


if __name__ == '__main__':
    main()
