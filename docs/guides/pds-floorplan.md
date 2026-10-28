# PDS 手动布局能力与 PG2L200H 内部排布

第二版，2026-10-28。第一版调研输入基线：`b6e17efcfe32a28b506b4f4bd51134e0de99b7b7`；
本版文档输入为当前分支提交 `358246b` 中的第一版。
本次只读资料，没有运行 PDS，没有修改 RTL、约束或导入脚本。

**结论边界**：原版手册明确了区域的 floorplan 整数坐标、层次传递和
CLMA/CLMS/DRM/APM 资源过滤，保证被约束实例放在区域内；可据此编写 CPU 区域实验。
PnR 模式、复制、多种子和布局结果导出也已有正式接口。`PAP_DONT_TOUCH` 仅保护
Device Map，不能解决已发生的 Compile 等价 FF 合并；三本手册未给出该合并的关闭方法。
PG2L200H 的精确 site↔block 关系、完整资源列和实际优化收益仍需 Windows 数据。
本版第 6.1 节保留 6 项手册不能回答的事项，第 6.2 节给出可直接安排的 P1 实验。

## 资料索引与引用约定

下文 `来源编号:行号` 都指原文件的物理行号；PDF 页码指 **PDF 第几页**，
避免教程的印刷页与 PDF 页错位。厂商目录未入库，完整根路径记为：

```text
V = /home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/doc/fpga/pago_200/
R = tasks/win/20261028-04-media-cpu-probes/
M = /home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/doc/fpga/pds_manuals/
D10 = V/2_Demo/4_10_timing/4_10_HDMI_IN_DDR3_HDMI_OUT/
D9  = V/2_Demo/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/pnr/
D12 = V/2_Demo/4_12_HDMI_IN_DDR3_HDMI_OUT/4_12_HDMI_IN_DDR3_HDMI_OUT/HDMI_IN_DDR3_HDMI_OUT/
D13 = V/2_Demo/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/
DC  = V/2_Demo/5_1 双目摄像头例程/ov5640_200k/
```

| 编号 | 文件、版本或含义 |
|---|---|
| PDS | `M/Pango_Design_Suite_User_Guide.pdf`，V1.5，修订记录最新 2022-11-18，274 页 |
| UCE | `M/User_Constraint_Editor_User_Guide.pdf`，V1.7，修订记录最新 2022-10-26，127 页 |
| PCE | `M/Physical_Constraint_Editor_User_Guide.pdf`，V1.3，修订记录最新 2023-01-12，62 页 |
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

下文 PDS/UCE/PCE 均指上表的**手册名**；引用统一为 PDF 页码，三本手册的
印刷页码均比 PDF 页码小 1。例如 UCE PDF 第 94 页即印刷第 93 页。
手册的发布日期不等于 P1 的 SP6.1 软件版本；正式能力与本项目实测分开记载。

复查 PDF 可用 `/usr/bin/pdftotext -layout <PDF> <build 下的文本>`，再按 `\f`
分页；文本行号可用 `nl -ba <文件>`。第一版还检查了 D10、D9、D12、D13 的
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
可用逻辑或硬核。（C1:1–25。）PDS PDF 第 78–79 页明确：区域坐标是 floorplan 中物理单元的
坐标，悬停在单元空白处可同时看到单元名与该坐标；UCE PDF 第 95 页规定左下角
`(x1,y1)`、右上角 `(x2,y2)`，PCE PDF 第 48 页规定四值为整数。
因此其单位是 floorplan 的离散物理单元坐标，不是微米，也不是站点名中的数字。
**未查到** PG2L200H 的网格步距、器件原点定义及 site 数字的编码公式。

时序的 `Location` 则是 `CLMA_651_781/Q0`、`DRM_490_768/QA0[4]` 等站点和站点引脚；
同一路径也出现 `IOBD_0_1386`、`IOLHR_16_1386`、`USCM_383_930`。
这些数字明显超出 Block Scope，不能直接填到 `PAP_REGION`。
（T1:11–47、188–190；E2:1194–1195。）

PDS PDF 第 79 页给出的教学器件对照为 `CLMA_5_133 → (4,44)`、
`CLMA_190_11 → (62,5)`、`CLMA_201_12 → (65,6)`。
这三个点证明“单元名”与“区域坐标”是不同表示；手册此节未把这些点标为
PG2L200H，**不能用它们给本项目建立换算公式**。
PCE 的 Properties 分别列出 gate device 的 `site(x,y)` 和 `(x,y)` 像素坐标，
两者也不能混为一谈（PCE PDF 第 26–27 页，表 3-1）。

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

### 1.4 物理视图和已有导出能力

PCE 的 Floorplan View 显示芯片资源位置，四周为 IO、中间为逻辑；
Settings → Layers 的 Design / Device / I/O Banks 可控制显示，搜索可定位 device instance。
Region 的 Properties → General 可过滤资源类型，Statistics 显示各类资源数量，
Instances 显示已关联实例（PCE PDF 第 14、17、25–27 页）。
Clock Region 按颜色边框区分，左下角标名字，可逐区隐藏；其画图范围只按
CLMA/CLMS 划分并作显示调整，不能据边框直接判定 DRM/APM 列或 IO bank 的边界
（PCE PDF 第 62 页；UCE PDF 第 56 页）。

已有四种导出手段，不必再把“是否能导出已放置实例位置”列为未知：

