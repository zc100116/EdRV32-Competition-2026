# VIN CH2 联调：内存源数据检查误触发溢出

## 1. 现象

基线 `4b177b3e6e1b0904ee04495743fb551801c7900c` 集成 CH2 RTL 与独立模块测试后，
VI-19 通过，VI-20 在 CH0 完成后等待 CH2_FRAME 失败：期望 IRQ_STAT 含 `0x200`，
实际为 `0x003`（DONE、ERROR）。VI-21、VI-23 尚未执行。

本次定位结论为**测试激励错误**：VI-20 加入的 P1 随机停顿触发了 CH2 合法的溢出
丢帧，测试却仍要求该帧完整输出。规格不存在歧义，修复位于独立测试。
修复后 VI-20 通过，随后 VI-21(b) 暴露另一项测试错误：把内存源 DONE 当成
MSRC_BUSY 已经清零，未给输入缓冲的剩余像素留出输出时间。

## 2. 复现

工具：Verilator 5.020（Debian 5.020-1），Linux，单核编译，每次一个仿真。
AXI 存储模型的伪随机初值为 `32'hadc01234`，按固定 xorshift 序列演进，复位时
不重置该随机状态；原始失败按 VI-19、VI-20 的 full 顺序复现。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/regress.py full --path verif/block/vin/ch2 -j 1
```

上述基线加上本次 `wait_irq` 的失败诊断后，仍复现相同 IRQ、ERR_CODE 和计数结果。
原始诊断日志保存在 `build/vin_ch2/integration/vi20-original-failure.log`，
回归摘要为 `build/vin_ch2/integration/original-regression.log`。
修复和最终验收对应本文所在提交；下列命令均在该提交的源码上执行。

## 3. 观察

VI-20 在仿真时刻 `193256664000 ps` 开始；诊断末尾在 `204145040000 ps` 报错。
该报错比原来晚 672 ns，为新增 APB 诊断读取所用的时间。

| 寄存器 | 实际值 | 含义 |
|---|---|---|
| IRQ_STAT | `0x003` | 内存源 DONE，存在 ERROR，CH2 无完成 |
| STATUS | `0x006` | IDLE、ERROR，已排空 |
| ERR_CODE | `3` | CH2 写 FIFO 溢出 |
| MSRC_STAT | `0` | 内存源空闲 |
| PERF2 / PERF3 / PERF5 | `1 / 1 / 0` | 内存源一帧、CH0 完成一帧、CH2 未完成 |
| PERF6 / PERF8 | `0 / 1` | CH0 未溢出、CH2 溢出一次 |
| PERF9–15 | 全部 `0` | 没有跳帧、不完整帧或配置错误；无 urgent 周期 |
| CH0 DONE_INFO / DONE_FRAME_ID / WR_STAT | `8 / 0 / 0` | 内存源、槽 0、frame_id 0，已结束 |
| CH1、CH2 DONE_INFO / DONE_FRAME_ID / WR_STAT | 全部 `0` | CH2 未发布完成，通道均已排空 |

CH0 Surface 的逐字节检查已先通过，随后才在 CH2 完成等待处失败。
`check_read_ready` 在整个 VI-20 中启用，没有报告 RREADY 反压错误。

首次修复回归中，VI-19、VI-20、VI-21(a) 已通过；VI-21(b) 在
`355214368000 ps` 读取 MSRC_STAT，期望 `0`、实际 `1`。该读取紧接 DONE 轮询
成功，P1 写侧仍停止。日志为 `build/vin_ch2/integration/vi21-done-busy-failure.log`。

## 4. 根因

原 `verif/block/vin/ch2/edrv32_vin_ch2_tb.sv` 的 `vi20()` 在开始内存源前设置
`u_memory.random_percent = 35`。存储模型分别对 AW、W、B、AR、R 加随机停顿。
该激励没有为“两个通道均必须完成”的断言保证写带宽。

规格 2.3、2.5 中内存源按 FIFO 容量反压的规则适用于 CH0/CH1；2.8 对 CH2 明确
规定“始终接收（含内存源帧）”，FIFO 满时按 2.7 丢帧。第 6 节的 CH2 溢出上报
与本次 ERR_CODE、PERF8、无 CH2_FRAME 的观察一致。不能将 CH0 能反压内存源的
性质推导成 CH2 在共享 P1 随机停顿下也必然完成。

`rtl/media/vin/edrv32_vin_ch2_data.v` 在 SOF 后以每拍一 beat 生成顶部 12 行，
共 `12 × 80 = 960` beat；`edrv32_vin_ch2.v` 的写 FIFO 容量为 512 beat。
CH0 同时写入并经 P1 轮询仲裁，随机停顿会进一步减慢 CH2 排出。以上是代码确认的
流量特征；本次 APB 诊断确认了溢出事实，没有采样第一次溢出的内部流水时刻。

VI-20 是验证方案 v0.3 中的定向数据通路测试，判据为两个 Surface 正确且读无反压；
该项没有要求随机写停顿下不溢出。写停顿和 CH2 溢出的规定由 VI-21 验证，VI-19
仍保留随机 P1 停顿。

VI-21(b) 的第二项错误同样来自 `vi21()` 的测试时序。规格 2.3 明确在最后一个
`dma2d_rd.done_o` 后置 DONE，表示软件可以回收输入 Surface，并不表示输入缓冲已
输出完。`edrv32_vin_msrc.v` 分别维护 `read_done_r`、`output_done_r`，两者完成才
清 BUSY，符合读缓冲和拆包的契约。因而不能在 DONE 后立即断言 MSRC_STAT 为零。

## 5. 修复

- VI-20 使用 `reset()` 已设置的无随机停顿 P1，继续同时启用 CH0、CH2；保留全部
  数据、stride 空洞、槽号、frame_id、中断、最后 B 和 RREADY 检查。新增 ERR_CODE、
  PERF6、PERF8 必须为零的检查，明确该项要求完整帧。
- VI-21(b) 在 DONE 后通过 APB 轮询 MSRC_STAT，等到输入缓冲输出完；P1 写侧在
  这整个过程中保持停止。沿用测试既有的 300000 次轮询预算，超时仍明确报错。
  因此继续验证内存源未被 CH2 反压，并保留读返回 RREADY 恒为 1 的检查。
- `wait_irq()` 超时后读取 STATUS、ERR_CODE、MSRC_STAT、全部 PERF、三个通道的
  DONE_INFO、DONE_FRAME_ID、WR_STAT，随后明确失败，便于直接判断未完成原因。
- CH2 full 编译使用 `-O1`，与已有 VIN full 相同；smoke、自测保留 `-O0`。
  原 CH2 full 在 `-O0` 下仅执行到 VI-20 失败已用 1142 秒，而 full 的主机预算为
  1800 秒。本次调整仿真执行效率，保留原超时和全部检查。
- 既有 VIN 综合 full 在并发主机上触及墙钟预算后，经协调者 Orca `ask` 明确授权，
  仅把任务原归属之外的 `verif/block/vin/full/test.yaml` 的 `timeout` 从 1800 改为
  3600 秒，按要求单独提交；保留全部功能检查与 smoke 配置。

预算修改提交为 `eb8d124`；CH2 测试修复和本记录位于其后的同一个提交。

## 6. 防回归

VI-20 每次重新运行原始完整双通道场景并检查无错误、无溢出；VI-21 保留三种
长时间停止 P1 写的公开端口激励，验证 CH2 丢帧、内存源继续读、槽号复用和下一帧
恢复。使用以下命令执行验收，每次 `--path` 只有一个目录：

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/media/vin
for tier in smoke full; do
    python3 tools/regress.py "$tier" --path verif/block/vin -j 1
    for directory in verif/unit/vin_*; do
        python3 tools/regress.py "$tier" --path "$directory" -j 1
    done
done
# 首次综合 full 墙钟超时后，经授权仅重跑该未完成目录。
python3 tools/regress.py full --path verif/block/vin/full -j 1
```

