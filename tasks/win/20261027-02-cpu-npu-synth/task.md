# 任务卡 20261027-02-cpu-npu-synth：CPU 第二轮综合 + NPU 数据通路单独 PDS 测量

本任务合并两项 Windows 工作，在同一个结果分支回传：

- **A 部分**：CPU 时序优化后的第二轮综合与布局布线，内容即原任务卡 `tasks/win/20261027-01-cpu-sys-synth-r2/task.md`（该卡不再单独执行）。
- **B 部分**：NPU 数据通路单独综合与布局布线（NPU 规格 5.4 第 4 条，npu-plan N-W1），包括 9 个 NPU IP 的生成和 10 个 NPU 包装模块的 ModelSim 等价性检查。

A、B 两部分互不依赖，用两个独立的 PDS 工程，可以按任意顺序做；某一部分卡住时，另一部分照常完成并回传。

## 1. 目标

- A：取得 SRAM 改为 64 KiB、C-R5/C-R6 优化后 CPU + 系统子系统测量顶层的 clk_sys Fmax、关键路径和资源分布。
- B：取得 NPU 数据通路 `edrv32_npu_datapath` 单独布局布线后在 150 MHz 约束下的时序、关键路径和资源（LUT/FF/DRM/APM），并确认 NPU 包装模块与实际 IP、`GTP_APM_E2` 原语行为一致。

## 2. 输入

- commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录实际使用的完整哈希）。分支：`git switch -c win/20261027-02-cpu-npu-synth origin/main`。
- A：与 20261027-01 卡第 2 节相同——`fpga/rtl/edrv32_fpga_cpu_sys_top.v`、`fpga/scripts/import_cpu_sys_top.tcl`（应打印 `edrv32: added 42 sources`）、`fpga/constraints/edrv32_fpga_cpu_sys_top.fdc`（150 MHz）。
- B：
  - 测量顶层 `fpga/rtl/edrv32_fpga_npu_dp_top.v`：数据通路全部 1025 位输入由一条串行激励移位寄存器（引脚 `stim_i`）逐位驱动，358 位输出逐位打一拍后经带寄存器的 6 输入异或树折叠到一个引脚 `obs_o`。顶层只有 4 个引脚：`clk_i`、`rst_n_i`、`stim_i`、`obs_o`。
  - 导入脚本 `fpga/scripts/import_npu_dp_top.tcl`：按 `rtl/filelists/npu_datapath.f` 展开 23 个源文件（13 个 `rtl/npu/`、10 个 `rtl/tech/` 包装），加 `rtl/common/edrv32_reset_sync.v` 和顶层，共 25 个；导入约束；以头文件目录 `rtl/include`、宏 `FPGA_MODE` 编译。应打印 `edrv32: added 25 sources`。
  - 约束 `fpga/constraints/edrv32_fpga_npu_dp_top.fdc`：`clk_i` 按 150 MHz（clk_npu 开发初值）约束，引脚沿用 CPU 测量顶层（D18、C22、C23、A20）。
  - ModelSim 检查：`tasks/win/20261027-02-cpu-npu-synth/src/check_npu_ip.do`、`src/npu_ip_check.sv`（协调者已在 Linux 用行为模型跑通，并确认能检出读延迟错误）。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- ModelSim SE-64 2020.4（与 20261025-01 相同）。
- A 工程：沿用 `G:\codex_project\EdRV32-FPGA\EdRV32\EdRV32.pds`。
- B 工程：**新建** `G:\codex_project\EdRV32-FPGA\EdRV32-NPU-DP\EdRV32-NPU-DP.pds`，器件同上。路径不同时，Codex 把实际路径写进 `result.md`，并相应修改本机 `check_npu_ip.do` 第 8 行 `ip_root`（这处本地改动随结果一起提交）。

## 4. 需要的 IP

A：按 20261027-01 卡第 4 节，**重新生成 `ip_ram_sram`**（深度 8192，地址 13 位），其他 6 个 IP 不变。

B：在 B 工程中按创建说明生成以下 9 个 IP（索引见 `fpga/ip/README.md`）：

