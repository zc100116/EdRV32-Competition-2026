# SoC 总线与外设资源、时序及 IP 质量评估（S-1）

## 1. 背景和问题

GPU SoC 卡 107 第 10 轮未布通，第 11 轮仍在实现；本记录寻找 CPU/GPU 运算核心之外的资源和布线优化机会，并评估独立 IP 发布的边界。结论是：GPU 版 mem_xbar 的统计和调度精简已经兑现，继续删调度的空间很小；下一步应集中看 rbuf 的地址选择、宽数据使能、GPU 配置快照和寄存器计数结构。ETH 的主要 FIFO 已经使用 RAM，不能再把它们当成 FF 阵列计算收益。

### 1.1 数据来源、版本与复现

| 标记 | commit / 条件 | 原始位置 |
|---|---|---|
| G | 结果分支 `96fd08ecee9c771f840f1ccad75a62bcb55d54fc`；报告自述 upstream `b2a27314`、local run `ced62bb5`；2026-11-27 15:30:41 +08:00 | `origin/win/20261124-107-gpu-board:tasks/win/20261124-107-gpu-board/artifacts/round11/` |
| V | 卡 75 结果记录代码 `42b3fa1615af0330b1a4aabcdbe06a0dbfee3fa5`；2026-11-16 完成 PnR | `tasks/win/20261114-75-soc-fan2-post/artifacts/` 和同目录上一级 `result.md` |
| R | 本次 RTL / spec 审查基线 `eaee4c832594ef1fcc39726dd3d6ba60c0a49ef2` | 当前树 `rtl/`、`docs/spec/` |

两次工具均为 PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676。G 的层次资源和时序来自综合 ADS，V 层次资源也来自综合 `.snr`，V 时序来自布线后 STA；二者时序不能直接作优化前后对照。R 的源码结构解释资源原因，不等于声称 R 和 Windows local run 的逐位映射完全相同。

复现（只读、不运行仿真或综合）：

```sh
git rev-parse HEAD origin/win/20261124-107-gpu-board
python3 tools/soc/eval/profile.py
# 查看报告原文；脚本固定使用 G 的完整结果 commit，不随远端引用移动。
git show 96fd08ecee9c771f840f1ccad75a62bcb55d54fc:tasks/win/20261124-107-gpu-board/artifacts/round11/timing_summary.txt
git show 96fd08ecee9c771f840f1ccad75a62bcb55d54fc:tasks/win/20261124-107-gpu-board/artifacts/round11/setup_top200_clk_mem.txt
```

### 1.2 层次资源画像

下表全部为 G/V `resource_hier.txt` 的实测映射计数；顺序为 LUT / FF / LUTRAM / DRM36K 当量。LUT 已包含 LUTRAM，不能再相加；DRM 0.5 是 18K 当量，不表示占用半个可自由摆放的硬宏。父行包含子行，不累计父子；“—”表示该版本没有对应实例。省略复位复制和 RAM 厂商内部层次；脚本保留所有模块路径，GPU 根前缀统一去掉 `u_soc/`。

