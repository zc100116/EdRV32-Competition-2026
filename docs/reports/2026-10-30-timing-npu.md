# NPU CONV residual/model 读请求路径时序（T-NPU1）

| 项目 | 条件 |
|---|---|
| 日期 | 2026-10-30 |
| 改前 RTL | `05088f4b13d5d8399f63deef48dc2760ad0f5bec` |
| 改后 RTL | `f9ac49836d58bd763e87b479227d5cf2d6985699` |
| PDS 起点数据 | `origin/win/20261030-10-b3-timing-rerun`，`2f43834d5d5a2759f200c7c4a86e020125748b61` |
| PDS 条件 | PDS 2022.2-SP6.1 build138931；PG2L200H-6/FBB676；clk_npu 150 MHz / 6.667 ns |
| Yosys | 0.70+219，git 5053d0e26；FPGA_MODE，LUT6，NPU RAM/APM 包装模块使用端口黑盒 |
| 仿真 | Verilator 5.020；独立 Python 参考模型；单编译任务、串行运行；NB 默认 clk_npu/clk_mem = 150/125 MHz，隔离 bench 单时钟 125 MHz |
| 原始数据 | 本 worktree 的 `build/npu-timing/`；正式回归另见 `build/regress/` |

最终仿真验收由 T-NPU2 合并后统一执行，本任务的排队仿真已按协调者要求取消。本轮修改 `rtl/npu/edrv32_npu_conv.v`，并按协调者在本 Dispatch 的明确授权修改 `rtl/npu/edrv32_npu.v`，寄存 conv/readDMA 使用的执行 stop；没有修改 readDMA 的 stop/ready 契约。未运行改后 PDS；下文 LUT6 级数是组合逻辑深度参考，不是 PG2L200H 的布线后时序或 Fmax。

协调者在本 Dispatch 的 `ask` 中同意保留寄存器→单个标准 32 位加法→寄存器的路径，不拆成两级；条件是加法操作数直接来自寄存器，途中不串接选择或比较。此类路径按“单个标准加法、PDS 映射进位链”单列真实 Yosys 级数，最终交 PDS 判定；该例外不适用于突发长度/比较/地址加法串联路径。随后协调者要求在 NPU 顶层寄存执行 stop，conv 和 readDMA 使用 `stop_r`，以 ER-05 空闲、读权重中、写回中三个 ABORT 场景通过为验收；若仍有超过 10 级的纯控制路径，列出起终点后交 PDS 判定，不再扩大本任务范围。

## PDS 改前路径

原始文件为任务卡 `artifacts/<工程>/synthesis_paths.tsv`、`synthesis_path_detail.txt`，均为综合估算 slow 角。

| 工程 | 起点 → 终点（省略 SoC/NPU 公共前缀） | 裕量 ns | 级数 |
|---|---|---:|---:|
| B3F | `u_apb_bridge/request_r[36]` → `u_conv/residual_addr_r[31]` | −0.770 | 15 |
| B3F | `u_apb_bridge/request_r[36]` → `u_conv/model_remaining_r[13]` | −0.746 | 10 |
| B3VN | `u_conv/residual_pairs_r[0]` → `u_conv/residual_addr_r[31]` | +0.006 | 15 |

逐级明细显示 APB 起点是 `unused_apb_addr_w[0]`，经过寄存器块 ABORT 写地址译码、顶层 `stop_w`、请求接受条件，再进入地址/剩余量运算。它不是配置数据直接进入 CONV 的路径；描述符和五个绝对地址已经由 `edrv32_npu_descriptor` 的寄存器提供。

## 修改与请求节拍

