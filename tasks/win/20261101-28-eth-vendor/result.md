# 卡28：厂商以太网例程与PHY时序资料

分支 `win/20261101-28-eth-vendor`，任务输入 `26eb3465`。本次只访问本地文件、提取原文和渲染PDF页面；未上板、未运行PDS、未修改RTL/约束/导入脚本。卡27已由下发提交取消，本次未执行卡27。

## 资料索引

| 项 | Windows本地路径 | 摘要与产物 |
|---|---|---|
| UDP/RGMII RTL | G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/2_Demo/2_11_ethernet_test/2_11_ethernet_test/source/ | 复制ethernet_test.v、rgmii_interface.v原文至artifacts/demo_rtl/udp_2_11/；包括IDDR、ODDR、IODELAY和PLL连接 |
| UDP PLL | G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/2_Demo/2_11_ethernet_test/2_11_ethernet_test/ipcore/ref_clock/ | 复制ref_clock.v/.idf；请求125MHz→125MHz、30°、50%，内部CLKOUTF反馈，外部反馈禁用，No Buffer；实际生成参数原文均保留 |
| UDP FDC | G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/2_Demo/2_11_ethernet_test/2_11_ethernet_test/ethernet_test.fdc | 全文artifacts/demo_fdc/udp_2_11.fdc；有RXC/TXC两个8ns create_clock；未找到input/output delay或PLL/时钟buffer站点约束 |
| 三速例程RTL/MDIO | G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/2_Demo/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/source/ | 当前顶层仅PLL+MDIO速率读取，无RGMII数据端口；复制顶层、mdio_ctrl、mdio_master_driver |
| 三速例程PLL | G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/2_Demo/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/ipcore/ | pll_gen为当前顶层使用；另存留有ref_clock配置但未在当前顶层例化，不能当作有效RGMII方案 |
| 三速例程FDC | G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/2_Demo/4_13_tri_eth_test/4_13_tri_eth_test/ethernet_test/ethernet_test.fdc | 全文artifacts/demo_fdc/tri_4_13.fdc，仅PHY reset/MDIO/MDC/系统时钟及LED引脚属性；无input/output delay、PLL/buffer站点约束 |
| 原理图PHY上下拉/串联电阻/走线 | G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/3_Hardware | **未找到本板原理图**；已找到资料仅点位图/结构图/映射表。schematic_phy.txt明确说明，未制作假原理图截图 |
| 硬件说明 | G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/1_Demo_document/实验例程说明篇/教程1 盘古100K MINI 硬件指导手册-盘古676系列.pdf | PDF28/印刷26的网络框图及后续引脚表；只有连接框图，不能证明strap电阻；见board_phy_block_diagram_pdf28.png和demo_docs/hardware_network.txt |
| RTL8211F手册 | G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/4_IC_datasheet/Ethernet_PHY/C187932_以太网收发器_RTL8211F-CG_规格书_WJ14392.PDF | Rev1.4；PDF67/印刷60 Table60时序表截图与抄录；另保存延迟模式、strap脚及寄存器页 |
| Logos2器件手册 | G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/4_IC_datasheet/FPGA/DS04001_Logos2系列FPGA器件数据手册.pdf | PDF12说明IOL动/静态延迟并引用UG040006；未给出IODELAY步进/范围或SAME_PIPELINED波形 |
| Logos2 PLL IP指南 | G:/Program/pango/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_pll/ipm2l_flex_pll_eval/ipm2l_pll/UG041001_PLL_IP.pdf | PDF19/20/45：反馈模式/反馈源及内部反馈结构，PNG与对应原文均保存 |
| Logos2 IO/GTP详细指南 | 上述资料包及本地PDS文档中未找到 | UG040006、SAME_PIPELINED正式波形页、IODELAY_E2正式步进/PVT页均标未找到；不以Logos旧系列UG020007替代 |

全部复制文件和截图的原始路径、PDF页码逐项列于 `artifacts/source_index.txt`。仅复制相关文件；没有复制完整资料包、完整PDF、工程数据库或无关IP。

## 例程事实

### UDP例程

