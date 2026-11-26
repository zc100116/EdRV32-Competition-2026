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

## 6f. 第 8 轮（2026-11-26，S-4 整改后：先综合，达标再布局布线）

- **第 7 轮结果**：资源装下了，但布线不通，clk_gpu 布局后 WNS 为 −13.4 ns。
- **本轮改动**：
  - GPU 规格 v0.5：三角形路径改为每拍 2 像素；四边形、像素运算、渲染目标仍为每拍 4 像素。
  - S-4 整改（183cae592..cefbd28fa）：
    - 四边形不经过透视单元；
    - raster→perspective 的平面总线从 1,736 位降到 868 位；
    - perspective 的 DRM 从 43 块降到 26 块；
    - 所有单拍宽运算切开，DRM 和 APM 的输入输出全部寄存；
    - 扇出超过 2,000 的控制网按区域复制，并加了 `syn_preserve`。
  - 仿真主机上 18 个 GPU 单元测试和 GT-01～GT-25 全部通过。
- **没有新增 IP**，沿用第 7 轮的 14 个 IP。
- 取本卡最新提交，步骤同第 6a 节：沿用原工程，移除旧源文件，重新执行导入脚本，从 Compile 开始。
- **第一段：只跑 Compile → 综合 → Device Map**，然后提交并推送以下内容：
  1. 资源汇总，以及按层次的资源表（格式同第 7 轮，GPU 各子模块单列）；
  2. 综合预估时序汇总（各时钟域的 WNS、TNS、估算频率）；
  3. **clk_gpu 最差 200 条 setup 路径**，一行一条：起点、终点、裕量、逻辑级数。第 7 轮只导出了 3 条，本轮要在报告设置里把路径数调到 200；不会调的话停下来问用户；
  4. clk_gpu 最差 20 条路径的逐级明细；
  5. **高扇出表**：Device Map 的 Reset / CE / Other 三张表（`high_fanout` 报告），以及综合报告中 `maximum fanout` 对应的网名。
- **第二段：布局布线**，按综合结果决定：
  - 综合估算的 clk_gpu 频率 ≥ 150 MHz（即 WNS ≥ −1.11 ns）：继续跑 Place & Route 和时序报告，回传内容同第 6e 节。
  - 低于 150 MHz：不跑布局布线，推送第一段的结果即可。
- 跑布局布线前先关闭仿真虚拟机。

## 6g. 第 9 轮（2026-11-26，S-5 + S-6 整改后：先综合，达标再布局布线）

- **第 8 轮结果**：综合估算 clk_gpu 114.9 MHz；LUT 68%、FF 58%、DRM 80%、APM 30%。最差路径是 setup 中多个 APM 级联的乘法。如果第 8 轮的布局布线还在跑，可以停掉；如果已经跑完，把结果一起回传。
- **本轮改动**：
  - S-5（aa61a0d08..b58b512c7）：geometry、setup 的宽乘法拆成 ≤ 18×18 的部分积，每个都寄存，再用流水加法树求和，去掉了多 APM 级联的那条最差路径。
  - S-6（9a30a7705..07b77f44c）：深度 ≤ 64 的延迟线、队列和小表，全部从 DRM 改为分布式 RAM（新 IP `ip_lutram_gpu_table`）或寄存器。估算 GPU DRM 从 286.5 降到 191，整片约 61%；LUT 增加约 8 千。
  - 仿真主机上 18 个 GPU 单元测试和 GT-01～GT-25 全部通过，GT-25 各命令周期与 S-5 相同。
- **IP 变化**：
  - **新生成 1 个**：`ip_lutram_gpu_table`，按 `fpga/ip/ip_lutram_gpu_table.md` 生成。它是 64 × 72 的分布式简单双口 RAM，组合读，输出不寄存；选项与已有的 `ip_lutram_gpu_read_pool` 相同，只把数据宽度从 256 改成 72。生成后核对端口名；与说明不一致时，把实际端口写进 result.md，不要改 RTL。
  - **不再使用**：`ip_ram_gpu_delay`（第 7 轮生成的 512 × 72 DRM）。RTL 已不再例化它，可以从工程里移除；不移除也不影响结果。
  - 其余 IP 沿用。
- 取本卡最新提交，步骤同第 6a 节：沿用原工程，移除旧源文件，重新执行导入脚本，从 Compile 开始。
- **第一段：只跑 Compile → 综合 → Device Map**，然后提交并推送以下内容（同第 6f 节）：
  1. 资源汇总，必须包括分布式 RAM 用量；以及按层次的资源表，GPU 各子模块单列；
  2. 综合预估时序汇总（各时钟域的 WNS、TNS、估算频率）；
  3. clk_gpu 最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数；
  4. clk_gpu 最差 20 条路径的逐级明细；
  5. 高扇出表：Device Map 的 Reset / CE / Other 三张表，以及综合报告中 `maximum fanout` 对应的网名。