- 模型流提前保存本突发的长度、段尾标志和下一 512 B 边界地址；非尾突发之后的起址必为 512 B 对齐，后继长度只需取剩余拍数与 16 的较小值。
- `model_remaining_r` 在既有配置握手后表示本突发之后剩余的拍数。段尾比较不再串接到接受拍的扣减、状态选择和地址加法；初始拍数在层开始时装入独立影子寄存器，再利用原配置握手初始化 live remaining 和首请求，隔离 APB/启动控制与 remaining 数据选择。
- 权重首段在 START 同拍寄存 5 位边界拍数；后继段并行计算 next base 的低 4 位 beat 偏移，寄存其 5 位边界拍数，之后才进入 15 位 remaining 比较/减法。这一级与完整 next base 地址寄存器并行；不从刚更新的 next base 再多等一拍，以保持短权重段/量化段连续请求时的准备关系，不增加请求气泡。`WEIGHT_BLOCK_BYTES = 256 × K_COUNT`（规格 4.1），低 5 位恒为 0；低 4 位 beat 地址的模加与完整地址加法的 `[8:5]` 完全一致。
- 下一权重块使用 current base 寄存器和无条件 `next_base = base + bytes` 寄存器分离完整加法与初装/推进选择；在前一量化/LUT 请求接受时，用已经寄存的 next base 准备后继突发。量化记录和 LUT 的起址/突发计划在前一段期间准备。量化记录和 LUT 基址每个输出块推进 512 B，保留原权重→量化→可选 LUT 的顺序。
- 残差在既有 BEGIN 握手拍准备首平面的长度、段尾标志、第二平面地址和本半区是否结束输出块的比较结果；首平面最后一个请求接受时，用已寄存的第二平面地址准备它的突发计划。一个半区最多 16 个像素对，因此一个平面最多跨两个突发；后继请求长度在上一个请求接受拍装好。
- 下一行、下一块、下一半区的地址提前保存；`residual_addr_r` 的请求接受/提交更新只选择准备好的地址。NPU 顶层的请求 valid 和 DONE 仍由原即时 stop 屏蔽；conv/readDMA 执行 stop 寄存一拍，阻断 APB 译码到接受控制的组合锥。
- 各生产者直接按原优先级生成接受条件，避免从公共请求选择器反向译码 counter enable；remaining 负载与 cancel/valid 控制分开。仲裁优先级、请求输出寄存器、响应标签、数据通路和写回逻辑不变；未增加 FSM 状态、超时、输入检查或兜底路径。数据及请求计划寄存器不复位。

## 回归命令

命令均先执行 `. ~/.local/opt/edrv32/env.sh`。Verilator 仿真、Yosys 和回归命令均由 `flock /tmp/edrv32-sim.lock` 串行化；Verilator/回归使用 `-j 1`，Yosys 使用其串行命令接口。协调者在本 Dispatch 的调度答复中允许 `--lint-only` 免锁，最终 lint 按此执行，输出 `lint_final.log`。

```sh
python3 tools/check/verilog_style.py rtl/npu
python3 - <<'PYLINT'
from pathlib import Path
import subprocess
from tools.regress import expand_files
subprocess.run(['verilator', '--lint-only', '-Wall', '-j', '1', '+define+SIM_MODE',
                '--top-module', 'edrv32_npu']
               + expand_files(Path('rtl/filelists/npu.f')), check=True)
PYLINT
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/npu_conv -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/unit/npu_conv -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/npu -j 1
PYTHONPATH="$PWD/third_party/ultralytics:$PWD" \
    flock /tmp/edrv32-sim.lock python3 tools/regress.py perf --path verif/block/npu -j 1
```

Lint 的文件列表通过 `tools.regress.expand_files` 展开后作为独立参数传入，实际调用见 `build/npu-timing/lint_final.log`。整网运行需要检出仓库锁定的 ultralytics 子模块；本轮使用 `9d25f80daa5b3af71c16521eba353cb6e7fb66e2`，没有修改依赖版本。

改前测量使用 `05088f4b` 的 CONV 与 NPU 顶层源文件快照（`git show <commit>:<file>`），其余 RTL、存储模型、输入和参考模型相同。`build/npu-timing/measure.py` 调用原 unit/NB runner，`edges.py` 使用原隔离 bench，临时副本仅打印接受的请求地址、长度、标签和仿真周期，不给 RTL 添加测试条件。正式 unit/block 回归使用仓库原测试文件，未修改 `verif/`。隔离用例使用 `MEM_MODE=bw`、`MEM_B_DELAY=200`；其中 CYCLES 是从仿真开始到检查输出时的总周期，包含固定复位和写响应尾延迟，仅用于同条件前后比较。

