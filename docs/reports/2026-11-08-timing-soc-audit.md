# 卡 68 R2 整片时序与拥塞审计（2026-11-08）

- 数据分支 `origin/win/20261108-68-soc-v021-full`=`a5d08903812061a894dd8cdfff970fc77eefbb0d`；实际构建 HEAD `49448d0c89ccecda82aa7bf23a5b9c82fdf98791`，CPU v0.21、NPU 卡63 `b5be940c`；PDS 2022.2-SP6.1 build138931，PG2L200H-6 FBB676，pre-silicon 模型。
- 约束 sys/npu/mem=125/180/125 MHz；慢角 WNS=−0.088/−0.205/−0.025 ns，违例端点=10/47/5，PDS **估算** Fmax=123.6399/173.5939/124.6106 MHz。上板可运行不等于慢角收敛。
- 以下由原文逐路径聚合：慢角 sequential setup、slack≤+0.5 ns，sys/npu/mem 各200个不同端点；列表末端仅到+0.243/+0.065/+0.237 ns，均被 top200 截断，不能视为全集。原生报告另有 NPU async recovery 50个≤+0.5 ns，单列；快角同域 setup WNS=3.048/1.910/2.982 ns，无此窗口路径。
- 表中“级/线%/F/距”为逻辑级数范围、数据走线占比范围、路径内最大数据网扇出、起终物理坐标曼哈顿距离范围（PDS坐标单位，脚本计算，非实际绕线路长）。端点数均为本次可见样本，原因和改法为**推断/待试建议**；“回收”是目标所需延迟缩减的**估算**，并非已测收益。

## 结论表

