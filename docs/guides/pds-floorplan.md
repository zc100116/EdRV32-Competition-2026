# PDS 手动布局能力与 PG2L200H 内部排布

调研日期：2026-10-28。仓库基线：`b6e17efcfe32a28b506b4f4bd51134e0de99b7b7`。
本次只读资料，没有运行 PDS，没有修改 RTL、约束或导入脚本。

**结论边界**：已经确认十个时钟区域的块坐标和资源、若干接口的 bank、
`PAP_LOC` 的寄存器实例写法，以及布局阶段确实存在时序驱动和复制。
**未取得逐实例 block/site 对照表，不能提供经过三个实例核验的精确坐标换算公式，
也不能提供 DRM/APM 全部列的块坐标。** 下文给出四个站点与区域的核对，
但它们只是范围证据，不冒充精确坐标核验；缺项均进入第 6 节。
协调者已在 Orca 问答 `msg_bbd52aa0b996` / 回复 `msg_c9684d61c125`
确认：检查指定 demo 后，查不到的按“未查到”交付，允许明确标注的候选关系。

## 资料索引与引用约定

下文 `来源编号:行号` 都指原文件的物理行号；PDF 页码指 **PDF 第几页**，
避免教程的印刷页与 PDF 页错位。厂商目录未入库，完整根路径记为：

```text
V = /home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/doc/fpga/pago_200/
R = tasks/win/20261028-04-media-cpu-probes/
D10 = V/2_Demo/4_10_timing/4_10_HDMI_IN_DDR3_HDMI_OUT/
D9  = V/2_Demo/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/
D12 = V/2_Demo/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT/
D13 = V/2_Demo/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/
DC  = V/2_Demo/5_1 双目摄像头例程/ov5640_200k/
```

| 编号 | 文件、版本或含义 |
|---|---|
| C1 | `R/artifacts/cpu/p1/native_reports/place_route/clock_utilization.txt` |
| C2 | `R/artifacts/media/native_reports/place_route/clock_utilization.txt` |
| P1 | `R/artifacts/cpu/p1/native_reports/place_route/edrv32_fpga_cpu_sys_top.prr`；2022.2-SP6.1 build 138931（第 1 行） |
| T1 | `R/artifacts/cpu/p1/setup_top20_detail.txt` |
| T2 | `R/artifacts/cpu/p1/setup_near_positive_top20_detail.txt` |
| U1 | `R/artifacts/cpu/p1/resource_summary.txt` |
| L1 | `R/artifacts/cpu/p1/logs/place_route_excerpt.txt` |
| W1 | `R/artifacts/cpu/p1/logs/warnings_detail.txt` |
| E1 | `R/artifacts/cpu/constraint_tests_excerpt.txt` |
| E2 | `R/artifacts/cpu/p3/region_failed.log` |
| F3 | `R/artifacts/cpu/p3/fdc_used.fdc` |
| B1 | `R/result.md`；环境与输入 commit 在第 5–8 行 |
| VDS | `V/4_IC_datasheet/FPGA/DS04001_Logos2系列FPGA器件数据手册.pdf`，DS04001 V1.5，2020-11-10 |
| VQ | `V/1_Demo_document/工具使用篇/02_PDS快速使用手册.pdf`，2022.8 V1.0（封面） |
| VH | `V/1_Demo_document/实验例程说明篇/教程1 盘古100K MINI 硬件指导手册-盘古676系列.pdf`；文件未标统一版本号 |
| VT | `V/1_Demo_document/实验例程说明篇/教程4 《国产FPGA权威开发指南》教材配套实验指导手册-盘古676系列.pdf`；配套实验手册，非教材正文，文件未标统一版本号 |
| VX | `V/3_Hardware/FPGA管脚分配/mini-base管脚映射.xlsx`，工作表“新底板”，按单元格引用 |

复查 PDF 可用 `/usr/bin/pdftotext -layout <PDF> <build 下的文本>`，再按 `\f`
分页；文本行号可用 `nl -ba <文件>`。本次还检查了 D10、D9、D12、D13 的
`compile/`、`device_map/`、`place_route/`、`.fdc` 与 `impl.tcl`：
`.prr` 有 IO/bank、资源、时钟和层次统计，`clock_utilization.txt` 有区域范围，
`*_pnr.netlist` 有逻辑实例/引脚连接，但未查到逐实例的块坐标列表。
例如 D10 的 `place_route/HDMI_IN_DDR3_HDMI_OUT_top_pnr.netlist:141–159`
只有 `Inst`、实例类型与 `Pin` 段；其工程把物理约束编辑入口关联到
`device_map/hdmi_ddr_ov5640_top.pcf`（`D10/HDMI_IN_DDR3_HDMI_OUT.pds:441–449`）。

## 1. 芯片内部排布（PG2L200H-6 FBB676）

### 1.1 块坐标、站点坐标与能够证明的关系

`clock_utilization.txt` 明确把区域矩形称为 **Block Scope**，顺序为
`(Xmin,Xmax,Ymin,Ymax)`；十区的坐标覆盖界限为 x=0..238、y=0..249。
这只能证明报告的块坐标域，不能证明矩形中每一点都是 CLM，也不能把空缺列解释成
可用逻辑或硬核。原点物理朝向、每格对应何种器件单元及长度单位：**未查到**。
（C1:1–25。）

