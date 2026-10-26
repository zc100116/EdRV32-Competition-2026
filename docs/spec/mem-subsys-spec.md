# 存储子系统规格

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-26 |
| 状态 | 已确认 |
| 范围 | DDR 网关、mem_xbar（含 MEM_XBAR 寄存器）、PERF_MON、P6 口内部仲裁、存储子系统顶层 `rtl/soc/edrv32_mem_subsys.v`；附录 A 为板级 DDR 适配器契约 |
| 关联文档 | SoC 规格 `edrv32-soc-spec.md` 3.2、4.2、5、6.3–6.5、7.1、8.4、9.1；系统子系统规格 `sys-subsys-spec.md`（S6）；DDR 带宽分析 `docs/design/2026-10-25-ddr-bandwidth-analysis.md` |

本文中"必须"表示强制要求，"应"表示推荐要求，"可"表示允许。SoC 规格已规定的条款本文只引用不重复；两者冲突时以 SoC 规格为准并提出修订。

---

## 1. 概述

| 模块 | 文件 | 时钟域 | 功能 |
|---|---|---|---|
| DDR 网关 | `rtl/mem/edrv32_mem_ddr_gw.v` | clk_sys（64 位侧）、clk_mem（256 位侧） | sys_xbar S6 的 AXI64 从口转换为 mem_xbar P2 的 AXI256 主口 |
| AXI64 异步桥 | `rtl/common/edrv32_axi_async_bridge.v` | clk_sys ↔ clk_mem | 网关 64 位侧的跨时钟域（SoC 5.2 X2），公共原语 |
| mem_xbar | `rtl/mem/edrv32_mem_xbar.v` | clk_mem | 7 主 × 1 从 AXI256 交叉开关，调度和流量控制按 SoC 6.4；MEM_XBAR 寄存器（媒体 APB 槽 8） |
| PERF_MON | `rtl/mem/edrv32_mem_perf_mon.v` | clk_mem | DDR 流量发生、读回校验、带宽和延迟测量（媒体 APB 槽 9） |
| P6 仲裁 | `rtl/mem/edrv32_mem_p6_arb.v` | clk_mem | ETH 与 PERF_MON 共用 P6 的 2:1 仲裁 |
| 存储子系统顶层 | `rtl/soc/edrv32_mem_subsys.v` | clk_sys、clk_mem | 连线顶层，供 SoC 顶层例化 |

clk_mem 直接使用 DDR3 IP 输出的 125 MHz 用户时钟 core_clk（板级提供），mem_xbar 到 DDR IP 之间不跨时钟域；`mem_ready_i` 取 DDR IP 的初始化完成信号（SoC 5.3）。mem_xbar、DDR 网关和 PERF_MON 使用 `rst_mem_core_n`，媒体软复位不影响它们（系统子系统规格 2.10）。

## 2. 功能描述

### 2.1 DDR 网关

| 项 | 规定 |
|---|---|
| 地址 | 0x8000_0000–0xBFFF_FFFF 与 0xC000_0000–0xFFFF_FFFF 都映射到 DDR 物理地址 `{2'b00, addr[29:0]}`（SoC 6.3） |
| 接受的事务 | (a) 32 B 对齐的 4 拍 INCR 突发，SIZE = 3（cache 行填充和写回）；(b) 单拍，SIZE ≤ 3，地址按 SIZE 自然对齐（非缓存访问） |
| 不接受的事务 | 其他任何 LEN/SIZE/BURST 组合、或未对齐地址：不发往 DDR，返回 SLVERR（读返回 LEN+1 拍 SLVERR，写在收齐 W 后返回 SLVERR B） |
| 宽度转换 | (a) 4 拍 → 1 拍 AXI256，WSTRB 全 1；读回的 256 位按拍序拆成 4 个 64 位拍。(b) 单拍 → 1 拍 AXI256，WSTRB 只置 `addr[4:0]` 起 2^SIZE 个字节；读回取对应的 64 位通道 |
| 并发 | 读、写各至多 1 笔在途（SoC 6.3）；新的同方向事务在前一笔响应返回后才接受 |
| ID | 64 位侧的 4 位 ID 保存在网关内，响应时原样返回；256 位侧本地 ID 固定为 0 |
| 响应 | DDR 侧 RRESP/BRESP 原样转回 64 位侧 |
| CDC | 异步桥放在 64 位侧（clk_sys 进、clk_mem 出），网关转换逻辑在 clk_mem |