## 综合与分析复现

交付数字来自 `build/npu-timing/{before,after}/npu.ys`，从 `rtl/filelists/npu.f` 取得源文件；端口黑盒声明由 `rtl/tech/edrv32_*npu*.v` 包装模块的固定端口生成，保存在 `build/npu-timing/stubs.v`。以 `edrv32_npu` 为顶层，执行与 CPU C-F1 报告相同的流程；早期 `netlist.json`/`after0/` 仅为优化过程中的诊断数据，不作为最终结果：

```text
read_verilog -D FPGA_MODE -Irtl/include <展开的 NPU RTL 和端口黑盒>
hierarchy -top edrv32_npu
synth -top edrv32_npu -flatten -noabc
abc -lut 6 -dress
opt_clean
write_json <output>.json
stat
```

```sh
flock /tmp/edrv32-sim.lock yosys -Q -T -l build/npu-timing/before/npu.log \
    -s build/npu-timing/before/npu.ys
flock /tmp/edrv32-sim.lock yosys -Q -T -l build/npu-timing/after/npu.log \
    -s build/npu-timing/after/npu.ys
PYTHONPATH=. python3 build/npu-timing/analyze.py before npu
PYTHONPATH=. python3 build/npu-timing/analyze.py after npu
```

分析使用 `tools/synth/netlist_paths.py` 的 `analyze`。NPU 顶层测量只把时钟连接到 `clk_npu_i` 的 FF Q 和 NPU RAM/APM 黑盒输出作为起点，终点限制在 `u_conv.*`，包含 FF D/CE 和存储/APM 输入；不把 clk_mem FIFO 存储起点算进 clk_npu 同域路径。起点集合仅在分析用 JSON 中加命名别名，未切断任何组合逻辑。下表保留各位终点；级数不能和 PDS 的 carry/LUT 级数直接等同。

## Yosys LUT6 结果与剩余路径

| 测量范围 | 改前最大级数 | 改后最大级数 | 说明 |
|---|---:|---:|---|
| clk_npu → CONV（含直接及深层子模块） | 25 | 23 | 改后最差是未修改的 CONV 写请求路径 |
| clk_npu → CONV 本层调度寄存器 | 25 | 21 | 改后最差为未修改的输入行装载 `load_addr_r` |
| clk_npu → 三个原目标寄存器 | 25 | 20 | 改后为寄存边界拍数后的 15 位比较/减法 |
| `residual_pairs_r` → `residual_addr_r` | 25 | 无组合路径 | 长度与地址加法已隔拍 |
| APB `request_r[36]` → 三个原目标 | 14 | 13 | 剩余来自 SOFT_RST/cancel → datapath cfg_ready，不再是 ABORT/stop 链 |
| clk_npu → 新 stop 级 | 不适用 | 7 | `request_r[43]` → `stop_r.D` |

最终版本已把 5 位边界拍数寄存，之后才进行 15 位比较/减法。此级前的最差路径为 `u_apb_bridge.request_r[43]` → `model_first_boundary_beats_r[0]`，9 级；数据预算锥单独筛选仍为 20 级。未宣称 LUT6 全部达到约 8 级。

### 剩余算术路径

| 起点 → 终点（省略 u_conv） | LUT6 级数 | 改前 PDS 裕量/级数 | 逻辑及判定 |
|---|---:|---|---|
| `model_next_weight_boundary_beats_r[3]` → `model_remaining_r[14]` | 20 | 同组 B3F `model_remaining_r[13]`：−0.746 ns / 10 | 已寄存边界之后的 15 位比较/减法借位链及饱和选择 |
| `model_next_weight_boundary_beats_r[3]` → `model_beats_r[0]` | 17 | `model_beats` 为新增寄存器，改前 PDS 未列出 | 比较与上述借位链共享映射逻辑 |
| `residual_row_addr_r[5]` → `residual_next_row_addr_r[30]` | 20 | 新增寄存器，改前 PDS 未列出 | 单个标准加法、PDS 映射进位链 |
| `u_descriptor.desc_r[384]` → `model_next_weight_addr_r[30]` | 19 | 新增寄存器，改前 PDS 未列出 | 单个标准加法、PDS 映射进位链 |

