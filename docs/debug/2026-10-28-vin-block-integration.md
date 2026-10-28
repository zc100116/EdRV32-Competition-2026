# VIN 首次模块级联调

## 1. 现象

起始提交 `c0f6e5a`，真实 VIN RTL（含 RAM 写 FIFO）与独立模块测试首次集成：

- 编译报告 13 条 `TIMESCALEMOD`；`-Wall` 另报告 testbench 复位信号的
  `SYNCASYNCNET`。
- VI-01 完成前三帧后，背靠背场景停止推进仿真时间。
- VI-05 在 5,304,864 ns、VI-06 在 4,889,592 ns 报告
  `FRAME expected=1 actual=0`。
- 采用 1800 秒预算后的首轮 full 中，VI-01–16 通过；VI-17 种子 2 在 904,918,232 ns 报告 CAM1
  不完整帧计数 `expected=2 actual=1`。单独运行 VI-17 时，种子 3 在
  14,671,160 ns 复现同类问题，`expected=4 actual=3`。
- 修复计数取样后，VI-17 种子 3 在 17,305,856 ns 报告 CH0 DONE_INFO
  `expected=1 actual=0`，差别仅为分配槽 1/0。

上述问题分别归因于测试编译环境、仿真器兼容性、测试激励/取样时机及参考模型。
缩环规则先经协调者澄清后修正参考模型；本任务全部修复均位于验证环境，VIN RTL 未修改。

## 2. 复现

