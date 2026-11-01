# 卡24三工程重跑：B3R完整实现与上板回传

代码输入fda551b0，源文件102，器件PG2L200H-6 FBB676，PDS2022.2-SP6.1。B3R流程已完成并上板；本次不将B3N/B3V填成完成。报告数字来自已运行报告和串口日志，没有重新综合或布局布线。

## 结果摘要

| 项目 | 结果 |
|---|---|
| 实现 | Compile/ADS/Device Map/PnR/Timing/bitstream完成，原实现流程E=0 |
| 布局布线 | 4h21m38s，639轮，Detailed routing14772.91s |
| 主要时序 | clk_mem setup +0.122ns，RGMII RX slow hold -0.361ns，仍Some Constraints Violated |
| 应用网口PHY复位 | 5/5 PASS，每轮有效UDP+10，PERF3+0 |
| RND自检 | 29组CRC与卡24rnd_expected.log全部一致，29/29 PASS |
| S3 | Benchmark平均24fps，16场景均非零；RN-17一条汇总PASS；用户确认LAYERS正常 |
| NES | 超级马里奥1超级版运行，用户确认键盘/鼠标松键正常；模拟fps均值54.53、shown18.07 |
| BIOS串口 | 115200成功；921600成功；2000000切换后乱码，未开始镜像数据传输 |
| BIOS网口 | ETH load ready后SendARP error67，sent=0，失败 |
| EDTM/照片 | 本轮S3/NES有效EDTM与照片未取得，不填正常值 |

## 实现耗时和资源

| 阶段 | 实际耗时 | CPU / Process CPU | 峰值内存池 | W / C / E行 |
|---|---|---|---|---|
| Compile |2m1s|7s / 7s|561MB|3166 / 0 / 0|
| Synthesize |5m58s|27s / 28s|2955MB|10239 / 34 / 0|
| Device Map |58s|8s / 8s|1655MB|40 / 0 / 0|
| PnR |4h21m38s|56m52s / 1h3m45s|5119MB|693 / 35 / 0|
| Report Timing |1m25s|16s / 16s|5476MB|133 / 0 / 0|
| Bitstream |1m29s|21s / 21s|3778MB|0 / 0 / 0|

消息行不等于独立问题数。完整CMR/SNR/DMR/PRR/RTR/BGR在artifacts/b3r/native_reports；按代码警告计数及原文节选在warning_counts.txt、logs/。Compile constant-probe loop、综合未约束端口、共享引脚/驱动强度等提示均保留，没有自行消除或认定根因。

Device Map资源：LUT66805（42%）、FF56157（18%）、DRM117.5（29%）、APM131（18%）、Distributed RAM750（2%）、IO109（28%）、GPLL5/PPLL2。包含子层次的完整SNR表见resource_hier.txt，不叠加父子模块数值。Clock/Reset/CE/Other High Fanout完整表、controlsets及RND高扇出条目均保存。Other表内u_rnd/N493_1负载1050等原文供Claude对照，报告范围外网络不补造负载。

### 与卡23比较及重叠说明

卡23任务卡基线PnR约4h21m、776轮、Detailed routing14695s、clk_mem setup约+0.003ns。本轮4h21m38s、639轮（减少137轮）、Detailed routing14772.91s（增加77.91s）、clk_mem +0.122ns（增加0.119ns）。**轮数下降，但实际耗时未明显下降。**

本轮GUI布线线程实际为5。卡31B3F首次后台启动17:38:05，按用户要求停止，后由用户重新运行，Map结束17:54:07；期间与R PnR重叠（R结束20:33:42）。17:38:05–17:54:07是活动窗口，中间停止/重启间隔未精确记录，不作为连续满负载时间；因此R耗时不是完全独占机器条件的严格对照。卡31也记录同一备注。

## 布线后时序

slow setup：clk_mem +0.122ns，clk_sys +0.459ns，clk_eth +0.654ns；fast最小setup为RGMII RX +0.513ns。
slow RGMII RX hold WNS=-0.361ns、THS=-1.698ns、5个失败端点，为本卡指定例外，仍照实回传；不宣称全时序零违例。其余已列顺序路径没有负hold，fast clk_mem最小hold +0.097ns，属于危险正裕量。
recovery最小slow +2.282ns/fast +4.469ns；removal最小slow +0.245ns/fast +0.169ns；最小pulse width +0.035ns。原始各时钟WNS/TNS/WHS/THS及失败数见timing_summary.txt。

