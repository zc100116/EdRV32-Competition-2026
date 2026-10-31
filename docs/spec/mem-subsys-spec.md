# 存储子系统规格

| 项 | 内容 |
|---|---|
| 版本 | v0.6 |
| 日期 | 2026-10-31 |
| 状态 | 已确认（v0.4，2026-10-29） |
| 范围 | DDR 网关、mem_xbar（含 MEM_XBAR 寄存器）、存储子系统顶层 `rtl/soc/edrv32_mem_subsys.v`；附录 A 为板级 DDR 适配器契约 |
| 关联文档 | SoC 规格 `edrv32-soc-spec.md` 3.2、4.2、5、6.3–6.5、7.1、8.4、9.1；系统子系统规格 `sys-subsys-spec.md`（S6）；DDR 带宽分析 `docs/design/2026-10-25-ddr-bandwidth-analysis.md` |

本文中"必须"表示强制要求，"应"表示推荐要求，"可"表示允许。SoC 规格已规定的条款本文只引用不重复；两者冲突时以 SoC 规格为准并提出修订。

---

## 1. 概述

| 模块 | 文件 | 时钟域 | 功能 |
|---|---|---|---|
| DDR 网关 | `rtl/mem/edrv32_mem_ddr_gw.v` | clk_sys（64 位侧）、clk_mem（256 位侧） | sys_xbar S6 的 AXI64 从口转换为 mem_xbar P2 的 AXI256 主口 |
| AXI64 异步桥 | `rtl/common/edrv32_axi_async_bridge.v` | clk_sys ↔ clk_mem | 网关 64 位侧的跨时钟域（SoC 5.2 X2），公共原语 |
| mem_xbar | `rtl/mem/edrv32_mem_xbar.v` | clk_mem | 7 主 × 1 从 AXI256 交叉开关，调度和流量控制按 SoC 6.4；MEM_XBAR 寄存器（媒体 APB 槽 8） |
| 存储子系统顶层 | `rtl/soc/edrv32_mem_subsys.v` | clk_sys、clk_mem | 连线顶层，供 SoC 顶层例化；子模块实例名必须为 `u_gw`、`u_xbar`（模块级测试按层次观察） |

clk_mem 直接使用 DDR3 IP 输出的 125 MHz 用户时钟 core_clk（板级提供），mem_xbar 到 DDR IP 之间不跨时钟域；`mem_ready_i` 取 DDR IP 的初始化完成信号（SoC 5.3）。mem_xbar 和 DDR 网关使用 `rst_mem_core_n`，媒体软复位不影响它们（系统子系统规格 2.10）。

## 2. 功能描述

### 2.1 DDR 网关