- `ethernet_test.v`：ref_clock输入为外部rgmii_rxc，clkout0叫rgmii_clk_90p，但idf请求相位为**30°**；该输出接到rgmii_interface.rgmii_rxc后经过CLKBUFG供IDDR/ODDR使用。不能凭网络名90p改写配置。
- `rgmii_interface.v`：RX数据和控制的PORT延迟值为247，经二进制→Gray编码送入GTP_IODELAY_E2；TXC延迟100步。源码注释为0~247、10ps/step；据此算术值2.47ns/1ns，不声称这是已取得的PVT保证。参数DELAY_STEP=8'hE6同时存在，但生效选择是PORT，不能把静态参数当作端口实际值。
- IDDR为SAME_PIPELINED；控制RS_TYPE=SYNC_RESET，数据为ASYNC_RESET，RS均接0。ODDR及IO缓冲等完整原文保留。
- PLL配置提取见demo_pll_parameters.txt：CLKIN_FREQ=125、CLKOUT0_REQ_FREQ=125、请求30°/50%；STATIC_RATIOI=5、RATIOM=2、RATIO0=8、STATIC_PHASE0=5，INTERNAL_FB=CLKOUTF、EXTERNAL_FB=DISABLE。请求相位与生成参数分别照录，没有把请求值自行换算成引脚实测相位。
- 全部source Verilog未找到MDC/MDIO配置；phy_rstn来自PLL lock。没有找到对0xd08/0x11、0xd08/0x15或0xa43的写寄存器流程。

### 三速例程

当前source顶层只例化pll_gen与mdio_ctrl，PHY reset接sys_rst_n；不是当前可见的RGMII回环数据通路。pll_gen请求27MHz→50MHz、0°（全部字段见demo_pll_parameters.txt）。目录还存留未被当前顶层例化的ref_clock，idf请求270°，不能与UDP例程的30°混用或声称它正在采样RGMII。

MDIO唯一找到的配置写为PHY地址1、reg0x1f←0x0a43，之后读0x1f确认并周期读0x1a监测速率。没有找到RXDLY/TXDLY配置写。原文及行号说明见demo_mdio.txt，教程4 PDF157–158亦有明确说明。

两个例程主FDC及三速constraint_backup的FDC搜索中均未找到set_input_delay/set_output_delay或PLL/clock-buffer位置约束。未把PAP_IO_LOC引脚约束误记为PLL位置约束；只上传当前主FDC，不上传全部历史备份。

## RTL8211F时序与配置

来源Rev1.4，PDF67/印刷60 Table60，单位ns：

| 符号 | 条件 | Min | Typical | Max |
|---|---|---|---|---|
| TskewT | transmitter输出，不含内部延迟 | -0.5 | 0 | 0.5 |
| TskewR | receiver输入，含PCB延迟 | 1 | 1.8 | 2.6 |
| TsetupT / TholdT | 延迟集成在transmitter | 1.2 | 2 | 未给出 |
| TsetupR / TholdR | 延迟集成在transmitter | 1.0 | 2 | 未给出 |

表中TskewR另要求关联时钟PCB额外延迟>1.5ns且<2.0ns；这是接口条件，不是本板走线已满足的证据。10/100Mbps最大skew未规定。完整抄录及脚注见rtl8211f_timing.txt，PNG已目视核对。

PDF16/印刷9和PDF23/印刷16：TXDLY/RXDLY置高增加2ns，配置脚分别复用RXD1/RXD0。TXDLY芯片内部默认下拉、RXDLY默认上拉；不能用这些芯片默认代替本板外接strap电阻结论，也不能据此覆盖卡26现场读到的1/1。

**手册寄存器说明缺口**：本版没有找到0xd08/0x11的TX延迟位说明；PDF55/印刷48对0xd08/0x15仅说明bit6为RGMII In-band CRS，bit5:0标Reserved，并未说明软件使用的RXDLY bit3。对应原文与截图已上传，不将这两个delay位写成已获本版文档证明。

## PG2L IODELAY、IDDR、PLL边界

已取得PLL内部/外部反馈定义和反馈源，尚未找到能证明“输出相位相对输入引脚、经过实际BUFG/IO路径完整补偿”的正式说明。UG040006/Logos2详细GTP指南未找到，正式IODELAY步进/PVT范围、SAME_PIPELINED波形均未取得；见pg2l_iodelay_pll.txt。

补充了PDS仿真模型相关行（pg2l_simulation_excerpts.txt）：IODELAY参数范围0x00–0xF7、IDDR输出选择syn_neg_w/syn_pos_w。仅作为模型原文，不替代芯片时序规范，未运行仿真。

## 缺失与偏离

1. schematic_phy.png未生成：未找到本板电路原理图；只有明确标为block diagram的手册图。未确认strap电阻、RGMII串阻或实际板上走线延迟。
2. 正式Logos2 IO/IDDR详细用户指南缺失；用“未找到”记录，没有套用不同系列或推测数值。
3. 资料包名为pago_200，但手册标题、例程IP header有PG2L100H/FBG676，手册框图又写PG2L200H；只保留原文，不推定这些资料与当前实物修订完全相同。
4. 只提供固定设置与约束设计所需的资料，不在本卡选择最终PHY/IODELAY/PLL组合，也不修改RTL或FDC。
