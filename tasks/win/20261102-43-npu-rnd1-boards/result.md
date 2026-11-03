# 卡43：完整版F D2/D3失败、VN实现与上板结果

代码输入13a17403ef38b27aedbfa9a816d5103aff1dce8d（实验分支zc100116/b3f-rnd1-npu-opt）：最新Q6+OPT2 NPU，RND v1。PDS2022.2-SP6.1，PG2L200H-6 FBB676。本文汇总本次F两种参数及VN；N、VRN完整验收不在本次已完成范围。原准备过程及早期测试记录另存artifacts/preparation_and_test_notes.md。

## 实现结论

|工程|Decongestion|源文件/ILA|PnR墙钟|CPU / Process CPU|峰值内存池|结果|
|---|---:|---|---|---|---:|---|
|F|2|159 / 400位ILA|1h56m55s|33m7s / 35m41s|6646MB|Route-0039、Route-0008，未布通|
|F-D3|3|复用F综合与Map|1h30m20s|18m10s / 22m45s|7280MB|同上，未布通|
|VN|2|144 / 不插ILA|41m33s|8m13s / 15m27s|6775MB|第162轮0未布通/0过用，成功生成bitstream|

### F失败原文和收敛

两者均有：

- `E: Route-0039: Design is too congested to be routed, iteration time exceed limit 2000 sec.`
- `E: Route-0008: Design cannot be routed.`

|参数|最后输出轮次|未布通|overused|该轮MT total route time|布局耗时|布局后slack / TNS原值|
|---|---:|---:|---:|---:|---:|---|
|2|14|102322|581383|3278.766s|295.83s|380 / 0|
|3|10|101663|578965|2043.237s|325.80s|318 / 0|

这里是单轮路由时间超过工具2000秒限制，不是用户设置的总运行超时；两个版本均在第40轮前自行失败，未触发任务卡第40轮止损。正的布局估算裕量不能保证可布通，不把失败归因于某条尚未取得的最终时序路径。F-D3较早失败不代表质量优于D2。两份失败PRR、诊断原文、逐轮进度、首尾拥塞原始数据已保存；没有PNR完成数据库、最终时序报告或bitstream。

## VN时序

原生RTR结论是Some Constraints Violated，不能记为全时序通过。所有setup通过；已知RGMII RX慢角hold例外单列：clk_rgmii_ref→clk_eth WHS=-0.242ns，THS=-1.103ns，5个失败端点。

|时钟域|slow setup WNS|slow hold WHS|fast setup WNS|fast hold WHS|
|---|---:|---:|---:|---:|
|clk_sys|+0.784|+0.102|+4.523|+0.101|
|clk_npu|**+0.030**|+0.105|+2.507|+0.100|
|clk_mem|**+0.197**|+0.100|+3.258|+0.101|
|clk_pix|+3.653|+0.185|+7.444|+0.126|
|clk_serial|+1.706|+0.346|+2.084|+0.225|
|clk_eth|+3.051|+0.263|+4.972|+0.167|

全部时钟对、TNS/THS、recovery/removal和脉宽原文见artifacts/VN/timing_summary.txt。clk_npu仅30ps裕量，属于危险正裕量，不能因无setup违例就认为余量充足。原生最差路径从u_npu/u_conv/u_datapath/u_mac_array/g_activation_copy[1].g_lane[6].g_skew.activation_r[89]到g_channel[10].g_lane[6].g_cascade.u_mac的APM X[13]，即激活广播/偏斜寄存器到MAC输入，不是量化器路径。还需关注fast DDR相关hold最小+0.050ns及clk_mem slow recovery+0.194ns。

只对VN已有PnR数据库补导多路径时序，不重新跑实现；详细路径索引及危险正裕量样本与最终导出说明在VN时序产物中。失败F没有伪造最终路径。

## 资源与阶段日志

|Map资源|F（D2/D3共用）|VN|
|---|---:|---:|
|LUT|90151|69734|
|FF|103700|84513|
|DRM|291|219|
|APM|386|304|
|分布式RAM|2206|2062|

F前置阶段：Compile2m35s/818MB，综合9m34s/3926MB，Map2m13s/2481MB，均E=0，ILA实际插入。VN：Compile2m23s/744MB，综合7m23s/3541MB，Map1m24s/2009MB；时序2m7s/6280MB，bitstream2m5s/3979MB。CPU时间、消息代码计数及不同诊断原文分别在flow_summary.txt、warning_counts.txt、logs/。消息条数不作为独立缺陷数量。