| 项 | 规定 |
|---|---|
| 地址 | 0x8000_0000–0xBFFF_FFFF 与 0xC000_0000–0xFFFF_FFFF 都映射到 DDR 物理地址 `{2'b00, addr[29:0]}`（SoC 6.3） |
| 接受的事务 | (a) 32 B 对齐的 4 拍 INCR 突发，SIZE = 3（cache 行填充和写回）；(b) 单拍，SIZE ≤ 3，地址按 SIZE 自然对齐（非缓存访问）。两类的 BURST 都必须为 INCR |
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
| 上游口 | P0–P6 各一个 AXI256 从口（SoC 4.2）；P0、P1 另有 `urgent_i`。P0 只有读通道，其余读写都有 |
| 下游口 | 一个 AXI256 主口，即 SoC 顶层 DDR 主口（SoC 3.2）：无 BREADY、无 RREADY，mem_xbar 必须随时接收 B 和 R |
| ID | 下游 ID = `{端口号[2:0], 本地 ID[0]}`；B、R 按 ID[3:1] 路由回端口 |
| 写数据 | 每个有写通道的端口有一个 16 拍 W 缓冲；一笔写事务的 W 数据全部进入缓冲后，该 AW 才参与仲裁。授权后 W 按 AW 授权顺序连续送往下游，不交织（SoC 6.4.2） |
| 写响应 | 每个有写通道的端口有一个 8 项 B FIFO，暂存下游返回、尚未被上游接收的 B |
| 在途计数 | 端口在途数（`OUTST_RD/WR[p]`，取值 0–8，0 表示该方向不授权）在上游 B 握手或 RLAST 握手时释放；全局在途数（`OUTST_TOTAL`）在下游 B 或 RLAST 到达时释放 |
| 读返回缓冲 | 容量 = `OUTST_TOTAL` 复位值 × 16 拍 = 128 拍 × 256 位，环形缓冲加事务表；读请求授权前按 LEN+1 拍预留 credit；空间按事务顺序释放：最老的事务的数据全部被上游取走后才释放它占的空间（SoC 6.4.4） |
| 令牌桶 | P2、P6：每个 clk_mem 周期加 `RATE[p]/256` 拍令牌，桶上限 32 拍，复位时为满；事务授权需要 LEN+1 拍令牌，授权时扣除；令牌不足的端口本拍不参与"低延迟"和加权轮询 |
| 紧急授权上限 | `URG_MAX` 计连续的紧急授权次数：其他端口获得授权，或 urgent 拉低时清零。达到上限后该端口仍可经第 2–5 条规则授权，这类授权不计入也不清零紧急计数 |
| 饿死计时 | 端口的队首事务每等待一个周期计数加 1，被授权时清零；超过 `STARVE_CYC` 进入第 3 优先级。多个端口同时饿死时，在这些端口之间轮转选择（不按等待时间长短） |
| 赤字轮询 | 事务授权扣 LEN+1 拍额度；权重为 0 的端口不参与加权轮询（仍受 1–3 条约束）。补额度：当至少一个参与者本拍可以授权、但所有可授权的参与者额度都不足其队首的 LEN+1 时，给全部参与者各加 `WEIGHT[p] × 16` 拍；参与者 = `WEIGHT` ≠ 0 且有合法完整队首的端口（含暂时被在途上限、credit、令牌或方向阻塞的端口）；没有端口可授权时不补。额度上限 255。全局在途饱和时，暂时受阻但仍有额度的端口不会在本轮补足，各端口的份额只是近似按权重分配，系统联调后依据真实流量再评估 |
| 违规检测 | 跨 4 KiB、地址非 32 B 对齐：丢弃事务，读返回 LEN+1 拍 SLVERR、写收齐 W 后返回 SLVERR，记录错误寄存器并置 IRQ_STAT.ERROR（SoC 6.4.3）。AXI256 的 LEN 只有 4 位，不存在 LEN > 15 的情况 |
| 统计 | 每端口和全局计数器见 4.1；32 位饱和计数（计满停在 0xFFFF_FFFF），WAIT_MAX 为 16 位饱和。事务数和拍数按读、写分别计数，在下游 AR/AW 握手时计数；等待周期从事务成为可仲裁队首起，到下游握手为止，含容量不足和选中到握手之间的周期 |

## 3. 接口

### 3.1 存储子系统顶层 `edrv32_mem_subsys`

| 信号组 | 方向 | 时钟域 | 说明 |
|---|---|---|---|
| `clk_sys_i`、`clk_mem_i` | 输入 | — | |
| `rst_sys_n_i`、`rst_mem_core_n_i` | 输入 | 各域 | 来自系统子系统 reset_ctrl |
| `gw_*` | 从侧，AXI64 五通道 | clk_sys | 接 sys_xbar S6（系统子系统 `s6_*`） |
| `p0_*`、`p0_urgent_i` | 从侧，AXI256 读 | clk_mem | DISP |
| `p1_*`、`p1_urgent_i` | 从侧，AXI256 读写 | clk_mem | VIN（写：摄像头和 NPU 输入通道；读：内存源） |
| `p3_*`、`p4_*`、`p5_*` | 从侧，AXI256 读写 | clk_mem | NPU、RND、GEO |
| `eth_*` | 从侧，AXI256 读写 | clk_mem | ETH（独占 P6） |
| `ddr_*` | 主侧 | clk_mem | SoC 顶层 DDR 主口（SoC 3.2），信号名不变 |
| `xbar_apb_*`、`pmon_apb_*` | 从侧，APB | clk_mem | 媒体 APB 槽 8、9（系统子系统 media_apb 的对应 psel 位） |
| `irq_mem_xbar_o` | 输出 | clk_mem | PLIC 源 15（经系统子系统的电平同步，SoC 5.2 X3） |