### 2.2 mem_xbar

端口、调度、流量控制、读返回缓冲、参数复位值按 SoC 6.4。本节补充实现约定：

| 项 | 规定 |
|---|---|
| 上游口 | P0–P6 各一个 AXI256 从口（SoC 4.2）；P0、P1 另有 `urgent_i`。P0 只有读通道，P1 只有写通道，其余读写都有 |
| 下游口 | 一个 AXI256 主口，即 SoC 顶层 DDR 主口（SoC 3.2）：无 BREADY、无 RREADY，mem_xbar 必须随时接收 B 和 R |
| ID | 下游 ID = `{端口号[2:0], 本地 ID[0]}`；B、R 按 ID[3:1] 路由回端口 |
| 写数据 | 每个有写通道的端口有一个 16 拍 W 缓冲；一笔写事务的 W 数据全部进入缓冲后，该 AW 才参与仲裁。授权后 W 按 AW 授权顺序连续送往下游，不交织（SoC 6.4.2） |
| 读返回缓冲 | 容量 = `OUTST_TOTAL` 复位值 × 16 拍 = 128 拍 × 256 位；读请求授权前按 LEN+1 拍预留 credit，数据被上游取走后释放（SoC 6.4.4） |
| 令牌桶 | P2、P6：每个 clk_mem 周期加 `RATE[p]/256` 拍令牌，桶上限 32 拍；事务授权需要 LEN+1 拍令牌，授权时扣除；令牌不足的端口本拍不参与"低延迟"和加权轮询 |
| 饿死计时 | 端口的队首事务每等待一个周期计数加 1，被授权时清零；超过 `STARVE_CYC` 进入第 3 优先级 |
| 赤字轮询 | 每轮给各端口加 `WEIGHT[p] × 16` 拍额度，事务授权扣 LEN+1 拍；权重为 0 的端口不参与加权轮询（仍受 1–3 条约束） |
| 违规检测 | 跨 4 KiB、LEN > 15、地址非 32 B 对齐：丢弃事务，读返回 LEN+1 拍 SLVERR、写收齐 W 后返回 SLVERR，记录错误寄存器并置 IRQ_STAT.ERROR（SoC 6.4.3） |
| 统计 | 每端口和全局计数器见 4.1；32 位饱和计数（计满停在 0xFFFF_FFFF） |

### 2.3 PERF_MON

PERF_MON 是命令式引擎：软件配置寄存器后写 CTRL.START，运行完 `TXN_COUNT` 笔事务后置 IRQ_STAT.DONE 回到 IDLE；CTRL.ABORT 按 SoC 7.1 规则停止。没有分配 PLIC 中断源，软件轮询 STATUS/IRQ_STAT。

| 功能 | 规定 |
|---|---|
| 模式 | 0 顺序读；1 顺序写；2 读写混合（每 16 笔中读 `RW_RATIO` 笔，按固定交错顺序） |
| 区域 | `BASE`（4 KiB 对齐的 DDR 物理地址）起 `SIZE` 字节（512 B 的倍数）；地址走到区域末尾回到 `BASE` |
| 突发 | 长度 `BURST_LEN`（1–16 拍）；每笔不跨 4 KiB（遇边界时截短该笔） |
| 地址模式 | 0 顺序；1 伪随机：每笔起始地址 = `BASE` + (LFSR 输出 mod 区域中 512 B 块数) × 512 B，LFSR 种子为 `SEED` |
| 在途数 | 读、写各至多 `OUTSTANDING` 笔（1–4），同时受 mem_xbar `OUTST_RD/WR[6]` 约束 |
| 写数据图样 | 每拍第 i 个 32 位字 = （该字的字节地址）XOR `SEED` |
| 读校验 | `CHECK_EN`=1 时逐拍比较读数据与上述图样（模式 0 用于校验模式 1 写入的数据）；记录错误拍数和第一个错误拍的字节地址 |
| 测量 | 完成事务数、拍数、运行周期数（START 到 DONE）；读延迟 = AR 握手到首个 R 拍的 clk_mem 周期数，记录 min、max、累计和 16 格直方图（格宽 `HIST_WIDTH` 周期，最后一格收纳所有更大值） |