时序的 `Location` 则是 `CLMA_651_781/Q0`、`DRM_490_768/QA0[4]` 等站点和站点引脚；
同一路径也出现 `IOBD_0_1386`、`IOLHR_16_1386`、`USCM_383_930`。
这些数字明显超出 Block Scope，不能直接填到 `PAP_REGION`。
（T1:11–47、188–190；E2:1194–1195。）

以下四项是“同一实例的站点 ↔ 所属时钟区域 ↔ 区域块坐标范围”的真实核对，
**不是该实例的精确块坐标**：

| 实例、封装球位 | 站点 | 报告所属区域 | 该区域块范围 | 两端证据 |
|---|---|---|---|---|
| CPU `clk_i_ibuf/opit_1`，D18 | `IOLHR_16_1386` | X0,Y4 | x 0..91，y 200..249 | P1:15；C1:5、39、53 |
| MEDIA `clk_mem_i_ibuf/opit_1`，K21 | `IOLHR_16_1080` | X0,Y3 | x 0..121，y 150..199 | `R/artifacts/media/native_reports/place_route/edrv32_fpga_media_top.prr:16`；C2:6、40、56 |
| 双目 `camera_clk_1_ibuf/opit_1`，M21 | `IOLHR_16_774` | X0,Y2 | x 0..121，y 100..149 | `DC/prj/place_route/Top.prr:24`；`DC/prj/place_route/clock_utilization.txt:7、47` |
| 双目 `camera_clk_0_ibuf/opit_1`，L22 | `IOLHR_16_786` | X0,Y2 | x 0..121，y 100..149 | `DC/prj/place_route/Top.prr:23`；`DC/prj/place_route/clock_utilization.txt:7、48` |

**推断：可检验的候选纵向比例**。令站点数字为 `s_y`，尝试
`b_y = floor(s_y / 6)`，上述四项依次得到 231、180、129、131，全部满足区域的 y 不等式。
但 `b_y = floor(s_y / 6) - 1` 同样满足四项；因此这些证据**不能确定平移量、
分段关系、原点或精确公式**。横向只有相同的 `IOLHR_16_*`，没有足够自变量。
不能把这个候选比例推广到 CLMA、CLMS、DRM、APM、USCM、IOBD。
（推导输入：上表；区域范围：C1:5–9。）

| 资源类别 | 精确的 site→block 公式及至少三个点核验 |
|---|---|
| CLMA、CLMS | **未查到**；时序有站点，区域报告只有总体范围 |
| DRM、APM | **未查到**；不能据 site x 数字直接指定区域 x |
| USCM | **未查到**；其后 `Non-IO Load Clock Region` 是负载包围框，不是 USCM 坐标 |
| IOBD、IOLHR、IOBS | **未查到**；上表仅核实了 IOLHR 所属区域 |

例如 C1:46 中 `USCM_383_930` 旁的 `(134,235,92,170)` 是
`Non-IO Load Clock Region`；把它当作该缓冲或某一个寄存器的位置，会错误建立换算关系。
（列标题见 C1:44。）

### 1.2 十个时钟区域与资源

下表前四个资源列原样来自 C1:16–25，矩形来自 C1:5–9。
LUT6 容量列为**推算**：`4 × (CLMA + CLMS)`，每 CLM 四个 LUT6 的依据是 VDS 第 10 页。
DRM 列是 36K 物理块口径；一块可以独立配置成两个 18K 或一个 36K（VDS 第 11 页）。

| 区域 | x 范围 | y 范围 | CLMA | CLMS | DRM | APM | LUT6 容量（推算） |
|---|---|---|---:|---:|---:|---:|---:|
| X0,Y0 | 0..91 | 0..49 | 2650 | 950 | 30 | 40 | 14400 |
| X0,Y1 | 0..121 | 50..99 | 3700 | 1200 | 50 | 80 | 19600 |
| X0,Y2 | 0..121 | 100..149 | 3000 | 900 | 50 | 80 | 15600 |
| X0,Y3 | 0..121 | 150..199 | 3000 | 900 | 50 | 80 | 15600 |
| X0,Y4 | 0..91 | 200..249 | 2525 | 925 | 25 | 40 | 13800 |
| X1,Y0 | 157..238 | 0..49 | 2350 | 850 | 30 | 60 | 12800 |
| X1,Y1 | 124..238 | 50..99 | 3500 | 1100 | 50 | 100 | 18400 |
| X1,Y2 | 124..238 | 100..149 | 3500 | 1100 | 50 | 100 | 18400 |
| X1,Y3 | 124..238 | 150..199 | 3500 | 1100 | 50 | 100 | 18400 |
| X1,Y4 | 157..238 | 200..249 | 2350 | 850 | 30 | 60 | 12800 |

每区还各列出 CLK PAD=4、PLL PAD=4、RCKB=4、IOCKB=4、HCKB=12、MRCKB=2；
它们是报告的资源类别，不能把 PLL PAD 数量当作 PLL 核数量。（C1:14–25。）
全器件报告可用 CLMA=30075、CLMS=9875、DRM=415、APM=740、IO=400、
GPLL=10、PPLL=10；前两项推得 LUT6=159800、FF=319600，与报告一致。
（P1:33–48、50、57、73；每 CLM 八 FF：VDS 第 11 页。）

