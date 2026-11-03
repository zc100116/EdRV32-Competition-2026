# 卡46 操作清单

已复制卡24 B3R为 `G:/codex_project/EdRV32-FPGA/EdRV32-B3R-RND1S`。原工程保留。
副本器件 Logos2 PG2L200H-6 FBB676，综合器 ADS；按当前导入脚本展开94个RTL文件，18个IP，移除window RAM、不插ILA。
源文件和约束使用 `../../EdRV32-Competition-2026/`；include保留原工程有效的带尾部Tab格式。所有关联输入路径存在。
初次仅复制IP与删减PDS的准备方式被用户反馈无法打开，已改为完整复制原工程目录，保留PDS原有流程记录与源文件timespec字段。复制来的旧数据库不是精简版结果，全部流程状态清零，必须重新Compile和综合。Map高扇出报告1000，PnR拥塞图开启，其余沿用卡24。未操控GUI，尚未确认GUI实际打开结果。

1. PDS打开 `G:/codex_project/EdRV32-FPGA/EdRV32-B3R-RND1S/EdRV32-B3R-RND1S.pds`。
2. 双击ip_rom_boot和ip_ram_sram，保持容量、端口、延迟等配置不变，各重新Generate一次。
   两个IDF的INIT_FILE已分别指向 `G:/codex_project/EdRV32-Competition-2026/tasks/win/20261103-46-b3r-rnd1slim/src/ip_rom_boot.dat` 和同目录 `ip_ram_sram.dat`。
   生成前确认IP界面初始化文件显示以上路径；复制的旧生成文件仍是旧初始化，不能直接当作已更新。
3. 源文件列表已准备好，无需再导入。GUI运行Compile，再运行Synthesize（ADS）。综合完成通知Codex。
4. Device Map完成后核对资源；PnR线程GUI确认5。当前F/VRN两份NOILA正在PnR，不启动第三个PnR。按任务卡：同时最多两份、启动本卡PnR时空闲物理内存至少12GiB，卡45 F优先。
5. 布通后Report Timing、Generate Bitstream，上板按task.md测试eth_diag、rnd_board 10行CRC、showcase及NES。

本次只准备工程，未运行任何编译、综合、Map或PnR。