| IP | 创建说明 | 要点 |
|---|---|---|
| `ip_ram_npu_line` | `fpga/ip/ip_ram_npu_line.md` | 1024 × 256，输出寄存器，读延迟 2 |
| `ip_ram_npu_weight` | `fpga/ip/ip_ram_npu_weight.md` | 512 × 256，输出寄存器，读延迟 2 |
| `ip_ram_npu_quant` | `fpga/ip/ip_ram_npu_quant.md` | 512 × 64，输出寄存器，读延迟 2 |
| `ip_ram_npu_lut` | `fpga/ip/ip_ram_npu_lut.md` | 4096 × 8，输出寄存器，读延迟 2 |
| `ip_ram_npu_residual` | `fpga/ip/ip_ram_npu_residual.md` | 512 × 256，输出寄存器，读延迟 2 |
| `ip_ram_npu_result` | `fpga/ip/ip_ram_npu_result.md` | 512 × 512，输出寄存器，读延迟 2 |
| `ip_ram_npu_scratch` | `fpga/ip/ip_ram_npu_scratch.md` | 512 × 256，无输出寄存器，读延迟 1 |
| `ip_mul_npu_quant_low` | `fpga/ip/ip_mul_npu_quant_low.md` | 18 × 16 有符号，2 级 |
| `ip_mul_npu_quant_high` | `fpga/ip/ip_mul_npu_quant_high.md` | 16 × 16 有符号，2 级 |

`edrv32_mul_npu_int8_pair` 直接例化 `GTP_APM_E2` 原语，**不需要生成**（`fpga/ip/ip_mul_npu_int8_pair.md`）。

**包装模块适配授权**（与 20261025-01 的做法相同）：生成的实际端口名、复位/使能/输出寄存器使能端口与创建说明"期望端口"不一致时，Windows Codex 可以只修改对应 `rtl/tech/edrv32_*npu*.v` 的 `ifdef EDRV32_FPGA_MEMORY_MODE` 分支：改端口名、复位接 `1'b0`、时钟使能和输出寄存器使能接 1、地址高位补 0。不得改包装模块的对外端口、行为模型分支和 IP 生成文件。每一处改动写进 `result.md` 的差异表；改完必须通过步骤 B4 的 ModelSim 检查。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261027-02-cpu-npu-synth origin/main`。阅读本卡和 20261027-01 卡，把用户步骤整理成一张清单交给用户。 |
| A1 | 用户（U） | 按第 4 节 A 重新生成 `ip_ram_sram`；告诉 Codex 生成目录，Codex 核对 `addr` 为 13 位、其他端口与 `fpga/ip/ip_ram_sram.md` 一致。 |
| A2 | 用户（U） | 打开 A 工程，在 PDS Tcl 控制台执行 `source <仓库路径>/fpga/scripts/import_cpu_sys_top.tcl`（路径用 `/`），确认打印 `edrv32: added 42 sources`。编译报错就停下，把报错原文交给 Codex。 |
| A3 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。 |
| A4 | Windows Codex（C） | 按 20261027-01 卡第 6 节收集产物，放 `artifacts/cpu/`。 |
| B1 | 用户（U） | 新建 B 工程（第 3 节），按第 4 节 B 生成 9 个 IP；建议先生成 `ip_ram_npu_line` 和 `ip_mul_npu_quant_low` 两个，交给 Codex 核对端口和延迟选项后再生成其余 7 个。告诉 Codex 工程路径和 `ipcore` 目录。 |
| B2 | Windows Codex（C） | 逐个核对实际端口与创建说明；不一致的按第 4 节授权适配包装模块 FPGA 分支。记录每个 IP 的实际端口和占用（DRM 块数 / APM 数），写 `artifacts/npu/ip_ports.md`。 |
| B3 | Windows Codex（C） | 按需修改 `check_npu_ip.do` 的 `ip_root`，执行 `vsim -c -do "do <仓库路径>/tasks/win/20261027-02-cpu-npu-synth/src/check_npu_ip.do"`，日志存为 `artifacts/npu/check_npu_ip.log`。通过时最后打印 `PASS npu_ip_check`，退出码 0。 |
| B4 | Windows Codex（C） | 失败时：先判断是包装模块适配问题（按授权修改后重跑）还是 IP 语义与行为模型不一致（例如读使能为 0 时输出寄存器不保持、同址读出新数据、乘法延迟不是 2 拍、SIMD 符号扩展错误）。后者**不改行为模型、不改检查程序**，停下来把失败行原文、对应 IP 选项写进 `result.md`，B 部分在此停止，A 部分照常完成。 |
| B5 | 用户（U） | 打开 B 工程，在 PDS Tcl 控制台执行 `source <仓库路径>/fpga/scripts/import_npu_dp_top.tcl`，确认打印 `edrv32: added 25 sources`。编译报错就停下，把报错原文交给 Codex。 |
| B6 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。 |
| B7 | Windows Codex（C） | 收集第 6 节 B 的产物，放 `artifacts/npu/`。 |
| 结尾 | Windows Codex（C） | 填写 `result.md`，提交 `result.md`、`artifacts/` 和授权范围内的包装模块改动（如果有），提交信息 `win: 20261027-02-cpu-npu-synth results`，推送 `win/20261027-02-cpu-npu-synth`，告诉用户完成并给出分支名。 |

本轮不做 `RVC_EN = 0` 对照，不做多种子运行，不上板。

## 6. 产物

A：放在 `tasks/win/20261027-02-cpu-npu-synth/artifacts/cpu/`，内容与 20261027-01 卡第 6 节的 7 项相同（`ip_sram_ports.md`、`timing_summary.txt`、`resource_summary.txt`、`resource_hier.txt`、`setup_top200.txt`、`setup_top20_detail.txt`、`hold_top20.txt`、`high_fanout.txt`）。

B：放在 `tasks/win/20261027-02-cpu-npu-synth/artifacts/npu/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `ip_ports.md` | 9 个 IP 的模块名、实际端口（名、方向、位宽）、关键选项实际取值、DRM/APM 占用；包装模块适配差异 |
| 2 | `check_npu_ip.log` | ModelSim 编译和运行日志（含每个检查器的 checks 计数和最终 PASS/FAIL） |
| 3 | `timing_summary.txt` | clk_npu 的 WNS/TNS/WHS/THS、违例端点数；推算 Fmax = `1000 / (6.667 − WNS)` MHz |
| 4 | `resource_summary.txt` | 资源汇总：LUT、FF、DRM（18K/36K 分别计数）、APM、分布式 RAM、IO、PLL；以及器件总量和占用率 |
| 5 | `resource_hier.txt` | 按层次的资源分布，至少到 `u_datapath` 下每个子模块实例（window、line_cache、weight_store、mac_array、accum、result_quant、activation_lut、residual_buffer、residual_add、writeback、input_unpack、quant_param_store），以及顶层激励/观测寄存器 |
| 6 | `setup_top200.txt` | 最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 7 | `setup_top20_detail.txt` | 最差 20 条 setup 路径的逐级明细（含每级单元、扇出和线延迟） |
| 8 | `hold_top20.txt` | 最差 20 条 hold 路径 |
| 9 | `high_fanout.txt` | 扇出最大的 100 个网络（网络名、扇出） |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。单个产物超过几 MB 时，在 `result.md` 里说明原因。

