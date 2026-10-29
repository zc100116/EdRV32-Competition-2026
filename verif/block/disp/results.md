# D-T1 DISP v0.3 独立模块验证结果

日期：2026-10-29。被测 RTL 基线：`4412a299b4e8c054ed73ab335226c8760470f5d9`
（v0.2）；smoke 功能激励/判定：`1c63e21`。后续 `03b723c` 修正诊断格式，
`beb0481`/`eac0a88` 调整 full-only DS-09 的黑盒观测窗口和 W/8 激励，
`cbbd985` 完善 DS-18 的固定内存视图及参考自测。规格/验证方案：DISP v0.3；已读取协调者
`e6ff241` 的澄清：首次启层不释放、关闭层的 CUR_BASE 保持、两层读空允许黑盒识别；
亦已读取 `b230b95`：L0 urgent 门限为 81 beat，v0.2 的 80 beat 属预期版本差异。
只修改 `verif/block/disp/`，没有打开 DISP RTL 源文件，没有修改 RTL、docs、unit 或模型。

## 实现与参考模型

| 测试项 | 文件与入口 | 覆盖内容 |
|---|---|---|
| DS-01 | `tb.sv:display_monitor`，case 1 | 两帧完整显示时序 |
| DS-02 | `tb.sv` case 2、`tmds_ref.py` | Python 整帧 TMDS 符号 |
| DS-03 | `tb.sv` 两个 monitor、case 3 | 复位图层配置、两种 stride、全帧像素和行地址 |
| DS-04 | `tb.sv` case 4 | 首次无 SWITCH、帧中/消隐换基址、重复帧、FRAME/CUR/REL/计数 |
| DS-05 | `tb.sv` case 5 | ENABLE、关闭、已请求帧完整显示 |
| DS-06 | `tb_layers.sv:memory_drive/memory_monitor`、case 6 | 两层全屏、随机 AR/R、RREADY、逐行 L0→L1、扣除在途的容量界限 |
| DS-07 | `tb_layers.sv:display_monitor`、case 7 三个 variant | 单独 L1/单独 L0/两层读空、跨帧迟到、逐层恢复和 PERF1/2/5/6 |
| DS-08 | `tb.sv` case 8 | 上帧未读完时记下请求、PERF4 |
| DS-09 | `tb_layers.sv:memory_monitor`、case 9 | 两层各自低水位、两层组合、L1 矩形外不触发、PERF3 精确周期 |
| DS-10 | `tb.sv` case 10、`boundary_stop_test` | ABORT、三个停止临界相位、IDLE 后无 AR |
| DS-11 | `tb.sv` case 11 | SLVERR、ERR_CODE 2、IRQ/RW1C、数据照常显示 |
| DS-12 | `tb.sv` 寄存器任务/case 12、`tb_layers.sv` case 12 | v0.3 ID/复位/对齐、停止相位、SWITCH1 RW1C、L1 读空计数非零后 SOFT_RST 清零 |
| DS-13 | `tb_layers.sv` case 13 | 十 seed、六帧、随机基址/图层/卷轴/矩形/OPA/停顿/ENABLE/时钟比和相位 |
| DS-14 | `tb_layers.sv` case 14 | SCROLL_X=0..15/16/31/48，SCROLL_Y=3，80/81 beat |
| DS-15 | `blend_ref.py`、`blend_ref.svh`、`tb_blend_ref.sv`、`tb_layers.sv` case 15 | 六个 OPA 全帧 Python/SV/接收像素逐位比对 |
| DS-16 | `tb_layers.sv` case 16 三个 variant | 8×1 原点/右下角、右边和底边贴屏的大矩形、无额外 L1 读 |
| DS-17 | `tb_layers.sv` case 17 | 独立换址、L1 开关、非基址参数变化不释放、SWITCH/SWITCH1/REL 精确值 |
| DS-18 | `tb_layers.sv` case 18 十八个 variant | 九个帧锁存寄存器分别在 FRAME 前/后写入，地址和扫描参数同时验证 |
| DS-19 | `tb_layers.sv` case 19 | 两层关闭仍请求/FRAME/黑色/无 AR，随后 L1-only |

