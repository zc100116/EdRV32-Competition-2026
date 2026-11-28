# 卡 112：GPU v2 算术与存储探针（5 个工程）布局布线

## 1. 目标

GPU v2 四项探针（G-P01 FP32 向量、G-P02 SFU、G-P03 setup 运算、G-P04 存储映射，其中 G-P04 有 DRM 和 LUTRAM 两种映射）各做一个独立小工程，在 220 MHz（4.545 ns）约束下综合、布局布线，量出真实裕量、资源、CLM 占用和高扇出，供 G-P05 定延迟和映射。只做时序和资源分析，不生成比特流，不上板。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | 用 `git log -1 --format=%H origin/zc100116/gpu-dev -- tasks/win/20261128-112-gpu2-probes` 找到本卡提交，从它拉出 `win/20261128-112-gpu2-probes`，记录 HEAD |
| 设计说明 | `docs/design/2026-11-28-gpu-v2-probes.md`（每拍做什么、关键段起止寄存器、Yosys 参考级数） |

| 工程 | 顶层 | 导入脚本 | 约束 | 需要的 IP |
|---|---|---|---|---|
| A · fp32 | `edrv32_fpga_probe_gpu2_fp32_top` | `fpga/scripts/import_probe_gpu2_fp32_top.tcl` | `fpga/constraints/edrv32_fpga_probe_gpu2_fp32_top.fdc` | `ip_ram_gpu2_queue` |
| B · sfu | `edrv32_fpga_probe_gpu2_sfu_top` | `import_probe_gpu2_sfu_top.tcl` | 同名 .fdc | `ip_rom_gpu2_sfu`、`ip_ram_gpu2_sfu_scratch`、`ip_lutram_gpu2_sfu_word16`、`ip_lutram_gpu2_sfu_word5` |
| C · setup | `edrv32_fpga_probe_gpu2_setup_top` | `import_probe_gpu2_setup_top.tcl` | 同名 .fdc | 无（APM 原语，见 `fpga/ip/ip_apm_gpu2_setup.md`） |
| D · banks（DRM 映射） | `edrv32_fpga_probe_gpu2_banks_top` | `import_probe_gpu2_banks_top.tcl` | 同名 .fdc | `ip_ram_gpu2_sdp72`、`ip_ram_gpu2_sdp36` |
| E · banks_lutram（LUTRAM 映射） | `edrv32_fpga_probe_gpu2_banks_lutram_top` | `import_probe_gpu2_banks_lutram_top.tcl` | 同名 .fdc | `ip_ram_gpu2_sdp72`、`ip_ram_gpu2_sdp36`、`ip_lutram_gpu2_setup92` |

全部是单时钟 `clk_i`，4.545 ns，没有 PLL。APM 原语（`edrv32_apm_gpu2_*`）不需要 IP。

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 111 相同。

## 4. 需要的 IP

按 `fpga/ip/` 下各自的创建说明生成（见第 2 节表格）。`ip_rom_gpu2_sfu` 的初始化文件由 Windows Codex 在仓库根目录执行 `python3 -B tools/gpu2/gen_sfu_rom.py` 生成 `build/gpu2_sfu/rom.hex`，再复制到工程目录选用。IP Compiler 生成的模块名或端口与说明不一致时，停下来把差异写进 result.md。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | C | 按第 2 节拉分支，记录 HEAD；生成 SFU ROM 的 hex |
| 1 | U | 为 A–E 各新建工程 `EdRV32-FPGA/gpu2_probe_<名>`（PG2L200H-6 FBB676），按第 4 节生成本工程需要的 IP |
| 2 | U | 在工程目录的 PDS Tcl 控制台执行 `source ../../EdRV32-Competition-2026/fpga/scripts/<导入脚本>`；确认工程的 include 路径含仓库 `rtl/include`（卡 111 曾因 include 为空报 Verilog-4104） |
| 3 | U | 默认参数跑综合、Device Map、布局布线；关闭 Generate Bitstream 的 Auto Run |
| 4 | C | 各工程导出报告（导出命令同卡 111），按第 6 节整理 |
| 4b | C | ModelSim 核实 DRM 同址读写：把 `src/check_drm_collision.do` 中 `ip_dirs` 改成本机 B、D 工程 ipcore 下三个 IP 的目录（以及 `vendor_root`），执行 `vsim -c -do "do <该文件绝对路径>"`，原样记录 PASS/FAIL 和输出。sdp72/sdp36 期望同沿读到旧字；scratch 包装自带同沿转发，期望新字。FAIL 不影响第 3、4 步的时序回传 |
| 5 | C | 填写 result.md，提交推送 |

五个工程互不依赖，可以同时跑。某一步报错，把报错原文写进 result.md 后停下，不要改 RTL 或约束。APM 相关告警（级联、CPI/CPO、内部寄存器）和 DRM/LUTRAM 推断告警原文照录。

补充（2026-11-28，用户 Windows 端反馈）：
- `ip_ram_gpu2_queue` 的 PDS 模板端口为 `wr_clk`/`rd_clk`/`rst`，包装已改为两时钟都接 `clk_i`、`rst` 接 0（异步读、无输出寄存器不变），重新拉本卡最新提交即可。
- DRM Simple Dual Port 的 GUI 没有 Old Data 选项：sdp72/sdp36/sfu_scratch 按默认生成，继续布局布线；同址语义由第 4b 步 ModelSim 核实（时序和资源与该语义无关）。

## 6. 产物

放在 `artifacts/<fp32|sfu|setup|banks|banks_lutram>/` 下，每个工程一套：
- `timing_summary.txt`：WNS/TNS/WHS/THS 和估算 Fmax；
- `setup_top200.txt`：最差 200 条 setup，一行一条（起点、终点、裕量、逻辑级数、逻辑/布线延迟）；`setup_top20_detail.txt`；`hold_top20.txt`；
- `segments.txt`：按终点寄存器所在流水级分组，每组最差 3 条（级名以设计说明为准，对不上时按寄存器名前缀分组并在开头说明）。重点单列：fp32 的 DP 加法段（`product_o → s1_small_r → s2_sum_r → result_o`）、sfu 最长段 `s6_c_r → s7_forward_r`、setup 的 N48 首拍、banks 的 RAM 读出到捕获寄存器；另列 APM 内部/级联最差路径；
- `resource_summary.txt`：LUT、FF、DRM、APM、分布式 RAM、IO，**Use of CLMA、Use of CLMS 和 control set 数量**；`resource_hier.txt`：按模块层次；
- `high_fanout.txt`：扇出最大的 50 个网络，及所有扇出超过 16 的使能网络；
- `settings.txt`：实际 P&R 参数。

## 7. 通过判据

五个工程都完成布局布线并交齐第 6 节产物（时序不满足也要完整回传，不判失败）。所有数字取自报告原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 112 结果

| 项 | 内容 |
|---|---|
| 分支 HEAD | |
| PDS 版本 | |

## 汇总
| 工程 | WNS | WHS | 估算 Fmax | LUT | FF | DRM | APM | 分布式 RAM | CLMA | CLMS | control set |
|---|---|---|---|---|---|---|---|---|---|---|---|
| fp32 | | | | | | | | | | | |
| sfu | | | | | | | | | | | |
| setup | | | | | | | | | | | |
| banks | | | | | | | | | | | |
| banks_lutram | | | | | | | | | | | |

## 各工程最差路径与重点段
（每工程：最差路径起点→终点、级数、逻辑/布线延迟；第 6 节点名的重点段裕量）

## 问题与偏离
```