边界拆级前的中间版，`model_next_weight_addr_r[7]` → `model_remaining_r[8]` / `model_beats_r[0]` 分别为 20 / 18 级；最终起点已移到边界寄存器，但通用 ABC 仍把剩余 15 位比较/减法映射成长借位链。根据卡 10 同组负裕量，已按协调者要求完成边界拆级；协调者看过最终 20 级结果后明确要求保留 `f9ac4983`，不改变预算编码，将该标准算术链的真实级数及原 PDS 负裕量单列，交给 B3N 的 PDS 结果判断。此处的进位链是 PDS 映射预期，改后物理路径尚未测量。

标准 32 位加法的两个操作数直接来自寄存器、结果直接寄存，中间不串接选择/比较；按协调者先前批准的标准加法例外保留。

### 剩余控制路径

| 起点 → 终点 | LUT6 级数 | 说明 |
|---|---:|---|
| `u_apb_bridge.request_r[36]` → `u_conv.model_remaining_r[0]` | 13 | SOFT_RST/cancel → datapath cfg_ready → live remaining 装载控制 |
| `u_apb_bridge.request_r[43]` → `u_conv.residual_addr_r[0]` | 11 | APB 即时执行控制 → 地址负载选择；末级不串接地址加法 |
| `u_apb_bridge.request_r[43]` → `stop_r` | 7 | ABORT/stop 执行寄存级；顶层即时请求/DONE 屏蔽保留 |

超过 10 级的纯控制按协调者授权只列起终点，不继续扩大本任务。精确路径分别保存在 `after/npu_targets.json`、`after/npu_burst_plans.json`、`after/npu_model_budget_math.json`、`after/npu_boundary_plans.json`、`after/npu_plans.json`、`after/npu_addr_adders.json`、`after/npu_apb_targets.json`。需要 B3N 改后 PDS 确认这些路径及 clk_npu 全域 setup/hold。

### 改前 clk_npu → CONV 最差 20 条

下表列出分析器返回的最差 20 个 bit 终点；终点均为 FF D，级数均为 LUT 级，无专用 carry 单元。公共 `u_conv.` 前缀保留，便于定位。原始文件 `before/npu_all_conv.json`。

| # | 起点 | 终点 | LUT6 级数 |
|---:|---|---|---:|
| 1 | `u_conv.residual_pairs_r[1]` | `u_conv.residual_addr_r[30]` | 25 |
| 2 | `u_conv.residual_pairs_r[1]` | `u_conv.residual_addr_r[31]` | 25 |
| 3 | `u_conv.residual_row_addr_r[5]` | `u_conv.residual_block_addr_r[29]` | 24 |
| 4 | `u_conv.residual_row_addr_r[5]` | `u_conv.residual_block_addr_r[31]` | 24 |
| 5 | `u_conv.residual_row_addr_r[5]` | `u_conv.residual_addr_r[29]` | 24 |
| 6 | `u_descriptor.desc_r[128]` | `u_conv.u_conv_write.addr_r[30]` | 24 |
| 7 | `u_descriptor.desc_r[128]` | `u_conv.u_conv_write.addr_r[31]` | 24 |
| 8 | `u_conv.residual_row_addr_r[5]` | `u_conv.residual_block_addr_r[30]` | 23 |
| 9 | `u_conv.residual_row_addr_r[5]` | `u_conv.residual_row_addr_r[30]` | 23 |
| 10 | `u_conv.residual_row_addr_r[5]` | `u_conv.residual_row_addr_r[31]` | 23 |
| 11 | `u_descriptor.desc_r[128]` | `u_conv.u_conv_write.addr_r[29]` | 23 |
| 12 | `u_conv.u_conv_write.row_addr_r[6]` | `u_conv.u_conv_write.row_addr_r[30]` | 23 |
| 13 | `u_conv.u_conv_write.row_addr_r[6]` | `u_conv.u_conv_write.row_addr_r[31]` | 23 |
| 14 | `u_conv.u_conv_write.row_addr_r[6]` | `u_conv.u_conv_write.block_addr_r[30]` | 23 |
| 15 | `u_conv.u_conv_write.row_addr_r[6]` | `u_conv.u_conv_write.block_addr_r[31]` | 23 |
| 16 | `u_conv.residual_row_addr_r[5]` | `u_conv.residual_block_addr_r[28]` | 22 |
| 17 | `u_conv.residual_row_addr_r[5]` | `u_conv.residual_row_addr_r[29]` | 22 |
| 18 | `u_conv.residual_pairs_r[1]` | `u_conv.residual_addr_r[28]` | 22 |
| 19 | `u_descriptor.desc_r[128]` | `u_conv.u_conv_write.addr_r[27]` | 22 |
| 20 | `u_descriptor.desc_r[128]` | `u_conv.u_conv_write.addr_r[28]` | 22 |