| 层次 | GPU LUT / FF / LUTRAM / DRM36K | 视觉 LUT / FF / LUTRAM / DRM36K |
|---|---:|---:|
| `u_aud` | 639 / 847 / 0 / 0.5 | — |
| `u_aud/u_dma` | 295 / 425 / 0 / 0 | — |
| `u_aud/u_fifo` | 109 / 177 / 0 / 0.5 | — |
| `u_aud/u_i2s` | 20 / 41 / 0 / 0 | — |
| `u_aud/u_play_enable` | 0 / 2 / 0 / 0 | — |
| `u_aud/u_regs` | 200 / 194 / 0 / 0 | — |
| `u_aud/u_underrun` | 1 / 4 / 0 / 0 | — |
| `u_disp` | 1693 / 2168 / 0 / 4 | 2458 / 3339 / 0 / 8 |
| `u_disp/u_blue` | 44 / 59 / 0 / 0 | 51 / 62 / 0 / 0 |
| `u_disp/u_control` | 7 / 19 / 0 / 0 | 7 / 19 / 0 / 0 |
| `u_disp/u_dma` | 216 / 134 / 0 / 0 | 192 / 139 / 0 / 0 |
| `u_disp/u_fifo1_ram` | — | 0 / 0 / 0 / 4 |
| `u_disp/u_fifo_ram` | 0 / 0 / 0 / 4 | 0 / 0 / 0 / 4 |
| `u_disp/u_green` | 42 / 54 / 0 / 0 | 43 / 56 / 0 / 0 |
| `u_disp/u_params` | 2 / 12 / 0 / 0 | 3 / 56 / 0 / 0 |
| `u_disp/u_perf0` | 37 / 96 / 0 / 0 | 37 / 96 / 0 / 0 |
| `u_disp/u_perf1` | 37 / 96 / 0 / 0 | 35 / 96 / 0 / 0 |
| `u_disp/u_read1_cnt` | — | 8 / 30 / 0 / 0 |
| `u_disp/u_read_cnt` | 8 / 30 / 0 / 0 | 8 / 30 / 0 / 0 |
| `u_disp/u_reader` | 197 / 257 / 0 / 0 | 338 / 396 / 0 / 0 |
| `u_disp/u_red` | 39 / 53 / 0 / 0 | 43 / 56 / 0 / 0 |
| `u_disp/u_regs` | 397 / 368 / 0 / 0 | 524 / 494 / 0 / 0 |
| `u_disp/u_scan` | 280 / 550 / 0 / 0 | 852 / 1007 / 0 / 0 |
| `u_disp/u_scan1_fifo` | — | 56 / 351 / 0 / 0 |
| `u_disp/u_scan_fifo` | 311 / 351 / 0 / 0 | 184 / 351 / 0 / 0 |
| `u_disp/u_timing` | 56 / 22 / 0 / 0 | 55 / 22 / 0 / 0 |
| `u_disp/u_underflow` | 2 / 4 / 0 / 0 | 1 / 4 / 0 / 0 |
| `u_disp/u_underflow1` | — | 2 / 4 / 0 / 0 |
| `u_eth` | 4519 / 4666 / 76 / 3 | 4415 / 4666 / 76 / 3 |
| `u_eth/u_mdio` | 60 / 110 / 0 / 0 | 60 / 110 / 0 / 0 |
| `u_eth/u_regs` | 1214 / 1271 / 0 / 0 | 1199 / 1271 / 0 / 0 |
| `u_eth/u_rx` | 776 / 983 / 0 / 0 | 762 / 983 / 0 / 0 |
| `u_eth/u_rx_buffer` | 0 / 0 / 0 / 1 | 0 / 0 / 0 / 1 |
| `u_eth/u_rx_fifo` | 61 / 94 / 0 / 0.5 | 59 / 94 / 0 / 0.5 |
| `u_eth/u_rx_front` | 45 / 34 / 0 / 0 | 45 / 34 / 0 / 0 |
| `u_eth/u_rx_packets` | 81 / 7 / 76 / 0 | 81 / 7 / 76 / 0 |
| `u_eth/u_rx_write` | 507 / 488 / 0 / 0 | 507 / 488 / 0 / 0 |
| `u_eth/u_tx` | 1255 / 1027 / 0 / 1 | 1210 / 1027 / 0 / 1 |
| `u_eth/u_tx_done` | 1 / 4 / 0 / 0 | 1 / 4 / 0 / 0 |
| `u_eth/u_tx_fifo` | 53 / 104 / 0 / 0.5 | 54 / 104 / 0 / 0.5 |
| `u_eth/u_tx_front` | 86 / 54 / 0 / 0 | 86 / 54 / 0 / 0 |
| `u_eth/u_write_dma` | 334 / 389 / 0 / 0 | 305 / 389 / 0 / 0 |
| `u_gpu/u_apb_async` | 9 / 213 / 0 / 0 | — |
| `u_gpu/u_axi_async` | 382 / 160 / 309 / 0 | — |
| `u_gpu/u_core/u_regs` | 1353 / 1911 / 0 / 0 | — |
| `u_mem` | 3701 / 4163 / 432 / 4 | 9751 / 9150 / 849 / 4 |
| `u_mem/u_gw` | 763 / 1116 / 0 / 0 | 767 / 1116 / 0 / 0 |
| `u_mem/u_gw/u_bridge` | 96 / 484 / 0 / 0 | 96 / 484 / 0 / 0 |
| `u_mem/u_xbar` | 2938 / 3021 / 432 / 4 | 8984 / 8002 / 849 / 4 |
| `u_mem/u_xbar/u_rbuf` | 1719 / 1574 / 0 / 4 | 2179 / 1232 / 0 / 4 |
| `u_mem/u_xbar/u_regs` | 116 / 53 / 0 / 0 | 3389 / 3621 / 0 / 0 |
| `u_mem/u_xbar/u_sched` | 25 / 8 / 0 / 0 | 410 / 151 / 0 / 0 |
| `u_sys` | 1872 / 1643 / 8 / 20 | 1931 / 1640 / 8 / 20 |
| `u_sys/u_clint` | 274 / 242 / 0 / 0 | 277 / 242 / 0 / 0 |
| `u_sys/u_gpio` | 234 / 204 / 0 / 0 | 235 / 204 / 0 / 0 |
| `u_sys/u_i2c` | 57 / 79 / 0 / 0 | 57 / 79 / 0 / 0 |
| `u_sys/u_media_apb_async` | 10 / 224 / 0 / 0 | 10 / 216 / 0 / 0 |
| `u_sys/u_media_apb_bridge` | 90 / 127 / 0 / 0 | 86 / 123 / 0 / 0 |
| `u_sys/u_media_apb_decoder` | 78 / 8 / 0 / 0 | 118 / 8 / 0 / 0 |
| `u_sys/u_plic` | 185 / 172 / 0 / 0 | 205 / 184 / 0 / 0 |
| `u_sys/u_rom` | 62 / 30 / 0 / 4 | 63 / 30 / 0 / 4 |
| `u_sys/u_sram` | 140 / 37 / 0 / 16 | 140 / 37 / 0 / 16 |
| `u_sys/u_sys_apb_bridge` | 95 / 127 / 0 / 0 | 98 / 127 / 0 / 0 |
| `u_sys/u_sys_apb_decoder` | 54 / 0 / 0 / 0 | 53 / 0 / 0 / 0 |
| `u_sys/u_sys_xbar` | 364 / 138 / 0 / 0 | 362 / 138 / 0 / 0 |
| `u_sys/u_sysctrl` | 25 / 68 / 0 / 0 | 25 / 68 / 0 / 0 |
| `u_sys/u_uart` | 192 / 143 / 8 / 0 | 191 / 143 / 8 / 0 |

