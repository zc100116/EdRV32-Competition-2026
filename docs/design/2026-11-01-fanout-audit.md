# 全芯片高扇出审计（卡 23 PDS Device Map 数据）

## 背景和问题

卡 23 的 B3R 布局布线用了 4 h 21 min（卡 21 是 40 min），clk_mem 最差裕量只有 +0.003 ns。T-RNDROUTE 对 RND 做了读数据寄存和高扇出网络复制，卡 24 用户观察到 B3R 布线明显变快。本记录把同样的检查扩展到全芯片，找出其余的大扇出网络并分级。

## 数据来源

- `tasks/win/20261031-23-b3-converged/artifacts/{b3r,b3n,b3v}/high_fanout.txt`（win 分支 `origin/win/20261031-23-b3-converged`）：Device Map 的 Reset / CE / Other 三张表。
- 同目录的 `timing_setup_top20_detail.txt`、`timing_near_setup.txt`：判断这些网络是否位于临界路径上。
- 卡 23 的 RTL 是 T-RNDROUTE 之前的版本，RND 部分以卡 24 回传的表为准。
- 以下排除了 DDR IP 内部网络、时钟网络、常量网络。表中网络名是综合后的名字，`N…` 一类已对照 RTL 定位的写明了来源；尚未定位的标"待定位"。

卡 23 各时钟域裕量：

| 工程 | clk_sys 100 MHz | clk_mem 125 MHz | clk_npu 150 MHz | clk_pix |
|---|---|---|---|---|
| B3R | 0.416 | **0.003** | — | 5.365 |
| B3N | 0.698 | 0.349 | **−0.078** | — |
| B3V | 0.796 | 0.433 | — | 7.366 |

## 分级结果

### P1：在临界路径上，或位于裕量最小的时钟域

| # | 网络（扇出） | 模块/时钟 | 来源与问题 | 建议 |
|---|---|---|---|---|
| 1 | `u_mem/u_xbar/u_rbuf/pending_error_r`（B3R 270，B3N 797，B3V 317） | mem_xbar / clk_mem | `edrv32_mem_xbar_rbuf.v:111`：`pending_data_w = pending_error_r ? {last, 2'b10, 256'b0} : ram_data_w`。错误时把数据清零，这个 256 位选择器直接串在"读缓冲 DRM → 各主设备"路径上。B3R 最差的 20 条路径大多是 rbuf DRM → `u_rnd/u_copy/source_word_r`（0.003–0.18 ns），其中一条直接经过该网络（0.145 ns，走线 2.80 ns） | mem-subsys-spec 只要求 SLVERR 体现在 RRESP 上，不要求错误拍的数据为 0。去掉数据清零，只保留 RRESP。这样可以减少约 256 个 LUT，并从读数据路径上去掉一级逻辑 |
| 2 | RND 余量（B3R）：`u_rnd/N585_1` 1033（同步复位/取消）、`N1350` 784（CE）、`blend_tag_w[1:0]` 743/673、`u_draw/N4018` 667、`pipe_tag_r[5][31]` 562、`N771` 560、`u_copy/state_r_reg[3]` 554、`source_aligned_r` 545、`window/row_addr_r[1:0]` 499/474、`geometry/sample_w` 440（临界路径 0.114 ns）、`write_beat_r` 140（走线 3.08 ns，到 xbar W RAM，0.087 ns） | RND / clk_mem | T-RNDROUTE 只处理了其中一部分（报告 `2026-11-01-rnd-route.md` 记为未解决的有 N585_1、N6114、N4018、N771、N94 和 state_r） | 等卡 24 的 B3R 高扇出表出来后，再决定第二轮复制哪些 |
| 3 | `u_mem/u_xbar/g_port[6].w_addr_w[3:0]`（417–576） | mem_xbar / clk_mem | `edrv32_mem_xbar.v:521`：`w_addr_w = w_active_r ? w_index_r + 4'd1 : 0` 是组合逻辑，直接作为 288 位宽 LUTRAM 的读地址，每一位都驱动全部 LUTRAM 单元。端口 2/4/5/6 的 `w_read_w` 也有 288 扇出 | 下一地址提前一拍算好放进寄存器，并按 64 位分片复制 |
| 4 | NPU：`u_npu/N30` 811（同步复位，推测为 soft_reset/cancel 合并）、`u_conv/N75` 477、`u_regs/perf_clear_r` 477、`conv_start_w` 423、`u_writeback/rd_en_w` 512、`param_rd_en_w` 432、`serial_valid_r` 319 | NPU / clk_npu（−0.078） | 卡 23 唯一的违例端点是 `weight_r`，已在卡 24 中修复；这些网络是下一批可能出问题的 | 先看卡 24 的 clk_npu 结果：还违例就复制前 4 个；已经满足就不动 |