| 手段 | 手册明确的内容及边界 | 来源 |
|---|---|---|
| PDS `generate_constraint -file {p1-placement.pcf}` | 从 post-PnR DB 导出 IO、group、prim 的全部约束；`-device {DRM}` 或 `-device {APM}` 按资源类型导出；`-logic` 导出 IO/device 的 FDC，`-prim` 导出 prim 的 FDC | PDS PDF 第 167–168 页 |
| PCE `Export pcf file (tidy data)` / `save_constraint -file_name ...` | 保存并排序当前约束，不能由此声称导出了全器件空闲站点表 | PCE PDF 第 45–46、50–51 页 |
| 资源报告表格 `Export` | Report Summary 表格右键可导出整个表；`dev_map -detail` 可使 map 报告列每个 module 实例的资源使用率。这是设计资源使用报告，不是器件空闲 site 表 | PDS PDF 第 94、106 页 |
| PCE `Export Region` | 把区域内 DRM/APM 的区域约束枚举成位置约束 PCF，可设区域、起始排列、步长和文件数；不是运行 PnR 的多种子，也不是空闲资源全集导出 | PCE PDF 第 55–57 页 |

PDS 的 `export_fdc -file p1-placement.fdc` 可把 dev_map 后 PCF 反标成 FDC。
`generate_constraint` 的结果自带 `no_check` 类设置，实例不存在可被忽略；
这些文件适合作为布局取证，不应把它们原样当作 CPU 区域实验的输入。
手册中 `-slack -1.0` 的示例与解释的 `-0.1ns` 数值不一致，本版采用全量导出，
不据此推荐 slack 筛选值。（PDS PDF 第 167–169 页。）

**未查到** 三本手册中的全器件空闲 site/资源表导出命令，也未查到直接批量导出
PG2L200H site↔block 双坐标的方法；已有命令解决的是已布局实例的取证。
完整资源列仍按第 6.1 节取得，不能把少量占用站点当成全部合法站点。

### 1.5 项目引脚与板级接口

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

### 2.1 区域约束 PAP_REGION 与分组 PAP_GROUP

| 问题 | 手册结论 | 来源 |
|---|---|---|
| 定义、关联 | `define_global_attribute {PAP_REGION} {r(xmin,xmax,ymin,ymax)[CLMA,CLMS,APM,DRM];}`；然后 `define_attribute {i:hier.instance} {PAP_REGION} {r}`；先声明后使用 | UCE PDF 第 89–90、95–96 页 |
| 坐标单位、顺序 | floorplan 物理单元整数坐标，次序为 xmin、xmax、ymin、ymax；左下到右上；非负且 min≤max，四数不能全为 0。不是 timing site 名或屏幕像素 | PDS PDF 第 78–79 页；UCE PDF 第 95 页；PCE PDF 第 48 页 |
| 资源过滤 | 支持 CLMA、CLMS、APM、DRM，其他资源建议用 PAP_LOC；`[CLMA,CLMS,APM,DRM]` 在区域定义的大括号内，列出支持的类型；类型列表允许缺省，但本版样例显式列全四类 | UCE PDF 第 49、90、96 页 |
| 对象与层次传递 | GTP 库单元实例或自定义 RTL module 实例；GTP 映射出的所有 GOP 继承属性；module flatten 后的所有 GTP、及其映射出的 GOP 均继承 | UCE PDF 第 95–96 页 |
| 软/硬 | 手册保证后续布局将实例放在区域内，未提供可越界的 soft 开关；本文把这种“保证在内”的语义称为**硬区域约束**，这是术语归纳；容量不足时具体报错及算法行为未写明 | PCE PDF 第 21、25 页；PDS PDF 第 79 页 |
| 多个区域 | 一条全局 PAP_REGION 可用分号声明多个命名矩形；每类全局属性在保存文件中最多一条，所以多区域合并在同一声明中 | UCE PDF 第 90 页 |
| 父子区域 | UCE GUI 明确处理层次冲突：先约束子 module 再约束父 module，会提示子约束被移除；先约束父 module 再约束子 module，会提示子约束被忽略。不能据此设计父子同时生效的嵌套区 | UCE PDF 第 52 页 |
| 几何嵌套/重叠、同实例多区域 | **未查到** 不同矩形嵌套或重叠时的完整合法性、同实例重复关联的覆盖/并集/交集规则。多区域声明不等于一个实例可关联多个区域 | UCE PDF 第 90、95–96 页只定义命名矩形与单区域关联 |
| 独占、其他逻辑能否进入 | **未查到** 普通 PAP_REGION 对无约束逻辑的排他规则；UCE 另列 Set/Unset Exclusive Region、属性 PAP_EXCLUSIVE_REGION，标为局部动态重配用途，不能用其名字替普通区域补出语义 | UCE PDF 第 55 页 |

**DRM/APM 可以被区域约束**，不是只约束 LUT/FF；对 `u_cpu_subsys` 设置包含四类资源的
区域，会按手册的层次传递规则覆盖其中映射出的 DRM/APM（UCE PDF 第 49、95–96 页）。
这是手册支持的能力，P3 的失败日志仍不是本项目成功实施的证据；具体矩形内是否有足够
合法 DRM/APM、是否满足级联与打包，仍需实际放置。

集成版 FDC 的层次分隔符是 `.`，对象前缀 `i:` 是 instance、`n:` 是 net、
`t:` 是 pin、`p:` 是 port；后端版 LCF/SDC 的层次分隔符为 `/`，pin 分隔符为 `:`
（UCE PDF 第 69 页）。`define_attribute` 为**单个对象**设置属性
（UCE PDF 第 89 页）；对多个对象用多行逐一关联，不把对象列表拼成一个名字。

若要表达靠拢意图，手册另有 `PAP_GROUP`：作用于自定义 module 的实例，取任意合法
字符串组名，flatten/map 后传给其全部实例，布局时“尽量”将同组逻辑放近。
这是手册描述的软性聚集意图，未规定矩形边界，不能替代 PAP_REGION
（UCE PDF 第 92 页）。

### 2.2 锁定站点 PAP_LOC