补充细分：G 的 W RAM 三个实例 `u_mem/u_xbar/g_port[2..4].g_w_ram.u_ram` 各为 144 LUT / 288 FF / 144 LUTRAM / 0 DRM；这些 288 FF 是 RAM 包装输出级，不能当成 16 深度 W 存储阵列。G 网关桥的 AR/AW/W/R/B 子 FIFO 分别为 21/86、21/86、6/144、40/150、8/18（LUT/FF），均无 LUTRAM/DRM。GPU AXI256 桥 AW/W/B/AR/R 各为 31/32/16、159/32/145、15/32/1、33/32/18、144/32/129（LUT/FF/LUTRAM），已用分布式 RAM。

### 1.3 占比与已经兑现的节省

口径 A 为 `u_mem + u_sys + u_eth + u_disp`，GPU 另计 AUD；口径 B 再加入 GPU 的 regs、AXI/APB 异步桥，排除 GPU 运算核心及 CPU。分母一律取层次报告的整片综合数，不能混用 `.dmr`：G 98,023 LUT / 143,393 FF；V 89,046 LUT / 109,700 FF。

| 版本 / 集合 | LUT | FF | LUTRAM | DRM36K | 整片 LUT 占比 | 整片 FF 占比 |
|---|---:|---:|---:|---:|---:|---:|
| GPU A | 12,424 | 13,487 | 516 | 31.5 | 12.675% | 9.406% |
| GPU B | 14,168 | 15,771 | 825 | 31.5 | 14.454% | 10.998% |
| 视觉 A（无 AUD） | 18,555 | 18,795 | 933 | 35 | 20.838% | 17.133% |

公式为 `100 × 集合计数 / 整片计数`。G `resource_summary.txt` 的 map 数为 98,019 LUT / 143,342 FF，与综合差 4 LUT / 51 FF；上述占比只使用综合层次口径。

控制集：G 综合整片 **1,953**（同 `resource_summary.txt`），但两版 `resource_hier.txt` 均没有逐模块控制集列，V 提供的资源汇总没有全片 unique control sets。故 A/B 的控制集数量和占比均为**未取得、不能由 FF 数推算**；公式应为 `|本集合实际 clock/reset/enable 组合的并集| / 1953`，而非各模块数量简单相加。高扇出表也不包含这个并集。后续 PDS 结果需按层次导出控制集及其 FF 归属，才能补齐此项；本记录不制造精确比例。

G 相比 V 的 mem：少 6,050 LUT / 4,987 FF / 417 LUTRAM；其中 xbar regs 少 3,273 LUT / 3,568 FF，sched 少 385 LUT / 143 FF。对应 GPU spec 8.3 已删除统计、令牌桶、饿死计时和加权调度，另有 7→5 端口差异；这不是待实施收益。rbuf 反而多 342 FF、少 460 LUT，说明版本/流水结构的取舍，不能归因于“端口减少必定省 FF”。DISP 少 765 LUT / 1,171 FF / 4 DRM，对应单层版和去混合，不能在 GPU 版重复申领。

### 1.4 时序画像和观测边界

G `timing_summary.txt`：clk_mem 8 ns，setup WNS +0.379 ns、TNS 0；clk_sys 8 ns，WNS −0.876 ns、TNS −441.123 ns、2,344 failing endpoints。这些是综合估计，并非第 11 轮布线成功证明。clk_mem 同域 hold −0.006 ns、157 端点也需在实现后复查。

| G clk_mem 路径（来源 `setup_top200_clk_mem.txt`） | 裕量 ns | 逻辑级 | 含义 |
|---|---:|---:|---|
| `u_mem/u_xbar/u_rbuf/received_r[2][1]` → rbuf DRM `ADDRA[12]`（rank 1–4） | +0.379 | 9 | 返回 RID 匹配/计数选取后再计算写地址，是本范围最差路径 |
| 同一起点 → DRM `ADDRA[11]`（rank 5–8） | +0.401 | 9 | 同一地址锥，不是独立问题 |
| `sent_r[3][0]` → `port_head_mask_r[3][0,3,4,7]`（rank 25–28） | +0.517 | 10 | 完成判定、队首选择组合链 |
| `skid_valid_r[1]` → DRM `CEB`（rank 29–32） | +0.578 | 9 | 端口就绪/预取资格决定 RAM 读使能 |
| ETH RX → `header_r[*]/CE`（120 个端点） | +1.186 | 见逐行报告 | 宽头寄存器装载使能扇出 |
| xbar → `cmd_len_r[0..3]/D` | +1.216 | 见逐行报告 | 事务命令控制 |

top200 中 rbuf 76 条、ETH RX 120 条、xbar 命令 4 条。AUD、DISP、gw、sys 不在这个采样中，不能把“未进入 top200”解释成已取得这些模块的最差裕量。

**clk_sys 模块路径缺口**：G 目录只有 `setup_top200_clk_mem.txt`、`setup_top200_clk_gpu.txt`，`setup_top20_detail.txt` 的路径属于 GPU；没有 clk_sys 的逐路径导出。可以报告整域 −0.876 ns，但不能断言 CLINT、PLIC 或 sys_xbar 是最差起终点。需要下一次结果附 clk_sys top200（含 sys 外设过滤导出）；这是数据待补，不是 RTL 失败推定。

V 布线后 `timing_summary.txt`：clk_sys WNS −0.546 ns / TNS −73.191 ns；clk_mem −0.218 ns / −4.297 ns。`timing_selected_modules_le_0p5.csv` 的 slow 最差 mem_xbar 路径为 DDR `calib_done/.../CLK` → rbuf DRM `.../DB0[9]`，裕量 −0.218 ns，逻辑 0.413 ns、路由 7.295 ns，说明跨区域宽数据路径的物理距离可能比逻辑精简更重要。该 CSV 不提供其他上述外设完整最差值，不能外推。