### P2：所在时钟域有裕量，但大扇出把布线拉散（影响布线时间和拥塞）

**模式 A：寄存器块的软清零/软复位，一个位驱动整个模块的计数器和状态**

| 网络（扇出） | 模块 |
|---|---|
| `u_vin/u_regs/N172` 949、`u_vin/g_channel[0]/N291` 836 | VIN |
| `u_eth/u_regs/N8` 784、`N342` 352、`u_eth/clear_w` 513（`clear_regs_r`）、`u_eth/N21` 376 | ETH |
| `u_disp/N120` 721、`N9` 670、`u_disp/u_regs/N16` 706、`soft_clear_w` 472 | DISP |
| `u_mem/u_xbar/u_regs/N68` 446，以及 N141…N652 共 7 个、各 428（推测为每端口一组的性能计数清零） | mem_xbar 寄存器块 |
| `u_mem/u_gw/N131` 497–620 | DDR 网关（待定位） |
| `u_geo/N161` 483 | GEO（待定位） |
| `u_npu/u_regs/perf_clear_r` 477、`soft_reset_w` 302 | NPU |
| `u_sys/u_i2c/N52` ~370、`u_sys/u_clint/N22` 347 | 系统外设（待定位） |

建议：清零/软复位寄存器按使用它的子单元复制（`syn_preserve`），每份只驱动本子单元，时序语义不变。这和 T-RNDROUTE 的做法相同。

**模式 B：APB 本地地址寄存器做读数据选择**

`u_mem/u_xbar/u_regs/apb_paddr_r[2]` 538、ETH 350、VIN 350。这是 SoC 4.3 规定的本地寄存器，扇出来自读数据多路选择，属于正常现象，暂不处理。

**模式 C：CPU（clk_sys 0.42–0.80 ns，临界路径上没有这些网络）**

| 网络（扇出） | 来源 |
|---|---|
| `u_frontend/u_ib/write_ptr_r[1:0]` 900（B3V） | 指令缓冲 4 项 × 179 位的写选择 |
| `u_csr/N426` 868 | 10 个 64 位计数器的同步控制 |
| `e_record_r[0][141]` 772 | 执行级记录中的一个位（待定位） |
| `u_frontend/N396`、`N452` ~720 | 前端（待定位） |
| `e_operand_load_w` 589（CE） | 执行级 |
| 预测器 `N8063`/`N8074` 512（CE）、`N203`/`N303` 512（复位） | BTB 表项 |
| icache `hit0_w` 614、`tag_write_w` 530、`victim_r` 516、有效位清零 3 × 512 | icache |
| dcache `N786` 645 | dcache |

只有在提高 clk_sys 频率时才需要处理，当前不动。

### P3：不处理

- PIX `advance_filter1_r[2]`/`advance_filter2_r[2]` 880：已经是 4 份副本，clk_pix 裕量 5–7 ns。
- VIN/ETH/GEO/RND/NPU 中 256/288 扇出的 CE 网络：256 位数据加 32 位选通的寄存器使能，宽度决定，不是问题。
- DDR IP 内部网络（`ddrphy_calib_top/N10` 2715、`prefetch_fifo/rst` 1990、`calib_done` 539）：厂商 IP，不改。