| 类别（模块/时钟） | 端点 | 最差ns | 级 / 线% / F / 距 | 原因推断 | 建议：RTL/约束/PnR | 估算回收ns | 代价 | 优先 |
|---|---:|---:|---|---|---|---:|---|---|
| 全片拥塞/三域 | — | 见各域 | CLMA87%/CLMS86% | 位置紧张；绕行比例未取得 | PnR slack_weight40→90对照；硬核列分区约束 | 收益待测 | PnR耗时/区域竞争 | P0 |
| MAC A/npu | 54 | -0.181 | 0–0 / 94.4–96.1 / 20 / 291–703 | 位置长线 | T-NPU-APM-LOCAL 正在处理；按APM列局部化 | 0.737 | FF/连线 | P0 |
| MAC P/npu | 36 | -0.138 | 0–0 / 91.1–91.6 / 1 / 433–848 | 位置长线 | T-NPU-APM-LOCAL 正在处理；sum FF贴近APM | 0.694 | 累加接口验证 | P0 |
| MAC W/npu | 46 | -0.205 | 0–0 / 95.5–96.0 / 3 / 289–674 | 位置长线 | T-NPU-APM-LOCAL 正在处理；APM旁局部FF/约束 | 0.761 | FF/APM周边竞争 | P0 |
| desc-write-addr/npu | 3 | -0.006 | 7–8 / 76.8–80.2 / 8 / 311–342 | 逻辑+长首段 | desc贴近conv_write；预计算/分级地址 | 0.562 | FF/调度改动 | P0 |
| dma-residual-unpack/npu | 6 | +0.040 | 0–3 / 86.3–94.8 / 263 / 107–535 | 扇出+绕线 | 写DMA/残差/unpack按负载分组、局部放置 | 0.516 | FF/宽总线布线 | P1 |
| nonconv-scratch/npu | 5 | -0.002 | 0–0 / 66.6–67.8 / 1 / 180–360 | DRM位置+tco | scratch读侧贴近DRM；必要时接口寄存 | 0.558 | 读延迟/控制对齐 | P0 |
| quant-param/npu | 5 | +0.013 | 0–0 / 95.8–95.9 / 8 / 642–750 | 跨区位置 | 量化bank入口贴近存储；必要时按bank寄存 | 0.543 | FF/配置时序 | P1 |
| reset async/npu | 50 | +0.126 | 0–1 / 92.5–94.7 / 312 / 487–727 | 跨区复位长线 | 按accum物理区分配既有复位副本；复核recovery | 0.430 | FF/复位释放验证 | P1 |
| schedule-control/npu | 4 | +0.007 | 5–6 / 69.5–73.6 / 73 / 35–103 | 逻辑+扇出 | 局部调度region；预计算/分级cmd_prepare | 0.549 | FF/调度改动 | P1 |
| weight-addr/npu | 12 | -0.017 | 0–1 / 90.1–96.4 / 96 / 563–916 | 跨DRM列位置 | 地址/控制按DRM片局部放置；必要时分片寄存 | 0.573 | FF/写入时序验证 | P0 |
| weight-valid/npu | 29 | -0.025 | 1–1 / 91.8–93.7 / 257 / 385–547 | 位置+高扇出 | 按DRM写片局部CE/FF；先试region | 0.581 | FF/CLM拥塞 | P0 |
| D$->E/sys | 10 | +0.187 | 5–7 / 56.7–66.1 / 139 / 82–245 | 逻辑+位置 | 冻结CPU：命中/操作数聚拢；RTL分级由用户决定 | 0.540 | 接口/旁路延迟 | P1 |
| D$->gateway/sys | 11 | +0.134 | 1–1 / 73.7–76.4 / 10 / 626–865 | 跨区位置 | 先贴近D$放gateway写侧FIFO；必要时接口寄存 | 0.593 | 区域竞争/握手改动 | P1 |
| F2->IB/sys | 8 | +0.112 | 6–6 / 71.8–72.3 / 228 / 377–408 | 逻辑+扇出 | 冻结CPU：F2/IB局部region；RTL使能分组由用户决定 | 0.615 | FF/验证 | P1 |
| I$->IB/sys | 126 | -0.088 | 5–9 / 51.8–64.5 / 52 / 137–245 | 逻辑+位置 | 冻结CPU：先region聚拢tag/IB；RTL拆预译码由用户决定 | 0.815 | 区域竞争；RTL增拍 | P0 |
| IB->D$/sys | 4 | -0.018 | 11–12 / 68.0–70.8 / 67 / 120–120 | 逻辑深+绕线 | 冻结CPU：操作数/early链分级由用户决定 | 0.745 | 流水/旁路改动 | P0 |
| IB->E/sys | 6 | +0.194 | 7–8 / 77.1–80.7 / 67 / 108–163 | 逻辑+绕线 | 冻结CPU：regfile/操作数聚拢；RTL分级由用户决定 | 0.533 | 区域/流水改动 | P1 |
| branch/other/sys | 18 | +0.090 | 2–10 / 70.5–82.6 / 108 / 72–480 | 逻辑+绕线 | 冻结CPU：分支/更新局部放置；RTL由用户决定 | 0.637 | 区域竞争 | P1 |
| tournament/sys | 17 | +0.043 | 3–3 / 85.5–87.3 / 48 / 235–277 | 位置/绕线 | 冻结CPU：回写LUTRAM局部region；RTL复制由用户决定 | 0.684 | CLMS竞争/FF | P1 |
| RND-control/mem | 12 | +0.153 | 0–9 / 63.3–96.5 / 258 / 146–622 | 扇出+绕线 | draw/copy/write按功能区局部控制 | 待测 | FF/区域竞争 | P1 |
| mem-local/mem | 36 | -0.025 | 2–4 / 63.1–95.1 / 688 / 48–1110 | 位置+绕线 | gateway读lane/FIFO聚拢；必要时读响应接口寄存 | 0.025 | 握手/延迟验证 | P0 |
| rbuf->RND/mem | 79 | +0.088 | 1–12 / 51.8–76.5 / 688 / 145–556 | 位置+部分逻辑深 | rbuf/RND入口region；长控制链单独分级 | 待测 | DRM竞争/事务对齐 | P1 |
| u_ddr3->u_ddr3/mem | 2 | -0.008 | 0–0 / 94.9–97.5 / 1 / 1460–1549 | 固定PLL远距 | 复核DDR phase-adj寄存器位置及IP约束 | 0.008 | IP固定资源限制 | P0 |
| u_ddr3->u_mem/mem | 6 | +0.193 | 4–6 / 80.9–87.8 / 539 / 156–571 | 扇出+位置 | calib_done/rvalid下游局部化 | 待测 | FF/控制时序 | P1 |
| u_eth->u_sys/mem | 8 | +0.036 | 2–4 / 81.1–94.7 / 64 / 121–733 | APB返回长线 | ETH寄存器与APB响应选择聚拢 | 待测 | 位置竞争 | P1 |
| u_mem->u_ddr3/mem | 5 | +0.194 | 1–1 / 92.7–95.4 / 2 / 533–857 | 跨区宽总线 | W RAM输出贴近DDR写数据通路 | 待测 | 位置竞争 | P1 |
| u_mem->u_eth/mem | 1 | +0.226 | 4–4 / 89.7–89.7 / 622 / 504–504 | 扇出+跨区 | 写仲裁/ETH ready链局部化 | 待测 | FF/握手验证 | P2 |
| u_mem->u_geo/mem | 4 | +0.115 | 5–5 / 64.5–64.8 / 272 / 167–173 | 逻辑+扇出 | GEO写控制靠近数据寄存器；局部CE | 待测 | FF | P1 |
| u_mem->u_npu/mem | 34 | -0.019 | 1–1 / 74.2–78.3 / 71 / 504–750 | 跨区宽总线 | rbuf输出/CDC写侧FIFO聚拢；必要时接口寄存 | 0.019 | CLMS竞争/缓冲延迟 | P0 |
| u_npu->u_mem/mem | 1 | +0.143 | 5–5 / 82.2–82.2 / 23 / 379–379 | 逻辑+跨区 | NPU AW FIFO读侧与xbar入口聚拢 | 待测 | 区域竞争 | P2 |
| u_sys->u_eth/mem | 3 | +0.131 | 10–11 / 74.5–75.6 / 104 / 786–804 | 逻辑+跨区 | APB写译码/计数器分组；先试region | 待测 | FF/计数器验证 | P1 |
| u_vin->u_sys/mem | 9 | +0.093 | 3–5 / 81.7–89.4 / 361 / 535–624 | APB返回/地址扇出 | VIN APB选择靠近响应端；局部分组 | 待测 | FF/区域竞争 | P1 |

