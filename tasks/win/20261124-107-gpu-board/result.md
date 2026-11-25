# 卡 107 结果

## 第 7 轮进度快照

| 项 | 内容 |
|---|---|
| 截取时间 | 2026-11-25 21:00:47（北京时间） |
| 实测代码 | 本地 `574b1e39`，RTL 与任务卡 `1ff65121` 一致 |
| 工程 | `G:/codex_project/EdRV32-FPGA/board_gpu/board_gpu.pds` |
| 工具与器件 | PDS 2022.2-SP6.1 build 138931，ADS 综合，Logos2 PG2L200H-6 FBB676 |
| 状态 | Compile、Synthesize、Device Map 和布局已完成。通用布线最新完成到第 12 轮，仍有 120,352 条网未布。 |

### 流程用时和布线进度

| 阶段 | 结果 | 用时 |
|---|---|---:|
| Compile | 完成 | 2 分 22 秒（阶段墙钟） |
| Synthesize | 完成 | 14 分 04 秒（阶段墙钟） |
| Device Map | 完成，第 5 轮的 FF 超限告警未再出现 | 2 分 57 秒（阶段墙钟） |
| Place | 完成 | 327.86 秒（PDS `Total placement takes`） |
| Route | 进行中，时钟网在第 4 轮全部布通 | 总用时未取得，`Pre route` 为 98.673 秒 |

P&R 于 19:44:56 开始。截取时最近一次日志写入为 20:58:56，PDS Shell 进程仍在。各阶段的现有日志均无 `E:` 行。布局日志记录了 `Place-2039`，涉及 `clk_i_ibuf/opit_1` 与 `u_pll_sys/u_gpll/gpll_inst` 的站点不兼容，工具随后完成布局并进入布线。[阶段用时与错误行](artifacts/round7/flow-excerpts.log) · [布局与布线原文](artifacts/round7/route-progress.log)

| 通用布线迭代 | 未布网 | `overused` | PDS `MT total route time`（秒） |
|---:|---:|---:|---:|
| 6 | 196,009 | 1,492,533 | 32.741 |
| 7 | 184,204 | 1,289,628 | 45.550 |
| 8 | 173,990 | 1,106,242 | 95.329 |
| 9 | 164,899 | 975,239 | 240.252 |
| 10 | 158,071 | 886,395 | 314.284 |
| 11 | 133,321 | 783,027 | 794.134 |
| 12 | 120,352 | 682,056 | 1311.289 |

未布网和超用计数均在下降，每轮报告的耗时持续上升。最终布线结果、拥塞图和 P&R 总用时未取得。[布线进度原文](artifacts/round7/route-progress.log)

### 资源和新 IP

| Device Map 资源 | 用量 | 容量 | PDS 占用 |
|---|---:|---:|---:|
| LUT | 117,864 | 159,800 | 74% |
| FF | 148,974 | 319,600 | 47% |
| DRM（36K 等效） | 343 | 415 | 83% |
| APM | 227 | 740 | 31% |
| Distributed RAM | 6,328 | 39,500 | 17% |
| I/O | 115 | 400 | 29% |
| GPLL | 7 | 10 | 70% |
| PPLL | 2 | 10 | 20% |

Device Map 的 FF 比第 5 轮 DRC 计数少 **171,866（53.57%）**。同口径的综合 FF 从 320,874 降到 149,008。GPU 层次从 286,085 降到 114,219 FF，其中 `u_perspective` 从 161,622 降到 24,407 FF，APM 从 48 降到 16；`u_raster` 从 51,448 降到 27,201 FF。综合报告的控制集从 1,544 增至 1,901，`maximum fanout` 从 156,088 降至 39,816。[Device Map 资源表](artifacts/round7/resource_summary.txt) · [综合层次资源表](artifacts/round7/resource_hier.txt)