resource_hier.txt为综合阶段层次表，不含之后插入的ILA；Map汇总含ILA及优化，不能简单作差当作独立ILA资源。父子层次不能相加。高扇出设置1000，保留Clock/Reset/CE/Other四表、控制集。D3复用D2的综合与Map，只独立保存PnR结果。

## VN上板测试

用户已下载VN新bitstream；两摄像头ID均0x5640，DDR MEM_READY=1。

### BIOS与ETH

- 串口2M切换后乱码，加载未完成；失败原文保留。115200串口加载eth_diag成功、自动运行。
- GUI网口加载eth_diag：1/1成功，4277B单段；CLI独立网口加载：1/1成功，均Run0x10000000并启动诊断程序。
- PHY复位接收5/5，通过时1000M全双工。10秒PERF1增量10/8/10/10/10，PERF3增量全部0。PC也收到板端EDRV32 DIAG UDP回复。
- 保持Clash及现有物理网卡直连配置；未修改PHY延迟。不是多次网口烧录稳定性测试。
- demo_vnpu初期PEER显示未知，但已有遥测；发送status后板端回读192.168.1.2:6000，GUI确认。记录为状态回读问题，不误判网口断开。

### NPU自检

网口加载board_npu.elf成功，programmedBytes5184584，自动Run0x80000000。**NPU board PASS39/39**，A3+B15+C1+D20全部PASS；C-YOLO PERF0=6105990，MAC=5347440，40.706ms/frame，24.566fps，CRC32=0738f96e，D01..D20 CRC一致。原文见VN/uart/board_npu.log。这是VN硬件测试，不冒充独立N实现结果；核心fps不等同摄像头或上传图片端到端fps。

### 摄像头与模型

模型3247136B，EDNM loaded。最初无框时实际Scene2、推理次数0；切到Scene1后推理次数43、检测数2，CH0/CH2 overflow0，用户反馈能出框并确认测试正常。样本NPU cycles6209960、Post cycles2802348、Overlay CPU cycles1230676。软件已有NMS，不记录“未做框去重”为已确认缺陷。未取得完整指定60秒EDTM或检测框照片，相关项如实标为未取得。

### 单图和批量

单图bus、cat、person三张均完整回传，对应2/2/1框，往返358.83/311.90/302.47ms。文件夹前7张成功，最后000000014888.jpg；下一张000000015278.jpg上传完成后未见新图像窗口/完整结果，之后持续“回传未结束（超时1s）”。现场快照已保存10次完成回传和39条超时，不能视为整个160张队列的最终统计；status当时未获回复。批量检测判失败，根因未确认，未自行改RTL或加大超时。完整会话与状态见VN/image_batch_issue/。

## Decongestion1副本

按用户要求复制D2完整F为：
`G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1-N-D1/EdRV32-B3F-RND1-N-D1.pds`。

保留综合与Map数据库/阶段状态、IP及FIC，FIC改指副本本地ADF，Decongestion改1、拥塞图保持开启；旧PnR/时序/bitstream未复制，PnR及以后状态待运行。Codex未启动流程；整理期间已观察到用户启动D1的PnR。副本可复用综合/Map，不需重新导入、综合或Map。

## 本地目录与提交范围

F原目录G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1-N；D3为其-D3副本；VN为EdRV32-B3VN-Q6-OPT2，bitstream在generate_bitstream/edrv32_fpga_board_vnpu_top.sbit。完整原始run.log留在各目录；本次上传精简诊断和上下文、原生CMR/SNR/DMR/PRR/RTR、测试原文、FIC及必要拥塞数据。SNR/DMR约1–3MB，保留完整层次/约束供分析；不提交数据库、网表、IP生成目录、PDS工程或bitstream。

卡43整体仍未完成：F未布通，VN批量异常，N/VRN其它结果待单独整理；不标为全卡通过。

## VN多路径补导完成

从既有PnR DB成功导出12892条时序样本，slow/fast各有3223条max及3223条min；其中0至+0.200ns危险正裕量setup/hold样本1828条。每组最多200条slow setup索引、全局最差20条setup/hold逐级明细、级数>=8样本计数均保存；完整约101.7MB RTR无删减gzip为约2.35MB，便于复查大量路径，数据库未上传。权重相关在本次导出中取得11条样本，未冒称已完成每方向20条定向查询。所有数量是导出样本数，不是全设计路径总数。