### 1.5 G 高扇出网

来源均为 G `high_fanout.txt`，名称是综合网名，不能仅凭 `Nxx` 认定 RTL 语义或时序关键性。表内有 reset、clock-enable、普通信号，负载数不可当作控制集数。

| 网（省略 `u_soc/`） | fanout | 优先检查 |
|---|---:|---|
| `u_gpu/u_core/u_regs/N21` | 1139 | GPU 配置/清零/装载控制，需 Windows 网表映射回 RTL |
| `u_eth/u_regs/N192`；`N111` | 364；233 | 寄存器组写入/清零锥 |
| `u_eth/u_write_dma/N91` | 288 | 256 位数据与 strobe 装载 |
| `u_mem/u_xbar/u_rbuf/N6519,N6515,N6042,N6037` | 各 262 | skid/pending 宽数据选择控制 |
| `u_eth/u_tx/N1631` | 259 | beat 暂存控制 |
| `u_mem/u_gw/write_take_w`；`N179` | 各 256 | 宽度转换数据暂存 |
| `u_disp/u_scan_fifo/head_load_w`；`u_disp/u_scan/N136` | 各 256 | RAM 输出/pixel beat 装载 |
| `u_aud/u_dma/N25`；`u_aud/N14` | 各 256 | DMA beat/复位负载；须区别数据 reset 和控制 reset |
| `u_eth/u_rx_write/state_r_reg [3]` | 248 | 宽写入状态使能 |
| `u_sys/u_gpio/N27` | 204 | GPIO 本地控制/去抖锥 |
| `u_eth/u_rx/N218` | 200 | 头字段接收控制 |

优先处理真实拥塞区域内的这些控制网，不盲目增加所有控制副本。时钟本身的 16,037 clk_mem、14,384 sys 全局缓冲负载由报告 Clock Signal 行给出，属于专用时钟树，不和普通 1,139 扇出网混排。

## 2. 约束

只产出设计记录与只读统计脚本，不改 RTL、规格、软件，不跑仿真/综合。建议均为待评审方案，不构成新的接口契约。遵守 CLAUDE.md §12：不建议新加超时、校验、兜底或内部重复协议检查；现有 spec 明确要求的 APB 超时、非法事务响应继续保留。共用分支只暂存本任务两个文件，不碰 C2-I3 的文件和暂存状态。

本评估引用 edrv32-soc §4–7、gpu-soc §5/6/8、mem-subsys §2/4/6、sys-subsys §2、ETH §2/4/5、DISP §2/4、AUD §2/4、DMA2D §2/5/7，以及 GPU §4。GPU spec 8.3 主表明确覆盖视觉调度；紧随其后的旧 RATE/统计表与主表冲突，记录为规格编辑残留，评估采用主表及 v0.3 变更记录，没有据旧表要求重新实现限速。

## 3. 可选方案

### 3.1 逐模块功能与资源审查