**资料版本差异**：本地 VDS V1.5 第 10 页只列 PG2L100H 的 66600 LUT6、155 DRM、240 APM，
不能把该表当成 PG2L200H。公开厂商产品表可交叉核对 PG2L200H 的 159800 LUT、415 DRM、
740 APM 与 FBB676 的 400 IO；这里只使用这些容量，不据其推出布局。
（[紫光同创 Logos-2 产品页](https://www.pangomicro.com/en/product/logos_family/195.html)，
“Product Selection Guide”，网页无页码；上述 P1 行号为本项目直接证据。）

### 1.3 DRM/APM 列与 IO bank 的空间信息

**DRM 列的全部块 x 值和 y 范围：未查到；APM 列同样未查到。**
从抽样报告只能取得下面这些占用站点，不能用已占用站点穷举器件空闲列，
也不能把这些站点的 x 当成块 x：

| 样本 | 站点数字中的 x、y | 来源 |
|---|---|---|
| P1 dcache tag0 | DRM x=490，y=768 | T1:188–190 |
| P1 SRAM | DRM x=490，y=552 | T2:1409–1411 |
| P1 dcache data1 | DRM x=490，y=858 | T2:1425、1443 |
| P1 乘法器 `mult[3]` | APM x=587，y=798 | T2:33–34 |

**已确认的 bank 锚点**：BANKL3 的 D18 位于 X0,Y4，BANKL4 的 K21 位于 X0,Y3，
BANKL5 的 L22/M21 位于 X0,Y2（1.1 表的 IO bank/时钟源两种报告）。
其余 BANKL6、BANKL7、BANKR3..R7 与十个区域的完整对应、bank 边界块坐标：**未查到**。
仅由 L/R 名称推测左右侧、由连续编号推测上下顺序，不能作为已确认位置。
DDR 的 GPLL 在 X1,Y2、站点 `GPLL_727_769`，但这是 PLL 的位置，
不能据此断言所有 DDR 数据引脚也在 Y2。
（`D10/place_route/clock_utilization.txt:43`。）

### 1.4 项目引脚与板级接口

CPU/MEDIA 探针的引脚已实测；完整 SoC 接口下表采用板卡和厂商 demo 的映射，
不代表这些外部接口已经进入当前探针工程。现有 CPU/MEDIA 导入约束分别见
`fpga/constraints/edrv32_fpga_cpu_sys_top.fdc`、`edrv32_fpga_media_top.fdc`；
MEDIA 对 K21/D18 的约束在后者第 16–26 行。

| 信号/接口 | 引脚、bank | 芯片空间位置与来源 |
|---|---|---|
| 板钟 D18 | CPU `clk_i`、MEDIA `clk_ext_i`，BANKL3 | X0,Y4；P1:15，C1:39；VH PDF 第 14 页标为 27 MHz 板钟 |
| K21 | MEDIA `clk_mem_i`，BANKL4；板上 `HD_RX_PCLK` | X0,Y3；C2:40；`D10/place_route/HDMI_IN_DDR3_HDMI_OUT_top.prr:125`；VX F83:H83（不是第二个板载晶振） |
| UART | TX C24、RX B24，BANKL3 | P1:22–23；VX L96:N97；bank 的区域锚点见 D18，单脚精确 block 未查到 |
| 按键 | 复位 C22、key C23；板上其余按钮 B22/A22/B20，均命名 L3 | P1:16、21；VX L100:N104；其余按钮 bank 推断来自 L3 核心 IO 名 |
| LED | A20/C18/C19/E18，BANKL3；另 A17 的 USER_LED4 | P1:17–20；VX G109:H110、L105:N110；A17 bank 推断来自 L3 核心 IO 名 |
| DDR3 | 地址、命令、CK、125 MHz 输入 N3/N2 在 BANKR5；DQ[31:0]、DM、DQS 在 BANKR4 | `D10/place_route/HDMI_IN_DDR3_HDMI_OUT_top.prr:28–29、53–123`；VH PDF 第 15 页；bank 的精确区域范围未查到 |
| HDMI 输入 | K21 像素钟，24 位数据/HS/VS/DE 与控制信号在 BANKL4 | VX F77:N94；D10 PRR:15–19、31、33–38、47–48、125–130、141；K21 锚点 X0,Y3 |
| HDMI 输出 TMDS | CLK N21/N22，D2 N23/N24，D1 P23/P24，D0 R25/P25，BANKL5；HPD P16，SCL M20、SDA L20 为 L5 命名 | VH PDF 第 34–35 页；VX Q6:Y8、Q13:S20；`DC/prj/place_route/Top.prr:121–128`；bank 锚点 X0,Y2 |
| 以太网 RGMII | RXC D19、RXCTL H16、RXD3..0 B19/A19/E16/D16；TXC G16、TXCTL D20、TXD3..0 D21/C21/B21/E20；MDC A25、MDIO E21，BANKL3 | VH PDF 第 28–29 页明确 BANK L3；VX F101:N115；bank 锚点 X0,Y4 |
| OV5640 camera0 | PCLK L22，数据 M24/R22/K26/K25/M25/N19/T24/R21；HREF T25、VSYNC L23；SCL P19、SDA R20、RESET T22，BANKL5 | `DC/ov5640.fdc:39–95`；`DC/prj/place_route/Top.prr:15、17、21、23、25–32、41、43`；PCLK 在 X0,Y2 |
| OV5640 camera1 | PCLK M21 在 BANKL5；数据[7:0] 为 AB25/AA24/M26/P26/AB24/T23/R23/M22，跨 BANKL5/L6；HREF U26、VSYNC U25、RESET V24、SCL AC24、SDA Y25 在 BANKL6 | `DC/prj/place_route/Top.prr:16、18、22、24、33–44`；PCLK 在 X0,Y2；L6 的区域范围未查到 |

注意两处资料差异：VX M108 把 `FPGA_GCLK_27M` 标到 E17，VH 第 14 页与本次 PDS 报告则为 D18，
本项目 D18 事实以现有 FDC/PRR 为准。双目 demo 的 camera1 **跨两个 bank**，
不能简单写成“一路摄像头一个 bank”。（VX M108:N108；P1:15；DC PRR:24、33–44。）

整体文本示意图如下；上下只表示块 y 大小，**不是 PCB 或 BGA 俯视方向**。
矩形取 C1:5–9；左边的 bank 注记仅来自上述三个时钟源锚点。
DRM/APM 列尚不能画到精确 x；中心未列入这些区域的坐标不擅自标为任何硬核。

```text
                           block y increases
                                  ^
  bank anchor       X0                                X1
  L3 / D18      +-----------------+               +-----------------+
   y 200..249   | Y4: x 0..91     |  x 92..156 ?  | Y4: x 157..238  |
                +-----------------+               +-----------------+
  L4 / K21      +----------------------+   ?   +----------------------+
   y 150..199   | Y3: x 0..121          |122/123| Y3: x 124..238       |
                +----------------------+       +----------------------+
  L5 / L22,M21  | Y2: x 0..121          |   ?   | Y2: x 124..238       |
   y 100..149   +----------------------+       +----------------------+
   y 50..99     | Y1: x 0..121          |   ?   | Y1: x 124..238       |
                +----------------------+       +----------------------+
   y 0..49      | Y0: x 0..91     |  x 92..156 ?  | Y0: x 157..238  |
                +-----------------+               +-----------------+
                0                                                238 --> block x

  DRM/APM columns: block x/y not found; every region's capacity is in 1.2.
  DDR bank R4/R5; L6/L7 and other banks: exact region boundaries not found.
```

## 2. PDS 支持哪些手动布局手段

### 2.1 区域约束 PAP_REGION

| 问题 | 能够确认的内容 | 证据/尚缺内容 |
|---|---|---|
| 定义与关联语法 | `define_global_attribute {PAP_REGION} {name(x_min,x_max,y_min,y_max)}`；随后 `define_attribute {i:hier.instance} {PAP_REGION} {name}` | F3:8–9；E2:1195 明确报合法格式；现有失败试验没有证明可成功布局 |
| 坐标次序 | x 最小、x 最大、y 最小、y 最大 | E2:1195；与 C1:3 一致 |
| 坐标单位 | 对应 floorplan 块坐标是现有报告与错误的解释；**推断**，尚缺 UCE/PCE 原文明确单位定义 | B1:125–126；E2:1194–1195；C1:1–9 |
| 对象 | 已试图关联层次实例 `i:u_cpu_subsys.u_core`；`i:` 和点分隔层次为 Windows 结果引用手册的结论 | F3:9；B1:122；直接 UCE 手册未取得，不能扩大成“所有对象均可” |
| 多个区域、嵌套、重叠、一个实例关联多个区域 | **未查到** | 指定 demo 的 FDC 未发现 PAP_REGION 正例；需第 6 节试验 |
| 软/硬、是否独占、是否允许其他逻辑进入 | **未查到** | 非法坐标被拒绝不等于证明这是硬约束 |
| 子层次继承、DRM/APM 是否被同一区域约束 | **未查到** | P3 在检查阶段失败，未进入可验证布局，不能声称覆盖四个 APM |

集成版 `define_attribute` 的多对象写法也不能照搬时序工具的列表：现有试验出现
“建议 foreach”的解析警告；点分隔的对象若已被 Compile 合并，又会报对象不存在。
（E1:24–29、36–39。）

### 2.2 锁定站点 PAP_LOC

厂商 PG2L200H demo 确实有以下 FDC 原句，说明 `PAP_LOC` 使用**站点名**，
FF 还带 `:FF3` 子资源后缀；这与 PAP_REGION 的四个整数不同。
（`D10/HDMI_IN_DDR3_HDMI_OUT_top.fdc:788–790`。）

```tcl
define_attribute {i:u_ddr3_test_h.u_ddrphy_top.u_ddrphy_cpd} {PAP_LOC} {DDRPHY_CPD_729_772}
define_attribute {i:u_ddr3_test_h.u_ddrphy_top.ddrphy_reset_ctrl.ddrphy_ioclk_gate[0]} {PAP_LOC} {CLMA_717_672:FF3}
define_attribute {i:u_ddr3_test_h.u_ddrphy_top.ddrphy_reset_ctrl.ddrphy_ioclk_gate[1]} {PAP_LOC} {CLMA_717_978:FF3}
```

寄存器定位：有上述厂商实例。DDRPHY_CPD 定位：有上述厂商实例。
**DRM、APM 的 PAP_LOC 值格式、18K 半块选择、APM 级联位置要求及普通 LUT 的子资源名称：未查到**。
不能仅给 DRM/APM 时序站点前面加 PAP_LOC 就声称写法已经验证。
（D10 FDC:788–790 仅涵盖所列三项；VDS 第 11–12 页说明 DRM 分割和 APM 级联功能，未给约束语法。）

### 2.3 防止优化/合并与高扇出控制

| 手段 | 已知状态及阶段边界 | 来源 |
|---|---|---|
| FDC `PAP_DONT_TOUCH TRUE` | 本次实际 FDC 对两份存活 FF 使用；Windows 结果转引 UCE 手册第 93 页说作用于 Device Map；**本次未直接取得该手册** | `R/artifacts/cpu/p2/fdc_used.fdc:1–5`；B1:123–124 |
| FDC `syn_preserve` / `syn_keep` | 在本机 SP6.1 报属性无效；不能推荐为合法 FDC 语法 | E1:6–17 |
| RTL 注释 `/* synthesis syn_keep = 1 */` | 厂商 DDR IP 的 `axi_rdata`、`axi_rvalid` 有这种写法；是 RTL 写法存在的证据，不证明会阻止等价 FF 合并 | `V/2_Demo/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/example_design/rtl/test_ddr.v:82–83` |
| RTL 注释 `/* synthesis syn_preserve=1 */` | 厂商 FIFO 的 wptr/wrptr1/rptr/rwptr1 使用；是否阻止本项目 Compile 等价合并未查到 | `V/2_Demo/3_9_HDMI_IN_DDR3_sobel/3_9_HDMI_IN_DDR3_sobel/HDMI_IN_DDR3_sobel/ipcore/fifo_line_buf/rtl/ipm2l_fifo_ctrl_v1_1_fifo_line_buf.v:46–61` |
| RTL `(* syn_preserve = 1 *)` / `(* syn_keep = 1 *)` / RTL PAP_DONT_TOUCH | 所查资料中可据以推荐给本版 ADS/Compile 的确切写法和阶段语义：**未查到** | 不用其他厂商或 Synplify 的同名属性推定 ADS 行为 |
| `PAP_MARK_DEBUG` | 教程有 `wire [7:0] o_rgb565/*synthesis PAP_MARK_DEBUG="1"*/;`，并提醒信号仍可能优化 | VT PDF 第 150 页；不能替代防合并属性 |
| Compile/综合关闭等价 FF 合并 | 选项名称、GUI 开关及 Tcl：**未查到** | 现有 Compile 已合并六份为两份；E1:2–5；B1:123 |
| 高扇出复制 | PnR 日志有 Replication placement，厂商日志有实际 `Replicate Registers` | L1:25–30；`D10/place_route/run.log:611–625` |
| `syn_maxfan` / max fanout | ADS 报告识别到该名称，但有 unable to honor、lutcarry 未复制警告；设置接口/默认值/对象范围：**未查到** | W1:2405–2411；不能把警告中的 10000 当作已验证的用户选项值 |

**推断**：要保住六份等价 FF，属性或开关必须在发生合并的阶段起效。
在 Compile 已经删除实例之后给 FDC/PAP_DONT_TOUCH，不可能把实例恢复出来。
这不排除 RTL 注释或 Compile 选项有效，只是当前没有成功实测。
（合并顺序：E1:1–6、19–23；B1:123–124。）

## 3. 时序相关的布局布线选项

不同版本、不同器件的证据分开看；本项目是 SP6.1，厂商 D10 是 SP6.4。
以下只列已出现的命令或行为，不猜 `-seed`、`-effort` 等参数。
（P1:1；`D10/impl.tcl:1–7`。）

| 项 | 名称、Tcl 或报告事实 | 适用边界与出处 |
|---|---|---|
| ADS 综合 | `synthesize -ads -selected_syn_tool_opt 2` | D10 impl.tcl:5；`2` 的含义未查到，不解释成优化等级 |
| 基本 PnR | `pnr` | D10 impl.tcl:7；P1:3 显示 normal 模式，并列出 fast/normal/performance 三名称 |
| 时序驱动布局 | `Timing-driven detailed placement`，包括 Replication、Swapping | 本项目实测 L1:25–30；独立启停 Tcl 未查到 |
| 时序驱动布线 | `Enter timing driven router mode.` | D9 place_route/run.log:430；D13 place_route/run.log:148；独立启停 Tcl 未查到 |
| 多角时序优化、hold 修复 | `pnr -optimize_multi_corner_timing -fix_hold_violation` | D9 impl.tcl:3–7；该文件器件为 PG2L100H/FBG676，不宣称在 PG2L200H SP6.1 已复验 |
| 努力程度/模式 | fast、normal、performance 名称有报告证据 | P1:3；切换命令、各模式默认参数及运行代价未查到 |
| multi-seed | D10 下存在 `multiseed_summary.csv` | 该文件字节 0..511 有 UTF-16 样式中文保护提示，后续含二进制内容，不能直接作为普通 CSV 解析；本次未取得种子列表、成绩或执行 Tcl |
| 物理复制/优化 | PnR 有复制寄存器的日志 | D10 place_route/run.log:625；D12 place_route/run.log:564–565 还有 LUT 复制；不等于支持用户可控完整 physical synthesis 流程 |
| 物理综合开关、retiming/重定时 | **未查到** | 没有从“时序驱动/复制”推定支持 retiming |

D10 的 `impl.tcl:4–39` 多次重复 `synthesize/dev_map/pnr/report_timing`，
但没有显式 seed 参数；不能据“重复跑了几次”推出用了不同种子。
教程 VT 的时序优化建议在 PDF 第 119–120 页，主要是降低组合延迟、流水、降低频率、
优化布局及 skew；它没有给上述 seed/effort/retiming 开关。

公开检索没有取得可直接核对的 PDS/UCE/PCE 完整手册。
厂商 HMIC_H 用户指南明确指向 **PDS 安装路径下**的
`User_Constraint_Editor_User_Guide`、`Physical_Constraint_Editor_User_Guide`、
`Route_Constraint_Editor_User_Guide`；因此下一步应从 Windows 安装包取对应版本的原文，
而不是引用同名二手教程的猜测。
（[HMIC_H IP User Guide，UG022001 V1.2_i1，第 16/34 页](https://www.pangomicro.com/en/uploads/89243576_1711509733.pdf)，§2.3.2；
该文档仅支持“手册位置”的结论，不用于证明 PG2L200H 的约束语义。）

## 4. .fdc 与导入 Tcl 的具体写法

### 4.1 区域的待验证最小例子

下面采用现有 F3 的“先定义再关联”结构，把数值改为 C1 已列出的一个区域。
**这是待 Windows 验证的语法样例，不是 CPU 选区结论，也未宣称该矩形可合法放入全部层次资源。**
依据为 F3:8–9、E2:1195、C1:8。

```tcl
# 独立的 floorplan_probe.fdc；仅用于最小试验
define_global_attribute {PAP_REGION} {probe_region(0,121,50,99)}
define_attribute {i:u_cpu_subsys.u_core} {PAP_REGION} {probe_region}
```

对于多个实例，现有警告建议 `foreach`（E1 的 ConstraintEditor-4026）；
其在 FDC 方言中的完整可接受写法未取得。最小试验可先用逐实例的单独
`define_attribute` 行，避免把空格分隔对象的失败写法继续当成正例。
（同类逐实例结构：F3:4–5。）

### 4.2 站点定位与防优化样例

`PAP_LOC` 直接照第 2.2 节厂商三个例子；位置值保留站点名和 `:FF3`。
对 CPU 应先取得当前映射后的实例名与合法子资源，再由 PCE/UCE 保存实际 FDC，
不能把 timing 的 `/Q0` 拼成定位值。
（厂商正例：D10 FDC:788–790；时序端子：T1:26–28。）

下面的防优化写法是本次实际用过的 FDC，只保护尚存在的对象；并不解决 Compile 等价合并。
（`R/artifacts/cpu/p2/fdc_used.fdc:1–5`，B1:123–124。）

```tcl
define_attribute {i:u_cpu_subsys.u_core.u_frontend.probe_f1_redirect_valid_r} {PAP_DONT_TOUCH} {TRUE}
define_attribute {i:u_cpu_subsys.u_core.u_frontend.probe_f1_d_redirect_valid_r} {PAP_DONT_TOUCH} {TRUE}
```

下面仅演示厂商 RTL 注释的放置位置；其防合并效果仍须第 6 节最小工程确认。
（test_ddr.v:82–83 及 FIFO RTL:46–61，完整路径见第 2.3 节。）

```verilog
reg copy_r /* synthesis syn_preserve=1 */;
wire copy_w /* synthesis syn_keep=1 */;
```

### 4.3 导入顺序

沿用本仓库 `$edrv32_repo`、`file join`、`add_constraint`、`compile` 写法；
现有脚本在 compile 前导入约束，并传递 include_path/compiler_directives。
（`fpga/scripts/import_cpu_sys_top.tcl:43–56`；本任务没有改它。）

```tcl
# 插入到现有导入脚本的 compile 之前；文件名是最小试验的示意名
add_constraint [file join $edrv32_repo fpga constraints floorplan_probe.fdc]

# 保留现有导入脚本的这三个参数
compile -top_module $edrv32_top \
    -include_path $edrv32_include_dirs \
    -compiler_directives $edrv32_defines

# 导入结束后执行实现；下列四条是 D10/impl.tcl:5–8 的实际命令
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr
report_timing
```

**不能由“add_constraint 在 compile 前”推导约束属性在 RTL 优化前起效**：
现有试验已经表明等价 FF 先被合并，随后 FDC 的失效对象才被检查。
（E1:1–6、32–40；B1:123。）

## 5. 对 CPU 子系统的含义（推断）

### 5.1 资源口径与可容纳区域

输入是 P1 CPU_SYS 探针**整个顶层**，包含 CPU/cache 和 SYS 的 ROM/SRAM/外设；
不把整个顶层的资源全归到 `u_core` 或 `u_cpu_subsys`。
其综合为 14749 LUT、8334 FF、4 APM、4 个 DRM18K + 24 个 DRM36K；
28 个 RAM 原语折合 `4/2 + 24 = 26` 个 DRM36K 物理块。
（U1:3、12–13、33–43；层次范围见 P1 的层次资源表及 B1:117–128。）

**推断：只看总容量**，以 14749 LUT、26 DRM36K 当量、4 APM 对照第 1.2 节，
X0/Y1、Y2、Y3 和 X1/Y1、Y2、Y3 六个中间区域都满足这三个总数。
X0/Y0 的 14400 LUT 不够；X0/Y4 的 13800 LUT 和 25 DRM 都不够；
X1/Y0、Y4 的 12800 LUT 不够。这个判断只针对整个探针放进**单区**；
对较小的 `u_core` 或跨区矩形不能套用这个排除结论。
（推导输入：U1:33–43，C1:16–25；公式见第 1.2 节。）

**推断：容量通过不等于可布局**。14749/15600≈94.5%，
所以 X0/Y2、Y3 的逻辑容量余量很小；X0/Y1 为约 75.3%，X1/Y1..Y3 为约 80.2%。
而 PnR 报告实际已占用 3663 CLMA + 1188 CLMS，并计 11612+3878=15490 个物理 LUT；
物理打包与综合 LUT 口径不同，不能直接保证“15K LUT 放得下一个区”。
CLMS 专有的分布式 RAM、控制集合和 RAM 打包也需单独检查。
（U1:59–67；仅 CLMS 支持分布式 RAM：VDS 第 10 页。）

**推断：DRM/APM 对形状有硬件限制**。上表容量来自整个时钟区域；若把矩形横向缩窄，
必须重新计入所覆盖的实际 DRM/APM 站点，不能按面积比例折算。
18K 双占位能否共同打包、APM 级联的相邻位置是否可用、区域是否约束宏单元，均未实证。
因此当前可以列六个“容量候选”，不能选出具体 x 边界或承诺四个 APM 均被覆盖。
（DRM 模式与 APM 级联：VDS 第 11–12 页；精确列坐标和 PAP_REGION 语义缺项见第 1、2 节。）

### 5.2 P1 的实际位置

P1 全局时钟非 IO 负载包围框为 **x 134..235、y 92..170**，
对应块网格右半侧，跨 X1/Y1、Y2、Y3。
这包含整个 clk_sys 的负载，**不是 CPU 或任一模块的独立边界，也不是所有组合 LUT 的边界**。
（C1:44–46；区域表 C1:6–8。）

| P1 对象 | 实际站点 | 来源 |
|---|---|---|
| I-cache `addr_r[11]/opit_0` | CLMA_651_781 | T1:26–28 |
| I-cache `N5_79[0]_muxf8_perm` | CLMA_675_739 | T1:30–31 |
| I-cache hit0 组合逻辑 `N6.eq_9/gateop_perm` | CLMA_555_810 | T1:36–37 |
| Frontend `N117[10]_muxf7_perm` | CLMA_429_858 | T1:45–46 |
| IB `entries_r[2][74]/opit_0_L6Q_perm` | CLMS_573_853 | T1:48、66 |
| D-cache tag0 RAM | DRM_490_768 | T1:188–190 |
| D-cache data1 RAM | DRM_490_858 | T2:1425 |
| SYS SRAM 的一个切片 | DRM_490_552 | T2:1409–1411 |
| CPU 乘法器 `mult[3].mult/gopapm` | APM_587_798 | T2:33–34 |
| 全局时钟缓冲 | USCM_383_930 | C1:46；P1:94 |

**推断**：最差路径在站点数字尺度上横向往返，ICache 地址到 frontend/IB 中间经过
651→675→669→555→441→429→573，支持“逻辑位置分散值得检查”，
但尚不能换算出各段跨越多少 CLM/块，更不能只按坐标距离预测延迟。
该具体路径已有 5.743 ns route、1.693 ns logic，route 占 77.232%；
这是单条最差路径，不能冒充背景中约 65–70% 或低扇出约 38% 的整体统计。
（T1:26–51。）

**推断**：把 CPU 靠近 D18 的 X0/Y4 不自然地等同于缩短 CPU 数据通路；
当前 D18 经全局缓冲驱动右侧负载，选区仍需同时考虑 cache/ROM/SRAM/APM 的位置与拥塞。
仅因 UART/LED 属于 L3，也不足以把内部 CPU 限定到左上区。
（C1:39、46；P1:15–23；上表 RAM/APM 样本。）

## 6. 需要在 Windows PDS 上确认的事项

以下共 **12 项**，都是待确认事项与建议的最小试验，尚未执行。
GUI 菜单名称只有已见教程或工程记录的才写作既有入口；未证实的“导出”能力不虚构菜单或 Tcl。

| 编号 | 要确认什么 | 建议最小试验/操作 | 需要导出什么 |
|---|---|---|---|
| W01 | 精确 site↔block 关系、原点、坐标单位 | 打开 P1 的 Post-PnR 物理视图；若当前 Flow 对应 `wgt_edit_placement_cons`，先在该入口定位 T1 的三个 CLMA/CLMS 实例，再定位一个 DRM、一个 APM、USCM、D18/K21 IOL；逐个记录属性窗口的 site/block；每种资源取分散位置，跨 y 区界。入口关联证据为 D10 `.pds:441–449`，窗口字段名待实际确认 | instance、primitive、site、block_x/y、clock_region 的文本表；若无文本导出则属性窗口截图加人工表；至少三对精确坐标，不能只给区域范围 |
| W02 | DRM/APM 全部列及 bank 完整排布 | 在 PG2L200H-6 FBB676 的物理资源视图显示空闲资源，逐列查看首末站点和块坐标；显示 IO banks；同时检查 center 未被时钟区范围覆盖的条带 | 各 DRM/APM 列的块 x、合法 y/空洞、18K 半块，全部 bank 范围及资源全图；若软件可列器件站点表，一并导出实际命令与输出 |
| W03 | PAP_REGION 正确单位/顺序和合法单区域写法 | 在微型 FF+LUT 层次上，先由 UCE/PCE GUI 建一个范围，再保存 `.fdc`；用第 4.1 节的范围重复导入，比较 GUI 保存与手写；不先把整个 CPU 放进去 | GUI 生成的 FDC、对应版本手册页、约束检查日志、实际成员坐标 |
| W04 | 多区域、嵌套、重叠和同实例多关联 | 微型父/子层次分别放两个不相交区域；再单独测试父子嵌套、重叠、同实例第二次关联；各测试只改变一种关系 | 每例 FDC、解析结果、最终关联关系及实例位置；区分覆盖旧值、并集、交集或报错 |
| W05 | 软/硬、独占、对象范围及子层次继承 | 对含 FF/LUT、DRM、APM 的最小层次加区；先给足容量，再分别缩到不含 DRM/APM、或逻辑容量不足；另放无约束层次观察是否可进入；在单叶实例上重复 | 约束覆盖对象列表、失败诊断、每类资源最终坐标；超出区域是否被允许及有无警告 |
| W06 | PAP_LOC 对 FF/LUT/DRM18K/36K/APM 的值格式 | 先复制第 2.2 节已知 FF 格式做一个 FF 试验，再由物理编辑器锁定其余资源并保存；18K 两半分别测试，APM 若级联则取最小级联实例 | 每类 GUI 生成的属性、站点子资源值、放置结果，冲突时的错误日志 |
| W07 | Compile 阶段如何保留等价 FF | 微型设计保留两个相同 FF、分别接可观测扇出；基线、RTL syn_preserve 注释、syn_keep 注释、文档支持的 `(* ... *)` 和等价合并开关逐例比较；每次从 Compile 重跑 | 该版 Compile/综合选项帮助与手册页、生成的 impl.tcl、Compile 删除日志、各阶段实例清单；只有 FF 两份真正存活才算成功 |
| W08 | PAP_DONT_TOUCH 的阶段、对象语义 | 在 W07 已保住两 FF 的情况下，再对单 FF/网络/层次按 UCE 提供的合法类别设置；与只在 FDC 设置的基线比较 | SP6.1 UCE 手册 §PAP_DONT_TOUCH 的版本/页码、GUI FDC、Device Map 前后实例数；核对此前第 93 页二手转引 |
| W09 | fanout 上限与复制的真实控制项 | 在同一 FF 驱动几十个独立且保留的负载的小设计上，从项目 Compile/综合/PnR 设置查看 maxfan/复制选项；取两档限制重跑；carry 另取一个小例子 | 选项精确名称、帮助、GUI 保存 Tcl、复制前后驱动/负载数量和警告，尤其无法 honor 的对象类别 |
| W10 | PnR 模式、时序驱动、多角与 hold 修复 | 固定同一小网表/约束，GUI 分别设 normal/performance/fast；切换时序驱动及多角/hold 可用开关，每次保存 impl.tcl；对照第 3 节厂商命令 | SP6.1 的 `pnr` 帮助、完整实际参数、模式日志、slow/fast WNS/TNS/WHS/THS 和运行时间 |
| W11 | multi-seed 入口、选种机制与结果格式 | 用 GUI 的实际 multi-seed 功能（如果存在）对同一设计运行少量种子；打开 D10 的 multiseed_summary.csv 并另存可读文本；确认是 seed、strategy 还是重复运行 | 功能对应版本文档、导出的 Tcl、真实 seed/strategy、逐次结果和选择规则；不能仅给重复 pnr 命令 |
| W12 | 物理综合、retiming 是否可用及 CPU 实际占区 | 查该版 Project Setting 和 PDS User Guide，只有发现选项后才在可观察的寄存器链上做前后比较；同时从 P1 导出 CPU/cache/SYS 的全部实例位置，按第 1 节容量候选统计 | 选项名称/Tcl、前后网表寄存器位置/数量、原始时序报告；P1 各层次 LUT/FF/DRM/APM 的 block/site 表及包围框 |

W03、W07–W11 先从 PDS 的 `Tools → User Constraint Editor (Timing and Logic)`
与工程设置/命令帮助取得本版写法；已知教程仅确认 Pre Synthesize UCE、Device→I/O 保存 FDC，
没有证明上述高级选项都在 UCE 内。应同时导出安装目录中实际版本的
`Pango_Design_Suite_User_Guide`、`User_Constraint_Editor_User_Guide`、
`Physical_Constraint_Editor_User_Guide` 和相关 Tcl 命令页。
（VT PDF 第 24–28 页；VQ PDF 第 14 页；第 3 节所引厂商 UG022001 第 16 页。）