`blend_ref.py` 只用标准库。`Frame.descriptors()` 独立生成行描述符；
`Frame.pixel()` 按地址读取两层、L0 卷轴开窗、L1 矩形和透明度得到期望像素；
`LayerDebt` 独立维护各层迟到 beat、欠账和禁扫帧中的偿还。
d(x) 与独立整数除法 `(x + 127) // 255` 对 0–65025 全部 65,026 个输入核对。
自测还检查混合、卷轴地址/行宽、矩形边界、缺失层和跨帧独立欠账。

DS-15 的 α 包括 0、1、127、128、254、255 和伪随机值，OPA 为
0、1、128、255、73、219；L0 为按 seed/行/列变化的伪随机 RGB565。
独立 `tb_blend_ref` 可在 DUT 仍为 v0.2 时核对六个完整帧，共 5,529,600 像素；
DUT 测试的像素 monitor 再重复 Python/SV 参考比对，并检查实际 TMDS 解码像素。

读空按协调者批准的黑盒方式检查：L0 有非零红通道、蓝通道为 0；L1 只有非零蓝通道，
α=255。读空随机项的 OPA 保持在 32–223，因此可分别识别 L0 黑组和 L1 透明组。
识别后按每层 beat 边界保持状态，逐通道比对完整混合值和原始坐标；每层缺失的 beat/帧数
与 PERF 精确比较。外部 FIFO 预留界限计入 accepted 但未返回的 beat；保留既有 8 beat
的 CDC/TMDS 边界窗口，urgent 使用 16 beat 窗口；不声称直接测量内部精确水位或偿还时钟。
DS-09 经第二次 ask 批准，只在 AR 行至 AR 行+8 全部位于矩形内/外时判断 L1；
跨上下边界的区间不判定。8 行来自 FIFO 512 beat、L0 每行至少 80 beat；
L1-only 阶段使用每行 160 beat，混合阶段使用每行 32 beat。矩形精确边界留给 RTL 单测。

smoke 共 39 个仿真实例；full 加 36 个实例（包括 DS-13 十 seed 和 DS-18 十八个写入位置）。
两个 YAML 明确相同 `group: verif/block/disp`，共享构建目录且串行执行。

## 命令与结果

环境：`. ~/.local/opt/edrv32/env.sh`；Verilator 5.020、Python 3.12.3。
所有构建使用 `-j 1`，不使用 `--parallel`，同一时刻只运行一个仿真。

- `python3 verif/block/disp/blend_ref.py`：PASS，含 d(x) 穷举和逐层欠账自测。
- 独立 `tb_blend_ref`：PASS，Python/SV 六帧 5,529,600 像素全部一致；
  `build/disp/blend-ref-sv.log`。
- `python3 tools/check/verilog_style.py verif/block/disp`：0 告警。该检查器只枚举 `.v/.vh`；
  另对本目录 `.sv/.svh/.py` 检查 100 列、Tab，0 告警，见 `build/disp/format.log`。
- 三个顶层 `tb`、`tb_layers`、`tb_blend_ref` 的 Verilator lint 均退出 0、日志为空：
  `build/disp/{tb,tb_layers,tb_blend_ref}-lint.log`。

Lint 复现命令：

```sh
python3 - <<'PY'
import subprocess
import sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, 'tools')
from regress import expand_files
for top in ('tb', 'tb_layers', 'tb_blend_ref'):
    subprocess.run([
        'verilator', '--lint-only', '--timing', '-Wall', '--timescale', '1ns/1ps',
        '-Wno-BLKSEQ', '-Wno-UNUSEDSIGNAL', '-Wno-SYNCASYNCNET', '--top-module', top,
        '+define+SIM_MODE', *expand_files(Path('verif/block/disp/files.f')),
    ], check=True)
PY
```

豁免沿用既有环境：行为 BFM/scoreboard 的阻塞赋值、未使用接口字段、testbench 对异步复位
信号的观察；没有豁免位宽、锁存器或连接错误。