`PAP_LOC` 在 map 时转为 PCF `def_inst_site`，值为具体 device instance 名，
映射时传给相应 GOP；指定基本子单元时使用 `site:impl`。
UCE 给出 APM 和 LUT 的正式例子；PDS 的 PCF 通式为
`def_inst_site inst_name site_name [impl_name]`，其中基本单元举例 FGA、FGB、FF1。
（UCE PDF 第 94–95 页；PDS PDF 第 76 页。）

| 对象 | 能确认的值格式 | 尚缺边界与来源 |
|---|---|---|
| FF | `CLMA_717_672:FF3`（厂商 PG2L200H 实例）；PDS 通式允许 FF1 之类基本单元名 | PDS PDF 第 76 页；`D10/HDMI_IN_DDR3_HDMI_OUT_top.fdc:789–790`；FF 子单元全集未给出 |
| LUT | `CLMA_5_4:FGA`，表示具体 LUT | UCE PDF 第 95 页；PCE PDF 第 47 页的 `constraint ... CLMA_5_4 FGA` 也给出相同 site/子单元结构 |
| APM | `APM_134_172`，不附时序 pin 名 | UCE PDF 第 95 页；此教学坐标不是 PG2L200H 的可复用位置 |
| DRM | 一般规则为具体 device 名；本项目已出现 `DRM_490_768`，可由 `generate_constraint -device {DRM}` 或 `export_fdc` 取得确切约束值 | UCE PDF 第 94 页；PDS PDF 第 167–168 页；T1:188–190；**三本手册未给 Logos2 DRM PAP_LOC 的直接正例、18K 半块后缀或级联合法站点规则** |
| DDRPHY_CPD | `DDRPHY_CPD_729_772` | `D10/HDMI_IN_DDR3_HDMI_OUT_top.fdc:788`，为厂商实例，不来自这三本手册 |

手册的 PDS PDF 第 77 页还举 `BRAM_71_39`、`MUL_71_38`，
那是教学器件的资源名，不能替换本项目的 DRM/APM 名。
同页把一个 FF 例子的 impl 写成 FGA，与前页 FF1 的说明不一致；
FF 的直接 FDC 正例采用上表 PG2L200H demo，不据该疑似笔误生成 FF 子单元名。
T1 中 `/Q0`、`/QA0[4]` 是 timing pin，不能拼成 PAP_LOC 值。

### 2.3 防止优化/合并与高扇出控制

| 手段 | 正式接口、阶段边界 | 来源 |
|---|---|---|
| FDC `PAP_DONT_TOUCH` | 对 GTP inst 和 module 实例，TRUE/FALSE；仅保证 **Device Map** 中不优化、不改变；**FF pack 忽略此属性** | UCE PDF 第 94 页（印刷第 93 页），直接核实第一版的二手引用 |
| Device Map 关闭重复逻辑消除 | GUI `Remove Duplicated Logic`，Tcl 名 `-devmap_remove_dups`；默认值 0，功能是合并部分重复逻辑，也可能抵消综合复制、降低时序性能 | PDS PDF 第 107、250 页；这是 map 选项，不是 Compile 选项 |
| Compile 关闭等价 FF 合并 | **未查到** 选项名、Tcl 或正式 RTL 属性。Compile、ADS 综合配置细节都转引未提供的 `ADS_Synthesis_User_Guide` §2.3，不能把 map 的开关提前解释成 Compile 开关 | PDS PDF 第 90、92 页；第 250 页的 compile 表也未列该项 |
| RTL `syn_preserve` / `syn_keep` | 厂商 RTL 有 `reg ... /* synthesis syn_preserve=1 */;`、`wire ... /* synthesis syn_keep=1 */;` 写法；**三本手册未写其 ADS/Compile 防等价合并语义**，也未给可据以推荐的 `(* syn_preserve=1 *)` / RTL PAP_DONT_TOUCH 示例 | 第一版厂商 FIFO RTL:46–61、test_ddr.v:82–83（路径见下文）；PDS PDF 第 90、92 页只指向 ADS 手册 |
| FDC `syn_preserve` / `syn_keep` | P1 同版 SP6.1 已报属性无效，不能当 FDC 正例 | E1:6–17 |
| RTL PAP 属性的一般机制 | UCE 展示 `(* PAP_REGION="reg(1,2,3,4)" *) reg cnt2;` 及综合后传递；这只证明 PAP_REGION 的写法，不能据此补出 syn_preserve 的效果 | UCE PDF 第 106 页 |
| 扇出上限 | ADS 设置图已有 `Fanout Guide=10000`；Synplify_Pro 小节明确它是 fanout limit 的指导值，默认 10000；不是布线必须满足的硬上限 | PDS PDF 第 92 页图 3-5、第 95–96 页 §3.2.2；ADS 的具体复制规则未在此展开 |
| `PAP_MAX_FANOUT` | UCE 正式列出该属性，但用法仅转引 ADS 手册 `syn_maxfan`；对象、取值范围和 RTL/Tcl 完整用法在本次三本中**未查到** | UCE PDF 第 99 页 |
| 布局复制 | `pnr -dc_duplication`，GUI `Design Cells Duplication`，采用自适应插入/复制逻辑单元进行布局时序优化；Logos2 默认开启 | PDS PDF 第 113、119、252 页；这与设置某个 net 的 fanout 上限不同 |

厂商 RTL 例子的完整路径为：
`V/2_Demo/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/example_design/rtl/test_ddr.v:82–83`；
`V/2_Demo/3_9_HDMI_IN_DDR3_sobel/3_9_HDMI_IN_DDR3_sobel/HDMI_IN_DDR3_sobel/ipcore/fifo_line_buf/rtl/ipm2l_fifo_ctrl_v1_1_fifo_line_buf.v:46–61`。
这些只证明注释存在，不证明本项目六份 FF 能保留。
`PAP_MARK_DEBUG` 也不能替代防合并：教程仍提醒信号可能被优化（VT PDF 第 150 页）。

