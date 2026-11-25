# 卡 107：GPU SoC 首次综合、布局布线和上板

## 1. 目标

为 GPU SoC 生成新的 IP，综合、布局布线，取得时序和资源报告；生成比特流后上板，验证 GPU 画面、音频和启动流程。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | 用 `git log -1 --format=%H origin/zc100116/gpu-dev -- tasks/win/20261124-107-gpu-board` 找到本卡的提交，从它拉出 `win/20261124-107-gpu-board`，记录 HEAD |
| 顶层 | `edrv32_fpga_board_gpu_top`（`fpga/rtl/edrv32_fpga_board_gpu_top.v`） |
| 约束 | `fpga/constraints/edrv32_fpga_board_gpu_top.fdc` |
| 导入脚本 | `fpga/scripts/import_board_gpu_top.tcl` |
| 程序 | `src/gpu_hello.elf`（旋转立方体 + 100 个弹跳精灵 + 帧号文字 + 方波声音）；`src/gpu_render.elf`（ST-10 渲染测试）；`src/gpu_audio.elf`（ST-12 放音测试）。三者都链接在 DDR，用 BIOS 的 UART 或 ETH 加载 |
| 准备报告 | `docs/reports/2026-11-24-board-gpu-prep.md`（IP 清单、PLL、引脚、跨时钟域对照） |

## 3. 环境

- PG2L200H-6 FBB676，PDS 版本与卡 75 的 full 工程相同。
- **布局布线期间关闭仿真虚拟机**：它与 PDS 共用 Windows 内存；卡 68 曾因内存不足，布线一轮从 19 s 变成 1294 s。
- J25 扩展口经 PMOD-X4 转接板，在 PMOD-D 接 MES-Speaker 放音模块，接耳机或音箱。

## 4. 需要的 IP

新工程目录：`EdRV32-FPGA/board_gpu`。

| 类别 | IP | 说明 |
|---|---|---|
| 新建（必须按说明生成） | `ip_pll_gpu`、`ip_pll_aud` | `fpga/ip/ip_pll_gpu.md`、`ip_pll_aud.md` |
| 新建 | `ip_ram_aud_fifo` | `fpga/ip/ip_ram_aud_fifo.md` |
| 新建（GPU） | `ip_ram_gpu_target_segment`、`ip_ram_gpu_target_tail`、`ip_ram_gpu_texture_segment`、`ip_ram_gpu_palette_segment`、`ip_ram_gpu_resolve_line`、`ip_lutram_gpu_palette_current`、`ip_lutram_gpu_read_pool`、`ip_lutram_gpu_write_pool`、`ip_rom_gpu_recip_q30`、`ip_rom_gpu_recip_p18` | `fpga/ip/` 下同名说明；两个 ROM 的初始化文件是 `fpga/ip/gpu_recip_q30.dat`、`gpu_recip_p18.dat` |
| 沿用 full 工程 | `ip_pll_sys`、`ip_pll_video`、`ip_pll_eth`、`ip_ddr3`，CPU、mem_xbar、DISP、ETH 的全部 IP | 可以从卡 75 工程复制 IP 目录后重新生成，或按 `fpga/ip/` 说明重建 |