所有结果计数器为 32 位饱和计数，START 时清零。

### 2.4 P6 仲裁

ETH 和 PERF_MON 共用 P6：AR、AW 各自按事务轮询仲裁（本地 ID：PERF_MON 为 0，ETH 为 1，作为 P6 的本地 ID 位），B、R 按本地 ID 路由。W 跟随 AW 授权顺序。

## 3. 接口

### 3.1 存储子系统顶层 `edrv32_mem_subsys`

| 信号组 | 方向 | 时钟域 | 说明 |
|---|---|---|---|
| `clk_sys_i`、`clk_mem_i` | 输入 | — | |
| `rst_sys_n_i`、`rst_mem_core_n_i` | 输入 | 各域 | 来自系统子系统 reset_ctrl |
| `gw_*` | 从侧，AXI64 五通道 | clk_sys | 接 sys_xbar S6（系统子系统 `s6_*`） |
| `p0_*`、`p0_urgent_i` | 从侧，AXI256 读 | clk_mem | DISP |
| `p1_*`、`p1_urgent_i` | 从侧，AXI256 写 | clk_mem | VIN |
| `p3_*`、`p4_*`、`p5_*` | 从侧，AXI256 读写 | clk_mem | NPU、RND、GEO |
| `eth_*` | 从侧，AXI256 读写 | clk_mem | ETH（经 P6 仲裁） |
| `ddr_*` | 主侧 | clk_mem | SoC 顶层 DDR 主口（SoC 3.2），信号名不变 |
| `xbar_apb_*`、`pmon_apb_*` | 从侧，APB | clk_mem | 媒体 APB 槽 8、9（系统子系统 media_apb 的对应 psel 位） |
| `irq_mem_xbar_o` | 输出 | clk_mem | PLIC 源 15（经系统子系统的电平同步，SoC 5.2 X3） |

各端口的 AXI256 信号名按 SoC 4.2，前缀为端口名。

## 4. 寄存器

两个模块都使用 SoC 7.1 公共布局（0x000–0x07C）；下表只列私有寄存器。未列出的偏移读为 0、写忽略。

### 4.1 MEM_XBAR（媒体 APB 槽 8）

ID = 0x0008_0001。CTRL.ENABLE、START、DOORBELL 等命令式位不使用；IRQ_STAT 只用 bit1 ERROR。

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x100 | OUTST_TOTAL | RW | 8 | 下游在途总数上限（1–8） |
| 0x104 | URG_MAX | RW | 8 | |
| 0x108 | STARVE_CYC | RW | 256 | |
| 0x10C | DIR_BATCH | RW | 4 | |
| 0x110 | STAT_CTRL | WO | — | bit0 SNAPSHOT：所有统计计数器同一拍锁存到 0x400 起的读寄存器；bit1 CLEAR：所有统计计数器清零。两位同时写 1 时先锁存后清零 |
| 0x120 | ERR_PORT | RO | 0 | 最近一次违规的端口号 |
| 0x124 | ERR_ADDR | RO | 0 | 最近一次违规的地址 |
| 0x128 | ERR_TYPE | RO | 0 | bit0 跨 4 KiB，bit1 LEN 超限，bit2 未对齐（可同时置位）；写 IRQ_STAT.ERROR 清零时一并清除 |
| 0x200 + 0x20·p | OUTST_RD[p] | RW | SoC 6.4.5 | p = 0–6 |
| 0x204 + 0x20·p | OUTST_WR[p] | RW | SoC 6.4.5 | |
| 0x208 + 0x20·p | WEIGHT[p] | RW | SoC 6.4.5 | P2 的权重不使用 |
| 0x20C + 0x20·p | RATE[p] | RW | P2 26，P6 13 | 单位 1/256；只对 P2、P6 有效（26/256 ≈ 10%，13/256 ≈ 5%） |
| 0x400 + 0x20·p | TXN_CNT[p] | RO | 0 | 快照值：授权事务数 |
| 0x404 + 0x20·p | BEAT_CNT[p] | RO | 0 | 快照值：授权拍数 |
| 0x408 + 0x20·p | WAIT_MAX[p] | RO | 0 | 快照值：最长等待周期 |
| 0x40C + 0x20·p | WAIT_SUM[p] | RO | 0 | 快照值：累计等待周期 |
| 0x410 + 0x20·p | URG_CNT[p] | RO | 0 | 快照值：紧急授权次数 |
| 0x500 | DIR_SWITCH | RO | 0 | 快照值：读写换向次数 |
| 0x504 | DS_BUSY | RO | 0 | 快照值：下游有在途事务的周期数 |
| 0x508 | WINDOW_CYC | RO | 0 | 快照值：上次 CLEAR 以来的周期数 |