`ip_ram_gpu_delay` 于 19:25 生成成功，0 错误、0 警告。实际 10 个端口与包装一致，数据 72 位、地址 9 位，读时钟使能开启、输出寄存器关闭、无初始化。综合层次共找到 51 个该 IP 的 DRM36K 实例，每个用 1 块。[IP 日志、参数、端口和综合实例计数](artifacts/round7/ip_ram_gpu_delay.txt)

### 当前时序

下表为 ADS 综合后、布局前的 Slow Corner 同域时序，单位 ns。

| 时钟域 | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|
| `clk_gpu` | −14.342 | −67269.698 | 0.324 | 0.000 |
| `clk_sys` | −0.526 | −59.608 | 0.324 | 0.000 |
| `clk_mem` | −0.402 | −18.440 | −0.006 | −0.942 |
| `clk_aud` | 77.765 | 0.000 | 0.619 | 0.000 |

综合报告列出 3 条 `clk_gpu` setup 路径，均为 −14.342 ns、41 逻辑级，从 `u_setup/g_attribute[1].value_r_1/CLKB` 到 `u_setup/u_plane/N156_m2/Y[9]`、`Y[10]`、`Y[11]`。布线后时序、`clk_gpu` 最差 200 条 setup 路径和最差 20 条明细待 P&R 完成。比特流和上板结果未取得。[综合时序汇总](artifacts/round7/timing_summary.txt) · [3 条 GPU setup 路径明细](artifacts/round7/synthesis-clk_gpu-setup.txt)

Windows 上保留了这次快照的原始日志和报告，目录为 `G:/codex_project/edrv32-card107/build/card107-pds-check/logbackup/round7-20261125-210047`。

## 第 5 轮及更早记录

| 项 | 内容 |
|---|---|
| 当前状态 | 第 5 轮 Compile 和 Synthesize 完成，Device Map 因 FF 超出容量报 `DRC-0018` |
| 实测代码 | 本地 HEAD `fd019a94`，RTL 与任务卡提交 `7bb2560e` 一致，包含 `ba1ab19f` 的 8 个 RTL 文件修复 |
| 测试时间 | 2026-11-24，Windows PDS 日志时间 22:09–22:35（北京时间） |
| PDS 版本 | Windows PDS 2022.2-SP6.1 build 138931，ADS 综合 |
| 器件 | Logos2 PG2L200H-6 FBB676 |
| 工程 | `G:/codex_project/EdRV32-FPGA/board_gpu/board_gpu.pds` |
| 输入 | 顶层 `edrv32_fpga_board_gpu_top`、宏 `FPGA_MODE`、GPU 专用 FDC、原工程 IP |

### 第 5 轮流程结果

| 阶段 | 结果 | 墙钟用时 | 进程 CPU 用时 | 峰值内存池 |
|---|---|---:|---:|---:|
| Compile | 完成，`rtl-infer` 通过，本轮无 `E:` 行 | 2 分 55 秒 | 16 秒 | 924 MB |
| Synthesize | 完成，报告寄存器超限警告 | 20 分 13 秒 | 6 分 30 秒 | 5,080 MB |
| Device Map | `DeviceMap-2003`、`DRC-0018`，容量检查失败 | 2 分 33 秒 | 55 秒 | 4,357 MB |
| Place、Route | 未开始 | 未取得 | 未取得 | 未取得 |

第 4 轮在 19 秒时因 `Sdm-4000` 中止。第 5 轮未复现该错误，也未见之前的内部崩溃或多驱动错误。Device Map 使用 320,840 个 FF，器件提供 319,600 个，**超出 1,240 个，约 0.39%**。[阶段日志及全部错误行](artifacts/round5/flow-excerpts.log)

### 资源

| 资源 | 综合用量 | 器件容量 | 占用 |
|---|---:|---:|---:|
| LUT | 141,214 | 159,800 | 88.37% |
| FF | 320,874 | 319,600 | 100.40% |
| LUT 作分布式 RAM（计入 LUT 总数） | 4,613 | 39,500 | 11.68% |
| DRM（36K 等效） | 296 | 415 | 71.33% |
| APM | 271 | 740 | 36.62% |
| I/O | 115 | 400 | 28.75% |
| PLL 基元 | 7 个 GPLL、2 个 PPLL | 未取得 | 未取得 |