**推断**：要保住六份等价 FF，属性或开关必须在合并发生前起效。
本项目 Compile 已将六份合成两份，之后的 FDC/PAP_DONT_TOUCH 或关闭 map 消除
不能恢复四个已不存在的对象（E1:1–6、19–23；B1:123–124）。
因此本版提供 map 阶段的防优化样例，同时保留第 6.1 节的 Compile 防合并问题。

## 3. 时序相关的布局布线选项

PDS 原版手册有通用参数表，也有按器件系列列出的可用性/默认值。
对 PG2L200H 应同时读两者，不能只看通用命令名称。
本项目实测是 2022.2-SP6.1 build 138931（P1:1），下列为手册事实，尚未在本任务重跑。

### 3.1 PnR 模式、复制、布局与布线优化

| GUI / 功能 | Tcl 名称、取值和含义 | 来源 |
|---|---|---|
| Mode | `pnr -mode fast\|normal\|performance`：fast 最快、性能最差；normal 折中；performance 性能优先、耗时最长；默认 Normal。手册正文一次误拼 nomal，本版用 P1 的 normal 拼写 | PDS PDF 第 109、118、253 页；P1:3 |
| Strategy | 0–7，0 不使用策略；**仅 Titan2 支持**，不是 PG2L200H 的模式或种子列表 | PDS PDF 第 109 页 |
| Placement Decongestion Mode | `-plc_decongestion`，整数 0–9，值越大通常扩散越广；资源占比大于 70% 时手册建议 0–4；默认 1 | PDS PDF 第 112、118、252 页 |
| Placement Initial Method | `-plc_initial_method`，Center 从中心起始，Quad 根据位置约束及 IO 起始；默认 Quad | PDS PDF 第 112、119、253 页 |
| Early Block Placement | `-early_block_placement`，Greedy / Global / Grouped / Close，分别偏网表时序 / 布局距离 / 网表设计特征 / 关闭宏优先放置；PG2L200H 默认 Global | PDS PDF 第 112、119、253 页 |
| 宏优先顺序 | `-auto_dispose_macro`；关闭自适应后可选 `-dispose_drm_prior`、`-dispose_apm_prior`、`-dispose_dram_prior`、`-dispose_carrychain_prior`；PG2L200H 默认自适应关闭，DRM/APM 优先开，其余关 | PDS PDF 第 112–113、119、253 页 |
| Design Cells Duplication | `-dc_duplication`，开/关；PG2L200H 默认开 | PDS PDF 第 113、119、252 页 |
| RefinePlacement | GUI Mode 为 Swap/Bump，PG2L200H 默认 Swap；`-refineplacement_cluster` 开/关，默认开；`-refineplacement_iteration` 默认 20，增大可延长时序收敛；**Mode 对应 Tcl 名未查到** | PDS PDF 第 113、119、253 页 |
| Placement Logic Optimization | Logos2 支持、默认开，目前仅 LUT6D pack；GUI `LUT6D Packing Strategy` 为 0 关、1 性能影响较大、2 较小、3 合并较多；PG2L200H 默认 2；**这两项 Tcl 名未查到** | PDS PDF 第 113、119 页；第 252–253 页表 9-12 未列 |
| Planning Before Place | 布局前模块级位置规划以减少同模块逻辑分散；PG2L200H 默认开，**Tcl 名未查到** | PDS PDF 第 113、119 页 |
| 布线时序权重 | `-slack_weight`，默认 90；`-pin_cost_increasing_speed` 默认 300；手册未给两者允许范围 | PDS PDF 第 114、119、253 页 |
| Fast Router / Slack Prior | `-fast_router`、`-fast_router_mode`（Auto/Mode1/Mode2）、`-slack_prior_in_global_router` 有通用定义，但 Logos2 表列**无该选项**，不作为 PG2L200H 建议参数 | PDS PDF 第 114、119、252–253 页 |

时序驱动已经由 P1 的详细布局 Replication/Swapping 日志证明（L1:25–30）；
手册补充了可控的复制、迭代和布线权重，**未查到**独立的总开关
`timing_driven_place` / `timing_driven_route`，不虚构此类 Tcl。
GUI 的可选值如 Center/Quad 是手册显示名；表 9-12 没给所有枚举的 Tcl 大小写/编码，
本版可直接运行的样例采用已知 mode 与数值型 seed 参数。

### 3.2 多角与 hold：PG2L200H 的适用边界

| 功能 | 正式 Tcl、语义 | PG2L200H 边界与来源 |
|---|---|---|
| Optimize Multi-Corner Timing | `-optimize_multi_corner_timing`；仅 Optimize Hold Timing 开启才有效，修 slow/fast 两角，否则旧 hold fix 只修 fast | PDS PDF 第 110、253 页；第 118 页 Logos2 列**无该选项** |
| Optimize Hold Timing（旧流程） | `-fix_hold_violation`，`-fix_hold_violation_iterations`，`-fix_hold_violation_threshold`（ps） | PDS PDF 第 110、253 页；第 118 页 Logos2 列三项**无该选项**；D9 的 PG2L100H 采用旧流程，不能套到 PG2L200H |
| Optimize Hold Timing In Route | `-fix_hold_violation_in_route`，开/关；Logos2 默认开 | PDS PDF 第 110、118、253 页 |
| 布线 hold 修复阈值 | `-fix_hold_violation_threshold_for_clock_path_cross_srb`：时钟经过 SRB，ps，建议 0–1800，默认 200；`-fix_hold_violation_threshold_for_clk_tree`：时钟不经过 SRB，ps，0–200，默认 100 | PDS PDF 第 110、118、253 页 |
| Max Number Of Hold Violated Paths To Fix | GUI 范围 0–100000，Logos2 默认 15000；**Tcl 名未查到** | PDS PDF 第 110–111、118 页；第 253 页未列该项 |

