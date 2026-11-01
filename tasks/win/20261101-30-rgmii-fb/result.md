# 卡30：厂商基线与B3V外部反馈结果

## 结果摘要

| 项 | 实际结果 |
|---|---|
| A例程 | PG2L200H-6/FBB676，ref_clock重新生成；仅按用户要求将PC目的IP改为192.168.1.2；ARP/ICMP及板端固定UDP正常 |
| B反馈配置 | External Feedback、CLKOUT0，125MHz/0度/50%，有clkfb，仅clkout0输出 |
| B实现 | 各阶段结束，0条E错误；布局布线14m5s；约束被接受 |
| B时序 | **未满足**：slow RGMII hold WNS=-0.361ns、TNS=-1.698ns，5个失败端点 |
| B PHY复位 | 首次下载5/5；断电重下后5/5，合计10/10成功 |
| B视频 | ETH60秒持续收数；用户反馈显示正常，截图接收30.5fps、显示27.8fps、丢弃帧0 |

工作分支win/20261101-30-rgmii-fb，任务/RTL输入921ca8fc（含31ef0617外部反馈改动）。PDS2022.2-SP6.1，PG2L200H-6/FBB676；B工程G:/codex_project/EdRV32-FPGA/EdRV32-B3V。功能结果与时序未满足分别记录，不判整卡全部通过。

## A：厂商例程

原件未改，工作副本G:/codex_project/EdRV32-FPGA/EdRV32-ETH-VENDOR。原固定PC地址.105无法由当前进程添加，Windows拒绝访问；用户明确要求修改例程，授权覆盖卡A阶段RTL不改要求，仅改顶层DEST_IP .105→.2，重新实现下载后测试。没有改例程RGMII/PLL/FDC。差异及原文见vendor/user_requested_pc_ip_change.md、pc_destination_change.patch、source_used/。

板端192.168.1.11:8080、MAC a0:b1:c2:d3:e1:e1；PC192.168.1.2:8080。源地址绑定ARP成功；ping5/5，0丢包，均<1ms。UDP采集60.075920秒：PC发60包，收到60条板端固定20字节消息，内容全匹配、异常0。源码无UDP负载回环，不能将收发数相同解释成PC请求逐包echo成功或UDP端到端丢包率为0。方法、每包hex/时间/方向及原始PC输出见vendor/。

A原厂时序报告All Constraints Met，但厂商FDC没有RGMII输入/输出延迟约束，不代表已证明RX采样裕量。PLL位于GPLL_7_1381，全局缓冲USCM_383_930；实现报告、时序和站点全文保存在vendor/native_reports及对应汇总。未取得Wireshark抓包。

## B：IP与实现

实际生成参数见ip_pll_eth/regenerated_parameters.txt：FB_MODE=true、INTERNAL_FB=DISABLE、EXTERNAL_FB=CLKOUT0；CLKOUT0 125MHz、0度、50%，仅clkout0/clkin1/clkfb/lock四端口，No Buffer、无reset、LOCK_MODE=0；STATIC_RATIOI=1、RATIOM=1、RATIO0=8。生成过程中曾发现反馈源CLKOUTF及多余CLKOUTF输出，用户纠正后才运行本次实现；初次检查记录也保留。IP GUI截图未取得，实际配置与端口原文已保存。

| 阶段 | 实际耗时 | CPU | Process CPU | 峰值内存池 | W行 | E行 |
|---|---|---|---|---|---|---|
| compile | 1m36s | 14s | 14s | 496MB | 3138 | 0 |
| synthesize | 4m22s | 56s | 58s | 2498MB | 9236 | 0 |
| device_map | 47s | 6s | 7s | 1376MB | 56 | 0 |
| place_route | 14m5s | 2m41s | 4m28s | 5280MB | 694 | 0 |
| report_timing | 1m9s | 12s | 14s | 4694MB | 161 | 0 |
| bitstream | 1m24s | 2s | 2s | 3500MB | 0 | 0 |

原厂CMR/SNR/DMR/PRR/RTR及警告节选保存于native_reports/、logs/，不以警告行数当作独立问题数。当前FDC也已保存，未自行修改RTL/约束或IP。

## B：PLL与外部反馈时钟路径

PRR实际位置：ETH PLL GPLL_7_1381，系统PLL GPLL_727_463，ETH缓冲USCM_383_930。PRR明确记录PLL CLKFB的源是u_rgmii/u_eth_clk/gopclkbufg的CLKOUT、网络clk_eth_w；见clock_sites.txt。

定向报告最差hold路径完整原文在rgmii_rx_clock_path.txt。捕获时钟路径的GPLL_7_1381/CLKOUT0单元td延迟为**-2.807ns**，后续全局缓冲td为0.177ns；原文保留负值，不人工归零、相减或修改裕量。时序路径未将整个反馈回路作为独立的一串条目展开，反馈连接另由PRR证明；不能将负延迟视为所有引脚/IO路径均完全补偿的证明。

## B：RGMII双沿时序

定向命令：

```tcl
report_timing -input_db_file {G:/codex_project/EdRV32-FPGA/EdRV32-B3V/place_route/edrv32_fpga_board_vision_top_pnr.adf} -delay_type min_max -max_path 200 -nworst 20 -from {rgmii_rxd_i* rgmii_rx_ctl_i} -input_pins TRUE -force_to_run
```

