# 卡31用户操作清单

1. 新建G:/codex_project/EdRV32-FPGA/EdRV32-B3F工程，PG2L200H-6 FBB676。暂不运行完整流程。
2. 准备卡片列出的IP。复用B3V公共/视频IP、B3N的NPU IP、B3R的RND IP；实际来源由复制时记录。ETH PLL须External Feedback/CLKOUT0/0度，ROM和SRAM用卡24dat，D-cache Tag20位。ILA不在IP Compiler生成。
3. 在PDS Tcl控制台：
```tcl
cd G:/codex_project/EdRV32-FPGA/EdRV32-B3F
source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl
```
用户已确认164个正确，按164个导入。 顶层edrv32_fpga_board_full_top、宏FPGA_MODE，FDC为同名fdc。脚本repo/include均从工程目录按../../EdRV32-Competition-2026定位，include保留已验证的tab分隔格式。
4. 只运行Synthesize（ADS），完成后暂停，核对ila_cpu_r的64位和CSR下10个计数器各低40位实际综合网表信号，未找到则报告。
5. 打开PDS菜单栏/工具栏的Inserter图标（或工程Constraints里的.fic），Next进入JtagHub，新建一个DebugCore Unit，Next进入DebugCore配置。Trigger Parameters设置深度1024，上升沿；Data Same As Trigger不选，数据和触发分别连接；不使用存储限定。
6. Net Connections → Modify Connection，使用Select Net和Make Connections连接clk_sys、464位Data Port和仅retire_pc/retire的Trigger Port。数据分组及位号严格按fpga/ip/ila_cpu.md，综合实际网名由Codex核对后提供。B组31:30也应采集以保持64位。
7. 触发位置前10%按界面配置；Debugger Capture Settings的Position是采样点索引（0到Depth-1），不是百分数字段。1024深度的10%约102点；本卡不上板。
8. 保存FIC和截图，退出Inserter，再运行Device Map，PDS自动调用插核流程。到此停止，不运行PnR/bitstream。
9. Codex检查Device Map高扇出报告条数选项，设1000以上；收集资源/层次/调试核/扇出/各时钟路径和级数/警告报告。若R PnR同时运行，记录真实重叠起止，分别放入卡24、31结果，当前不预填结束时间。

出处：本机G:/Program/pango/PDS_2022.2-SP6.1/doc/Fabric_Inserter_User_Guide.pdf，第9–10页（启动/JtagHub）、11–15页（参数和连线）、17页（保存FIC并由Map自动插核）；Fabric_Debugger_User_Guide.pdf，PDF第36页（正文35页，Capture Settings/Position）。
