# B3F 面积与时序优化（RND 优先）

| 项 | 内容 |
|---|---|
| 日期 | 2026-10-31 |
| 状态 | 讨论中 |
| 关联 | rnd-spec v0.3、设计记录 2026-10-31-rnd-v2、cache-spec、mem-subsys-spec；卡 21（`win/20261031-21-b3-rerun-eth`）、卡 22（`win/20261031-22-b3-rnv` 4c976d59） |

## 背景和问题

- 卡 22 布线前（Device Map，PDS 2022.2-SP6.1，PG2L200H-6）：B3R/B3N/B3V LUT = 82411/64136/62877。
- RND 2.0 使 B3R 增加 17.3K LUT、11.3K FF、68 APM；RND 合计 35181 LUT / 26013 FF / 150 APM / 64.5 DRM，超出 rnd-spec 第 7 节预算（32K / 130 / 66）。
- 用户反馈：B3N、B3V 单轮布局布线迭代 < 1 分钟，B3R 单轮 5–6 分钟。
- B3F 按各工程模块直接相加估算（估算，mem 按端口数取 14.5K）：LUT ≈ 121K（75%）、APM ≈ 487（66%）、DRM ≈ 290（70%）、FF ≈ 116K（36%）。卡 21 B3VN 84K LUT（53%）已出现布线拥塞。

## 约束

- clk_mem 125 MHz；RND 逐位结果与参考模型一致（rnd-spec 2.2–2.6）。
- rnd-spec 7：既有命令 RN-18 周期不增加；G1 峰值 62.5 Mpx/s、G4 125 Mpx/s 写在规格中，降低需改规格并经用户确认。
- 资源决策以 PDS 实测为准，Yosys 只作参考。

## 数据

### RND 层次（卡 22 综合层次表，B3R）

| 单元 | LUT | FF | APM | DRM | 说明 |
|---|---:|---:|---:|---:|---|
| draw 自身（v1 alpha 两 lane 通路 + v2 接入） | 9038 | 7092 | 47 | 36 | 卡 21 为 7237 LUT；DRM 为 2 bank ×（2 源 + 2 next + result + target） |
| geometry（G1） | 8760 | 5430 | 30 | 0 | 2 lane × 4 子列 = 8 列，每列 4 圆（48 位）+ 3 边（51 位）加法和比较 |
| affine window（G3） | 4619 | 2338 | 1 | 4 | 源窗口 32 块 tag/命中/替换 |
| affine filter（G4） | 374 | 1002 | 35 | 0.5 | 双线性单 lane |
| copy | 3264 | 1339 | 2 | 4 | 256 位任意字节对齐搬运 |
| blur | 2281 | 2727 | 7 | 0 | |
| alpha | 611 | 1617 | 22 | 1 | |
| blit | 1251 | 531 | 4 | 16 | |
| 其他（fill/read/write/regs/decode/round_row） | ~1.5K | | | | |

### B3R 高扇出（卡 22 Device Map）

| 网络 | 扇出 | 含义 |
|---|---:|---|
| `u_rnd/command_r[16]` | 2733 | AA 位，几何每列的 `aa_w ? :` 选择 |
| `u_geometry/N1218` | 2723 | 几何全局推进使能（advance，背压冻结整条流水） |
| `u_filter/advance_w` | 1094 | 双线性全局推进使能 |
| `u_rnd/state_r[5]`、`N1349` | 814、800 | 顶层状态广播 |
| `u_alpha/tag_r[8][*]`、`valid_r[8]` | 490–622 | 混合结果标签广播 |
| `u_copy/src_addr_r[0..4]`、`dst_addr_r[0..3]` | 350–605 | 256 位字节移位器选择 |
| `u_window/row_addr_r[*]` | 480 | 源窗口行地址 |

数千扇出的使能和选择位叠加在 8 列 50 位宽加法阵列上（B3R 共 25083 个 LUT6CARRY），是 R 迭代慢的直接原因；N、V 没有同类结构。

### RND 时间花在哪（卡 21 B3R `lvgl_split.tsv`，RND v1）

| 场景 | RND ms/帧 | RND 周期 | 读等待 | 写等待 | 判断 |
|---|---:|---:|---:|---:|---|
| ALL 平均 | 11.9 | 1.35M | 0.28M | 0.19M | |
| Moving wallpaper | 13.1 | 1.31M | 0.60M | 0.43M | 等 DDR 约 79% |
| Screen sized text | 20.1 | 2.38M | 1.91M | 0.67M | 基本在等 DDR（字形读） |
| Containers / overlay / scrolling / opa_layer | 69–140 | 8.4–16.2M | 0.4–0.6M | 0.35–0.6M | 计算受限，约 0.1 px/拍，主要是阴影模糊，不是 2 px/拍混合 |