clk_mem最差setup：xbar读缓冲DRM的CLKB[0]到u_rnd/u_draw/u_geometry/edge_sample_r[2][35]/opit_0_AQ_perm/CE，5级逻辑、+0.122ns，完整路径见clk_mem_worst_setup.txt。

从已完成的PNR数据库只读补导出global max_path200/nworst1，取得9624条路径样本；包含负裕量及小于1ns的危险正裕量索引，另存每角最差20条完整明细。路径样本数不当作全部失败端点数。全局展开大RTR留build，不提交；所需明细、索引和原生RTR已保留。

### RGMII双沿与外部反馈

| corner | setup上升/下降 | hold上升/下降 |
|---|---|---|
| slow | +0.319 / +0.232ns | -0.361 / -0.260ns |
| fast | +0.516 / +0.513ns | +0.136 / +0.141ns |

定向80条路径、双沿覆盖和完整时钟路径已保存。PRR：ETH PLL GPLL_7_1381，全局缓冲USCM_383_930，CLKFB由u_rgmii/u_eth_clk/gopclkbufg的CLKOUT、clk_eth_w驱动。原文见clock_sites.txt、rgmii_rx_clock_path.txt、rgmii_rx_*。

## 上板数据

- **PHY**：115200加载eth_diag后，每秒probe1包，每轮r→千兆全双工→s→约10秒→s；5轮PERF1均+10、PERF3均+0，判5/5。probe已结束，未改PHY延迟。逐轮计数、probe收发和串口见phy_reset/。
- **RND**：crc_comparison.txt逐项对比卡24期望，29/29一致、ERR_CODE输出为0，见rnd_selftest/。
- **S3**：完整Benchmark Summary、17条split（16场景+ALL，含CPU/cache/RND/draw/copy等字段）在s3/。平均24fps，Widgets16，Containers with opa_layer3；RN-17 full_max_lsb0、edge_max_lsb21、over1_ppm1559、PASS。只有一条汇总，不能改写为逐项15/16。日志未见S3 CPU mcause，用户确认LAYERS正常；菜单五项两轮、WIDGETS独立30秒和S3松键没有逐项确认，未补写。
- **LAYERS5**：unclaimed始终0，claimed含9/10和交互后累计336，重新进入场景会重置，不能跨场景相减。无照片。
- **NES**：用卡24nes.elf配合--rom单独加载用户本地超级马里奥1超级版，未打进ELF、未上传ROM。mapper0、PRG32KiB/CHR8KiB，155条fps样本模拟均值54.53/shown18.07，含标题与游戏阶段。按键/鼠标松键用户反馈正常；load_and_run.raw及GUI后续日志已保存。NES首次只加载ELF时ROM槽为空，单独加载ROM后正常，不归为兼容失败。
- **BIOS115200**：eth_diag、RND、S3及NES串口加载均取得PASS/Run；没有独立精确传输时长测量，不填推算耗时。
- **BIOS921600**：日志有两次切换后正常菜单和Load PASS/Run，分别可见RND display ready和S3运行。工具最后选择s3.elf，发送完成且error=null。见baud_921600/。
- **BIOS2000000**：实际选s3.elf；Baud result后乱码/NUL，无正常新速率菜单，sent0；随后断开串口导致最终error，不将断开当作最初乱码原因。BIOS阶段仍有1B56虚拟输入帧及Input error，记录为干扰证据、不认定根因。芯片CP210x，VID10C4/PIDEA60，驱动Silicon Labs11.3.0.176；见baud_2000000/。API无原始接收字节，保存解码条目而不伪造.raw。
- **BIOS网口失败**：ETH link up/load ready后，主机SendARP error67、sent0；错误时邻居Unreachable。错误状态和缓冲、整理时网卡/路由/ARP输出在bios_eth_diag/；当前邻居查询无对象的命令错误也保留。未取得pcap、专用BIOS probe或独立CLI复测，不将应用5轮probe混为BIOS诊断。
- **EDTM**：S3工具records0/latest null，CSV仅表头；S3/NES遥测未取得。没有依据旧会话UDP包计数宣称EDTM成功。

本轮功能测试成功项与失败项分别保留。资料包含完整必要原厂报告（DMR约2.15MB）及工具会话JSON/文本（部分单文件数MB，用于保留乱码和错误上下文）；不提交IP目录、数据库、网表、bitstream、ROM或完整原始PDS日志。