| 模块 | 资源原因与结论 | 可选优化及边界 |
|---|---|---|
| sys_xbar 364/138 | 两主设备（I$ 只读、D$ 读写）到 ROM/SRAM/CLINT/PLIC/两 APB/gw；每主每方向只一笔，已经很小 | 不应升级为任意 N×M/full AXI 交换机；发布版可将连接矩阵与地址表参数化 |
| ROM/SRAM 202/67、20 DRM | 主成本是 16 KiB Boot ROM、64 KiB SRAM 的存储；接口资源小 | 没有规格允许缩容量；不以压缩启动镜像代替硬件容量指标 |
| CLINT 274/242 | mtime、mtimecmp 各 64 位，64 位加法和比较，另有 AXI 返回 64 位寄存与事务状态 | 功能相称；mtime 每 sys 周期递增是规定，不能随意分频或改 32 位；150 MHz 时需检查真实比较路径 |
| PLIC 185/172 | 15 源 × 3 位优先级、threshold、enable/pending/claimed、同步及 claim 选择 | 仅一个 M context，已简化；GPU 只有部分源连接也不能删掉软件可写的 priority/enable 地址。压源/优先级需改 spec，收益小 |
| UART 192/143、8 LUTRAM | 16×8 TX/RX FIFO、分数波特率和移位状态；已映射分布 RAM | FIFO 数据位 256 已经不是 256 FF；保留 8N1、可编程波特率和错误语义 |
| GPIO 234/204 | 16 位寄存器 + 24 位去抖计时；板级常量输入使部分逐 pin 逻辑消失，4 个输入同步实例 | 24 位位宽不能当无用 FF 删除；引脚数/去抖位宽是独立 IP 参数候选，不是本板新增功能 |
| I2C 57/79 | 单个字节引擎复用两对引脚、16 位分频；不支持拉伸/多主/10 位地址 | 已经精简；57 LUT 不值得为布线删接口，GPU 板保留的软件寄存空间按 spec |
| 两 AXI→APB 桥、decoder | 每桥约 90 LUT/127 FF，已分开系统和媒体 | 合并可减一组事务寄存，但拉长控制跨区连线，失去媒体 CDC 边界；非短期优先 |
| DDR gw 763/1116 | 64→256 打包与 256→64 拆分、错误处理、484 FF CDC | 功能相称；浅 FIFO 与同域化可比较，不能把 CPU cache-line 4 拍能力删除 |
| xbar sched 25/8、regs 116/53 | GPU 已是 urgent→CPU→RR，固定上限、无统计 | 没有几千 LUT 可继续删，视觉版通用调度另作可选发布配置 |
| rbuf 1719/1574、4 DRM | 8 个描述符、128 beat credit、返回 RID 匹配、共享 RAM 和各端口 skid；DDR 无 RREADY | 数据主体已是 RAM；优先地址链与读控制，保留能够隔离不同端口反压的能力 |
| ETH RX 776/983 | 以太网/IP/UDP 头字段、过滤、窗口和包状态，异步前端 CRC 独立 | 部分 header 寄存使用 FF 是并行解析需要，不能整段改 RAM 后假定时序不变；字段活跃期可逐项缩短 |
| ETH TX 1255/1027 | 描述符、beat 拆字、ARP 插入、校验和和包调度；1 DRM 包缓冲 | 无 TCP/重传等多余协议栈；一拍 256 位暂存和算术不是深 FIFO |
| ETH rx_write 507/488、write_dma 334/389 | 包搬运、字节偏移、256 位数据/strobe 和 AXI outstanding | 分别负责成包与标准 DMA 发射，不能因两级都含 data 就认定重复；波形确认可共享暂存后才提 RTL 改案 |
| DISP 1693/2168、4 DRM | 单层、reader/DMA、跨域扫描、欠账及三路 TMDS | L1/alpha 已删；scan_fifo 的 351 FF 包含 256 位 RAM 输出和 FIFO 控制，不是整条扫描 FIFO 用 FF |
| AUD 639/847、0.5 DRM | 512×32 样本 RAM、256 位 DMA beat、I2S 和水位 Gray 回传 | 满足 LUT≤1K 开发预算；不能把水位回传删除，实时 urgent 依赖它 |
| DMA2D | DISP rd 216/134，ETH rd 201/116（在 TX 内）、wr 334/389，都小于 spec §7 每实例 600 LUT/800 FF 开发指标 | 通用行跨度、边缘 strobe、4 KiB 分段有规格依据；改窄数据口会牵动性能契约 |
| GPU AXI/APB CDC | 382/160/309 LUTRAM 与 9/213 | GPU 时钟不同，不能因 sys=mem 同频顺带删除这两座桥 |

#### ETH regs：1,271 FF 的组成

`rtl/eth/edrv32_eth_regs.v` 的声明位数是解释性盘点，不是映射 FF 的精确反解：

- 配置约 **570 位**：ENABLE/IRQ_EN/DESC_BASE/DESC_COUNT 为 61，MAC/IP/端口/目的地址/TX_GAP/PHY 为 253，4 个窗口 base+size 为 256。对齐常零位和不用的 IRQ 位会被综合裁掉。
- 性能计数 **11×32=352 位**（ETH spec §4.3）；另有 DONE_COUNT 32 位和四窗口 WIN_BYTES **4×32=128 位**，两者是进度/软件可见完成状态，不能当成任选诊断事件删掉。
- 状态包含 IRQ 12、ERR 2、最近 peer **96 位**；peer 是保留最近包来源，不是另存一套配置。
- APB setup 负载声明 49 位、9 组本地读地址/选择声明 **9×6=54 位**；事件 pipeline 21 位；另有命令/soft reset 分组副本。常零位裁剪、未用字段和保留复制使声明数与 1,271 不相等。

11 个 32 位可独立并行更新的 PERF 占映射 FF 的 `352/1271=27.70%`（声明计数与实测分母比较）。删除全部 PERF 也绝不等于删除整个 1.27K FF。它们目前是固定地址 ABI；改 HPM 是规格和软件变更。

#### GPU regs：1,911 FF 的组成

`rtl/gpu/edrv32_gpu_regs.v`：对象配置 live mask 64、targets 512、hit/free base 各 32、max 各 24，合计 **688 位**；工作配置与 `object_cfg_*_o` 提交快照各一份，声明 **2×688=1376 位**。PERF **9×32=288 位**，事件 staging 声明 9×3=27 位；结果为 hit/free/alive 三个 24 位计数和 2 overflow，共 **74 位**；还包括 CTRL/IRQ、描述符、DONE_COUNT、错误和 APB 本地读选 45 位等。

因此大 FF 首因是**宽配置的双份一致快照**，不是只有性能计数。提交后配置要在 valid/ready 等待期间稳定，软件仍可改下一份工作配置；单纯连线代替快照会改变事务语义。688 位转 RAM 也要求读出时序和配置接收协议协同，不可只改数组声明。

### 3.2 FIFO / rbuf / 事务能力