第 253 页参数表把 multi-corner 泛写成满足各模式时序；本版采用第 110 页更具体的
hold 语义，并遵循第 118 页的器件可用性。三本手册**未查到** PG2L200H 布线 hold
修复逐 corner 的算法说明，不能把旧 multi-corner 选项的行为移植过来。
验证时仍须导出 slow/fast 的 setup/hold 结果，不能只以开关开启判定 hold 通过。

### 3.3 Multi-seed：正式命令、保留与选择

| GUI 项 | `pnr` 参数 | 默认值/语义及来源 |
|---|---|---|
| Global Random Seed (Placement) | `-gplace_seed` | 初始随机布局种子，默认 0；PDS PDF 第 115、119、252 页 |
| Iterations (Placement) | `-gplace_times` | 执行种子次数，最小 1、默认 1，也支持 Place Only；PDS PDF 第 115、119、252 页 |
| Random Seed Step (Placement) | `-seed_step` | 种子步长，默认 1；PDS PDF 第 115、120、252 页 |
| Save Best Run (Placement) | `-saved_outcome` | 保存最优结果数，默认 1；PDS PDF 第 115、120、252 页 |
| Maximum Number ... Parallel | `-parallel` | 同时执行种子的最大数，默认 1；PDS PDF 第 115、120、252 页 |

手册正式定义了不同随机初始位置和步长，不再从 D10 的重复 `pnr` 推测是否多种子。
默认 filter 为空，sort 为 setup；筛选先按 Filter Strategies，再按 Sort Strategy，
默认优先级 setup > hold > recovery > removal > wirelength；四类时序比较都取
slow/fast 中较小的 slack。最后按 `saved_outcome` 保留结果。
汇总文件名是 **`multiseed_result.csv`**，包含两角四种检查的 8 个时序结果、
Routing Arc Length、Worst Slack(before route)、Wire Length，UserFilter 标记是否符合过滤。
GUI 可用 PNR 右键 `Select a Seed To Apply` 选择种子，再重跑 Report Timing。
（PDS PDF 第 115–117、120 页。）

Filter/Sort、多种子 Timeout、Generate Bitstream 等 GUI 项的 Tcl 名在三本手册中
**未查到**；不妨碍使用默认筛选规则执行下文三种子实验。
D10 留存的 `multiseed_summary.csv` 仍是受保护内容，不能把它等同于已读到上述
`multiseed_result.csv` 的实测数据。

### 3.4 Compile/综合、物理优化和 retiming

Compile 把 Verilog 编译成 RTL 网表；ADS Synthesize 基于 Compile DB 做 mapping/optimization
生成 technology 网表（PDS PDF 第 89、91 页）。
PDS PDF 第 165 页确有 `synthesize -ads -selected_syn_tool_opt 2 -top_module add`，
但三本手册**未解释 `2` 的枚举含义**，保留已有工程写法而不把它称为优化等级。
Compile 的常用命令表仅列 `-top_module`、`-include_path`；本项目已有的
`-compiler_directives` 来自导入脚本，不冒称本表给出的接口
（PDS PDF 第 250 页；`fpga/scripts/import_cpu_sys_top.tcl:49–56`）。

**重定时不是完全“未查到”**：ADS Synthesize 设置截图明确显示 Retiming、Resource Sharing、
Fanout Guide、Enable Advanced LUT Combining、Minimum Control-Set Size 等选项
（PDS PDF 第 92 页图 3-5）。但详细 ADS 配置被转引到未提供的 ADS 手册；
UCE 的 `PAP_ALLOW_RETIMING` 也仅指向 `syn_allow_retiming` 用法
（UCE PDF 第 98 页）。本版仍**未查到** ADS retiming 的确切 Tcl、默认语义、对象范围和
是否可在 Compile 合并前保护复制寄存器。

PDS 的 Synplify_Pro 小节另解释 Retiming 为跨组合单元移动存储，且 RAM/DSP/生成时钟
相关寄存器可能不受该开关限制；Pipelining 会将乘法器/ROM 后的寄存器移入宏。
这些是**Synplify_Pro** 的描述，不能当作 ADS 算法保证
（PDS PDF 第 95、98 页）。

PnR 已有第 3.1 节的复制、LUT6D pack、模块规划等**物理布局优化**。
三本手册**未查到**独立的完整“物理综合”总开关或 **PnR 阶段 retiming** 命令；
不能由有布局复制就推导 PnR 会重定时。

## 4. .fdc 与导入 Tcl 的具体写法

本节代码是按手册接口编写、可作为项目实验输入的片段；坐标是实验候选，
不是已经测得最优的布局。以下两个区域 FDC **择一**，不叠加父子区域。
手册语法依据为 UCE PDF 第 69、89–90、95–96 页；矩形范围来自 C1:6–8。

### 4.1 整个 CPU 子系统的单矩形

```tcl
# floorplan_probe.fdc：CPU/cache；不把 u_sys_subsys 放进此区
define_global_attribute {PAP_REGION} {cpu_region(124,238,50,199)[CLMA,CLMS,APM,DRM];}
define_attribute {i:u_cpu_subsys} {PAP_REGION} {cpu_region}
```

该区域横跨右侧 Y1–Y3；按 C1 的总量有 55200 LUT6（推算）、150 DRM、300 APM。
相对 P1 的整个顶层综合资源也有容量余量，但不能据总量保证 packing、级联和拥塞通过。
`u_cpu_subsys` 是板级顶层现有实例，含 `u_core`、`u_icache`、`u_dcache`、`u_cache_ctrl`
（`fpga/rtl/edrv32_fpga_cpu_sys_top.v:101`；`rtl/soc/edrv32_cpu_subsys.v:113` 起）。