### v0.2 实际运行

`python3 tools/regress.py smoke -j 1 --path verif/block/disp`：39 个实例，
**6 PASS、33 FAIL**；耗时 3381 秒（含构建、参考生成，共享负载环境）。
统一回归的 YAML 汇总为 0 PASS、1 FAIL；没有把新功能缺失标成 xfail 或跳过。
原始日志：`build/regress/smoke/block/disp/verilator/run.log`、`build/disp/DS-*.log`。

| 实例 | 数量 | 实际结果与原因 |
|---|---:|---|
| DS-01；DS-03 的 2560/4096 stride；DS-05；DS-11；DS-07 L0-only variant 1 | 6 | PASS |
| DS-04 | 1 | 新规格首次只 FRAME：IRQ_STAT 期望 0x4、实际 0x104，属已确认版本差异 |
| DS-12 普通实例 | 1 | ID 期望 0x50002、实际 0x50001 |
| DS-12 的 -8/-2/+4 停止相位 | 3 | 原停止/排空和首次 IDLE 后整帧无 AR 的检查执行完；新增 0x118 期望 1、实际 0 |
| DS-06；DS-12 L1 补充 variant 1；DS-07 双层 variant 2；DS-15；DS-16 三实例；DS-17 | 8 | L1_CUR_BASE 期望 0x81000000、实际 0；旧 RTL 没有 L1 寄存器/扫描层 |
| DS-07 L1-only variant 0 | 1 | L0 应关闭、首读应为 L1 0x81000000，实际仍读 L0 0x80000000 |
| DS-14 的 0..15/16/31/48 | 19 | 首行应从 0x80003000/0x80003020/0x80003060 读，实际 0x80000000，旧 RTL 未实现卷轴 |

所有失败均为规格版本差异；没有发现需要修改 RTL 或外部接收模型的问题。
上述新增项在最早的寄存器/地址差异处结束，不声称已在 v0.2 验证其后续像素行为。
DS-07 L0-only 的新 scoreboard 完整运行：扫描 2 帧、L0 缺失 47,520 beat、L1 缺失 0；
PERF1/2 与观测精确一致，禁扫帧中偿还后下一扫描帧逐像素完整正确。

为独立确认被版本字段挡住的原有功能，从被测基线提取原 v0.2 testbench 到
`build/disp/legacy/tb.sv`，没有给正式测试增加兼容选项或跳过新检查。
该副本使用相同 RTL、接口/接收模型和 `-j 1 -Wall` 构建：

| 原 v0.2 项 | 结果 | 日志 |
|---|---|---|
| DS-04 | PASS，4 帧读取，0 读空；原交接、重复帧、释放检查通过 | `build/disp/legacy-DS-04.log` |
| DS-06 | PASS，2 帧读取，0 读空；原 L0 RREADY/容量/协议检查通过 | `build/disp/legacy-DS-06.log` |
| DS-12 | PASS，1 帧读取，0 读空；原 ID/对齐/PSTRB/寄存器/软复位/计数基线通过 | `build/disp/legacy-DS-12.log` |

原有项基线加上正式测试中通过的部分，共 9 个完整 PASS 实例；正式 DS-12 三个相位
在新增寄存器检查之前的原有停止部分也无失败。

原 v0.2 补充基线可复现为：

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, 'tools')
from regress import expand_files
out = Path('build/disp').resolve()
(out / 'legacy').mkdir(parents=True, exist_ok=True)
(out / 'legacy/tb.sv').write_text(subprocess.check_output([
    'git', 'show', '4412a299b4e8c054ed73ab335226c8760470f5d9:verif/block/disp/tb.sv',
], text=True))
sources = [p for p in expand_files(Path('verif/block/disp/files.f'))
           if Path(p).name not in ('tb.sv', 'tb_layers.sv', 'tb_blend_ref.sv')]