1. **gw 的深度 2 FIFO**：AXI64 五通道标称总 payload 宽 `49+73+6+49+71=248`，两槽 **496 bit**；映射桥共 484 FF，说明不能把“496 payload + 控制”直接当作实测。改 LUTRAM 需要保持异步读口/满空和复位契约；深度仅 2，LUTRAM 最小深度浪费且宽端口不少，未必比 FF 更省 LUT/布线。DRM 以宽度切片计，不会只耗 496/36864 块；不推荐为这点容量消耗多块硬 RAM。
2. **ETH**：512×10 TX/RX stream FIFO 均用 `async_fifo_ram` + `ram_eth_fifo`，各 0.5 DRM；RX/TX 包 buffer 各 1 DRM，RX packet metadata 用 76 LUTRAM。不存在将这几千 bit 从 FF 改 RAM 的第二次收益。小 packet queue、头字段和 beat 暂存须按访问模式区别。
3. **GPU bridge**：五个深度 8 FIFO payload `37+289+3+37+260=626 bit/槽`，总 **5008 bit** 已映射 309 LUTRAM；160 FF 主要是各 FIFO 指针、跨域同步与输出控制。删同步寄存不合法；减深度改变可吸收 burst 和吞吐。
4. **rbuf**：共享 128×259 bit RAM（4 DRM）吸收不可反压 DDR 返回。每端口 skid 声明 259 bit，五端口合计 1295 bit 的逻辑容量上限，但实测 rbuf 总 FF 1574，部分常量/通道会消失；不能直接宣称可省 1295 FF。一个共享 skid 会在一端口 RREADY=0 时堵住其他端口，违背当前隔离目标。可比较按端口分银行、精简完成/可用计数冗余、预计算返回地址，但先保留 credit、同 ID 顺序、全局顺序释放和错误响应长度。
5. **ID/突发/outstanding**：AXI64 已只用 INCR，ID 4 位、每主每方向 1 笔；AXI256 只有 1 位本地 ID + 3 位端口号、LEN 4，SIZE/BURST 已省略，未实现 LOCK/CACHE/QOS。不存在可再删的 WRAP/FIXED 引擎。GPU P0/P1 读限 4/1、P2 1/1、P3 4/2、P4 2/2、全局 8；缩成单在途降低回程 RAM 压力，却可能让 GPU 和显示争用 DDR 延迟。按 40 周期返回延迟、16 beat burst 的估算，单在途理想上限约 `16/(40+16)=28.6%` beat/clk（非实测，且定义未含命令间隔），不足以用“平均流量低”保证实时性。

### 3.3 时钟域划分

当前 clk_sys 来自系统 PLL，clk_mem 来自 DDR PHY core_clk；即使同为 125 MHz，也不能直接短接时钟或删除 CDC。以下三案是互斥架构选择：

| 方案 | 优点 | 代价 / 对 CPU 150 MHz 的影响 |
|---|---|---|
| 保持异步（推荐近期） | 保留 CPU 独立升频、DDR 初始化和软复位契约，现有接口无需改动 | 保留 gw 96/484 和 media APB 10/224 成本 |
| sys 全域使用同一 DDR core_clk，125 MHz | 可去掉 X2 与系统→媒体 APB CDC，减少往返同步周期 | CPU 被固定在 125 MHz；系统启动依赖 DDR 用户时钟的持续输出与 reset 释放。需板级确认初始化前 core_clk 行为；不能用“时钟同源”代替该事实 |
| 从可证明相位关系的时钟树生成 sys 150 / mem 125（6:5） | 保留升频目标，可考虑同步多周期/速率转换器 | 公共晶振或两个 PLL 的频率比例不保证相位；需 DDR clocking 能力、生成时钟约束及 setup/hold 分析。6:5 不是整除 enable，仍需 buffering/节拍控制；不能声称省掉全部桥 |

相同且同相时钟下“直接去桥”的**毛上限**为 **106 LUT / 708 FF**，公式 `96+10`、`484+224`（两个父层次实测）；实际还需同域 elastic/事务寄存及复位处理，净值小于上限。单纯同域化不能去 GPU、pixel、AUD 或 PHY 外部收发 CDC。IRQ 按 sys spec §2.5 明确同域源也同步，不能顺手删除。CPU 150 MHz 最保守路线保持异步，桥优化单独评估。

### 3.4 性能计数器：分散固定计数与统一 HPM

现状优点是事件本地、可同时统计所有事件、软件地址稳定；缺点是每个计数器独立加法、使能/清零组和读 mux。GPU PERF9 个、ETH PERF11 个，共 **20×32=640 位**；DISP 的两个跨域 PERF 不宜归并：PERF0 还是 BUSY/帧排空判断的一部分，Gray 源/目标和 soft-reset 基线都是功能状态。AUD 欠载是事件，不可和 FIFO 水位计数混合删减。

可选 A：维持 20 个逻辑计数器及原 ABI，只统一代码结构、合理分组，或将稀疏事件计数存 RAM 并复用加法器。优点是软件不变；但每拍可能多个事件，RAM 单写口无法同时更新全部计数，GPU pixel 还是 0–4 增量，ETH PERF9 是连续 busy cycle。没有事件到达率证明就不能时间复用，亦不建议引入队列/丢事件兜底。

可选 B：每域 4 个可选事件 32 位 HPM，软件轮换观测。按 GPU 9→4、ETH 11→4，理想 FF 毛节省 `((9−4)+(11−4))×32=384`。按每选择器 4 位事件号共 `8×4=32`，净声明位节省 **352 FF**；若每 bit 加法/使能的 LUT 成本按 0.5–1.5 作估算，毛减 `384×(0.5..1.5)=192..576 LUT`，还要扣事件 mux/增量 mux，故不能承诺净 LUT 正收益。每域保留 4 个独立 enable 也不意味着控制集少 12：实际 reset、enable 合并/拆分由映射决定，控制集收益未取得。

真正全 SoC 单块 HPM 还需精确跨域事件传送，增加连线和 CDC；本地 HPM 更符合物理布局。B 会失去 20 项同时可观测能力，必须先由用户决定修改 GPU/ETH spec §4 和驱动/性能测试；不把它列作不改软件的低风险布线修复。

### 3.5 总线拓扑