环境：Verilator 5.020（Debian 5.020-1）、Linux，任务主机 3 核、8 GB，
单核编译、VIN 仿真串行。
定向测试无外部随机种子；使用 testbench 默认伪随机初值。
编译问题的基线为 `c0f6e5a`；功能问题可在只修复编译环境的 `5d4a0cc` 上复现。
VI-17 的计数取样问题以 `0fcc8aa` 为基线。
VI-17 的缩环槽号差异以 `4455110` 为基线。

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/block/vin'
stdbuf -oL build/regress/smoke/block/vin/verilator/obj/sim +CASE=1
stdbuf -oL build/regress/smoke/block/vin/verilator/obj/sim +CASE=5
stdbuf -oL build/regress/smoke/block/vin/verilator/obj/sim +CASE=6
stdbuf -oL build/regress/full/block/vin/full/verilator/obj/sim +CASE=17
```

原始失败日志保存在 `build/vin-smoke-diagnostic.log`、
`build/vin_cases/case5.log`、`build/vin_cases/case6.log`。
定位用的 testbench 副本、Verilator 生成代码和观察日志全部位于 `build/vin_debug/`，
不作为正式测试或 RTL 提交。
VI-17 失败原始日志为 `build/vin-full-seed2-incomplete-fail.log`、
`build/vin-case17-original.log`；仅给生成模型连接观察入口的诊断程序和输出位于
`build/vin_counter_probe/`，没有修改正式 testbench 或 RTL 来取得这些观察值。
缩环故障与状态观察保存在 `build/vin-case17-counter-fixed.log`、
`build/vin_ring_probe/run.log`。

## 3. 观察

- 其他 block 的 `sys_cpu`、`sys_subsys` 已采用文件列表首项的编译单元 timescale 文件，
  不向 RTL 添加 timescale。`cache` 等环境在 testbench 复位声明处局部豁免同步观察告警。
- VI-01 在 140 us 时，已检查 3 帧，AXI 累计 AW=26、B=24；直到下一次 150 us
  主循环观察点均未返回。生成的 C++ 将 `final_b_seen()` 内部的索引递增表达式提前计算，
  内部扫描循环重复把索引赋为 1，无法完成扫描。
- VI-05 在 1 ms 时，AW=B=112，已检查 CH0=4 帧、CH1=3 帧，PIX 仍有一帧期望，
  该帧未输出首字。对应最后一次在 HREF 后 10 个 clk_mem 周期清 ENABLE 的激励。
- VI-06 在 1 ms 时，AW=B=50，已检查两通道各 12 帧，PIX 仍有一帧期望。
  对应运行中把 CH0 全部槽置忙的激励。
- VI-17 失败时，CAM1 整形器为 `S_PAD`，尺寸 1044×18，位置为第 17 行、第 121 个字
  （每行 522 字），`incomplete=1`、`end_seen=1`，仍需输出约 400 个补零字。
  CH0/CH1 分别选 cam0/cam1，RING_N 均为 2，SLOT_BUSY 为 5/7；CAM1 被 CH1 跳过，
  两通道均不在接收。PERF13 为 3，测试期望为 4。
- 缩环差异发生时，CH0 当前 RING_N=2、SLOT_BUSY=0，完成 frame_id=2、槽号0；
  `receive_previous`、`write_previous` 均为2。上一个槽2来自此前 RING_N=3 的内存帧。

## 4. 根因

1. 正式文件列表首先展开无 timescale 的 RTL，随后才遇到带 timescale 的测试源文件。
   `SYNCASYNCNET` 则来自 testbench 同步观察复位与 DUT 异步复位的正常组合。
2. VI-01 的 `do ... while (!final_b_seen(...))` 在本机 Verilator 5.020 中触发
   错误的 C++ 循环生成；普通语句位置调用同一个函数时，生成的索引递增正确。
   这是测试应适配的仿真器兼容问题，不是 DMA 或 RAM FIFO 死锁。
3. VI-05、VI-06 用传感器 HREF 代替通道接收 SOF 的时刻。DVP 前端保留行内最后字、
   经异步 FIFO 送到帧整形，首个通道字晚于 HREF。原激励在实际通道分配之前就清
   ENABLE 或置满 SLOT_BUSY，因此硬件正确地拒收该帧。规格 2.4、2.6、5.2 要求的
   “接收帧后修改”必须以公开像素流 SOF 握手为依据。
4. `drain()` 在没有通道完成可等待时，只延迟 100 拍便比较不完整帧计数。
   规格 2.2 规定缺行需要按每拍一字补齐；上述 CAM1 仍在补零，尚未完成该帧。
   此时尚未到达该帧的完成记账点，测试在源完成前读取了计数。
   这是公共测试驱动的取样时机错误。
5. 参考模型直接使用 `(last_slot+step)%ring`，使上次槽2、新环2的第一个候选变成1。
   规格 2.6 原文字未明确旧槽超出新环的处理，故先通过 ask 提出两种口径。
   协调者确认：先计算上次槽号加一；若不小于本帧锁存的 RING_N，则从0开始，
   然后递增回绕搜索。现有 RTL 符合该口径，错误位于参考模型。

## 5. 修复

- 新增 `edrv32_vin_timescale.sv` 并置于正式 VIN 测试文件列表首项。
- 只在 testbench 的 `rst_mem_n` 声明处局部豁免 `SYNCASYNCNET`。
- VI-01 在循环体中将 `final_b_seen()` 结果赋给局部变量，循环条件只读取该变量。
  保留原有逐拍观察和最后 B 判定。
- VI-05 两处帧中配置写入、VI-06 帧中 SLOT_BUSY 写入，都在 PIX 输入 SOF 握手后执行。
- `drain()` 通过公开 PERF12/13 等待不完整帧记账，再执行原有的精确寄存器比较。
  等待使用与既有 APB 完成轮询相同的 200000 次上限；未达到期望值仍由原比较报错，
  超额计数也不会通过。
- 参考模型先按确认后的规则确定首个候选，再用模运算遍历本环；保留全部忙槽跳过检查。
- full 构建使用 `-O1`、墙钟预算 1800 秒，smoke 保留 `-O0`；两者仍为 `-j 1`。
  最初 900 秒预算的 full 在约 5 分 33 秒时已通过 VI-01–15 并进入 VI-16；VI-16 还要重复三次
  完整尺寸 VI-01。依据已观察到的耗时，判断原 900 秒预算偏紧，主动停止该轮并增加
  主机预算后重新完整运行。该轮没有功能检查失败，日志保存在
  `build/vin-full-900-budget-interrupted.log`；SV 的 2 秒仿真时间终止条件照常执行。

## 6. 防回归

沿用独立测试 VI-01、VI-05、VI-06，保留全部原有数据、状态、计数和中断检查。
没有削弱期望值，也没有添加 RTL 特殊条件。
VI-17 新增一个定向前置场景：CAM1 为 1044×18、少一行，CH1 的两槽全部占用，
验证没有通道完成中断时补零与源计数仍能排空；随后照常运行原有十个随机种子。
参考自测新增旧槽2、新环2和旧槽3、新环3两个场景，均明确期望从槽0分配。

修复提交：

| 提交 | 内容 |
|---|---|
| `5d4a0cc` | 统一编译单元 timescale、局部复位观察 lint 豁免 |
| `070b116` | VI-01 扫描函数移出循环条件 |
| `82488ed` | VI-05、VI-06 在已接收 SOF 后写配置 |
| `0fcc8aa` | full 使用 `-O1` 和 1800 秒主机预算 |
| `4455110` | 等待被跳过帧的补零记账，并新增 VI-17 定向复现 |
| `35e0303` | 修正缩环参考游标，新增两个参考自测 |

验收使用上述提交后的工作树；文档修改不影响仿真源文件。

| 命令 | 结果 |
|---|---|
| `make smoke REGRESS_ARGS='-j 1 --path verif/block/vin'` | 2 PASS、0 FAIL；全部 11 项 smoke 测试通过 |
| `stdbuf -oL make full REGRESS_ARGS='-j 1 --path verif/block/vin'` | 3 PASS、0 FAIL；VI-01–17、完整尺寸时钟比与十种子全部通过 |
| `build/regress/full/block/vin/full/verilator/obj/sim +CASE=17` | 定向补零复现与十个随机种子全部 PASS |
| 下列六个单元目录逐项执行 smoke | 6 个目录均 1 PASS、0 FAIL |
| `python3 tools/check/verilog_style.py rtl/media/vin/` | 7 文件、0 告警 |
| 真实 VIN 顶层 `verilator --lint-only -Wall` | 0 告警 |
| 集成 testbench `verilator --lint-only --timing -Wall` | 0 告警 |

单元目录为 `vin_ch`、`vin_dvp`、`vin_fmt`、`vin_msrc`、`vin_p1_arb`、`vin_regs`。
执行命令：

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
for path in sorted(Path('verif/unit').glob('vin_*/test.yaml')):
    subprocess.run(['make', 'smoke', f'REGRESS_ARGS=-j 1 --path {path.parent}'], check=True)
PY
```