各端口的 AXI256 信号名按 SoC 4.2，前缀为端口名。

## 4. 寄存器

两个模块都使用 SoC 7.1 公共布局（0x000–0x07C）；下表只列私有寄存器。未列出的偏移读为 0、写忽略。

### 4.1 MEM_XBAR（媒体 APB 槽 8）

ID = 0x0008_0001。公共寄存器：CTRL 读为 0、写忽略；STATUS 由内部状态计算：BUSY = 任一端口有待仲裁的事务、W 正在向下游发送、下游有在途事务或读返回缓冲非空，IDLE = 非 BUSY，ERROR = IRQ_STAT.ERROR；ERR_CODE 等于 ERR_TYPE；DESC_BASE、DESC_COUNT、DOORBELL、DONE_COUNT、PERF 读为 0、写忽略；IRQ_STAT 只用 bit1 ERROR。寄存器块忽略 `pstrb`，按整字写（SoC 4.3）。

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x100 | OUTST_TOTAL | RW | 8 | [3:0] 下游在途总数上限（1–8） |
| 0x104 | URG_MAX | RW | 8 | [7:0] |
| 0x108 | STARVE_CYC | RW | 256 | [15:0] |
| 0x10C | DIR_BATCH | RW | 4 | [7:0] |
| 0x110 | STAT_CTRL | WO | — | bit0 SNAPSHOT：所有统计计数器同一拍锁存到 0x400 起的读寄存器，锁存的是该拍更新前的值；bit1 CLEAR：所有统计计数器清零，CLEAR 优先于同拍的递增。两位同时写 1 时先锁存后清零 |
| 0x120 | ERR_PORT | RO | 0 | 最近一次违规的端口号 |
| 0x124 | ERR_ADDR | RO | 0 | 最近一次违规的地址 |
| 0x128 | ERR_TYPE | RO | 0 | bit0 CROSS_4K 跨 4 KiB，bit1 预留（读为 0），bit2 MISALIGN 未对齐（可同时置位）；写 IRQ_STAT.ERROR 清零时一并清除 |
| 0x200 + 0x20·p | OUTST_RD[p] | RW | SoC 6.4.5 | [3:0]，0–8；p = 0–6 |
| 0x204 + 0x20·p | OUTST_WR[p] | RW | SoC 6.4.5 | [3:0]，0–8 |
| 0x208 + 0x20·p | WEIGHT[p] | RW | SoC 6.4.5；P2 为 0 | [3:0]；P2 的权重不使用 |
| 0x20C + 0x20·p | RATE[p] | RW | P2 26，P6 13，其余 0 | [8:0]，单位 1/256；只对 P2、P6 有效（26/256 ≈ 10%，13/256 ≈ 5%） |
| 0x400 + 0x20·p | RD_TXN[p] | RO | 0 | 快照值：授权的读事务数（下游 AR 握手） |
| 0x404 + 0x20·p | RD_BEAT[p] | RO | 0 | 快照值：授权的读拍数（ARLEN + 1 之和） |
| 0x408 + 0x20·p | WAIT_MAX[p] | RO | 0 | 快照值：最长等待周期 |
| 0x40C + 0x20·p | WAIT_SUM[p] | RO | 0 | 快照值：累计等待周期 |
| 0x410 + 0x20·p | URG_CNT[p] | RO | 0 | 快照值：紧急授权次数 |
| 0x414 + 0x20·p | WR_TXN[p] | RO | 0 | 快照值：授权的写事务数（下游 AW 握手） |
| 0x418 + 0x20·p | WR_BEAT[p] | RO | 0 | 快照值：授权的写拍数（AWLEN + 1 之和） |
| 0x500 | DIR_SWITCH | RO | 0 | 快照值：读写换向次数 |
| 0x504 | DS_BUSY | RO | 0 | 快照值：下游有在途事务的周期数 |
| 0x508 | WINDOW_CYC | RO | 0 | 快照值：上次 CLEAR 以来的周期数 |