`verif/block/vin` 的发现范围包含 CH2 smoke、full 和自测，因此上述父目录回归同时
覆盖 CH2 的两个档位。风格与 lint 日志在 `build/vin_ch2/integration/`，正式回归
日志在 `build/regress/{smoke,full}/`，CH2 runner 日志在 `build/vin_ch2/`。

顶层和独立 testbench 的 lint 使用正式文件列表展开结果：

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, 'tools')
from regress import expand_files
for top, files, timing in [
    ('edrv32_vin', 'rtl/filelists/vin.f', []),
    ('edrv32_vin_ch2_tb', 'verif/block/vin/ch2/files.f', ['--timing']),
]:
    subprocess.run(['verilator', '--lint-only', '-Wall', *timing,
                    '--top-module', top, '+define+SIM_MODE',
                    *expand_files(Path(files).resolve())], check=True)
PY
```

验收结果：

| 检查 | 结果 |
|---|---|
| RTL 风格 | 9 文件，0 告警 |
| `edrv32_vin`、独立 CH2 testbench 的 `-Wall` lint | 均 0 告警 |
| `verif/block/vin` smoke（含 CH2 smoke、自测和真实 PIX） | 5 PASS、0 FAIL |
| `verif/block/vin` full（首次通过目录加授权单目录重跑） | 7 个目录最终全部 PASS |
| 既有 VIN 综合 full，3600 秒预算下单独重跑 | 1 PASS、0 FAIL；VI-01–17、十个随机种子全部通过，1424 秒 |
| CH2 full，VI-19–23（VI-21 含三个溢出场景） | 全部 PASS；含编译、参考数据生成与仿真共 1721 秒 |
| `verif/unit/vin_*` smoke | 7 PASS、0 FAIL |
| `verif/unit/vin_*` full | 7 PASS、0 FAIL |

七个单元目录为 `vin_ch`、`vin_ch2`、`vin_dvp`、`vin_fmt`、`vin_msrc`、
`vin_p1_arb`、`vin_regs`，两档均逐目录运行。

首次父目录 full 中，既有 `verif/block/vin/full` 通过 VI-01–16，VI-17 的种子 1、2
通过后触及 1800 秒主机墙钟预算，未发生功能断言失败。在墙钟 29 分 49 秒的进程
快照中，累计 CPU 时间为 16 分 26 秒。该次未完成的日志保存在
`build/vin_ch2/integration/vin-full-1800-timeout.log`。
协调者明确授权上述单文件、单字段预算修改，并要求只重跑该目录；其余通过目录
不重跑。该授权属于任务归属扩展，不涉及规格、RTL、测试内容或通过判据的改变。
首次父目录 full 最终汇总为 6 PASS、1 FAIL，其中唯一失败为上述墙钟超时。
指定目录重跑摘要保存在 `build/vin_ch2/integration/vin-full-3600.log`。
授权重跑结果为 1 PASS、0 FAIL，VI-01–17 以及 VI-17 的十个种子全部通过，用时
1424 秒；与首次通过的其余六个目录合计，全部七个 full 目录均已完成验收。

## 7. 同类排查

- VI-19 的摄像头双通道场景保留 `random_percent = 35`，其三帧逐字节结果已在
  原始失败前通过。
- VI-21 分别验证摄像头仅 CH2、内存源仅 CH2、摄像头 CH0+CH2 的溢出；内存源的
  检查继续要求 `p1_rready` 始终为 1，并在写停顿期间报告 DONE。
- VI-23 的 SLOT_BUSY 激励与 VI-22 的错误尺寸拒收不依赖随机写带宽，不需要修改。
- CH0/CH1 的内存源反压契约仍由既有 VI-09 检查；本次没有将 CH2 加入源 READY。
