# 20261029-05-b3-vision 结果

B3V已完成编译、综合、器件映射；布局布线在routing阶段失败，停止于任务步骤5。未生成bitstream，未上板。

| 项 | 内容 |
|---|---|
| 代码commit（zc100116/b3） | eef7537b97f957e3cf53f9cbceb52d9d8f4505c2 |
| PDS / 器件 | 2022.2-SP6.1 build138931；PG2L200H-6/FBB676 |
| 工程路径 | G:/codex_project/EdRV32-FPGA/EdRV32-B3V |
| 导入源文件数 | 112 |
| 运行方式 | 用户在GUI执行，与其他工程并行准备/运行；未另核对并发进程时间 |

## 布线失败

- 总网络80380，布通80379；剩余1条GND常量网络。
- 失败负载：IOLHR_16_678、702、726、750的OSHIFTIN0和OSHIFTIN1，共8处。
- Route-2014列出不可达端点；Route-0038与Route-0008终止流程。
- PnR耗时23分7秒；其中routing为853.38秒，峰值内存6581 MB。
- 未见资源容量超限；物理资源APM 153/740、DRM 109/415、IO 137/400。

初步排查方向：TMDS四个从串化单元将级联输入接0，与8个失败端点的形态对应；物理位置与TMDS IO区域相近。但尚未建立物理单元到RTL实例的逐个映射，DDR PHY也使用这些端口，不能认定最终根因，更不能直接把接0判定为错误。请协调者检查级联原语配置、映射和常量布线。

证据：`artifacts/route_failure/`；完整失败网络报告5.9 MB，包含18332个负载和路由树，保留用于定位专用IO端口不可达原因。未提交DB/ADF。

## 各阶段耗时和日志

| 阶段 | Real | CPU | Process CPU | 峰值内存 | W / C / E行数 |
|---|---|---|---|---|---|
| compile | 0h:1m:47s | 0h:0m:7s | 0h:0m:7s | 488 MB | 2842 / 0 / 0 |
| synthesize | 0h:5m:1s | 0h:0m:27s | 0h:0m:30s | 2,507 MB | 7899 / 62 / 0 |
| device_map | 0h:0m:52s | 0h:0m:4s | 0h:0m:5s | 1,448 MB | 19 / 0 / 0 |
| place_route | 0h:23m:7s | 0h:2m:34s | 0h:4m:19s | 6,581 MB | 0 / 69 / 2 |

完整warning/critical/error行、分类计数、阶段耗时见flow_summary.txt和logs/。保留常量传播Loop提示，但它本身不证明RTL组合环。GUI历史导入日志与最终阶段日志分开保存。

## 约束

综合SNR列出16个时钟；clk_sys=10ns、clk_mem=8ns、clk_pix=13.468ns、clk_serial=2.6936ns、clk_cam0/1=10ns、clk_eth=8ns，以及DDR内部时钟。无clk_npu。详见clock_checks.txt和原生SNR。
约束检查：857条约束，0 error、61 critical warning、0 warning；共享引脚和IO属性提示保留在原生CCR中。没有修改FDC。综合识别时钟不等于完成路后约束/时序验收。

## 时序

路后slow/fast角WNS/TNS/WHS/THS、路后Fmax、每时钟setup最差200条和最差20条setup/hold：未取得，因为布线失败，未运行report_timing。

以下仅为综合单角预估。全部已报告172条路径（包括正裕量路径、跨组路径、无约束路径）的一行列表和逐级明细已保存，未只截取违例。不能作为路后签收。

| 时钟组 | 已报告setup最差裕量ns | 已报告hold最差裕量ns | setup / hold路径数 |
|---|---:|---:|---|
| clk_cam0 | 6.046 | 0.555 | 3 / 3 |
| clk_cam1 | 6.046 | 0.555 | 3 / 3 |
| clk_sys | -0.097 | 0.324 | 3 / 3 |
| clk_pix | -8.976 | 0.619 | 3 / 3 |
| clk_serial | 0.484 | 1.809 | 3 / 3 |
| rst_clk | 1.787 | 0.507 | 7 / 7 |
| clk_mem | -7.371 | -2.926 | 10 / 10 |
| phy_dq_sysclk_0 | 5.913 | -1.316 | 3 / 3 |
| phy_dq_sysclk_1 | 6.138 | -2.552 | 3 / 3 |
| clk_eth | 3.483 | 0.619 | 3 / 3 |