### 改后 clk_npu → CONV 最差 20 条

原始文件 `after/npu_all_conv.json`；包含未修改的写回、输入装载及数值计算子模块，因此不会用调度器过滤器隐藏更深的路径。

| # | 起点 | 终点 | LUT6 级数 |
|---:|---|---|---:|
| 1 | `u_conv.u_conv_write.row_addr_r[6]` | `u_conv.u_conv_write.block_addr_r[30]` | 23 |
| 2 | `u_conv.u_conv_write.row_addr_r[6]` | `u_conv.u_conv_write.block_addr_r[31]` | 23 |
| 3 | `u_conv.u_conv_write.row_addr_r[6]` | `u_conv.u_conv_write.row_addr_r[30]` | 23 |
| 4 | `u_conv.u_conv_write.row_addr_r[6]` | `u_conv.u_conv_write.row_addr_r[31]` | 23 |
| 5 | `u_conv.u_conv_write.row_addr_r[6]` | `u_conv.u_conv_write.block_addr_r[29]` | 22 |
| 6 | `u_conv.u_conv_write.row_addr_r[6]` | `u_conv.u_conv_write.row_addr_r[29]` | 22 |
| 7 | `u_descriptor.desc_r[128]` | `u_conv.u_conv_write.addr_r[30]` | 22 |
| 8 | `u_descriptor.desc_r[128]` | `u_conv.u_conv_write.addr_r[31]` | 22 |
| 9 | `u_conv.u_datapath.u_result_quant.q_tag_r[7][30]` | `u_conv.u_datapath.u_result_quant.g_lane[0].q8_zero_point_r[45]` | 21 |
| 10 | `u_conv.u_datapath.u_result_quant.q_tag_r[7][30]` | `u_conv.u_datapath.u_result_quant.g_lane[0].q8_zero_point_r[46]` | 21 |
| 11 | `u_conv.u_datapath.u_result_quant.q_tag_r[7][30]` | `u_conv.u_datapath.u_result_quant.g_lane[0].q8_zero_point_r[47]` | 21 |
| 12 | `u_conv.u_datapath.u_result_quant.q_tag_r[7][30]` | `u_conv.u_datapath.u_result_quant.g_lane[0].q8_zero_point_r[48]` | 21 |
| 13 | `u_conv.u_datapath.u_result_quant.q_tag_r[7][30]` | `u_conv.u_datapath.u_result_quant.g_lane[0].q8_zero_point_r[49]` | 21 |
| 14 | `u_conv.u_datapath.u_result_quant.g_lane[0].q_shift_r[4][5]` | `u_conv.u_datapath.u_result_quant.g_lane[0].q5_round_r[47]` | 21 |
| 15 | `u_conv.u_datapath.u_result_quant.g_lane[0].q_shift_r[4][5]` | `u_conv.u_datapath.u_result_quant.g_lane[0].q5_round_r[48]` | 21 |
| 16 | `u_conv.u_datapath.u_result_quant.q_tag_r[7][30]` | `u_conv.u_datapath.u_result_quant.g_lane[1].q8_zero_point_r[48]` | 21 |
| 17 | `u_conv.u_datapath.u_result_quant.q_tag_r[7][30]` | `u_conv.u_datapath.u_result_quant.g_lane[1].q8_zero_point_r[49]` | 21 |
| 18 | `u_conv.u_datapath.u_result_quant.g_lane[1].q_shift_r[4][5]` | `u_conv.u_datapath.u_result_quant.g_lane[1].q5_round_r[47]` | 21 |
| 19 | `u_conv.u_datapath.u_result_quant.g_lane[1].q_shift_r[4][5]` | `u_conv.u_datapath.u_result_quant.g_lane[1].q5_round_r[48]` | 21 |
| 20 | `u_conv.u_datapath.u_result_quant.q_tag_r[7][30]` | `u_conv.u_datapath.u_result_quant.g_lane[2].q8_zero_point_r[42]` | 21 |