参数寄存器在运行中可写，新值从下一次授权判定起生效。

### 4.2 PERF_MON（媒体 APB 槽 9）

ID = 0x0009_0001。

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x100 | MODE | RW | 0 | 2.3 模式 |
| 0x104 | BASE | RW | 0 | [11:0] 只读 0 |
| 0x108 | SIZE | RW | 0x1000 | [8:0] 只读 0 |
| 0x10C | BURST_LEN | RW | 16 | 1–16 |
| 0x110 | ADDR_MODE | RW | 0 | 0 顺序，1 伪随机 |
| 0x114 | RW_RATIO | RW | 8 | 0–16 |
| 0x118 | TXN_COUNT | RW | 0 | 本次运行的事务数 |
| 0x11C | OUTSTANDING | RW | 4 | 1–4 |
| 0x120 | SEED | RW | 0 | |
| 0x124 | CHECK_EN | RW | 0 | |
| 0x128 | HIST_WIDTH | RW | 16 | 直方图格宽（周期），≥ 1 |
| 0x200 | TXN_DONE | RO | 0 | |
| 0x204 | BEATS | RO | 0 | |
| 0x208 | CYCLES | RO | 0 | |
| 0x20C | LAT_MIN | RO | 0xFFFF_FFFF | |
| 0x210 | LAT_MAX | RO | 0 | |
| 0x214 | LAT_SUM | RO | 0 | |
| 0x218 | READ_CNT | RO | 0 | 已完成读事务数（延迟平均值 = LAT_SUM / READ_CNT） |
| 0x21C | ERR_BEATS | RO | 0 | 校验错误拍数 |
| 0x220 | FIRST_ERR_ADDR | RO | 0 | |
| 0x300–0x33C | HIST[0..15] | RO | 0 | |

配置寄存器的非法值（BURST_LEN 为 0 或大于 16、OUTSTANDING 为 0 或大于 4、SIZE 为 0、TXN_COUNT 为 0、HIST_WIDTH 为 0）在 START 时检测：不发出事务，置 IRQ_STAT.ERROR，ERR_CODE = 1。

## 5. 行为与时序

1. **复位**：`rst_mem_core_n` 有效期间，mem_xbar 和 PERF_MON 不发出任何下游事务；DDR 网关 256 位侧同样保持空闲（SoC 5.3）。
2. **写完成**：上游端口的 B 响应在下游 B 返回后发出；下游 B 表示数据已被 DDR 控制器接收，其后发出的读一定读到该数据（SoC 4.2）。
3. **事务边界**：mem_xbar 以事务为仲裁粒度；一笔写事务的 W 拍在下游连续发出。
4. **ABORT（PERF_MON）**：停止发出新事务，等待所有在途事务的 B/R 全部返回后回到 IDLE。

## 6. 错误处理

| 错误 | 检测 | 上报 | 恢复 |
|---|---|---|---|
| DDR 网关收到不支持的事务 | 网关 64 位侧 | 该事务返回 SLVERR | 无需恢复 |
| mem_xbar 上游违规 | 端口入口 | SLVERR、ERR_* 寄存器、IRQ_STAT.ERROR、PLIC 源 15 | 软件写 IRQ_STAT 清除 |
| 下游返回 SLVERR/DECERR | R/B 通道 | 原样转回上游 | 由上游处理 |
| PERF_MON 配置非法 | START 时 | IRQ_STAT.ERROR、ERR_CODE = 1 | 改配置后重新 START |
| PERF_MON 读校验不符 | 每个 R 拍 | ERR_BEATS、FIRST_ERR_ADDR（不是错误中断，属于测量结果） | — |