结论（推断，需仿真确认）：大多数场景里 RND 的瓶颈是 DDR 等待或模糊，alpha 通路两 lane 的峰值很少用满。

G1 收益（设计记录 rnd-v2，估算）：弧场景 260667 px/帧，两 lane 计算 4.2 ms，软件 84 ms；单 lane 计算约 8.3 ms，仍可消除约 75 ms。

## 可选方案（RND）

节省量均为按结构推算的估算，最终以 PDS 为准。

### 第 1 档：不改规格、不改功能，主要解决拥塞和时序

| # | 做法 | 估计效果 |
|---|---|---|
| R1 | 几何、双线性改为"有效位流水 + 输出缓冲（深度≥流水级数，按余量发起）"，去掉冻结整条流水的全局 advance 使能；背压时不丢数据，满足 5.2 | 去掉 2.7K/1.1K 扇出网络；LUT 基本不变，FF +几百 |
| R2 | 命令开始时把 AA/LINE/TRIANGLE 模式位和各元素 dx/dy 锁存到几何本地寄存器，每拍不再从 1024 位参数总线经选择器取值 | 去掉 `command_r[16]` 2.7K 扇出和参数总线每拍选择，LUT −0.5~1K |
| R3 | 几何里的常数乘（STEP 2–14）改为移位加，确认不占 APM | APM −20~30（RND 回到 ≤130） |
| R4 | 源窗口命中比较拆成两级（卡 22 −0.104 路径）；draw `sample_addr_r` 扇出拆级（卡 21 11 级） | 时序 |
| R5 | copy 的 32 字节移位器改为两级（32 位字级 + 字节级），选择位寄存复制 | LUT −0.5~1K，去掉 600 扇出 |

### 第 2 档：改规格，结果仍逐位一致

| # | 做法 | 估计效果 | 代价 |
|---|---|---|---|
| R6 | 规格限定几何参数范围（软件保证 \|dx\|、\|dy\| 以及初值在屏幕坐标推导出的范围内），累加器 48/51 位 → 约 38–40 位 | geometry LUT/FF −20%（约 −1.8K LUT、−1K FF） | 驱动需按新范围检查后才交给硬件，超出时退回软件 |
| R7 | G1 几何改单 lane（1 px / 4 拍，31.25 Mpx/s） | LUT −4.4K、FF −2.7K、APM −15 | 弧场景约 +4 ms/帧、widgets 约 +2~4 ms/帧（估算），仍远好于软件 |

### 第 3 档：大改，需先仿真定量

| # | 做法 | 估计效果 | 代价 |
|---|---|---|---|
| R8 | alpha 通路改单 lane（125 Mpx/s） | draw 自身 LUT 约 −4K、APM 约 −24、DRM −18；连同 R7 合计 RND 约 20K LUT | 违反"RN-18 周期不增加"；需先用 RN-17/RN-18 在两种配置下对比周期，证明多数场景受 DDR 限制 |

合计估算：第 1 档 + R6 + R7 → RND 约 27K LUT、≤110 APM，回到预算内；加 R8 约 20K。

## 其他模块（B3F）

| # | 项目 | 做法 | 估计 | 需要 |
|---|---|---|---|---|
| A | DDR 流量发生器 `perf_mon`（3.8K LUT、9 APM、一个 xbar 主端口） | B3F 不放，保留在调试工程；EDTM 带宽统计不受影响 | 约 −4.4K LUT | 改 mem-subsys-spec，用户确认 |
| B | D$ valid/dirty/lru（5×512 位 FF） | 改放分布式 RAM 或 tag RAM，复位后由维护扫描器清除（约 512 拍） | 约 −4~5K LUT、−2.5K FF | 改 cache-spec，用户确认，协调者逐行评审 |
| D | 各寄存器块的 perf 统计 | 敲定功能后只保留在用的 | −0.5~1K | 最后做 |

## 时序：组合链类型（卡 21 布线后 top200、卡 22 布线前）