**新 IP 生成后，逐个核对模块名、端口名和位宽与说明一致；不一致就停下，把实际端口记入 result.md，不要改包装模块。** 特别确认：`ip_ram_gpu_palette_segment`（1024 × 20 真双口）实际占几块 DRM。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | C | 按第 2 节拉分支，记录 HEAD |
| 1 | U | 新建工程 `EdRV32-FPGA/board_gpu`（PG2L200H-6 FBB676），按第 4 节生成全部 IP |
| 2 | U | 在 PDS Tcl 控制台中，在工程目录下执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_gpu_top.tcl` |
| 3 | U | 关闭仿真虚拟机，然后综合、布局布线、生成比特流 |
| 4 | C | 收集报告：时序汇总、最差路径、资源（按第 6 节） |
| 5 | U | 下载比特流，串口打开 BIOS，确认启动信息和菜单。记录 CHIP_ID（应为 0xED32_0002） |
| 6 | U | 加载 `gpu_render.elf` 运行：拍屏幕照片，保存串口输出（应有 `PASS ST-10 render HDMI`） |
| 7 | U | 加载 `gpu_audio.elf` 运行：听是否有声音，保存串口输出 |
| 8 | U | 加载 `gpu_hello.elf` 运行：录 20 秒视频。看立方体是否转动、精灵是否弹跳、帧号是否增加；按方向键（ETH 虚拟手柄或板上按键）听音高是否变化 |
| 9 | C | 填写 result.md，推送分支 |

## 6. 产物

放在 `tasks/win/20261124-107-gpu-board/artifacts/`：
- `timing_summary.txt`：每个时钟域的 WNS/TNS/WHS/THS，必须包括 clk_gpu（目标 180 MHz）、clk_sys、clk_mem、clk_aud；
- `setup_top200_<域>.txt`：每个时钟域最差 200 条 setup 路径，一行一条（起点、终点、裕量、逻辑级数）；
- `setup_top20_detail.txt`、`hold_top20.txt`；
- `resource_summary.txt`：LUT、FF、DRM、APM、分布式 RAM、IO、PLL；能导出的话，另附按模块层次的分布 `resource_hier.txt`；
- `pll.txt`：两个新 PLL 的实际输出频率、VCO 和分频值；
- `uart/<步骤>.log`、`photo/`、`video/`（超过 100 MB 用 Git LFS）。

## 6a. 第 3 轮（2026-11-24，GPU RTL 硬件风格整改后）

- **代码**：仍按第 2 节的命令取本卡最新提交（本节随它一起提交），从它拉出或重置 `win/20261124-107-gpu-board`，记录 HEAD。这一轮包含卡 109 的两处修复，以及 S-1A–D 对 21 个 GPU 模块的硬件风格整改（CLAUDE.md 5.5 第 1–5 条；仿真回归 GT-01–25 通过，逐周期不变）。
- **IP 和工程**：沿用已生成的 13 个 IP 和工程 `EdRV32-FPGA/board_gpu`，不用重新生成。在 PDS 中移除旧的源文件后，重新执行第 5 节第 2 步的导入脚本，从 Compile 开始。
- **额外记录**（写进 result.md 的"问题与偏离"）：
  - Compile、Synthesize、Place、Route 各步的耗时（PDS 日志原文），以及是否再出现内部崩溃或多驱动错误；
  - 如果 Compile 仍明显偏慢（超过 10 分钟），记下日志里耗时最长的模块名。
- 其余步骤和产物同第 5、6 节。

## 6b. 第 4 轮（2026-11-24，修复第 3 轮 Compile 报错）

- 第 3 轮 Compile 报 `Verilog-4205 edrv32_gpu_texture.v(656) Size of concatenate expression should not be 0`：整改引入了 39 处跨 generate 作用域的层次引用，PDS 不支持。已在 7ce424fe0 全部改写（texture 30 处、perspective 9 处），风格检查新增此规则（becd1795e）。
- 取本卡最新提交（随本节一起提交），同第 6a 节：沿用工程和 IP，移除旧源文件，重新执行导入脚本，从 Compile 开始；额外记录同第 6a 节。
- 这一轮的仿真回归在仿真主机恢复后补跑，结果不影响你先做 Compile 和综合。

## 6c. 第 5 轮（2026-11-24，修复第 4 轮 Compile 报错）

- 第 4 轮 Compile 报 `Sdm-4000 edrv32_gpu_texture.v(389) Part select for array net g_lod[3].normalized_w is illegal`：整改在 generate 块内声明了 15 个 wire 数组并对元素做了部分选择/位选择，PDS 不支持。已在 ba1ab19f8 全部改成扁平向量（8 个文件），风格检查新增此规则（d97d7ac16）。已对照第 1 轮 PDS 通过的代码逐项比对，其余新写法在 SoC 其他已综合模块中都用过。
- 取本卡最新提交（随本节一起提交），同第 6a 节：沿用工程和 IP，移除旧源文件，重新执行导入脚本。
- **先只跑 Compile**（Windows Codex 或用户 GUI 均可）：Compile 结束后立即把结果告诉协调者——通过就直接继续综合和布局布线；报错就把 Compile 日志中全部 `E:` 行（不止第一条）提交到 `win/20261124-107-gpu-board` 并推送，停下等修复。
- 额外记录同第 6a 节；仿真回归仍在仿真主机恢复后补跑，不影响本轮。

## 6d. 第 6 轮（2026-11-25，修复第 5 轮 Device Map FF 超限）

> **不跑，已由第 7 轮（6e）取代。** 本节保留作记录。

- 第 5 轮 Device Map 报 `DRC-0018`：FF 320,840 > 319,600。原因是 GPU 的深延迟线全部用寄存器实现，并且长流水线共用一个停顿使能（扇出 156,088）。S-2 整改（4a84be516..8807e6580）：深延迟线改用 RAM 环形缓冲，perspective 和 raster 改成按 credit 接收的不停顿流水线，纹理 mip 地址在配置时预先计算。仿真主机上 18 个 GPU 单元测试和 GT-01～GT-25 全部通过。
- **需要新生成 1 个 IP**：`ip_ram_gpu_delay`（DRM 简单双口，512 × 72，读延迟 1 拍），按 `fpga/ip/ip_ram_gpu_delay.md` 在 PDS 中生成，放进原工程的 ipcore；生成后核对端口名，与创建说明不一致时，把实际端口写进 result.md（不要自己改 RTL）。其余 13 个 IP 沿用。
- 取本卡最新提交，同第 6a 节：沿用工程，移除旧源文件，重新执行导入脚本，从 Compile 开始。
- **本轮一直跑完布局布线**（Compile → 综合 → Device Map → Place & Route → 时序报告），各阶段记录用时。任一阶段报错就停下，把该阶段日志中全部 `E:` 行提交并推送。
- 回传：资源汇总、按层次的资源表（同第 5 轮格式，GPU 各子模块单列）、各时钟域 WNS/TNS/WHS/THS、clk_gpu 最差 200 条 setup 路径一行一条、最差 20 条逐级明细、布线拥塞摘要（如果 PDS 给出）。
- Yosys 参考估算：GPU FF 约降 27%，新增 60 块 DRM（全片估计约 356/415）。这只是估算，以 PDS 为准。

## 6e. 第 7 轮（2026-11-25，S-2 + S-3 资源整改后，跑完整流程）

- **本轮的改动**：
  - S-2（4a84be516..8807e6580）：深延迟线改用 RAM，长流水线改成不停顿，纹理地址在配置时预先计算。
  - S-3（0725ffa10..0018e27f2）：重写宽加法、规格化等算术单元，只寄存后面还要用的位，拍数减少；GPU 规格 v0.4，平面精度改为方案 G，LOD 改为 2×2 像素组，去掉逐像素偏导。
  - 仿真主机上 18 个 GPU 单元测试和 GT-01～GT-25 全部通过；各命令周期数与 S-2 基本相同。
  - Yosys 参考估算：GPU FF 从 286k 降到 201k，LUT6 从 315k 降到 269k；perspective 的乘法器从 48 个降到 16 个。Yosys 的绝对数偏大（第 5 轮同一份代码，Yosys 394k FF，PDS 286k），以本轮 PDS 为准。
- **需要新生成 1 个 IP**：`ip_ram_gpu_delay`（DRM 简单双口，512 × 72，读延迟 1 拍），按 `fpga/ip/ip_ram_gpu_delay.md` 在 PDS 中生成，放进原工程的 ipcore。生成后核对端口名；与创建说明不一致时，把实际端口写进 result.md，不要自己改 RTL。其余 13 个 IP 沿用。
- 取本卡最新提交，步骤同第 6a 节：沿用原工程，移除旧源文件，重新执行导入脚本，从 Compile 开始。
- **跑 P&R 前先关闭仿真虚拟机**：它和 PDS 共用 Windows 的内存，开着会让布局布线慢几十倍。本轮不需要仿真。
- **本轮一直跑完布局布线**：Compile → 综合 → Device Map → Place & Route → 时序报告，记录各阶段用时。任一阶段报错就停下，把该阶段日志中全部 `E:` 行提交并推送。
- **回传内容**：
  - 资源汇总；
  - 按层次的资源表，格式同第 5 轮，GPU 各子模块单列；
  - 各时钟域的 WNS/TNS/WHS/THS；
  - clk_gpu 最差 200 条 setup 路径，一行一条；最差 20 条的逐级明细；
  - 布线拥塞摘要（如果 PDS 给出）。
- 布局布线通过后，继续第 5 节的上板步骤（第 5～8 步）。

## 7. 通过判据

- 布局布线完成（时序不满足也要完整回传报告，不判失败）。
- clk_aud 实际频率误差 |ppm| ≤ 1000，ppm = (实际 MHz / 12.288 − 1) × 10⁶。
- 第 5 步 CHIP_ID 正确；第 6 步出现 PASS 且画面正常；第 7 步有声音；第 8 步画面和声音按描述工作。
- 所有数字取自报告或串口原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 107 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | |
| PDS 版本 | |

## IP
| IP | 生成结果 | 端口一致 | 备注（palette_segment 写 DRM 块数） |
|---|---|---|---|

## PLL
| 时钟 | 目标 MHz | 实际 MHz | VCO / 分频 | 误差 ppm |
|---|---|---|---|---|

## 时序
| 时钟域 | 目标 MHz | WNS | TNS | WHS | THS | 最差路径起点→终点 |
|---|---|---|---|---|---|---|

## 资源
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

## 上板
| 步骤 | 结果 | 观察 |
|---|---|---|
| 5 BIOS/CHIP_ID | | |
| 6 gpu_render | | |
| 7 gpu_audio | | |
| 8 gpu_hello | | |

## 问题与偏离
```