## 拥塞与放置证据

- `resource_hier`是映射层次量：总 LUT/FF=91342/107111；PnR `resource_summary` LUT=73742+25018，CLMA=25871/30075(87%)、CLMS=8473/9875(86%)，DRM=286/415、APM=372/740；不能用57%的映射LUT占比断言布线宽松。**推断**：CLM打包/可用位置紧张比APM总数更直接限制局部化，盲目复制FF可能恶化拥塞。
- NPU LUT/FF/DRM/APM=16953/39009/122/266，其中 MAC-array=270/9388/0/256、weight-store=11/2177/96/0；RND=16785/11129/58/68；CPU=19358/12119/27/4；mem=9168/9096/4/0、DDR=4976/5200/0/0。**推断**：NPU多列APM与96个权重DRM、宽激活/权重广播和局部副本、RND与fabric宽数据选择共同争用CLM与通道；资源量不能直接归责某一热点。
- 卡68 PNG：迭代7几乎全可用区域拥塞；迭代40残余主要在网格列约25–100、行约60–200，尤其中部/中下部；迭代172显示全零。文本迭代7未布通147564/过用1103823，172通用网归零，176最终布通，167053网，路由7495.14s；**没有回传卡68原始数值网格**，不能给热点精确峰值/模块占比。
- 卡48对照=`origin/win/20261103-48-vrn-f-rnd1slim`=`42c34430d368ecd1bfb4c51009680e9ca9417567` 的 `F-cpu125m-r2`：初始网格(123列×255行，div=6)最大65在(94,208)，另有(21,202)=63、(61,97)=59；网格值合计403249、正值格20708，末次205网格全零。中部/下部热点与卡68大体重叠（**视觉推断**），无法量化热点迁移/增强；两卡最终归零也不能证明关键网未绕行。
- 卡48路由初报迭代5未布通136135/过用1016134，210轮通用网收敛，153067网、4741.98s；卡68初报迭代7且算法参数/RTL不同，轮数和早期过用量不能直接作优劣对照。层次报告卡48→68 CPU LUT/FF=15585/9564→19358/12119、NPU=16469/30874→16953/39009，RND=16802/11296→16785/11129：新增压力更像CPU/NPU而非RND面积增长（**推断**）。
- 物理定位：NPU W最差 CLMA(213,505)→APM(659,492)，仅1网4.919ns、扇出3；A(129,415)→APM(659,582)、P APM(659,582)→(231,283)，位置拉远证据明确。weight-store(291,529)→DRM(40,1194)，量化参数(339,535)→(87,37)，均应试按硬核列分区的region/PAP_LOC，先避免整块NPU塞进小矩形。
- CPU I$最差 DRM(550,156)→IB(513,319)，tco1.644ns、逻辑3.300ns/走线4.119ns，7级：需同时考虑逻辑预算；tournament(519,222)→(363,337)距离271，却走线6.692ns，说明中途LUTRAM读改写折返/绕线（**推断**），不能只看起终距离。mem gateway(231,1009)→FIFO(465,414)的中间单网5.008ns；rbuf(436,1008)→NPU FIFO(93,601)中途落到(105,1225)，为跨模块共享选择逻辑折返的直接证据。
- DDR phase-adj(669,1044)→GPLL(7,157)，单网7.451ns、扇出1；PLL固定位置需要单独核实。按卡48网格div=6粗映射，CPU tag/IB约(92,26)→(86,53)，NPU右侧APM约(110,82–97)、左侧权重DRM约(7,199)，RND copy DRM约(56,112)，DDR控制约(112,140)；与热点重叠仅为**推断**，没有模块放置图/网实际轨迹，不能确证拥塞绕行比例。