### 4.2 按指令/执行/数据流划分三个条带

```tcl
# 替代 4.1 的区域声明和关联；同一条全局声明包含全部区域
define_global_attribute {PAP_REGION} {fetch_region(124,238,150,199)[CLMA,CLMS,APM,DRM];core_region(124,238,100,149)[CLMA,CLMS,APM,DRM];data_region(124,238,50,99)[CLMA,CLMS,APM,DRM];}
define_attribute {i:u_cpu_subsys.u_icache} {PAP_REGION} {fetch_region}
define_attribute {i:u_cpu_subsys.u_core} {PAP_REGION} {core_region}
define_attribute {i:u_cpu_subsys.u_dcache} {PAP_REGION} {data_region}
```

三个条带分别覆盖 X1/Y3、Y2、Y1；其 CLM/DRM/APM 容量见第 1.2 节。
cache_ctrl 和 SYS 暂由自动布局处理；这些是互为兄弟的层次，避免 UCE 的父子冲突。
**推断**：I-cache→frontend/执行→D-cache 的相邻条带可能减少跨模块距离，也可能因
强行分开 tag/data 或增加回传距离而变差，须看真实路径。CPU 其余流水逻辑多在
`u_core` 内，没有独立 `u_execute` 层次，不能虚构该对象来约束。
如果只想让 frontend 与 I-cache 靠近，可单独试下面的软性分组，组名相同；
不与前述硬区域实验混用，以便比较原因（UCE PDF 第 92 页）：

```tcl
define_attribute {i:u_cpu_subsys.u_core.u_frontend} {PAP_GROUP} {fetch_group}
define_attribute {i:u_cpu_subsys.u_icache} {PAP_GROUP} {fetch_group}
```

### 4.3 防优化/防合并的阶段写法

对 P2 已存在的两份 FF，可直接采用下列 FDC 防止 Device Map 改动
（UCE PDF 第 94 页；`R/artifacts/cpu/p2/fdc_used.fdc:1–5`）：

```tcl
define_attribute {i:u_cpu_subsys.u_core.u_frontend.probe_f1_redirect_valid_r} {PAP_DONT_TOUCH} {TRUE}
define_attribute {i:u_cpu_subsys.u_core.u_frontend.probe_f1_d_redirect_valid_r} {PAP_DONT_TOUCH} {TRUE}
```

这两行只适用于含上述探针的 P2 输入，不应直接加到没有这些对象的 P1。
P1 若对现有 module 做 map 阶段保护，可单独实验：

```tcl
define_attribute {i:u_cpu_subsys.u_core.u_frontend} {PAP_DONT_TOUCH} {TRUE}
```

Device Map 的 `Remove Duplicated Logic` 保持未勾选（默认 0；正式参数名
`-devmap_remove_dups`），不在该阶段重新合并综合复制的逻辑。
三本手册给出了这个 GUI 值与 Tcl 名，但未示范该布尔选项的显式关闭写法；
本节用默认的 `dev_map`，不猜 `-devmap_remove_dups false/0` 方言
（PDS PDF 第 107、250 页）。**FF pack 仍会忽略 PAP_DONT_TOUCH，Compile 防等价合并
仍无已确认写法**；因此不把上述片段包装成“六份 FF 必定保留”的方案。
RTL 的 syn_preserve/syn_keep 只保留第 2.3 节的厂商证据，待第 6.1 节取得 ADS 定义后再使用。

### 4.4 导入、PnR 模式与三种子

区域片段保存为独立实验 FDC；在现有导入脚本的 compile 之前插入 `add_constraint`。
以下是实验脚本片段，没有修改仓库现有脚本；`edrv32_repo`、top/include/defines 和
`add_constraint` 用法沿用 `fpga/scripts/import_cpu_sys_top.tcl:11–56`。

```tcl
add_constraint [file join $edrv32_repo fpga constraints floorplan_probe.fdc]
compile -top_module $edrv32_top \
    -include_path $edrv32_include_dirs \
    -compiler_directives $edrv32_defines

# 既有 ADS 选择参数，不解释 2 为优化等级
synthesize -ads -selected_syn_tool_opt 2
# Remove Duplicated Logic 在工程设置中保持默认未勾选
dev_map

# 单种子 normal 基线；与 performance 实验分别运行
pnr -mode normal -gplace_seed 0 -gplace_times 1
report_timing
```

模式和种子参数来自 PDS PDF 第 109、115、252–253 页。
把最后的 pnr 改为下列命令，可执行 performance 下 0、1、2 三种子，串行运行并保留三份结果；
这里的种子序列是依据起始值、次数和步长的配置推得，实际序号以汇总报告为准：

```tcl
pnr -mode performance -gplace_seed 0 -gplace_times 3 \
    -seed_step 1 -saved_outcome 3 -parallel 1
report_timing
```

按手册 PG2L200H 默认开启 Design Cells Duplication 和 Optimize Hold Timing In Route；
需要显式启用时，表 9-12 中的开关名分别为 `-dc_duplication` 和
`-fix_hold_violation_in_route`。本版不把 PG2L100H demo 的
`-optimize_multi_corner_timing -fix_hold_violation` 附到 PG2L200H 样例中
（PDS PDF 第 118–119、252–253 页）。

### 4.5 P1 或实验结果的位置导出

加载已完成 PnR 的工程/DB 后，在 PDS Console 执行：

```tcl
generate_constraint -file {p1-placement.pcf}
generate_constraint -file {p1-drm.pcf} -device {DRM}
generate_constraint -file {p1-apm.pcf} -device {APM}
generate_constraint -file {p1-placement.fdc} -logic
```