现有组织把低带宽配置限制在 APB32，CPU cache line 在 AXI64，媒体数据在 AXI256，和 DDR 用户口一致。峰值数据面 `256/8×125 MHz=4 GB/s`；若全改 64 位同频则仅 1 GB/s，已低于 GPU spec §9.1 原尺寸场景估算 1.14 GB/s，尚未扣 DDR 效率。256 位全片广播代价高，但不是靠统一成 64 位就能无损解决。

可选替代是标准 AXI4 适配层 + 内部窄命令/宽流数据、固定连接矩阵、只读端口显式裁剪；这些可减少系统特定元数据广播，保留 xbar 的 RT 仲裁与返回隔离。以接口净化为目的的全量 AXI4（增加完整 sideband、8 位 LEN、可反压 DDR 适配）可能反而增资源，应做独立 IP 外壳，板级构建仍固定不用项为常量。APB decoder 已承担共享时限和非法槽响应，不应把同一检测复制进每个寄存器块。

### 3.6 可移植性与可配置性评价

这里的“参数候选”是将来独立 IP 规格要讨论的清单，本任务没有授权把它们写入 RTL，也不保留临时试验开关。

| 独立 IP 候选 | 当前接口/可移植性 | 适合列入独立规格的参数和需要拆出的本工程约定 |
|---|---|---|
| async/sync FIFO、RAM 控制 FIFO、CDC primitives | 最适合先发布；WIDTH/DEPTH 等已有参数，纯 Verilog 核可复用 | 明确深度约束、RAM 读延迟、复位双方契约、Gray 计数接口；厂商 RAM 放 tech 包装 |
| DMA2D rd/wr | 高价值；但 AXI256 是 AXI4 子集，固定32B/4位LEN、本地1位ID | DATA/ADDR/ID width、MAX_BURST、MAX_OUTSTANDING、行参数位宽；标准 AXI4 端口壳补固定 SIZE/BURST 和 LEN 高位常零，独立说明错误/ABORT 排空 |
| AXI→APB bridge/decoder | AXI64 子集→APB4 风格，可复用 | AXI 数据宽/ID宽、APB地址宽、槽数/地址表、规格已有超时长度；PPROT 当前不暴露，需注明固定属性，而非宣称完整标准端口 |
| sys_xbar / gw | 中等；固定 2×7 连接、地址映射和 cache line 32B/4拍契约 | 地址/连接矩阵、主从数、line 大小、合法 burst 集合、单在途；避免附带 CPU/cache 专用命名 |
| mem_xbar | QoS 与不可反压 DDR 适配有展示价值，但当前非通用 full AXI4 crossbar | 端口/只读写 mask、ID、outstanding、返回容量、RT优先和调度策略。GPU 简单调度与视觉 QoS 作两个明确 profile，不能无规格地叠加大量分支 |
| CLINT / PLIC | 寄存器模型清晰，单 hart/M context；AXI64 frontend 与功能核可分 | hart/context/source/priority bits、时基、地址窗口；不要因 CLINT 名称就宣称所有平台地址/mtime时基一致 |
| UART / GPIO / I2C / MDIO | 小而完整，适合独立发布 | 时钟频率/FIFO深度、GPIO数/去抖宽度、I2C端口数/分频宽度；明确不支持的模式。GPIO输入同步、开漏IO留在接口契约，三态在板级 |
| ETH | 自包含 UDP/ARP offload 展示价值高，非通用 MAC/IP/TCP 栈 | RX窗口数、包缓存数/最大帧长、流FIFO深度、地址宽/AXI壳；本工程应用头、描述符布局、窗口与通知语义是主要耦合 |
| DISP / AUD | 数据流组件价值高；DISP是720p60 TMDS固定时序/格式，AUD为I2S固定样本格式 | 模式/像素格式/FIFO容量及I2S样本宽度/采样率候选；帧锁存、欠账、停止确认必须作为明确协议。DMA、扫描、编码器可分别发布 |
| GPU regs | 不适合以“通用APB寄存器块”独立发布，688位对象快照与GPU协议强耦合 | 属于GPU控制面示例；寄存器生成和分组mux模式可复用，不能把目标表/统计地址硬塞进通用核 |

AXI64 用标准握手但限制并发/突发和 sideband；AXI256 省略 SIZE/BURST、LEN 仅4位，DDR侧又无 RREADY/BREADY，故发布文档应写“项目 AXI 子集 + adapter 契约”，不能仅标“标准 AXI4/AXI4-Lite”。APB 有 setup/access/PREADY/PSLVERR/PSTRB，但各设备是否忽略 strobe 依规格逐项注明；GPU 的字节 mask 与 ETH 的整字写也不能统一抹平。

## 4. 决策

本次决定只完成画像与候选排序，不作架构/规格选择。建议近期保持拓扑和时钟域，先以等价结构修正宽控制路径；中期再讨论 HPM、IP 参数和时钟树。下表按资源收益与功能风险的综合优先级排序，“GPU 布通”指可直接减少本版布线负担，**不是保证布通**。所有节省都是估算或毛上限，互有重叠不能累计为交付承诺；控制集净变化均待 PDS，不能由 bank 个数代替。