## 高扇出交集与频率路线

- `high_fanout`为device-map阶段，按去空白后的完整网名与近临界数据网求交，得到45网>32；与rtr扇出可能不同。CPU：`u_core/u_frontend/u_ib/N1515,N1607`各228，D$ `_N49868`164、`dc_early_way_hit_w[1]`139、`u_core/d_operand_addr_w[23]`67（前缀均`u_cpu/`）。
- NPU（前缀`u_npu/`）：`u_conv/N1397`261、`is_conv_r`246、`u_conv/N2095`161、`u_conv/u_conv_write/read_ptr_r[1]`129、`u_conv/cmd_prepare_w`70、`u_conv/desc_r[5]`67；`u_conv/u_datapath/u_weight_store/`下`N3,N13,N25,N85`各256，`g_bank[0].wr_addr_r[3..7]`各96；input-unpack `g_write_slice[7].capture_w`75。W/A/P最差网扇出仅3/4/1，不应当成高扇出问题修。
- 其余（完整模块前缀）：`u_rnd/cancel_region_w[6]`684、`u_mem/u_xbar/w_port_r[1]`621、`u_ddr3/u_ddrphy_top/calib_done`539、`u_vin/u_regs/apb_paddr_r[2]/[8]`361/300；`u_rnd/u_write/N61`288、`u_rnd/u_draw/N7313/N2143/N7969/N12328[4]`283/258/81/77、`u_geo/u_wr/N61`272、`u_rnd/u_blit/N909`126、`u_rnd/u_copy/g_alignment[0].source_offset_r[1]`113、`u_eth/u_regs/write_w`104；`u_mem/u_xbar/N633`153、`g_port[6].g_w_ram.read_hi_w`144；同xbar下`u_rbuf/ram_data_w[15,95,5,4,10,17,19,16]`分别73/72/72/71/69/68/68/68。复位网在rtr为312，未在high_fanout同名交集中，不冒充映射表结果。
- **频率估算**（假设路径/偏斜不变，ΔT=T旧−1000/f目标，目标slack=0）：NPU200需整体少0.5556ns，最差需回收0.7606ns；可见200个setup全要处理：W46/A54/P36（当前负10/19/11），以及weight-valid29、weight-addr12、desc3、quant5、scratch5、schedule4、DMA/残差/unpack6；另有56个可见async recovery在新周期下不满足。表中async50是≤+0.5ns窗口，目标计数额外含6个0.5–0.5556ns路径。APM局部化后必须继续看这64个setup和复位，不能据独立卡63的198.9MHz承诺整片200MHz。
- sys137.5/150分别缩短0.7273/1.3333ns，最差回收0.8153/1.4213ns；表中sys回收列按137.5计算，150再加0.6061ns。两目标均至少涉及表中全部200个端点（类别/数量同表），截断部分未知；CPU独立卡64也仅**估算**138.3MHz，故137.5先试布局/参数，150须由用户决定是否解冻CPU逻辑流水优化，不能承诺只调PnR可达。
- mem维持DDR用户时钟125MHz：当前5个setup违例＝gateway FIFO2、NPU CDC FIFO2、DDR phase-adj1；先闭合−0.025ns，现无正setup余量。sys/npu/mem快角hold最差+0.100/+0.100/+0.098ns，缩线后重看hold；另有RGMII输入慢角hold −0.242ns/5端点，独立于本次三域提频路线。