这是布局结果的文本证据，包含实例位置；不将其反导入下一个实验。
命令、输出格式和附带的 no_check 行为见 PDS PDF 第 167–168 页。
多种子时逐个 `Select a Seed To Apply` 并重跑 Report Timing 后导出，按种子分目录保存，
避免把一个种子的 timing 与另一个种子的位置混在一起（PDS PDF 第 117 页）。
生成文件中的网表层次名与 FDC 集成版名字可能不同，按 UCE PDF 第 69 页的阶段命名规则解释。

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
区域能够约束 DRM/APM 已由手册确认；18K 双占位能否共同打包、APM 级联的相邻位置
是否可用，以及本项目在指定矩形内的实际 packing，仍未实测。
因此六个区域仍只是容量候选；第 4 节的具体矩形可作为实验起点，
其能否放入全部目标资源、是否改善时序还没有实测结论。
（DRM 模式与 APM 级联：VDS 第 11–12 页；精确列坐标和剩余语义缺项见第 1、2 节。）

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

## 6. Windows 未决事项与 P1 布局实验

### 6.1 手册尚不能回答的 6 项事项（按 CPU 布局优化优先级）

第一版 W03 的基本语法/单位、W05 的硬边界/层次/DRM/APM 覆盖、W08 的
PAP_DONT_TOUCH 阶段、W10 的模式定义和 W11 的多种子接口均已由手册回答，
不再作为能力发现试验。父子 GUI 冲突、结果位置导出也已有说明。
下面只保留手册缺失或必须由 PG2L200H/P1 实测才能得到的部分，均尚未执行。

| 优先级/编号 | 为什么三本手册不能回答 | 最小试验 | 导出什么 |
|---|---|---|---|
| 1 / R-W01 | 手册只给教学器件的坐标点和视图功能，未列 PG2L200H 完整 site↔block/DRM/APM 列；P1 实际各层次占区也不在手册中（PDS PDF 第 79、167 页；PCE PDF 第 26–27 页） | 在现有 P1 上执行第 4.5 节全量/DRM/APM 导出；用 PCE 定位至少 3 个分散的 CLMA/CLMS、每条涉及的 DRM/APM 列，记录悬停 floorplan 坐标与 site；显示空闲 Device、I/O Banks、Clock Region，补齐可选矩形覆盖列/空洞；按 CPU/cache/SYS 分组位置 | 全量位置 PCF/FDC、实例/primitive/site/block_x/y/clock_region 文本表；各层次包围框、LUT/FF/DRM/APM 数；DRM/APM 列合法 y/空洞、18K 半位及完整 bank 图。手工坐标需保留 Properties/悬停截图；不以占用列表代替空闲器件全集 |
| 2 / R-W02 | Compile 合并关闭选项和 syn_preserve/syn_keep 的 ADS 定义被转引至未提供的 ADS 综合手册；PAP_DONT_TOUCH 仅管 map（PDS PDF 第 90、92 页；UCE PDF 第 94 页） | 从 SP6.1 安装目录 ADS_Synthesis_User_Guide §2.3 与该版 Compile 帮助取得正式方法；两份同输入同控制 FF 分别接可观察输出，比较基线和手册支持的防合并设置；每例从 Compile 重跑，随后确认 synth/map 均保留。不要把 map 默认不消除重复逻辑当成 Compile 修复 | ADS 原文页、精确属性/GUI/Tcl、Compile 合并日志，以及 Compile/synth/map 三阶段两 FF 的实例数/名称；若该版无此功能，明确记录，而不是报 map 通过就称保留成功 |
| 3 / R-W03 | 已知可声明多区域、父子 GUI 会冲突，但几何重叠/嵌套、单实例二次关联及普通区域排他规则未写全（UCE PDF 第 52、55、90 页） | 微型两兄弟 FF+LUT 层次分别建区，依次只改成几何重叠、几何嵌套、同实例二次关联；再加入一个无约束层次观察是否能进入区域。无需重测资源四类型支持或硬边界的定义 | 每例 FDC、GUI 最终属性、生成 PCF、解析/布局诊断、全部实例位置；说明覆盖/拒绝/其他结果；一次无约束逻辑未进入不能证明独占 |
| 4 / R-W04 | 手册有 APM/LUT 及通用 site/impl 语法，未给 Logos2 DRM18K 半块和 APM 级联的合法子位/邻接规则（UCE PDF 第 94–95 页；PDS PDF 第 76–77 页） | 先由 R-W01 的实际导出取得 DRM/APM 合法值，再用一对 DRM18K、一个 DRM36K 和现有最小 APM 级联在 PCE 各锁一组可用位置并保存；只改变半位或一个级联端点观察诊断 | GUI 保存的 FDC/PCF、每类实例/站点/impl、半位打包关系、级联位置与放置报告；不再把普通 LUT FGA 或已知 FF3 格式列为未知 |
| 5 / R-W05 | PAP_MAX_FANOUT/PAP_ALLOW_RETIMING 仅转引 ADS；ADS 截图给了 Fanout Guide/Retiming，但没给具体对象、Tcl、范围和算法（UCE PDF 第 98–99 页；PDS PDF 第 92 页） | 取得该版 ADS 属性章节；一 FF 驱动多个可观察负载，按正式选项取两个 fanout guide 值比较复制；对可观察寄存器链分别开关 ADS retiming。若合并影响观察，先采用 R-W02 已确认的方法 | ADS 页码、实际导出的选项 Tcl、各阶段驱动/负载/FF 位置数和复制警告；retiming 前后寄存器拓扑与时序；区分 fanout 指导值与硬上限 |
| 6 / R-W06 | 手册给出 Planning Before Place、LUT6D pack、RefinePlacement Mode、hold path 数量限制、multi-run Filter/Sort 的 GUI 语义，却未列完整 Tcl；PG2L200H route-hold 的逐 corner 细节也未展开（PDS PDF 第 110、113、115、118–120、252–253 页） | 在同一 P1 映射网表上，GUI 每次只切一个上述项目，保存 impl.tcl 并读该版 pnr 帮助；若需探明 route-hold 角落行为，取有 hold 违例的同一网表对比开/关后的两角报告。无需重复发现 mode/seed 接口 | SP6.1 帮助、GUI 生成的准确 Tcl/取值、该器件实际支持状态，slow/fast setup/hold 汇总及前后网表/布局变化；没有违例时不能据报告证明修复算法覆盖哪一角 |