参数寄存器在运行中可写，新值从下一次授权判定起生效。

## 5. 行为与时序

1. **复位**：`rst_mem_core_n` 有效期间，mem_xbar 不发出任何下游事务；DDR 网关 256 位侧同样保持空闲（SoC 5.3）。
2. **写完成**：上游端口的 B 响应在下游 B 返回后发出；下游 B 表示数据已被 DDR 控制器接收，其后发出的读一定读到该数据（SoC 4.2）。
3. **事务边界**：mem_xbar 以事务为仲裁粒度；一笔写事务的 W 拍在下游连续发出。

## 6. 错误处理

| 错误 | 检测 | 上报 | 恢复 |
|---|---|---|---|
| DDR 网关收到不支持的事务 | 网关 64 位侧 | 该事务返回 SLVERR | 无需恢复 |
| mem_xbar 上游违规 | 端口入口 | SLVERR、ERR_* 寄存器、IRQ_STAT.ERROR、PLIC 源 15 | 软件写 IRQ_STAT 清除 |
| 下游返回 SLVERR/DECERR | R/B 通道 | 原样转回上游 | 由上游处理 |

## 7. 性能与资源指标

| 项 | 要求 |
|---|---|
| clk_mem | 125 MHz 时序收敛 |
| mem_xbar 下游利用 | 在仿真 DDR 模型的同行顺序读流量下（模块级测试激励），有效带宽 ≥ 模型数据线带宽的 90% |
| 网关延迟 | 在下游零等待时，CPU cache 行读从 S6 AR 到最后一个 R 拍不超过 [待定] 个 clk_sys 周期（开发初值：由实现报告，C-W2 之后定稿） |
| 资源 | DDR 网关 + mem_xbar ≤ 8K LUT（SoC 9.3）；读返回缓冲使用 DRM，W 缓冲使用分布式 RAM |

## 8. 验证要点

见 `docs/testplan/mem-subsys-testplan.md`。必须覆盖：网关两类合法事务和非法事务；mem_xbar 每条调度规则、令牌桶、饿死保护、读写分组、在途上限、读返回缓冲在 R 反压下不丢数据、违规检测；统计计数器的快照、清零和饱和。

## 9. 待定事项

| # | 项 | 开发初值 | 定稿依据 |
|---|---|---|---|
| 1 | 网关延迟指标 | 实现报告值 | C-W2 后的系统级综合 |
| 3 | 板级适配器地址单位、控制器读写顺序 | 见附录 A | DDR IP 文档 + 上板实验 |
| 4 | 仿真 DDR 模型时序参数 | testplan 2.3 | 上板 EDTM 带宽实测后校准 |