## 7. 性能与资源指标

| 项 | 要求 |
|---|---|
| clk_mem | 125 MHz 时序收敛 |
| mem_xbar 下游利用 | 在仿真 DDR 模型的同行顺序读流量下，PERF_MON 测得的有效带宽 ≥ 模型数据线带宽的 90% |
| 网关延迟 | 在下游零等待时，CPU cache 行读从 S6 AR 到最后一个 R 拍不超过 [待定] 个 clk_sys 周期（开发初值：由实现报告，C-W2 之后定稿） |
| 资源 | DDR 网关 + mem_xbar ≤ 8K LUT（SoC 9.3）；PERF_MON ≤ 2K LUT [待定]；读返回缓冲和 W 缓冲使用 DRM |

## 8. 验证要点

见 `docs/testplan/mem-subsys-testplan.md`。必须覆盖：网关两类合法事务和非法事务；mem_xbar 每条调度规则、令牌桶、饿死保护、读写分组、在途上限、读返回缓冲在 R 反压下不丢数据、违规检测；PERF_MON 三种模式、伪随机地址、读校验发现错误、直方图边界；统计计数器的快照、清零和饱和。

## 9. 待定事项

| # | 项 | 开发初值 | 定稿依据 |
|---|---|---|---|
| 1 | 网关延迟指标 | 实现报告值 | C-W2 后的系统级综合 |
| 2 | PERF_MON LUT 上限 | 2K | 综合结果 |
| 3 | 板级适配器地址单位、控制器读写顺序 | 见附录 A | DDR IP 文档 + 上板实验 |
| 4 | 仿真 DDR 模型时序参数 | testplan 2.3 | 上板 PERF_MON 实测后校准 |

## 10. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-26 | v0.1 | 初稿。用户确认：一份规格；板级适配器契约写附录并做 Linux 单元测试 + 上板验证；统计计数器 32 位饱和、快照 + 清零；PERF_MON 含流量发生、读校验、延迟直方图；仿真 DDR 模型为简化时序模型；clk_mem 直接使用 DDR IP core_clk |
| 2026-10-26 | v0.1 | 用户确认，状态改为已确认 |

---

## 附录 A：板级 DDR 适配器契约

文件 `fpga/rtl/edrv32_fpga_ddr_adapter.v`，由板级顶层例化，连接 SoC 顶层 DDR 主口（SoC 3.2）与紫光 DDR3 IP 的用户端口（端口名以 IP 端口模板为准，见 `fpga/ip/` 中的 DDR3 IP 创建说明，板级阶段补写）。

| 项 | 规定 |
|---|---|
| 时钟 | IP 的 core_clk（125 MHz）同时作为 clk_mem 输出给 SoC；适配器内无跨时钟域 |
| 地址 | SoC 30 位字节地址换算为 IP 的 `axi_*addr[27:0]`；地址单位 **[待定]**，由 DDR IP 文档确认后写入本表 |
| AW/AR/W | 直通；`awlen/arlen` 4 位不变；IP 的自动预充电位 `axi_awuser_ap`/`axi_aruser_ap` 固定为 0 **[待定]**（上板对照实验后定） |
| B 合成 | 每收到 IP 的 `axi_wusero_last`，按其 `wusero_id` 生成一个 B 响应（BRESP = OKAY）。前提：IP 内部按序执行读写，使"B 之后的读能读到该写"成立 **[待定]**（DDR IP 文档 + 上板实验确认） |
| R | IP 读数据直通 SoC 的 R 通道（两侧都无反压） |
| 初始化 | IP 初始化完成信号作为 `mem_ready_i` 送 SoC |
| 验证 | Linux：按 IP 端口模板写 IP 端口行为模型 `verif/models/` 中，对适配器做单元测试；上板：PERF_MON 写入后读回校验、带宽和延迟测量（Windows 任务卡） |