| 序 | 建议及 GPU 布通标记 | 收益估算、输入/公式 | 功能/软件/spec 影响及风险 | 工作量估算 |
|---|---|---|---|---|
| 1 | **GPU 布通：rbuf 返回地址和完成链分解** | 增加每槽当前写地址寄存 `8×7=56 FF` 的一个候选，原 mux后加法改为取预算地址；目标把 rank1 的9级压到约4–6级（估算少3–5级，无ns保证）。LUT/控制集净值未取得 | 保持same-cycle DDR接收、128 credit与释放；内部改动不改ABI；风险为并发reserve/return/release一致性 | RTL+单元/模块回归 3–5人日；1次综合/PnR |
| 2 | **GPU 布通：已发现的宽装载控制按区域收敛** | 1139扇出若按4组物理分区，理想平均约 `1139/4≈285`；新增3–16个FF/每个选中控制网为试验预算（复制数输入），不宣称面积下降或控制集下降 | 只保持同D/enable/复位/有效边沿的局部复制；R已有rbuf四片valid副本，不重复盲加；先映射N21/N192到RTL确认。无软件/spec变化 | 2–4人日，结合实现报告；中低风险 |
| 3 | **GPU 布通候选：GPU targets 配置存储结构** | 最大可释放一份 targets 快照 **512 FF**；688整组是理论毛上限。若改两份16×32 LUTRAM工作/提交bank，逻辑存储1024bit，按每LUT 16–32bit估算32–64 LUTRAM，加串行读/控制；并行重建快照会吃回FF收益 | 必须保持提交一致性/等待稳定性；可能改变object_cfg传输延迟并改GPU §4接口/验证；软件寄存地址可保持。高风险，先确认接收端能按bank消费，不可直接删快照 | 5–8人日+GPU控制验证；非首轮小修 |
| 4 | 网关深2 FIFO改分布式RAM（比较项） | AR/AW/W/R/B桥484FF是全删除毛上限；若保留约100–200FF控制/读输出，净 **284–384FF** 为假设估算，不能超过484。LUTRAM按宽248×两槽、最小原语深度及端口宽切分，未取得净LUT收益 | 不改五通道次序和复位；浅RAM未必比FF快，不能保证帮助布通；不用DRM | 2–3人日+CDC/网关验证 |
| 5 | ETH/GPU每域4个HPM代替固定PERF | 毛384FF、selector扣32后 **352FF**；加法逻辑毛192–576LUT再扣mux，见3.4；控制集不承诺 | 同时观测能力下降，改ETH/GPU §4、驱动与perf测试；不得删DONE_COUNT/WIN_BYTES/功能性水位 | 3–5人日，先规格决策；中风险 |
| 6 | sys/mem真正同相同钟 | 毛上限 **106 LUT/708 FF**，扣替代同域寄存；可少CDC往返周期，不保证纳秒裕量 | 限CPU125MHz且改变启动/复位/时钟域spec §5；与CPU150MHz方向冲突；GPU bridge保留 | 3–5人日+板级clocking确认，另需实现验证；高风险 |
| 7 | 独立IP外壳与参数化 | 资源收益 **0承诺**，价值为可移植/可配置；板内固定profile应回到现有规模 | 建立明确AXI子集/adapter、RAM技术边界，参数先入独立spec；全面回归组合数上升 | FIFO/CDC 2–3人日；DMA2D/APB各3–5人日；其余分批 |
| 8 | 暂不做：压PLIC源/优先级、缩CLINT位宽、删I2C、统一64位数据面 | PLIC全部仅185LUT/172FF，I2C仅57/79，收益上限已小；64位峰值仅1GB/s | 明确的软件/实时性代价，不符合不改规格的近期目标 | 不投入实施；若将来产品profile另行讨论 |

短期清单独立列示：优先 1、2，取得 PDS 映射和实现结果后再评估 3；4 只是小容量技术映射比较，不保证正收益。已经完成的 xbar 统计删除、DISP L1 删除、ETH FIFO RAM化均不列入未来节省。

## 5. 影响

本提交仅新增本设计记录和 `tools/soc/eval/profile.py`。脚本只读 Git 报告和当前视觉卡报告，标准库、单进程、不写输入文件；未运行 RTL lint/仿真，因为无 RTL 改动且 Task 明确不需要仿真。

后续若选择 1/2：修改 `rtl/mem/edrv32_mem_xbar_rbuf_gpu.v`、对应宽控制所属 RTL，测试覆盖并发入队/DDR返回/R反压/释放及错误帧长度，规格行为不变。若选择 3：还涉及 GPU regs/object 配置接收和GPU接口规格；4 涉及 `common` FIFO/RAM包装、网关CDC回归；5 涉及 GPU/ETH规格、寄存器描述生成、驱动和性能观测程序；6 涉及 SoC §5、板级PLL/约束、复位控制和启动测试。上述实现均留给后续已批准 Task，本次没有修改这些文件。

验收命令：`python3 tools/soc/eval/profile.py` 成功输出两版表、集合占比、fanout、G top200分组与V最差已导出路径；`PYTHONPYCACHEPREFIX=build/soc-eval/pycache python3 -m py_compile tools/soc/eval/profile.py` 语法通过；`git diff --check -- docs/design/2026-11-27-soc-bus-periph-eval.md tools/soc/eval/profile.py` 无格式错误。资源表人工交叉核对 G 原始行2477–2605及 AUD/GPU regs层次；未做新的PDS实测。

## 6. 状态

**讨论中**，2026-11-27。画像和结构评估完成；收益是明确带输入的估算，未获新的RTL/规格变更决定。原始产物不足以给出模块控制集占比、G clk_sys逐模块最差起终点及top200之外的最差路径；这些项目明确为待下一轮报告补齐，不将综合估计当布线结果。
