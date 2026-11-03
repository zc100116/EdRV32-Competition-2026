# 卡48工程准备与GUI步骤

输入11046fb0627afc3d182a072c8b150edab44191f3。完整复制卡45两个NOILA工程目录，不新建器件模板，不启动任何实现流程。

| 项目 | VRN（先跑） | F |
|---|---|---|
| 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3F-VRN-RND1S/EdRV32-B3F-VRN-RND1S.pds | G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S/EdRV32-B3F-RND1S.pds |
| 顶层 | edrv32_fpga_board_vrn_top | edrv32_fpga_board_full_top |
| RTL / IP数 |139 / 30|156 / 31|

已按各导入脚本展开并替换源文件列表，仅保留精简RND文件；移除window IP关联且不复制其目录，无FIC/ILA。源文件及约束保留../../EdRV32-Competition-2026路径；include使用同工程目录出发的../../EdRV32-Competition-2026/rtl/include及PDS原有尾部Tab。全部setup输入路径存在。
保留原器件Logos2 PG2L200H-6 FBB676及ADS（selected_syn_tool_opt=2）、原工程流程结构和文件timespec。所有旧流程状态归零，去除卡45显式选择旧综合数据库的input_db_file选项；复制来的数据库/报告只作历史副本，不代表新RTL结果，必须从Compile、Synthesize重新跑。

1. PDS File → Open Project，先打开VRN工程。
2. 分别双击ip_rom_boot、ip_ram_sram，保持原类型/容量/位宽/延迟等，确认INIT_FILE后重新Generate。两工程的两个IDF都已指向：
   - G:/codex_project/EdRV32-Competition-2026/tasks/win/20261103-48-vrn-f-rnd1slim/src/ip_rom_boot.dat
   - G:/codex_project/EdRV32-Competition-2026/tasks/win/20261103-48-vrn-f-rnd1slim/src/ip_ram_sram.dat
   注意两个工程各有自己的IP副本，都需要生成；旧生成文件尚未更新初始化内容。
3. 源文件及include已配置，不必再次导入。GUI执行Compile，再执行Synthesize（ADS），完成后通知Codex。
4. F同样生成两个初始化IP并重新Compile/Synthesize。综合期间保持当前卡48分支。
5. Map及PnR参数已写入PDS：fanout_number1000；D2、逻辑优化TRUE、LUT6D0、slack40、pincost600、router threads5、congestionTRUE。逻辑优化/线程选项已由本机pnr -help核实名称；GUI打开后核对显示并保存。
6. 先VRN Map→PnR，进入布线后可用物理内存至少16GiB才并行启动F，否则等VRN结束。工具报Route0039/0008即失败；第40轮未布通大于18000则按卡停止。

准备阶段未操控GUI，未宣称实际GUI打开成功。未执行Compile/Synthesize/Map/PnR。
卡45旧F已自然报Route-0008不能布通，未发现仍运行的PnR进程，无需强制结束；历史错误与本次新工程结果分开记录。