| 全 NPU 通用 LUT6 代理资源 | 改前 | 改后 | 变化 |
|---|---:|---:|---:|
| LUT | 54148 | 55400 | +1252 |
| FF | 41943 | 42371 | +428 |
| RAM/APM 黑盒 | 342 | 342 | 0 |

资源为相同工具/相同黑盒划分下的整 NPU 代理数字，不能作为 PDS 的实际 LUT/FF/DRM 数量。布局布线、专用进位链、RAM/APM 的物理映射均未测量。

## 回归：合并到 T-NPU2 统一验收

本节仿真数字为基于 `05088f4b` 的优化中间版参考结果（已加入 stop 寄存及地址/请求计划寄存，尚未加入最后的 5 位边界寄存级），不是最终 RTL 的验收结论。协调者按用户 2026-10-30 的调整要求取消本任务的最终回归队列，合并到 T-NPU2 统一验收；统一验收按协调者最终精简安排，只跑 lint、改动模块的单元 smoke、少量模块级用例和板级 smoke，其余由上板验证；本报告保留既有 full/ER-05/9 个请求轨迹/NET-02 参考结果，不新增回归要求。风格/lint 为最终 RTL 的检查结果。

| 检查 | 参考结果（风格/lint 为最终版） | 日志 |
|---|---|---|
| `verilog_style.py rtl/npu` | 21 文件，0 告警 | `style_final.log` |
| NPU 顶层 `verilator --lint-only -Wall -j 1` | PASS，0 告警 | `lint_final.log`（无输出） |
| `verif/unit/npu_conv` smoke | 1 PASS，0 FAIL | `reference_final_smoke.log` |
| `verif/unit/npu_conv` full | 1 PASS，0 FAIL | `reference_final_full.log` |
| `verif/block/npu` smoke | 22 PASS，0 FAIL | `reference_final_block.log` |
| NET-02 perf | zero / latency / bw 三种配置均 PASS | `reference_final_perf.log`、`after/net_02_perf.csv` |
| 前后请求序列及 PERF0–15 比较 | PASS | `request_compare.json`、`compare.py` |

中间版 ER-05 通过空闲、读权重中、写回中三个 ABORT 场景（`build/npu/er_05/phase{1,2,3}/run_*.log`）；原始 test runner 的三阶段检查均保留。block smoke 按仓库独立 Python 参考模型逐位检查输出，原有 AXI/错误/停机检查均通过。

中间版隔离 bench 的前后比较逐条匹配 CONV 请求输出接口接受的 `(addr, beats, tag)`，共 433 条，地址、长度、标签与次序完全一致；所有用例的输出均通过原 Python 参考模型。原四个用例覆盖 K1/K3、stride1/2、C4、LUT、残差与 HALF_TAIL；额外五个用例保持相同合法描述符格式，将模型首址错开一个 32 B 拍、输出/残差 plane stride 设为 `0x6020`，覆盖 512 B 边界、多个输出块及短段连续推进。原用例 seed 17–20，额外用例 seed 17–21；其余沿用 `verif/unit/npu_conv/run.py` 的输入生成与逐位比较。临时 bench 在 `posedge clk` 且 `read_req_valid && read_req_ready` 时打印三个请求字段，输出检查结束时打印 `$time / 8`，不改变驱动条件。