综合预估中特别需要审查：

| 时钟 | 起点 → 终点 | 裕量ns | 逻辑级数 |
|---|---|---:|---:|
| clk_pix | u_disp/u_timing/horizontal_r[2]/CLK (GTP_DFF_C) → u_disp/u_green/data_ones_r[2]/D (GTP_DFF) | -8.976 | 25 |
| clk_mem | u_mem/u_perf_mon/hist_width_r[1]/CLK (GTP_DFF_CE) → u_mem/u_perf_mon/hist_r[0][31]/D (GTP_DFF_CE) | -7.371 | 25 |
| clk_sys | u_sys/u_plic/priority_r[2][1]/CLK (GTP_DFF_CE) → u_sys/u_plic/axi_rdata_o[0]/D (GTP_DFF_E) | -0.097 | 16 |
| clk_serial | u_tmds/g_channel[0].u_slave/OCLK (GTP_OSERDES_E2) → u_tmds/g_channel[0].u_master/OSHIFTIN0 (GTP_OSERDES_E2) | 0.484 | 0 |

综合中的clk_mem/PHY负hold估计也保留，需完成实现后的STA再判断。布局日志原始slack值-8253等未标单位，单独保留原文，不直接当作ns或每时钟WNS。

## 资源

下表为综合SNR逻辑层次口径；失败PnR的物理CLMA/CLMS、APM、DRM、IO、GPLL/PPLL容量与用量另见resource_summary.txt。PRR无模块层次表，所以未把综合层次冒充路后层次。

| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |
|---|---:|---:|---:|---:|---:|
| edrv32_fpga_board_vision_top | 49967 | 47800 | 346 | 153 | 109 |
| u_cpu | 12687 | 7171 | 143 | 4 | 6 |
| u_ddr3 | 4705 | 5232 | 48 | 0 | 0 |
| u_disp | 3018 | 3541 | 0 | 7 | 8 |
| u_eth | 4122 | 4458 | 76 | 0 | 3 |
| u_geo | 3240 | 3306 | 0 | 9 | 16 |
| u_mem | 9756 | 7622 | 34 | 1 | 28 |
| u_pix | 4993 | 7860 | 0 | 132 | 11 |
| u_pll_sys | 0 | 0 | 0 | 0 | 0 |
| u_pll_video | 0 | 0 | 0 | 0 | 0 |
| u_rgmii | 0 | 0 | 0 | 0 | 0 |
| u_sys | 1978 | 1617 | 8 | 0 | 20 |
| u_tmds | 0 | 0 | 0 | 0 | 0 |
| u_vin | 5455 | 6993 | 37 | 0 | 17 |

资源层次完整462行见resource_hier.txt。DRM18K/36K原语拆分、全工程原语计数在SNR Cell Usage，PLL物理用量包含DDR内部PLL，不能直接按外部PLL IP种类计数。

## IP与导入脚本

19类IP实际模块、端口、位宽、配置与初始化检查保留在artifacts/B3V/ip/ip_check.md。ROM/SRAM使用B3R/F任务的G盘HEX初始化文件。
本次提交包含此前用户授权的vision导入脚本路径修正：仓库由FPGA工程工作目录的../../EdRV32-Competition-2026计算，include_path传仓库rtl/include，定义FPGA_MODE。未修改RTL、IP或约束。

## 上板

未执行：布局布线失败，没有bitstream；boot/sysinfo/BIOS/HDMI和2000000波特率测试未取得。

## 本地完整报告与复现

- G:/codex_project/EdRV32-FPGA/EdRV32-B3V/{compile,synthesize,device_map,place_route}/run.log
- 各阶段CMR/SNR/DMR/PRR、constraint_check/constraint_check.ccr。
- place_route/fail_route_nets.txt、mt_route_fail_net_loads.txt；失败数据库留在本地。

整理命令：`C:/Python314/python.exe tasks/win/20261029-05-b3-vision/src/collect_reports.py`。只读取现有文件，没有核对时间戳、重跑实现、导出数据库、修改RTL/IP/约束，也没有操控桌面。
