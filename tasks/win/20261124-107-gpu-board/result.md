# 卡 107 结果

| 项 | 内容 |
|---|---|
| 当前状态 | Compile 阻塞于 ADS RAM 写模式推断 |
| 代码 HEAD | `2f6c3a61`，基于卡 107 `1a211b093`，已合入端口修复和配套说明 |
| PDS 版本 | Windows PDS 2022.2-SP6.1 build 138931 |
| 器件 | Logos2 PG2L200H-6 FBB676 |
| 工程 | `G:/codex_project/EdRV32-FPGA/board_gpu/board_gpu.pds` |
| 输入 | 顶层 `edrv32_fpga_board_gpu_top`，宏 `FPGA_MODE`，GPU 专用 FDC |

## IP 与 PLL

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

## Compile 诊断

| 范围 | 结果 | 用时（墙钟 / CPU） | 证据 |
|---|---|---|---|
| 整片 `board_gpu` | 源码分析 2.375 s、层次展开 1.581 s、编译准备 2.455 s，三步均通过。随后 `rtl-infer` 中 `pds_shell` 崩溃，报 `Flow-0189`。 | 10 分 51 秒 / 1 分 51 秒 | [整片 Compile 日志](artifacts/compile/board-compile-excerpts.log) |
| 独立 GPU 顶层 `edrv32_gpu` | 仅导入 `gpu.f` 的 RTL 和 GPU 存储 IP。层次展开通过，随后同样在 `InferWriteMode.cpp:2983` 崩溃。 | 6 分 45 秒 / 1 分 24 秒 | [GPU-only 日志](artifacts/compile/gpu-only-compile-excerpts.log) |
| 单独编译写 DMA、32×32 strobe RAM、简化纹理队列写入 | 三组均通过 | 5 秒、3 秒、3 秒 | [小工程日志](artifacts/compile/isolated-probes-excerpts.log) |

整片和 GPU-only 都在打印 `Found Ram strobe_r, depth=32, width=32` 后报内部错误。写 DMA 原模块和该数组单独编译均通过，导致崩溃的具体阵列或连接组合尚未定位。纹理队列含动态寻址、多处写入和按 lane 分段写入。PDS 对 `completed_r` 报反馈多路选择器警告，相关精简样例通过。对 `rtl/gpu` 的 36 个 Verilog 文件运行仓库风格检查，结果为 0 告警。此前的 `Verilog-4119` 是更新前的端口差异，已经过修复，当前运行通过层次展开。

[GPU-only 复现脚本](artifacts/compile/compile-gpu-only.tcl)使用两个环境变量。将 `EDRV32_REPO` 设为结果分支的源码根目录，将 `BOARD_GPU_IPCORE` 设为现有 board_gpu 工程的 ipcore 目录。另建空目录作为工作目录，以同版本 PDS 运行 `pds_shell.exe -file <脚本路径> -work_dir <工作目录> -project_name gpu_compile_probe`。

原始日志在 Windows 的 `G:/codex_project/EdRV32-FPGA/board_gpu/pds.log`、`compile/run.log` 和 `G:/codex_project/edrv32-card107/build/card107-pds-check/compile-crash/`。附件保留原始行号和崩溃调用栈。

## 时序、资源与上板

| 项 | 结果 |
|---|---|
| Synthesize、Device Map、Place & Route | 尚未开始 |
| 各时钟域 WNS/TNS/WHS/THS、最差路径 | 未取得 |
| 整片 LUT、FF、DRM、APM、分布式 RAM、IO、PLL | 未取得 |
| 比特流、BIOS CHIP_ID、渲染和音频上板结果 | 未取得 |