R-W01 可与以下 P1 实验同步采集；除需要 Compile 保住手工复制 FF 的后续实验外，
R-W02 不阻塞区域、模式和多种子实验。其余未决项也不作为所有 P1 实验的前置门禁。

### 6.2 可以直接安排在 P1 上的布局实验

本节是实验建议，**没有测得收益**。以 P1 所用 commit、PDS SP6.1、PG2L200H-6 FBB676、
原时钟/引脚约束及 IP 为共同输入（B1:5–8；P1:1）。
区域实验固定同一份 RTL、IP 和综合/map 设置；新增区域 FDC 后从相同源重新
compile/synthesize/dev_map 产生关联 PCF，并记录网表/逻辑资源数是否变化。
只换 PnR mode/seed 时复用同一映射输入。
不改变 CPU 功能或频率来掩盖布局差异。

| 顺序/方案 | 约束或命令写法 | 比较目的与需导出的数据 |
|---|---|---|
| E00 无区域基线 | 原 P1 FDC；`pnr -mode normal -gplace_seed 0 -gplace_times 1` | 导出第 4.5 节位置、P1 原始 timing/resource、实际 pnr 命令和运行时间；新跑基线与历史 P1 分开记，确认可比条件 |
| E01 CPU 单矩形 | 第 4.1 节 `cpu_region(124,238,50,199)[CLMA,CLMS,APM,DRM]` 关联 `i:u_cpu_subsys`；保持 E00 mode/seed | 观察 CPU/cache 是否集中、全部 DRM/APM 是否留在矩形内；导出逐层次包围框、区内容量/使用、关键跨层次路径位置；若可布通，再单独缩 y 范围到 `(124,238,75,174)` 比较更紧矩形，容量依据实际覆盖资源重计 |
| E02 三条带 | 第 4.2 节三个兄弟层次的 `fetch_region` / `core_region` / `data_region`；保持 E00 mode/seed | 比较 I-cache→frontend、core→D-cache、分支返回路径的 route/logic delay、关键端点位置、各条带资源与拥塞；不对 `u_cpu_subsys` 再加父区 |
| E03 fetch 软性聚集 | 仅第 4.2 节两条 `PAP_GROUP {fetch_group}`；保持 E00 mode/seed | 比较硬条带与“尽量靠拢”的效果；导出 I-cache/frontend 实例位置、包围框、关键路径和 group 对应导出；不能以 group 存在代替时序改善 |
| E04 PnR 模式 | 同一映射网表及一份固定 FDC，分别 `pnr -mode fast -gplace_seed 0 -gplace_times 1`、normal、performance | 比较模式的实际耗时和时序/资源，保留各模式原始报告、mode/seed 日志和布局导出；先在 E00 上比较，区域效果较好后再组合 |
| E05 三种子 | 第 4.4 节 `-gplace_seed 0 -gplace_times 3 -seed_step 1 -saved_outcome 3 -parallel 1`，normal/performance 分别作为两组 | 导出 `multiseed_result.csv`、filter/sort、保留种子目录与实际种子；逐种子 apply 后导出两角 timing 和位置；比较分布，不只交最好 WNS；再把同一组种子用于候选区域验证稳定性 |

E01 缩区的坐标是**待试候选**；若最小容量/级联不满足，保留工具错误作为结果，
不能声称“手册保证在区内”等于“任意矩形都可布局”。
坐标/区域写法依据 UCE PDF 第 95–96 页，模式/种子依据 PDS PDF 第 109、115、252–253 页。
所有布局实验至少交付实际输入 commit、FDC/PCF、impl.tcl/命令、运行时间、LUT/FF/DRM/APM、
slow/fast 各时钟域 WNS/TNS/WHS/THS、最差 200 条 setup 汇总、最差 20 条 setup 逐级明细、
最差 20 条 hold、完整原始报告的 Windows 路径（仓库 `CLAUDE.md` §10.5）。
额外交付第 4.5 节位置导出和按 CPU/cache/SYS 的包围框；多种子数据按种子分别保存。
布线拥塞可用 GUI `Dump Router Congestion Plot`，报告目录产生 CongestionPlot /
CongestionNetInfo；这项默认关闭、Tcl 名本版未取得，可在需要解释拥塞时从 GUI 打开
（PDS PDF 第 114、119 页）。

## 7. 变更记录

| 日期 | 版本 | 修改及依据 |
|---|---|---|
| 2026-10-28 | 第一版 | 基于本项目 P1/P2/P3 结果、厂商 demo/器件数据手册整理内部排布与手动布局证据；任务引用提交 `05a6f67`，本次读取的分支文档基线为 `358246b` |
| 2026-10-28 | 第二版 | 依据 `Pango_Design_Suite_User_Guide` V1.5、`User_Constraint_Editor_User_Guide` V1.7、`Physical_Constraint_Editor_User_Guide` V1.3 逐项补充语法、坐标、资源与阶段边界，修正 PG2L200H hold 选项适用性，增加布局导出、可用 FDC/Tcl 与 P1 实验；Windows 未决项由 12 项重写为 6 项 |