| 用例 | 特征 | 接受请求数（前=后） | CYCLES（前=后） |
|---|---|---:|---:|
| operators/conv_0 | 原 K3/stride1/LUT/残差 | 154 | 10166 |
| operators/conv_1 | 原 C4/K3/stride2/LUT/残差 | 25 | 1486 |
| operators/conv_2 | 原 K1/stride2/HALF_TAIL | 22 | 2782 |
| operators/conv_3 | 原 K1/stride1/残差 | 38 | 2226 |
| edges/conv_0 | 4×2，Cin16/Cout96，LUT/残差 | 30 | 1831 |
| edges/conv_1 | 4×2，Cin16/Cout80，残差/HALF_TAIL | 24 | 1086 |
| edges/conv_2 | 80×2，Cin16/Cout16，残差 | 18 | 1339 |
| edges/conv_3 | 80×2，Cin16/Cout96，LUT/残差 | 107 | 5612 |
| edges/conv_4 | C4/K3/stride2，Cin3/Cout32，LUT/残差 | 15 | 1089 |

以上特征来自原 runner 与 `edges.py` 的 case 配置，CYCLES 包含 bench 固定开销。正式整网使用默认 NET-02（68 层：63 CONV、3 POOL、2 UPSAMPLE），原始日志/CSV 为 `{before,after}/perf_run_{0,1,2}.log`、`{before,after}/net_02_perf.csv`。

| NET-02 内存配置 | 改前 RTL 周期 | 改后 RTL 周期 | 变化 | DDR 读拍数（前=后） | DDR 写拍数（前=后） |
|---|---:|---:|---:|---:|---:|
| zero（延迟 0） | 6008683 | 6008683 | 0.000% | 512472 | 309000 |
| latency（延迟 94，4.0 GB/s） | 6249662 | 6249662 | 0.000% | 512472 | 309000 |
| bw（延迟 94，1.4 GB/s） | 6938488 | 6938488 | 0.000% | 512472 | 309000 |

三配置的 doorbell→IRQ 周期、MEM 周期及 PERF0–15 每项也完全一致。请求计划利用原有配置/BEGIN/前段等待时间准备，中间版未观察到正常层/段的固定气泡，性能增幅为 0%；最终边界寄存版本的周期与请求序列由 T-NPU2 合并后统一确认。

## 从干净检出重建代理综合文件

以下步骤分别在改前与改后 RTL 提交执行，将固定 tech 包装模块替换为相同端口的 IP 黑盒。生成脚本只写 `build/`，不修改仓库 filelist 或包装模块。

```sh
python3 - <<'PYSYNTH'
from pathlib import Path
import re
from tools.synth.yosys_synth import read_filelist
root = Path.cwd()
out = Path('build/npu-timing/reproduce')
out.mkdir(parents=True, exist_ok=True)
files, includes = [], set()
read_filelist(root / 'rtl/filelists/npu.f', files, includes)
blocks, sources = [], []
for name in dict.fromkeys(files):
    if not name.startswith('rtl/tech/'):
        sources.append(name)
        continue
    text = Path(name).read_text()
    match = re.search(r'module\s+(\w+)\s*\((.*?)\);', text, re.S)
    module, ports = match.groups()
    names = re.findall(r'(?:input|output)\s+(?:wire|reg)\s+'
                       r'(?:\[[^]]+\]\s*)?(\w+)', ports)
    header = f'module {module} ({ports});'
    ip_header = f'module ip_stub_{module} ({ports});'
    connections = ','.join(f'.{port}({port})' for port in names)
    blocks.append('(* blackbox *) ' + ip_header + '\nendmodule\n' + header
                  + f'\nip_stub_{module} u_ip ({connections});\nendmodule\n')
(out / 'stubs.v').write_text('\n'.join(blocks))
sources.append(str(out / 'stubs.v'))
commands = ['read_verilog -D FPGA_MODE '
            + ' '.join('-I' + p for p in sorted(includes))
            + ' ' + ' '.join(sources),
            'hierarchy -top edrv32_npu',
            'synth -top edrv32_npu -flatten -noabc',
            'abc -lut 6 -dress', 'opt_clean',
            f'write_json {out}/npu.json', 'stat']
(out / 'npu.ys').write_text('\n'.join(commands) + '\n')
PYSYNTH
flock /tmp/edrv32-sim.lock yosys -Q -T \
    -l build/npu-timing/reproduce/npu.log -s build/npu-timing/reproduce/npu.ys
```

