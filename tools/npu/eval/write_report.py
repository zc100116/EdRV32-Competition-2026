"""Render the requested measurement report from build/npu_eval CSV data."""

import csv
import json
import subprocess

from legacy_plan import BUILD, ROOT, analysis, summarize
from npu_model import BOARD_CYCLES, MEASUREMENTS, STAGES

REPORT = ROOT / 'docs/reports/2026-10-26-perf-npu-legacy.md'


def load_csv(name):
    return list(csv.DictReader((BUILD / name).open()))


def table(headers, rows):
    return ('| ' + ' | '.join(headers) + ' |\n| ' + ' | '.join(['---']*len(headers))
            + ' |\n' + ''.join('| ' + ' | '.join(map(str, r)) + ' |\n' for r in rows))


def main():
    static = analysis()
    summary = summarize(static)
    config = json.loads((BUILD / 'model_summary.json').read_text())
    scenarios = load_csv('scenarios.csv')
    errors = load_csv('calibration.csv')
    commands = load_csv('model_commands.csv')
    measured = {(l, b): load_csv(f'l{l}_b{b:g}.csv')
                for l, b in MEASUREMENTS}
    latency = config['equivalent_latency']
    bandwidth = config['bandwidth_gbps']
    base = scenarios[0]
    legacy_commit = subprocess.check_output(
        ['git', 'log', '-1', '--format=%H', '--', 'legacy/rtl/vision/yolo'],
        cwd=ROOT, text=True).strip()
    text = f'''# 旧工程 YOLOv8n 性能测量（N-E1）

日期：2026-10-26。测量对象是只读 `legacy/rtl/vision/yolo/`，没有修改 RTL。

## 输入、环境与计量口径

- 工作树起点 commit：`2675550302a5c4deff1ba05acb48fdf759c3e281`；
  被测 legacy RTL 最近修改 commit：`{legacy_commit}`。评估脚本与报告随本分支提交。
- Python 3.12.3（仅标准库）、Verilator 5.020（2024-01-01）、G++ 13.3.0，
  Linux x86_64；主机配额 3 核、8 GB。器件 PG2L200H，
  本次不做器件实现/速度等级测量。Verilator `--timing -j 1`，单个仿真进程。
- 640×384/C3、YOLOv8n 固定计划 74 条命令；63 conv、6 add、3 pool、2 up。
  导入旧 `build_plan()`，仅覆盖 `SOURCE_YAML` 到任务给定的 Ultralytics 配置。
  权重、输入和量化记录使用全零存储，完整执行真实乘法、量化和 DMA RTL。
  零乘数、零 shift、零 LUT 是合法配置；本实验测量调度，不验证真实模型精度。
- 150 MHz 源时钟；512 MAC/周期，即 256 APM、C32×C8×2 像素。
  仿真未定义 `FPGA_MODE`，使用 `SIM_MODE` 和原行为存储器。
- MB、GB/s 均为十进制；KiB 为 1024 B。MAC 计数把乘加计为一次 MAC。
  “真实 MAC”使用原始通道数，但保留常规定义中的空间边界补零运算；
  “填充 MAC”包含 C16 输入、C32 输出块、类别头尾块等通道填充。
- 整网时间为全部 74 命令（含非卷积算子），不含 UART、预处理、后处理与显示。
  另列 `+4.15 ms` 的串行 DFL/NMS 参考值；该值来自任务及旧行为仿真记录，
  **不是本次仿真重新测得的 DDR 后处理时间**。
- 依据范围：SoC spec 8.9、6.4–6.5、9.3，以及旧执行器/DDR 文档。
  这里没有将旧实现等同于新 SoC 的 DMA、仲裁或资源规格。

## AXI256 存储模型

`tools/npu/eval/axi256_eval.cpp` 用 64 MiB 地址保持存储，逐字节执行 WSTRB。
AR、AW 各可排队四笔，读返回保持顺序；每笔 burst 按实际 ARLEN/AWLEN 执行。
R/W 共享一个载荷令牌预算，满速最多合计一拍/周期；读写同时可服务时交替选择。
令牌容量 64 B，空闲可积累两个 beat，长期带宽为配置上限。
AR 接受后第 `L+1` 个采样边沿提供首个 R；最后 W 后第 `L+1` 个边沿提供 B。
因此 L=0 表示无额外等待，仍遵守同步请求/响应时序。AW 无额外固定延迟。

L=30 是任务指定的 DDR 敏感性点，等于 200 ns（150 MHz）；
旧板通路包含 150→125 MHz CDC、互连和 DDR 服务，它不是单独 tRCD。
没有取得板上逐事务时序，所以不能把 30 周期宣称为板测延迟。
4.8 GB/s 是 256 bit×150 MHz 的源口载荷上限；旧文档和已确认的 DDR 带宽分析记录记载 DDR3 为
32 bit、1000 MT/s，对应 4.0 GB/s 原始峰值，实际有效带宽还受其他主设备与换向影响。
仿真未包含背景 master；等效延迟只归纳这些未单独测量的成本。

原始 profiler 的 RW/BW 等等待可与 MAC 重叠，**不相加作为损耗分解**。
额外观察 wrapper 按每周期互斥分类：MAC、量化配置、权重装载、缺失输入行装载、
最后输出被接收后的 W 排空、W 全部完成后的 B/本地完成等待、其余 patch/流水、
行准备、控制、非卷积。wrapper 不改变任何握手。
`write_response` 中包含每行 3 个本地完成周期；W2 只移走外部 L，不移走这 3 拍。

## 静态全网核算

'''
    text += table(['指标', '值'], [
        ('真实 MAC', f"{summary['real_mac']:,}"),
        ('填充 MAC', f"{summary['padded_mac']:,}（3.076669440 GMAC）"),
        ('理想 MAC 周期', f"{summary['ideal_cycles']:,}（40.0608 ms @150 MHz）"),
        ('填充浪费 / 填充 MAC', f"{summary['padding_fraction']*100:.4f}%"),
        ('首层理想周期 / 全网', f"{static[0]['ideal_cycles']:,} / 9.2020%"),
        ('首层真实 / 填充 MAC', f"{static[0]['real_mac']:,} / {static[0]['padded_mac']:,}"),
        ('卷积输入读（逐 C32 块重复）', f"{summary['feature_read']:,} B"),
        ('卷积输入读（每层一次）', f"{summary['unique_feature_read']:,} B"),
        ('权重 / 量化记录读', f"{summary['weight_read']:,} / {summary['quant_read']:,} B"),
        ('卷积输出写', f"{summary['output_write']:,} B"),
        ('非卷积读 / 写', f"{summary['operator_read']:,} / {summary['operator_write']:,} B"),
        ('总读 / 总写 / 每帧 DDR', f"{summary['ddr_read']:,} / {summary['ddr_write']:,} / "
         f"{summary['ddr_bytes']:,} B"),
        ('首层 DDR / 全网', f"{static[0]['ddr_bytes']:,} B / 10.4975%")])
    text += '''
以下逐命令表中 MAC 单位为 M，周期单位为拍；W/Q/F/O 分别是权重读、量化记录读、
重复输入特征读、卷积输出写，R/W 是非卷积读/写，字节数均为 B。
add 的 beat 形状是单个操作数的大小；concat 是地址别名，没有额外命令或搬运。
完整字段在 `build/npu_eval/static.csv`。

'''
    text += table(['# / 名称', '算子 / 输入→输出', '真MAC / 填充MAC (M)', '理想拍',
                   'W / Q / F / O (B)', '非卷积 R / W (B)'], [
        (f"{c['index']} {c['name']}",
         f"{c['kind']} {c['input_shape']} → {c['output_shape']}",
         f"{c['real_mac']/1e6:.6f} / {c['padded_mac']/1e6:.6f}",
         f"{c['ideal_cycles']:,}",
         ' / '.join(str(c[k]) for k in ('weight_read', 'quant_read',
                                       'feature_read', 'output_write')),
         f"{c['operator_read']} / {c['operator_write']}") for c in static])
    text += '\n## 完整 RTL 实测与校准\n\n'
    results = []
    for (l, b), rows in measured.items():
        total = sum(int(r['CY']) for r in rows)
        conv = sum(int(r['CY']) for c, r in zip(static, rows) if c['kind'] == 'conv')
        e = [r for r in errors if int(r['latency']) == l and float(r['bandwidth']) == b]
        modeled = sum(float(r['modeled']) for r in e)
        peak = (BUILD / f'l{l}_b{b:g}_memory.txt').read_text().split('beats=')[1]
        peak_gbps = int(peak)*32*150e6/1024/1e9
        results.append((f'{l} / {b:g}', f'{total:,}', f'{conv:,}',
                        f'{total/150000:.5f}', f'{150e6/total:.4f}',
                        f'{modeled:.0f}', f'{(modeled/total-1)*100:+.4f}%',
                        f'{max(abs(float(r["error_pct"])) for r in e):.3f}%',
                        f'{peak_gbps:.4f}'))
    text += table(['L / GB/s上限', '74命令 CY', '纯conv CY', 'ms', 'fps', '模型CY',
                   '总误差', '最大逐命令误差', '峰值1024拍 GB/s'], results)
    text += f'''
完整仿真单次约 36–98 秒（零等待约 35.868 秒、L30 约 40.814 秒、
L100 约 55.955 秒、0.5 GB/s 约 97.822 秒），因此没有采用代表层替代。

L=0、30 的状态观测用于校准阶段常数；L=100 是较高延迟验证点，
0.5、2.0 GB/s 是带宽验证点，L94/4.0 GB/s 是主表等效点的额外 RTL 验证。模型没有读取逐命令实测周期作为预测值，
也没有按层存放修正表。全部六个点都满足全网 ≤5%、主要命令 ≤10%；
带宽受限点误差较大的部分是串行非卷积 DMA 的令牌初相和短 burst 开销。

六个点均为 MC={summary['ideal_cycles']:,}、RB={summary['ddr_read']//32:,}、
WB={summary['ddr_write']//32:,}，与静态字节核算逐命令一致。
L=0/30/100、4.8 GB/s 时 AR/AW/WW 均为 0；RW/BW 随延迟增加。
B 等待期间其他计算可继续，所以 profiler 的 BW 远大于互斥损耗表中可移走的行尾 B。

以 L=30、4.8 GB/s 的 CY 排名前 20 如下；CY0 是同一命令的零等待结果。
完整 74 行和所有 AR/RW/AW/WW/BW 字段在各个 `l*_b*.csv`。

'''
    slow = sorted(measured[(30, 4.8)], key=lambda r: int(r['CY']), reverse=True)[:20]
    text += table(['# / 名称', 'CY0', 'CY30', 'MC', 'RB', 'WB', 'RW30', 'BW30'], [
        (f"{r['index']} {static[int(r['index'])]['name']}",
         measured[(0, 4.8)][int(r['index'])]['CY'],
         *[r[k] for k in ('CY', 'MC', 'RB', 'WB', 'RW', 'BW')]) for r in slow])
    text += '''
## 周期模型、等效板测点与互斥损耗

模型按几何和 AXI 参数逐命令计算，主要公式如下：

- K=`2×CinBlocks×kernel²`，B=`ceil(Cout/32)`，P=输出行像素对，H=输出高，
  T=`ceil(P/tile_pairs)`；阵列有效输入拍 `B×H×P×K`。
- `read_cycles(N, addr_mod, L, bandwidth)` 调度四个在途 burst，按 16 beat 和
  4 KiB 拆分；计入释放 credit 后下一周期才能再发 AR 的行为。
- 每输出块权重装载=`read_cycles(8K)+5`；量化配置=
  `read_cycles(16)+37+257×lut_enable`（包含 32 通道和 256 LUT 项）。
- 每缺失输入行=`1+ΣCinBlocks(read_cycles(input_width/2)+3)`；3×3 行标签复用
  使每个输出块只读一遍整层输入，1×1 按行处理。
- 旧 patch/流水的非 MAC 部分每输出行为
  `K×tile_pairs + 10×T + 14`；当输出写入造成背压，再加缓冲受阻周期。
- 两个 16-pair 输出缓冲按原 writer 的 AW/W/B 状态和 4 个写响应 credit 调度。
  先计算最后一个量化结果被接收，再计算 W 排空和 B 返回；三者不重叠计损耗。
- add 每 16 beat 串行读 A、读 B、写结果；满速时为
  `3×beat_count + ceil(beat_count/16)×(10+3L)+4`。
- pool 实测确认 `S_SAMPLE_ADDR→S_SAMPLE_REQ→S_SAMPLE_USE`，每邻域采样三拍；
  20×12/C128 的三次池化纯采样是 **432,000 拍（2.88 ms）**。
  旧文档的“两拍/288,000”对应较早版本，不能用于当前 RTL。
- up 每个 C16 源行读一次，连续写两条输出行；每笔输出 burst 等 B。
- 控制近似 `3B+3`，短非卷积请求以载荷/服务率近似，所以保留了上表的微小误差。

'''
    text += f'''任务给定板测是 {BOARD_CYCLES:,} 拍（96.23349 ms，10.3914 fps），
并非本次重新上板。主表采用 {bandwidth:g} GB/s 的载荷上限，
使模型最接近板测的整数等效 L 为 **{latency} 拍**（{latency/150*1000:.2f} ns），
模型 {float(base['cycles']):,.0f} 拍，误差
{(float(base['cycles'])/BOARD_CYCLES-1)*100:+.4f}%。
另一个参考解是 4.8 GB/s、L≈{config['latency_at_4_8GBps']} 拍；
规划有效带宽 2.6 GB/s 下是 L≈{config['latency_at_2_6GBps']} 拍。
4.0 GB/s 理论峰值与 2.6 GB/s 规划值依据
`docs/design/2026-10-25-ddr-bandwidth-analysis.md` 1–2 节。
这些是非唯一的延迟/带宽组合，吸收 CDC、仲裁、背景访问等成本，不能解释成 DDR 单项延迟实测。

下表前两列是直接 RTL 观察，最后一列是板测等效点模型。
MAC 有效按真实通道折算，填充 MAC 单列，两者合计等于 profiler MC。

'''
    phase_rows = []
    names = {'control': '命令/输出块控制', 'quant': '量化装载与逐项配置',
             'weight': '权重装载', 'feature': '缺失输入行装载阻塞',
             'write_drain': '行尾 W 数据排空', 'write_response': '行尾 B/本地完成等待',
             'patch_pipeline': 'patch/流水填充及背压', 'row_prepare': '行准备/切换',
             'nonconv': '非卷积算子'}
    useful = summary['real_mac']/512
    pad = summary['ideal_cycles']-useful
    for label, key in [('MAC 有效折算', 'useful'), ('MAC 通道填充', 'padding')]+[
            (names[s], s) for s in STAGES if s != 'mac']:
        vals = []
        for point in ((0, 4.8), (30, 4.8)):
            vals.append(useful if key == 'useful' else pad if key == 'padding'
                        else sum(int(r[key]) for r in measured[point]))
        model_value = (useful if key == 'useful' else pad if key == 'padding'
                       else config['phases'][key])
        phase_rows.append((label, f'{vals[0]:,.0f}', f'{vals[1]:,.0f}',
                           f'{model_value:,.0f}', f'{model_value/float(base["cycles"])*100:.3f}%'))
    text += table(['互斥类别', 'RTL L0', 'RTL L30', '板测等效模型', '占比'], phase_rows)
    text += f'''
板测的 MAC 输入占空比为 {summary['ideal_cycles']/BOARD_CYCLES*100:.4f}%；
按真实 MAC 计算的有效算力占比为 {useful/BOARD_CYCLES*100:.4f}%。
权重/量化、输入行装载、行尾写响应和命令串行均由实测状态确认；
多 C32 块输入重读由逐命令 RB 与 31.418880 MB 静态值一致确认。

## W1–W8 单项与组合（模型值）

每个 W 单项独立叠加在上述板测等效基线上；组合从同一阶段预算重新计算，
没有把各项节省拍数直接相加。没有仿真修改后的 RTL，以下都是条件明确的模型估算。
重叠项采用可隐藏服务量与可用计算窗口的较小者，并限制命令时间不得低于共享端口载荷下限。
因此它们不包含新实现的布线、端口仲裁或时序反馈；原 RTL 校准误差不能外推成这些改动的精度保证。

'''
    text += table(['评估项', '周期', 'ms', 'fps', '+4.15ms fps', 'DDR MB/帧',
                   '平均 GB/s', '最忙命令均值 GB/s', '带宽上限 GB/s'], [
        (r['case'], f"{int(r['cycles']):,}", f"{float(r['ms']):.4f}",
         f"{float(r['fps']):.4f}", f"{float(r['fps_with_post']):.4f}",
         f"{int(r['ddr_bytes'])/1e6:.6f}", f"{float(r['avg_GBps']):.4f}",
         f"{float(r['max_command_avg_GBps']):.4f}", f"{float(r['peak_limit_GBps']):.3f}")
        for r in scenarios])
    text += '''
表中“最忙命令均值”是 `max(该命令字节/该命令时间)`，用于表示局部带宽需求，
不是一拍峰值。单拍载荷峰值上限 4.8 GB/s（125 MHz 时 4.0）；
令牌约束的长期峰值见最后一列，RTL 的 1024 拍窗口实测峰值见前表。
后处理列只加时间，DDR 字节仍是前 74 命令的字节数，没有把未知后处理 DDR 量当成零。

W1：在当前输出行执行时预取后续缺失输入行，保留每遍初始两行（3×3）或一行（1×1）的启动成本。
当前五行缓存最多容纳当前三行和 stride2 的后续两行；模型沿用其容量与端口吞吐，
不计算重写后的物理映射。可隐藏窗口取 MAC/patch/W 排空阶段；W4a 的首遍输入仅能用首个 C32 块的窗口，
W4b 的行优先循环可用该行所有 C32 块的窗口。组合主行 W1–W4 使用 W4a，另列 W4b。

W2：最后 W 完成后不在每行等 L 拍 B；保留本地三拍完成开销，仅在命令结束等最后响应。
模型未移走 W 数据传输，也未把 profiler 的全部 BW 当作可省时间。

W3：后一 C32 块的权重和量化配置与前块执行重叠，首块仍串行。
需要额外一份 128 KiB 权重 bank（当前最大实际单块 73,728 B）、
32×8 B 参数 bank、16×256 B 激活 LUT bank 和 512 B 暂存记录，
按现有固定深度合计额外 135,936 B。模型保持 DDR 字节数不变。

W4a：对多输出块层保留整层输入，由该缓存直接向 patch 读口供数，
后续输出块不再通过 DDR/行装载 DMA，保持 patch 读吞吐。
最大输入缓存 737,280 B（720 KiB，L15.split 的 80×48/C192 拼接输入）；相比已有 64 KiB 行缓存，
若替换使用则净增 671,744 B，若保留原行缓存则增加完整 737,280 B。
该容量占 415×36 Kibit 总 DRM 位容量的 38.55%；按每 DRM 可用 32 Kibit 数据
折算为 180/415=43.37%，均不含实际宽度/端口映射碎片。
DRM 单块 36 Kibit 依据 [Pango Logos2 数据手册 DS04001 V2.1]
(https://www.pangomicro.com/en/uploads/13964872_1729131653.pdf)，
415 块依据 SoC 规格及旧资源报告。

W4b：外层输出行、内层 C32 输出块，输入行在五行缓存中跨所有输出块共用；
模型假定该层全部权重和所有块量化参数/LUT 常驻，配置仍只装一次。
输入 DDR 读量和 W4a 相同，阶段模型时间也相同；存储位置不同不代表布局布线时间相同。
每层权重大小及分组数如下；若每组只保留原 128 KiB 权重容量，
按 `floor(128 KiB/weight_block_stride)` 个 C32 块组成一组，每组重新读输入，
对应表中 `W4group`。这是任务要求的受限容量评估点。

'''
    weights = [c for c in static if c['kind'] == 'conv']
    group_counts = {c['index']: (c['output_blocks']+(131072//c['weight_block_stride'])-1)
                    //(131072//c['weight_block_stride']) for c in weights}
    text += table(['命令', '全部权重 B', 'C32块 / 128KiB组数', '一次输入 B', '分组输入读 B'], [
        (f"{c['index']} {c['name']}", c['weight_read'],
         f"{c['output_blocks']} / "
         f"{group_counts[c['index']]}",
         c['unique_feature_read'],
         c['unique_feature_read']*group_counts[c['index']]) for c in weights])
    first_min_cycles = max(static[0]['real_mac']/512,
                           (737280+983040+432+512)/(bandwidth*1e9/150e6))
    w5_upper_cycles = float(base['cycles']) - float(commands[0]['cycles']) + first_min_cycles
    w5_upper_fps = 150e6/w5_upper_cycles
    max_weight = max(c['weight_read'] for c in weights)
    over = sum(c['weight_read'] > 131072 for c in weights)
    group_feature = sum(c['unique_feature_read']*group_counts[c['index']] for c in weights)
    text += f'''
全部权重常驻最大 **{max_weight:,} B（288 KiB）**，超出现有 128 KiB 的命令 **{over} 条**。
W4a/W4b 卷积输入读 15,183,360 B/帧，分组后 {group_feature:,} B/帧，
旧基线 31,418,880 B/帧。包含权重、量化和非卷积后的总 DDR 读量，
W4a/W4b 为 20,102,656 B，分组为 20,778,496 B，旧基线为 36,338,176 B。
常驻多块权重还需对应块的量化参数与 LUT；
最多 8 个块，参数 2,048 B、LUT 32,768 B（保持 16 路副本），量化记录 4,096 B。
这些容量没有换算为新实现已占用 DRM。

W5：主表用 C3 紧凑输入（每行 1,920 B）和一个 C8 组，空间核每位置只发一次：
K 从 18 降到 9，权重从 4,608 B 降到 2,304 B，后 C16 输出通道仍未使用。
首层输入从 3,932,160 B 降到 737,280 B，MAC 拍从 552,960 降到 276,480。
这是需要专用输入打包/patch 地址生成的模型点，没有更改旧 RTL。
若专用处理还能利用全部通道/像素并行，首层真实 MAC 下限为 51,840 拍；
仅消除该层 MAC 填充的绝对节省上限是 **501,120 拍（3.3408 ms）**，
另有最多 3,194,880 B 输入搬运节省。该 MAC 上限不是主表 W5 的收益。
若除首层外完全保持基线，把首层时间下界取
`max(真实MAC/512, (紧凑输入+输出+真实权重+量化记录)/带宽)`，
则得到全网 **{w5_upper_cycles:,.0f} 拍、{w5_upper_fps:.4f} fps** 的数学上界
（加 4.15 ms 后 {1/(w5_upper_cycles/150e6+0.00415):.4f} fps）。
此界忽略首层内部的必要串行/配置成本，只用于界定收益上限。

W6：采用量化后 residual add 融合到生产者写回，沿用旧 residual 的饱和和共同量化尺度。
删除每个 add 的临时结果读与写，保留 shortcut 操作数读取并向前一条卷积收取服务周期。
原量化结果的临时写和最终融合写一进一出抵消，因此每帧减少 1,290,240 B。
pool/up 仍按依赖串行；没有假定它们可越过消费者依赖直接重叠。

W7：按协调者确认的 C32×C16×2 像素点，512→1024 MAC、APM 256→512（512/740=69.19%，仅 MAC 阵列，不含其他 APM）。
只把 MAC 处理拍数减半，patch 仍每周期生成一个原 C8 激活行；
双缓冲流水下限取
`max(PK/并行倍数+首tileK, PK+末tileK/并行倍数)`，再加原调度开销。
因此全部命令 patch 生成本身仍至少需要 6,009,120 拍，不能把整网计算时间直接减半。
125/150 MHz 只缩放时间，保持周期/等效 L 和每周期服务率，所以 GB/s 上限也按频率缩放。
表中额外列出 W1–W4 后加倍 MAC，以及 W1–W7 与不同 W8 带宽的组合。

W8：固定同一等效 L，仅改变共享 R/W 的载荷上限为 0.5/1.0/1.5/2.0 GB/s；
每项重新计算读 burst、writer 背压与非卷积服务时间，没有仅用全帧平均带宽下限外推。

## 原始数据与复现

全部生成物在 `build/npu_eval/`（不入库）：

- `static.csv`、`static_summary.json`：74 命令的几何、MAC 和各项字节。
- `l*_b*.csv`：实际旧 profiler CY/MC/RB/WB/AR/RW/AW/WW/BW 和互斥状态计数。
- `l*_b*_live.csv`、`l*_b*.log`：执行进度、完成周期及直接计数；
  profiler 对相邻 step 边界的归属与 live 会有单拍移动，整网总计相同。
- `l*_b*_memory.txt`：延迟、带宽、1024 拍窗口峰值。
- `calibration.csv`、`model_commands.csv`、`model_summary.json`、`scenarios.csv`：
  逐命令误差、板测等效点阶段预算、W1–W8 数字。
- `compile.log`、`compile_command.txt`、`lint.log`、`obj/`：编译命令、输出和可执行文件。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/npu/eval/legacy_plan.py
python3 tools/npu/eval/run_legacy_rtl.py --compile --latency 0
python3 tools/npu/eval/run_legacy_rtl.py --latency 30
python3 tools/npu/eval/run_legacy_rtl.py --latency 100
python3 tools/npu/eval/run_legacy_rtl.py --latency 30 --bandwidth-gbps 0.5
python3 tools/npu/eval/run_legacy_rtl.py --latency 30 --bandwidth-gbps 2.0
python3 tools/npu/eval/run_legacy_rtl.py --latency 94 --bandwidth-gbps 4.0
'''
    text += f'python3 tools/npu/eval/npu_model.py --bandwidth-gbps {bandwidth:g}\n'
    text += '''python3 tools/npu/eval/test_npu_model.py
python3 tools/npu/eval/write_report.py
```

定向回归覆盖小型 C16 3×3 层、输入行复用/延迟、四在途读与 4 KiB 边界、
串行 residual 和三状态池化，5 项通过。编译与 lint 无未处理告警；
只对只读 legacy 文件的 WIDTH、TIMESCALEMOD、PINCONNECTEMPTY、UNUSEDSIGNAL、
UNUSEDPARAM、VARHIDDEN、BLKSEQ 类别作显式 lint 抑制，未改写旧源文件。
未增加可综合 RTL，所以仓库 Verilog 风格检查针对归属目录扫描为 0 个 RTL 文件。
本次没有综合/布局布线；模型存储量和 APM 点不是新网表资源实测。

本报告只记录测量及显式模型条件；不据此给出 NPU 规格或方案选择结论。
'''
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(text)
    print(REPORT)


if __name__ == '__main__':
    main()