## 10. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-31 | v0.6 | 删除 PERF_MON（原 2.3、4.2、错误处理两行、待定 2）和 P6 仲裁（原 2.4）：ETH 独占 P6；DDR 带宽由 xbar 统计计数器/EDTM 观测。原因：正式构建不需要 DDR 压测，省约 3.8K LUT/9 APM，并去掉其控制信号的高扇出（设计记录 2026-10-31-b3f-area-timing A；用户确认 2026-10-31） |
| 2026-10-26 | v0.1 | 初稿。用户确认：一份规格；板级适配器契约写附录并做 Linux 单元测试 + 上板验证；统计计数器 32 位饱和、快照 + 清零；PERF_MON 含流量发生、读校验、延迟直方图；仿真 DDR 模型为简化时序模型；clk_mem 直接使用 DDR IP core_clk |
| 2026-10-26 | v0.1 | 用户确认，状态改为已确认 |
| 2026-10-27 | v0.2 | 汇总开发中经问答确认的事项（M-R1–M-R4、M-V1、M-A1、M-T1、M-I1，DRR 两项由用户 2026-10-26 确认）：1 节子模块实例名；2.1 BURST 只接受 INCR；2.2 B FIFO、在途计数释放时点与 0–8 范围、读返回缓冲按序释放、令牌桶复位为满、URG_MAX 连续计数规则、饿死端口轮转、DRR 补额度规则与份额近似说明、删除 LEN > 15 违规、统计时点；2.3 混合模式累加器、LFSR 多项式与 SEED = 0、伪随机地址改为乘法缩放；4.1 寄存器位宽、公共寄存器语义、SNAPSHOT/CLEAR 时点、ERR_TYPE bit1 预留；4.2 公共寄存器语义、BASE/SIZE 实现位；附录 A 地址位、W 连续契约、B/R 响应 |
| 2026-10-27 | v0.2 | 用户确认，状态改为已确认 |
| 2026-10-27 | v0.3 | 随 SoC 规格 v0.9（用户确认）：P1 增加读通道（VIN 内存源，设计记录 `2026-10-27-image-path.md` Q7），`OUTST_RD[1]` 复位值 2（SoC 6.4.5） |
| 2026-10-29 | v0.4 | 4.1、2.2：每端口统计的事务数和拍数拆成读、写两组（RD_TXN/RD_BEAT 取代 TXN_CNT/BEAT_CNT，新增 WR_TXN 0x414、WR_BEAT 0x418），供 B2 调试工具实时显示各端口读写带宽（用户确认 2026-10-29） |
| 2026-10-31 | v0.5 | 7：W 缓冲（每口 16 × 288）改用分布式 RAM，读返回缓冲仍用 DRM；读延迟和保持语义不变。依据设计记录 `docs/design/2026-10-31-drm-lutram.md` 方案 B（每个 W 缓冲由 4 DRM 降为 0）；用户确认 |
| 2026-10-29 | v0.4 | 寄存器回填（B2-1f 调查，与 RTL 一致，用户确认 2026-10-29）：4.1 WEIGHT[P2] 复位 0、RATE 除 P2/P6 外复位 0；ERR_TYPE 位域命名 CROSS_4K、MISALIGN |

---

## 附录 A：板级 DDR 适配器契约

文件 `fpga/rtl/edrv32_fpga_ddr_adapter.v`，由板级顶层例化，连接 SoC 顶层 DDR 主口（SoC 3.2）与紫光 DDR3 IP 的用户端口（端口名以 IP 端口模板为准，见 `fpga/ip/` 中的 DDR3 IP 创建说明，板级阶段补写）。

| 项 | 规定 |
|---|---|
| 时钟 | IP 的 core_clk（125 MHz）同时作为 clk_mem 输出给 SoC；适配器内无跨时钟域 |
| 地址 | SoC 字节地址的 `[29:2]` 送 IP 的 `axi_*addr[27:0]`（IP 地址单位 4 B）**[待定]**：依据待 DDR IP 文档和上板实验确认 |
| AW/AR/W | 直通；`awlen/arlen` 4 位不变；IP 的自动预充电位 `axi_awuser_ap`/`axi_aruser_ap` 固定为 0 **[待定]**（上板对照实验后定）。IP 写数据口没有 WVALID/WLAST，适配器依赖 mem_xbar 的契约：AW 握手后该事务的 W 拍连续提供（2.2 写数据） |
| B 合成 | BVALID = IP 的 `axi_wusero_last`，按其 `wusero_id` 生成一个 B 响应（BRESP = OKAY）；RRESP 固定为 OKAY。前提：IP 内部按序执行读写，使"B 之后的读能读到该写"成立 **[待定]**（DDR IP 文档 + 上板实验确认） |
| R | IP 读数据直通 SoC 的 R 通道（两侧都无反压） |
| 初始化 | IP 初始化完成信号作为 `mem_ready_i` 送 SoC |
| 验证 | Linux：按 IP 端口模板写 IP 端口行为模型 `verif/models/` 中，对适配器做单元测试；上板：DDR 写读校验（板级程序）和 EDTM 带宽统计（Windows 任务卡） |