综合超出 1,274 个 FF，Device Map 的容量检查使用另一个计数 320,840。最终 Device Map 资源汇总在 `multiseed_summary.csv` 里为 NA，表中其余数字均来自综合。[资源原文](artifacts/resource_summary.txt)

| 综合层次（包含子模块） | LUT | FF | 分布式 RAM LUT | APM | DRM |
|---|---:|---:|---:|---:|---:|
| `u_soc/u_gpu` | 101,007 | 286,085 | 3,372 | 260 | 233.5 |
| `u_soc/u_gpu/u_core/u_perspective` | 32,457 | 161,622 | 0 | 48 | 2 |
| `u_soc/u_gpu/u_core/u_raster` | 12,580 | 51,448 | 0 | 0 | 0 |
| `u_soc/u_gpu/u_core/u_geometry` | 13,724 | 21,346 | 262 | 68 | 1 |
| `u_soc/u_cpu` | 19,189 | 12,109 | 680 | 4 | 27 |

GPU 占全片综合 FF 的 89.16%，其中 `u_perspective` 单独占全片的 50.37%。综合报告有 1,544 组控制集，284,656 个 FF 带 CE 且没有同步或异步置位、复位。综合的 `u_palette` 层次共用 8 个 DRM，与 8 个 `palette_segment` 实例的配置相符。[完整层次资源表](artifacts/resource_hier.txt)

### 综合预估时序

以下为 ADS 综合后、布局前的 Slow Corner 估算。同域路径的 slack 单位为 ns。

| 时钟域 | 请求 MHz | 估算 MHz | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|---:|---:|
| `clk_gpu` | 180.0002 | 43.3514 | −17.510 | −163756.564 | 0.324 | 0.000 |
| `clk_sys` | 125.0001 | 115.0076 | −0.695 | −43.644 | 0.324 | 0.000 |
| `clk_mem` | 125.0000 | 119.2464 | −0.386 | −13.246 | −0.006 | −0.942 |
| `clk_aud` | 12.2880 | 276.6247 | 77.765 | 0.000 | 0.619 | 0.000 |

综合估算的 GPU 最差 setup 路径为 `u_soc/u_gpu/u_core/u_texture/log2_w_r[3]/CLK` 到 `u_soc/u_gpu/u_core/u_texture_ram/g_bank[3].read_addr_r[0]/D`，28 逻辑级，slack −17.510 ns。[时序汇总](artifacts/timing_summary.txt) · [已报告的路径索引](artifacts/round5/synthesis-path-index.txt) · [20 条最差 setup 明细](artifacts/round5/synthesis-setup-top20.txt) · [20 条最差 hold 明细](artifacts/round5/synthesis-hold-top20.txt)

布局布线时序、每时钟域布线后最差 200 条路径、拥塞、比特流和上板结果均未取得。原始报告为 `G:/codex_project/EdRV32-FPGA/board_gpu/synthesize/edrv32_fpga_board_gpu_top.snr`，阶段日志在同一工程的 `compile/run.log`、`synthesize/run.log`、`device_map/run.log` 和 `pds.log`。

### IP 与 PLL

13 个新 IP 均在 GUI 生成成功。逐项比对生成的 IDF 端口与当前 RTL 例化，13 项端口名称均一致。13 条原始成功记录见 [PDS GUI 日志节选](artifacts/compile/pds-gui-excerpts.log)。