| 类 | 例子 | 修法 |
|---|---|---|
| T1 APB 写副作用直通数据通路 | `media_apb_async` → ETH `abort_o` → TX `rready` → xbar `rbuf` → RAM CEB（卡 22 B3V −0.792，11 级，走线 82%）；同起点到 `perf_mon/hist_r`（92 条）、xbar 寄存器块（11–12 级）、ETH `bytes_r`（15 级）；NPU `apb_bridge/request_r` → `conv/u_datapath`（69 条） | 寄存器块把写选通/地址/数据打一拍再产生副作用 |
| T2 计数器组合监听握手 | xbar `rbuf` → `perf_mon/txn_done_r`、RND `perf_r`（12 级）；`w_port_r` → `beats_r`（14 级）；`cmd_len_r` → xbar 寄存器块（16 级） | 事件先打一拍再计数 |
| T3 xbar 与主设备 valid/ready 组合往返 | RND `copy/u_row` → xbar W RAM（46 条）；`rbuf` → RND 片上 RAM | 主设备 ready/valid 由寄存器或 FIFO 余量产生 |
| T4 RND 内部 | 见 R1、R2、R4 | 同上 |
| T5 CPU | `m_instr_r → u_csr` 24 级；D$ 命中前递 → `e_record/e_value/e_pc_target` 16 级；`e_operand_a → icache lookup_bank` 13 级 | CSR 地址 E 级预译码；单独任务，协调者逐行评审 |

B3F 布局：xbar 靠近 DDR PHY 区域居中，RND、NPU 各自划区贴近 xbar。

## VN 布线失败（卡 21 工程，卡 22 补充回传 258cab83）

- 工程：B3VN（卡 21 RTL），Device Map 84432 LUT（53%）、337 APM、225 DRM。
- PnR 运行 3h26m，第 16 轮后报 `Route-0039 too congested`、`Route-0008 cannot be routed`；结束时未布通通用网络 49263 条，overused 221725。
- 未布通负载最多的网络（`artifacts/b3vn_card21_failure/failed_nets_top200.tsv`）：

| 类 | 网络（负载 / 未布通） | 对应优化项 |
|---|---|---|
| 常量 | `GND` 34330/34330、`VCC` 22108/22108 | 待查：需要 Windows 端从本地转储按负载引脚类型（LUT/APM/DRM）分类 |
| NPU 数据通路广播 | `u_accum/r4_first_r` 2048/1497、`accum_valid_w` 1141/1011、`sum_tag_w[48]` 1070/966、`quant_valid_w`、`u_window/a4_valid_r` | 同 R1：去掉全局推进/有效位广播，改有效位流水和局部复制 |
| 媒体 APB 地址 | `media_apb_paddr_w[2]` 1851/1229、`[3]` 1446/889、`[5]`、`[4]` | T1：各从设备在 APB setup 拍本地寄存 paddr，或按区域加 APB 寄存级 |
| 复位 | `rst_sys_n_w` 4392/867、`rst_mem_core_n_w` 1700/1070、`rst_mem_n_w` 1336/722、`ddrc_rstn` 862、`rst_npu_n_w` 536 | 核查数据寄存器不带复位（CLAUDE.md 5.2）；按区域复制复位（由 reset_ctrl 产生，需改系统子系统规格 2.10） |
| D$ 元数据 | `u_dcache/buffer_addr_r[13:11]` 1344/1000、`N1000`/`N996` 1024 | B |
| 流量发生器 | `u_perf_mon/soft_reset_w` 727/694、`start_w` 763/606 | A |
| xbar | `w_port_r[*]` 598、`g_port[6].w_addr_w[*]` 705（LUT RAM 写地址） | 写地址按 RAM 片复制寄存 |

- 位置抽样（同表 driver 坐标）：NPU 在 TY 145–177，xbar/APB 在 TY 97–120，D$ 在 TY 55–70；NPU 与 xbar 相距最远。
- 结论：只有 V+N（53% LUT）在没有区域规划、没有治理扇出时已无法布通。B3F（估算 75% LUT）必须先完成上述扇出治理和区域规划；已有区域规划草案 `2026-10-31-b3f-floorplan.md`（T-FP1，基于卡 10/14/15 数据）需要按卡 22 数据重做。

## 决策

- 2026-10-31 用户确认：RND 第 1 档开工（T-RNDOPT1）；第 3 档先测量（T-RNDMEAS，报告 2026-10-31-rnd-lane-util）。
- 2026-10-31 用户确认：R6（几何范围 signed36/signed24）、R7（G1 单 lane），rnd-spec v0.4；R8 暂缓，待第 1 档 + R6 + R7 的 PnR 结果。
- 待确认：A、B；VN 扇出治理各项。

## 影响

- RTL：`rtl/media/rnd/`（geometry、affine、filter、window、draw、copy）；T1–T3 涉及 `rtl/eth/`、`rtl/mem/`、`rtl/npu/` 的寄存器块和计数器。
- 规格：R6、R7、R8 改 rnd-spec 2.6/5.2/7；A 改 mem-subsys-spec；B 改 cache-spec。
- 验证：RND 全部单元测试、模块 smoke、RN-17、RN-18、RN-29 周期对比；Windows 卡重跑 B3R 测 PnR 单轮时间、资源和 WNS。