## 卡69可直接加入的导出与试验条目

- [ ] 保留当前125/180/125MHz基线；导出每个launch/capture域、每类sequential/async、双角slack≤+1.0ns的全部路径及唯一端点计数，不受200条截断；每条含逻辑/走线、扇出、起终及逐级物理坐标、launch/capture clock和完整时钟偏斜；附setup/hold/recovery/removal汇总。
- [ ] 回传初始、迭代40附近、最后残余、最终原始CongestionPlot网格与PNG，注明iteration/div/offset/坐标方向；导出网的实际路由轨迹/长度（工具支持时）及对应网表逻辑，以区分折返与资源绕行。
- [ ] 导出按CPU/NPU MAC/weight-store/quant/accum/RND/mem/DDR/ETH/VIN的放置边界、CLMA/CLMS/DRM/APM占用和区域网格拥塞统计；保留含模块着色、硬核列、坐标、热点叠加的截图，重点看NPU通道7、CPU tag/IB/predictor和两侧CDC FIFO。
- [ ] 以卡68 `-plc_decongestion 2 -slack_weight 40 -pin_cost_increasing_speed 600 -logic_optimize_lut6d_combing_strategy 0`为基线，仅改`slack_weight 90`做对照（卡48 R2省略该参数、记录默认90）；其余参数固定。再单独比较小范围局部region/PAP_LOC方案；每次记录路由耗时/过用曲线/CLM占用/三域最差路径，区域试验和参数试验分开。
- [ ] 集成T-NPU-APM-LOCAL后重跑同频整片；闭合mem与当前三域违例，再分别试sys137.5、npu200并完整导出；sys150仅在用户决定CPU路线后试。所有PAP_LOC/region Tcl语法和值由PDS工程验证，本审计不生成未经验证的约束命令。

## 复现

- 全部原始数据用`git show <上述ref>:<路径>`只读取得；卡68路径前缀`tasks/win/20261108-68-soc-v021-full/artifacts/R2/`，读取timing_summary、setup_top200、setup_top20_detail、hold_top20、routing_congestion.txt/png、high_fanout、resource_hier/summary、settings及native_reports下rtr/snr/dmr/prr/cmr.gz；卡48对应`tasks/win/20261103-48-vrn-f-rnd1slim/artifacts/F-cpu125m-r2/`的timing、resource、settings、pnr_progress及congestion网格。历史参考为`2026-11-07-timing-cpu-v021.md`、`2026-11-07-timing-npu-r5.md`、`2026-11-02-fanout-soc.md`。
- 本地脚本（按任务要求不入库）：`python3 build/soc-audit/read.py`解压；`python3 build/soc-audit/analyze.py > build/soc-audit/stats.txt`按Startpoint分块、Path Group/Type/Class及Slack分组，取tco至Data arrival数据段；物理坐标仅匹配行首CLMA/CLMS/DRM/APM/GPLL，避免把逻辑名`mem_2_1`当坐标；`python3 build/soc-audit/extra.py > build/soc-audit/extra.txt`求高扇出交集/网格统计；`write_report.py`生成表格，后附本报告分析。
- 自检：脚本聚合负slack端点与summary的sys10/npu47/mem5一致，近临界sequential各200与精简列表一致；`git diff --check`通过。仅文档改动，无RTL lint/仿真适用项，未访问仿真机或运行仿真；建议收益均待卡69实测。