| IP | 核对结果 |
|---|---|
| `ip_ram_gpu_texture_segment` | PDS 实际为 `a_*` / `b_*` 端口，共 16 个。每端地址 11 位、数据 16 位，字节写使能 2 位。|
| `ip_ram_gpu_palette_segment` | 同样为 `a_*` / `b_*`，共 14 个。每端地址 10 位、数据 20 位，整字写。生成 RTL 的地址和数据各展开一次，单实例为 1 个 `GTP_DRM36K_E1`。设计例化 8 个，整片 Device Map 占用待测。|
| `ip_rom_gpu_recip_q30`、`ip_rom_gpu_recip_p18` | 两个 IDF 都保存 `INIT_EN=true`、`INIT_FORMAT=HEX` 和所选 .dat 绝对路径。生成文件中每个 ROM 的 1024 个 18 位初值均与对应 .dat 逐字相等。|

| 时钟 | 目标 MHz | 生成配置 MHz | VCO / IDIV / MDIV / FDIV / ODIV0 | 误差 ppm |
|---|---:|---:|---|---:|
| clk_gpu | 180 | 180.00000000 | 1147.5 / 1 / 2 / 21.25 / 6.375 | 0.00 |
| clk_aud | 12.288 | 12.28798343 | 1112.0625 / 2 / 1 / 82.375 / 90.5 | −1.35 |

频率由生成的 IDF 分频参数计算。上板实测频率未取得。[PLL 参数](artifacts/pll.txt)

### 第 1 轮 Compile 诊断（历史记录）

| 范围 | 结果 | 用时（墙钟 / CPU） | 证据 |
|---|---|---|---|
| 整片 `board_gpu` | 源码分析 2.375 s、层次展开 1.581 s、编译准备 2.455 s，三步均通过。随后 `rtl-infer` 中 `pds_shell` 崩溃，报 `Flow-0189`。 | 10 分 51 秒 / 1 分 51 秒 | [整片 Compile 日志](artifacts/compile/board-compile-excerpts.log) |
| 独立 GPU 顶层 `edrv32_gpu` | 仅导入 `gpu.f` 的 RTL 和 GPU 存储 IP。层次展开通过，随后同样在 `InferWriteMode.cpp:2983` 崩溃。 | 6 分 45 秒 / 1 分 24 秒 | [GPU-only 日志](artifacts/compile/gpu-only-compile-excerpts.log) |
| 单独编译写 DMA、32×32 strobe RAM、简化纹理队列写入 | 三组均通过 | 5 秒、3 秒、3 秒 | [小工程日志](artifacts/compile/isolated-probes-excerpts.log) |

整片和 GPU-only 都在打印 `Found Ram strobe_r, depth=32, width=32` 后报内部错误。写 DMA 原模块和该数组单独编译均通过，导致崩溃的具体阵列或连接组合尚未定位。纹理队列含动态寻址、多处写入和按 lane 分段写入。PDS 对 `completed_r` 报反馈多路选择器警告，相关精简样例通过。对 `rtl/gpu` 的 36 个 Verilog 文件运行仓库风格检查，结果为 0 告警。此前的 `Verilog-4119` 是更新前的端口差异，已经过修复，当前运行通过层次展开。

[GPU-only 复现脚本](artifacts/compile/compile-gpu-only.tcl)使用两个环境变量。将 `EDRV32_REPO` 设为结果分支的源码根目录，将 `BOARD_GPU_IPCORE` 设为现有 board_gpu 工程的 ipcore 目录。另建空目录作为工作目录，以同版本 PDS 运行 `pds_shell.exe -file <脚本路径> -work_dir <工作目录> -project_name gpu_compile_probe`。

原始日志在 Windows 的 `G:/codex_project/EdRV32-FPGA/board_gpu/pds.log`、`compile/run.log` 和 `G:/codex_project/edrv32-card107/build/card107-pds-check/compile-crash/`。附件保留原始行号和崩溃调用栈。

卡 109 随后将 RAM 推断崩溃定位到 `edrv32_gpu_unpack` 的跨通道共享数组，并单独定位了 `edrv32_gpu_clip` 的多驱动问题。两处修复均已进入第 5 轮的代码基线。[卡 109 复现与日志](https://github.com/zc100116/EdRV32-Competition-2026/tree/win/20261124-109-gpu-compile-bisect/tasks/win/20261124-109-gpu-compile-bisect)