同域筛选与最差 20 条可直接调用仓库分析器：

```python
from pathlib import Path
import json
from tools.synth.netlist_paths import analyze, is_ff
mfile = Path('build/npu-timing/reproduce/npu.json')
design = json.loads(mfile.read_text())
m = design['modules']['edrv32_npu']
clock = m['ports']['clk_npu_i']['bits'][0]
starts = []
for cell in m['cells'].values():
    if is_ff(cell['type']) and cell['connections']['C'] == [clock]:
        starts.extend(cell['connections']['Q'])
    elif (cell['type'].startswith('ip_stub_')
          and cell['connections']['clk_i'] == [clock]):
        starts.extend(bit for port, bits in cell['connections'].items()
                      if cell['port_directions'][port] == 'output' for bit in bits)
m['netnames']['clk_npu_start_r'] = dict(hide_name=1, bits=starts, attributes={})
r = analyze(design, [r'^clk_npu_start_r'], [r'^u_conv\.'])
for path in r['paths'][:20]:
    print(path['start']['signal'], path['end']['signal'], path['levels'])
```

## T-NPU2 联调复用的定向用例

本 worktree 的 `build/npu-timing/` 保留 `measure.py`、`edges.py`、`compare.py`、`tb_npu_operator.sv`、`lint.vlt` 以及 `before/edrv32_npu{,_conv}.v` 两份基线快照，供需要时复用，不扩大最终精简验收范围；它们是本机生成物，不随提交入库。`measure.py` 只替换顶层/CONV 源文件及 bench 的打印副本，其余文件来自当前 worktree 的原 filelist。before/after 对比时必须保持其余 RTL 相同。

可以将这些辅助文件复制到合并 worktree 的同一 `build/npu-timing/` 目录再运行；所有路径由当前工作目录解析。unit 用例无需外部依赖，NET-02 需要已检出的 ultralytics 子模块：

```sh
flock /tmp/edrv32-sim.lock python3 build/npu-timing/measure.py before unit
flock /tmp/edrv32-sim.lock python3 build/npu-timing/edges.py before
flock /tmp/edrv32-sim.lock python3 build/npu-timing/measure.py after unit
flock /tmp/edrv32-sim.lock python3 build/npu-timing/edges.py after
flock /tmp/edrv32-sim.lock python3 build/npu-timing/measure.py before perf
flock /tmp/edrv32-sim.lock python3 build/npu-timing/measure.py after perf
python3 build/npu-timing/compare.py
```

`edges.py` 从原 runner 派生五个已在上表列明的形状：仍使用 seed `17 + case_index`、`in_offset=0x1e0`、`out_offset=0xfe0`、`in_plane_stride=0x4000`、`out_plane_stride=0x6020`，量化 bias=37、mult=−3、shift=10、out_zp=−7。生成合法 case 后，将整个模型镜像的地址增加一个 32 B beat，并将描述符 word6/word7 的权重/量化 offset 同时增加 32，然后调用原 Python 参考模型。HALF_TAIL 由原生成器根据通道数决定；C4 形状明确设置 `in_c4=True`。每次运行都检查输出，最后逐行比较 REQUEST/CYCLES 与 PERF0–15；没有给 RTL 增加测试专用分支。