subprocess.run([
    'verilator', '--binary', '--timing', '-j', '1', '-Wall', '--timescale', '1ns/1ps',
    '-Wno-BLKSEQ', '-Wno-UNUSEDSIGNAL', '-Wno-SYNCASYNCNET', '+define+SIM_MODE',
    '--top-module', 'tb', '--Mdir', str(out / 'obj_legacy'), '-o', 'sim',
    *sources, str(out / 'legacy/tb.sv'),
], check=True)
for case in (4, 6, 12):
    subprocess.run([str(out / 'obj_legacy/sim'), f'+CASE={case}',
                    '+SEED=1', '+STRIDE=4096'], check=True)
PY
```

### 最终修正与诊断验证

完整 smoke 的二进制来自 `1c63e21`。后续修正：

- `03b723c`：把错误格式串改为单个字面量，解决 Verilator 将拼接格式串打印为数字的问题。
- `beb0481`、`eac0a88`：full-only DS-09 使用实际观察到的 AR 行及协调者批准的 8 行窗口，
  增加 W=256（32 beat）与 W=1280（160 beat）的不同门限激励；以实际 ARVALID 观察到的行
  为窗口起点，避免将尚未发描述符的初始空档或下一预期行误当作当前内部行。
- `cbbd985`：源 RAM 物理布局固定为 L0 4096、L1 5120 字节/行；DS-18 改 STRIDE 时，
  像素期望改为对固定内容的新视图。Python 自测增加非默认 stride 的固定地址样例。
  smoke 使用的 stride 始终为上述布局（DS-03 的 2560 由原独立 L0 模型处理），因此这些
  地址换算与已执行 smoke 的像素期望等价。

最终三个顶层 lint 全部 0 告警；Python 自测再次 PASS。
`build/disp/blend-ref-sv-final.log`：最终 SV 参考再次与全部 5,529,600 个 Python 像素一致。
另外从最终 `tb.sv` 提取原样的 `check` 任务到 `build/disp/tb_fmt.sv`，调用期望 4/实际 0x104，
以及把 Python 首像素翻转一位输入最终 `tb_blend_ref`；两者均按预期非零退出并明确输出值和位置：

```text
FAIL DS-4 register 010 expected=00000004 actual=00000104 t=0 L0 row=100 col=7
FAIL DS15 expected=39754b actual=39754a L=blend row=0 col=0 OPA=0
```

诊断日志：`build/disp/diagnostic-format.log`、`build/disp/blend-ref-negative.log`。
这些是 testbench 诊断自查，不计为 DUT 回归失败，也没有新增正式测试项。
提取诊断任务的复现方式（随后按前述 Verilator 参数构建 top `tb_fmt`）：

```python
from pathlib import Path
source = Path('verif/block/disp/tb.sv').read_text()
start = source.index('    task automatic check(')
end = source.index('    endtask', start) + len('    endtask')
Path('build/disp/tb_fmt.sv').write_text(
    'module tb_fmt;\nint test_case=4;\nint x=7;\nint y=100;\n' + source[start:end] +
    '\ninitial check("register 010", 32\'h4, 32\'h104);\nendmodule\n')
```

负向参考诊断可在正常构建后复现：将 `build/disp/blend.hex` 的首行整数异或 1，写到
`build/disp/blend-bad.hex`，运行
`build/disp/obj_ref/sim +BLEND_REF=build/disp/blend-bad.hex`；应非零退出并显示上面的像素差异。

## 剩余与修改文件

v0.3 新增功能的实际输出、DS-09 最终观察窗口、DS-18 非默认 stride/锁存和 full 随机回归，
仍需在 v0.3 RTL 上联调；本 Task 未收到 RTL 就绪通知，没有运行 full 或访问新的 RTL。
协调者批准的精确内部 urgent/矩形边界由 D-R1 单测覆盖，联调时核对。

修改文件（均在 `verif/block/disp/`）：`blend_ref.py`、`blend_ref.svh`、`tb_blend_ref.sv`、
`tb_layers.sv`、`tb.sv`、`run.py`、`files.f`、`test.yaml`、`full/test.yaml`、`README.md`、
`results.md`。未修改 `tmds_ref.py`、`rtl/`、`docs/`、`verif/unit/`、`verif/models/`。