SV/SVH 的 100 列、4 空格缩进、Tab 检查覆盖 6 个文件，0 告警。
正式回归日志位于 `build/regress/{smoke,full}/block/vin/`，单元日志位于
`build/regress/smoke/unit/vin_*/verilator/`。
lint 日志为 `build/edrv32_vin-final-lint.log`、`build/edrv32_vin_tb-final-lint.log`。
最终单独 VI-17 的日志为 `build/vin-case17-final.log`。

真实 RTL 与集成 testbench 的 lint 可复现为：

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, 'tools')
from regress import expand_files
for top, files, timing in [
    ('edrv32_vin', 'rtl/filelists/vin.f', []),
    ('edrv32_vin_tb', 'verif/block/vin/files.f', ['--timing']),
]:
    subprocess.run(['verilator', '--lint-only', '-Wall', *timing,
        '--top-module', top, '+define+SIM_MODE']
        + expand_files(Path(files).resolve()), check=True)
PY
```

## 7. 同类排查

- 检查 VI-01 的函数扫描调用位置；其他 Surface 完成检查在普通语句位置调用该函数。
- 检查其他 HREF 等待：VI-13 在 HREF 后等待 400 个 clk_mem 周期才 ABORT；
  VI-15 等待实际 AW 握手后 SOFT_RST，均与本次过早写配置的情况不同。
- 真实 VIN 顶层及集成 testbench 已分别通过 `-Wall` lint，RTL 风格检查 7 文件、0 告警。
- 仿真资源约束曾通过 `ask msg_d4296b848acb` 提问，并发送阻塞说明
  `msg_946a7b1aaa96`。等待 DISP 回归进程结束后开始 VIN 功能仿真；full 重跑期间观察到
  另一个 CPU worker 启动仿真，按“本 worker 内串行”的解释继续执行。
  协调者随后通过 `msg_36f5dfebe76a` 确认：每个 worker 同时最多一个仿真进程、
  编译 `-j 1`，不要求全机互斥。该问询已关闭，VIN 的执行方式符合该约束。
- 缩环起点 ask 附上 VI-17 测试名、17,305,856 ns 的期望/实际槽号、前一槽状态和
  规格 2.6、2.4、4.3。协调者选择旧槽越界时从0搜索，要求保留 RTL、修参考模型并补自测，
  且由协调者补入规格 2.6。该问询已关闭。