## 卡 24 B3R 综合与 Device Map 复核（win aa76c028，布局布线前）

**RND（T-RNDROUTE 之后）**：RND 在 Other 表中扇出 ≥ 300 的网络从 38 个降到 33 个，CE 表中从 10 个降到 8 个。

- 已消失：`blend_tag_w[1:0]`（743/673）、`pipe_tag_r[5][31]`（562）、`source_aligned_r`（545）、参数捕获 CE `N1350`（784）、`u_copy/state_r_reg[3]`（554）。
- 仍在（右侧为卡 23 名 → 卡 24 名，扇出）：
  - 同步复位 `N585_1` → `N493_1`（1033 → 1050）
  - blit 装载状态驱动的 draw CE `N6114` → `N794`（727 → 737）
  - `N4018` → `N4175`（667 → 725）
  - `N771` → `N866`（560 → 608）
  - window 驱动的 copy CE `N94` → `N182`（528）
  - window 的 `N6308`（504）、`row_addr_r[1:0]`（490/478）、`row_addr_r[3]`（322）
- 变大：`command_r[8]` 416 → 585，`command_r[16]` 398 → 441。
- 不变：顶层 FSM `state_r_reg[13]/[5]/[7]`（528/426/329）、geometry `sample_w`/`aa`/`group_start`/`N2198`（441/374/367/348）、copy `source_words_r[0]`/`target_words_r[1:0]`（440/408/404）、decode `N169` 379、blur `shadow_r` 373、`cancel_w_cpy` 354（工具自动复制）。

**综合估算的最差路径**（`.snr`）：clk_sys 0.728 ns，共 10 级：`u_ib/read_ptr_r`（扇出 289，1.21 ns）→ 译码 → 非法指令判断 → `redirect_w`（43）→ `u_frontend/_N361972`（扇出 784，1.34 ns）→ icache 数据 RAM 的 CEB。也就是说，CPU 提频的第一条瓶颈本身就是大扇出。

**PDS 表的覆盖范围**：Other 表只列全芯片前 100 个网络（B3R 的门槛约为 300），扇出 100–300 的网络看不到。完整普查要另做。

## 范围修正（用户 2026-11-01）

所有有风险的大扇出都要处理，不能因为当前时序有裕量就放过。原因：最终整体上板布线时布局会变化，CPU 还要优化和提频。上文"P2/P3 暂不处理"的结论作废，只有位宽决定的数据 CE（256/288）和厂商 IP 内部网络保留不改，并说明原因。

## 决策

讨论中。建议拆成三个任务：

| 任务 | 范围 |
|---|---|
| T-FANOUT-RND | 上述 RND 剩余网络。PDS 自动名不能直接对应 RTL，先由 Windows Codex 在综合门级网表中查出每个网络的驱动和负载，再按子单元复制或提前一拍算好 |
| T-FANOUT-SOC | mem_xbar：读错误不清零数据、W RAM 地址寄存并复制、寄存器块按端口清零；各寄存器块的软清零/软复位复制（ETH、DISP、VIN、GEO、NPU、DDR 网关、I2C、CLINT）；APB 本地地址寄存器的读选择改成两级；NPU 控制网络；PIX 副本负载不均 |
| T-FANOUT-CPU | redirect → 前端（784）与 IB 读/写指针（289/900）、`e_record_r[0][141]` 772、前端 N396/N433 713、CSR N426 868 与 656、`e_operand_load_w` 589、`e_advance_w` 313、预测器 4 × 512、icache 的 hit/tag_write/victim/写使能/有效位清零（512–613）、dcache N786 645 与 2 × 512。属于关键模块，由协调者逐行评审 |

每个任务都先用 Yosys 对本范围做一次扇出 ≥ 128 的普查，补上 PDS 表看不到的部分。规格不变（只做复制、寄存和去掉多余逻辑；CPU 如果需要增加流水级，另行提出）。

## 状态

讨论中。