## 7. 通过判据

- A：同 20261027-01 卡第 7 节。
- B：
  - 9 个 IP 按创建说明生成，包装模块（含授权范围内的适配）与 IP 端口一致；
  - `check_npu_ip.do` 打印 `PASS npu_ip_check`，退出码 0；
  - 综合、布局布线完成，没有未解析的模块或黑盒（IP 和原语除外）；DRM、APM 不超过器件容量；
  - 第 6 节产物齐全；所有数字来自 PDS 或 ModelSim 报告原文，找不到的写"未取得"。

时序是否达到 150 MHz 不是本任务的通过条件：本任务是测量，结果交给协调者判断是否回到 N-D1 修改。

## 8. result.md 模板

```markdown
# 20261027-02-cpu-npu-synth 结果

| 项 | 内容 |
|---|---|
| commit | <完整哈希> |
| PDS 版本 | |
| ModelSim 版本 | |
| 器件 | PG2L200H-6 FBB676 |
| A 工程路径 | |
| B 工程路径 | |
| 完成情况 | A：全部完成 / 在步骤 N 停止（原因）；B：全部完成 / 在步骤 N 停止（原因） |

## A. CPU 第二轮

### SRAM IP
（深度、端口与包装模块是否一致；差异）

### 时序
| 时钟 | WNS | TNS | WHS | THS | 违例端点数 | Fmax（推算） |
|---|---|---|---|---|---|---|

上一轮（20261025-01）：WNS −7.708 ns，估计 69.6 MHz，19008/46871 个端点违例。

最差路径前 10 条（起点 → 终点，裕量，级数）：

### 资源
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

上一轮：24.4K LUT、9.1K FF、74 DRM、4 APM。

按层次（主要模块）：

## B. NPU 数据通路

### IP 生成与包装模块
| IP | 实际端口是否与期望一致 | DRM/APM 占用 | 包装模块改动 |
|---|---|---|---|

### ModelSim 等价性检查
（命令、PASS/FAIL、每个检查器 checks 计数；失败时失败行原文）

### 时序
| 时钟 | WNS | TNS | WHS | THS | 违例端点数 | Fmax（推算） |
|---|---|---|---|---|---|---|

最差路径前 10 条（起点 → 终点，裕量，级数）：

### 资源
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

规格估算（设计记录 2026-10-27-npu-datapath）：DRM 156（上限 170），APM 288（上限 300）。

按层次（datapath 各子模块）：

## 完整报告在 Windows 本地的路径

## 备注
```