- **第二段：布局布线**，按综合结果决定：
  - 综合估算的 clk_gpu 频率 ≥ 150 MHz（即 WNS ≥ −1.11 ns）：继续跑 Place & Route 和时序报告，回传内容同第 6e 节，另附布线拥塞摘要和各阶段用时。
  - 低于 150 MHz：不跑布局布线，推送第一段的结果即可。
- **跑布局布线前先关闭仿真虚拟机。**

## 6h. 第 10 轮（2026-11-26，S-7 + S-8 整改后：先综合，达标再布局布线）

- **第 9 轮结果**：
  - Device Map：LUT 73%、FF 55%、DRM 62%、APM 33%、分布式 RAM 31%；
  - clk_gpu 综合估算 153.6 MHz，最差路径集中在 `u_command/stop_r` 的高扇出；
  - 布局布线结果还没有回传。**如果第 9 轮的布局布线已经跑完，先把结果按第 6e 节的格式提交推送**：是否布通、各时钟域时序、拥塞摘要、各阶段用时。还在跑的话就停掉，不用等。
- **本轮改动**：
  - S-7（466aa8a99..46352f6a8）：
    - `stop_r` 等控制信号按区域复制，最大扇出 1,956；
    - LOD 路径切拍；
    - clip 的 8 顶点工作集改放分布式 RAM，并改为逐顶点输出；
    - LOD 差分单元从 8 个减为 4 个；
    - Yosys 估算 GPU 少 1.3 万 FF、1.7 万 LUT6。
  - S-8（2b89c48b6..104e9b252，GPU SoC 规格 v0.3）：
    - mem_xbar 改为"紧急 → CPU → 轮转"的简单调度，删除统计和运行时参数；
    - DISP 删除 L1 叠加层。
  - 仿真回归全部通过。完整系统不跑 SoC 仿真，放到上板测试。
- **没有新增 IP**，沿用第 9 轮的全部 IP（包括 `ip_lutram_gpu_table`）。`ip_ram_gpu_delay` 不再使用。
- 取本卡最新提交，步骤同第 6a 节：沿用原工程，移除旧源文件，重新执行导入脚本，从 Compile 开始。
- **第一段：只跑 Compile → 综合 → Device Map**，然后提交并推送以下内容（同第 6g 节）：
  1. 资源汇总，包括分布式 RAM；按层次的资源表，GPU、mem、DISP 的子模块单列；
  2. 综合预估时序汇总；
  3. clk_gpu 最差 200 条 setup 路径，一行一条；
  4. clk_gpu 最差 20 条路径的逐级明细；
  5. 高扇出表。
- **第二段：布局布线**，按综合结果决定：
  - 综合估算的 clk_gpu ≥ 150 MHz：继续跑 Place & Route 和时序报告。回传内容同第 6e 节，另附布线拥塞摘要；记录每个布局阶段和每次布线迭代的用时。
  - 低于 150 MHz：不跑布局布线，推送第一段的结果即可。
- **跑布局布线之前必须关闭仿真虚拟机。** 虚拟机和 PDS 共用 Windows 内存：第 9 轮虚拟机一直开着，布局一个阶段就跑了半小时；正常情况下第 7 轮整个布局只用了 5.5 分钟。布局布线结束后再打开虚拟机。
- 上板步骤（第 5 节第 5～8 步）本轮先不做，等协调者看过布线后的时序再定。
- **补充（2026-11-26 23:10）**：要定位拥塞在哪个模块，请 Windows Codex 回传以下内容。
  1. **第 9 轮未布网的模块分布**：用已经备份的第 9 轮未布网清单（`logbackup/before-round10/place_route`），按网名的层次前缀统计条数，输出到 `artifacts/round9/unrouted-by-module.txt`，每行一个前缀和条数，按条数从多到少排序。统计两级：
     - 先按 `u_soc/u_gpu/u_core/` 下一级（`u_texture`、`u_setup` 等）和 `u_soc/` 下一级（`u_cpu`、`u_mem` 等）；
     - 再对条数最多的 3 个模块展开下一级。
     另附 50 条未布网的原名作为样例。
  2. **第 10 轮**：布线结束后（不管成功还是失败），按同样的方法统计未布网；回传失败报告中的 `Use of CLMA`、`Use of CLMS` 等全部 `Use of` 行；如果布通了，回传第 6e 节的全部时序内容。
  3. **第 10 轮 clk_mem**：最差 50 条 setup 路径（起点、终点、裕量、逻辑级数），用综合报告或布局后报告都可以。

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