| 工艺角 | 捕获沿 | RX最差setup/ns | RX最差hold/ns |
|---|---|---|---|
| slow | rising | 0.319 | -0.361 |
| slow | falling | 0.232 | -0.260 |
| fast | rising | 0.516 | 0.136 |
| fast | falling | 0.513 | 0.141 |

slow RGMII hold WNS=-0.361ns、TNS=-1.698ns，5个失败端点。setup slow0.232ns、fast0.513ns，fast hold0.136ns。全部时钟域WNS/TNS/WHS/THS和recovery/removal/pulse检查在timing_summary.txt及timing_minima.txt。

定向导出80条：每角setup/hold各20条，每类上升/下降沿捕获各10条，覆盖四条RXD及RX_CTL。保存每角最差20条逐级明细、边沿覆盖计数及完整定向RTR；时钟路径包含输入引脚/缓冲、PLL、全局缓冲、IDDR端点每一级。原报告未约束输入警告中未见这五个RX端口，但其他未约束端口警告保留。

全局-max_path200/-nworst1导出12072条，含5条负裕量样本；数量只代表导出样本，不是失败路径穷举。setup/hold索引、每角最差20条、<1ns危险路径都保存。完整全局扩展RTR留在build/win/20261101-30-rgmii-fb/exports/global200/，未提交超大重复报告或数据库。两次补导出在60秒视频采集结束后才运行。

## B：两批PHY复位

每轮r后等link=1 speed=1000 duplex=full，发s取完整状态，约10秒后再发s。独立probe绑定192.168.1.2:6000每秒发包；按PERF1≥8且PERF3不增加判定。未修改PHY延迟或自动重复样本。

| 批 | 次 | 实测间隔/s | PERF1增量 | PERF3增量 | 成功 |
|---|---|---|---|---|---|
| 1 | 1 | 10.120 | 10 | 0 | 是 |
| 1 | 2 | 10.308 | 10 | 0 | 是 |
| 1 | 3 | 10.091 | 10 | 0 | 是 |
| 1 | 4 | 10.090 | 10 | 0 | 是 |
| 1 | 5 | 10.195 | 10 | 0 | 是 |
| 2 | 1 | 10.155 | 11 | 0 | 是 |
| 2 | 2 | 10.148 | 10 | 0 | 是 |
| 2 | 3 | 10.148 | 10 | 0 | 是 |
| 2 | 4 | 10.153 | 10 | 0 | 是 |
| 2 | 5 | 10.124 | 10 | 0 | 是 |

合计10/10成功，所有PERF3增量0。第二批为用户断电上电并重新下载同一比特流、加载诊断程序后；物理操作按用户完成反馈归属。原始串口、probe及前后值见phy_reset_round1/、phy_reset_round2/、phy_reset_summary.md、phy_reset_combined.json。只对本轮实测窗口下结论，不以功能通过忽略hold违例。

## B：ETH视频60秒

卡24demo_vision.bin经COM7/115200加载成功，Output mode=1、目标30fps、monitor100Hz。采集期间没有运行PDS，未修改PHY延迟。0/10/30/60秒PEER均192.168.1.2:6000、rx active且error=null；数据持续增长，UDP计数79552→3284830、字节81416160→3361858048。这些是包/字节，不冒充完整视频帧计数。

用户反馈显示正常，原始截图保存于photos/video_eth_gui.png。截图读数：接收30.5fps、显示27.8fps、丢弃帧0、缓冲64MiB、网口跳帧33；画面标题30.0fps、1280x720、FRAME2857。截图晚于60秒API采集窗口，为瞬时单点，不作为60秒平均或起点值。GUI起点帧率/丢弃数未取得。

EDTM records165→6149，序号缺口lost0→16，decode errors保持0；video_skipped2→23。video_skipped是工具对EDTM vid_skip字段的累计，截图后续值33另记；不等同于不完整视频帧丢弃数0，也不能换算成UDP丢包数。串口四次Video skips(current window)=0只代表查询窗口，不覆盖累计跳帧。Monitor dropped records保持2381，连接前已有值未作为期间新增。

CLINT60.00105375秒内camera0/1各增加1800帧，均29.99947fps；VIN CH0溢出四次为0。完整状态、原始EDTM CSV、串口采样和相机计算输入见video_eth/。

## 问题与偏离

- B时序判据未通过，slow RX hold仍违例；PHY10/10及视频正常分别记录，不标整卡全部达标。
- 视频截图丢弃帧为0，但没有起点GUI截图；EDTM lost与累计跳帧实测有增长，不写成所有丢失计数都不增长。
- IP GUI设置截图未取得；实际生成参数/端口和布线反馈连接证据已取得。
- A仅按用户授权改变PC目的IP，不标成完全未改动的厂商RTL；无UDP echo、无pcap。
- 本轮未改路由或关闭TUN，未重新配置已生成的IP、RTL、FDC。
- 不上传IP生成目录、PDS工程数据库、bitstream或完整原始run.log。较大原厂DMR、SNR、EDTM CSV用于保留资源/时序/监控数据，未以默认少量时序路径代替定向采样。