## 9. 补充（2026-10-27）：B4 诊断与测量范围

背景：首次运行 `check_npu_ip.do` 在 `u_chk_residual` 失败（5166 ns，随机读写阶段第 3–4 拍；前 512 拍为只写填充），原检查第一处失败即停止，其余 RAM 与乘法器尚无结论。按 B4，NPU 后续流程暂停。

### 9.1 同步

Windows Codex 先在 `win/20261027-02-cpu-npu-synth` 上提交本机已有的包装模块适配和 `check_npu_ip.do` 的 `ip_root` 改动（提交信息 `win: adapt NPU wrappers to generated IP`），再 `git fetch origin`、`git rebase origin/main` 取得本节和诊断文件。

### 9.2 诊断步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| B4a | Windows Codex（C） | 打开 `src/diag_npu_ram.do`，`ip_root` 改成与本机 `check_npu_ip.do` 相同。执行 `vsim -c -do "do <仓库路径>/tasks/win/20261027-02-cpu-npu-synth/src/diag_npu_ram.do"`，日志存为 `artifacts/npu/diag_npu_ram.log`。 |
| B4b | Windows Codex（C） | 在 PDS 中查看 7 个 RAM IP 的 `CAS_MODE`、`RD_OCE_EN`，以及是否有读写冲突模式（Write Mode / Read First / Write First / No Change 等）选项及其取值，写进 `artifacts/npu/ip_ports.md`。 |
| B4c | Windows Codex（C） | 填写 `result.md` 的"B4 诊断"小节，提交并推送 `win/20261027-02-cpu-npu-synth`（提交信息 `win: 20261027-02-cpu-npu-synth B4 diagnosis`），告诉用户。 |

诊断期间不修改包装模块行为分支、IP、`npu_ip_check.sv` 和诊断程序；B5 之后（NPU 综合、布局布线）等协调者根据诊断结果给出处理后再做。A 部分不受影响，照常进行。

`src/npu_ram_diag.sv` 包含两个顶层：

- `npu_ram_diag_top`：7 个 RAM 用与 `npu_ip_check` 完全相同的激励和种子，每拍同时与 4 个候选模型比较，只计数、不停止。
  - `m0_spec`：规格行为（同址读写读出旧数据，读使能只控制阵列读，输出寄存器每拍推进）；
  - `m1_write_first`：同址读写读出新数据；
  - `m2_oce_gated`：读使能同时门控输出寄存器；
  - `m3_both`：两者同时成立。
  每个 RAM 打印一行汇总，并打印第一次 m0 失配的时刻、期望/实际值、此前 4 拍端口记录，以及实际值是否与 m1/m2/m3 相符。最后打印 `DIAG DONE`。
- `npu_mul_only_top`：只运行 `npu_ip_check` 中的 4 个乘法检查器（int8_pair 两路、quant_low、quant_high），通过时打印 `PASS npu_mul_only`。

协调者已在 Linux 上用行为模型（SIM_MODE）运行：7 个 RAM 的 `m0_spec` 均为 0，m1–m3 各有数百到数千次失配（四个模型可区分）；`PASS npu_mul_only`。

### 9.3 result.md 增加的小节

```markdown
### B4 诊断
| RAM | CAS_MODE | RD_OCE_EN | 冲突模式选项 | checks | collisions | m0_spec | m1_write_first | m2_oce_gated | m3_both |
|---|---|---|---|---|---|---|---|---|---|

每个 RAM 第一次 m0 失配（日志原文，含 edge-0..3 和 actual matches 行）：

乘法器：PASS npu_mul_only / 第一条 FAIL 原文
```

### 9.4 测量范围说明

`edrv32_ram_npu_scratch` 属于 N-C1 的非卷积执行器，当前 `edrv32_npu_datapath` 不例化它；它在文件列表中存在但不计入本次 B 部分综合资源，IP 检查仍然要做。B 部分资源对比的基准为 148 DRM（设计记录估算 156 减去两块 scratch 的 8）。
