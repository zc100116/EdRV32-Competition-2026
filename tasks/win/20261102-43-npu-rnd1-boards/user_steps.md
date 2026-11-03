# 卡43用户步骤（当前先更新ROM/SRAM）

工作分支win/20261102-43-npu-rnd1-boards，综合完成前保持此分支。
四个新工程见result.md；N/VN不插ILA，F/VRN综合后再配置400位计数器ILA。

1. 在PDS打开新工程。
2. 双击ip_rom_boot进入IP Compiler，初始化文件已指向本工程init/ip_rom_boot.dat；确认后重新Generate。
3. 双击ip_ram_sram，初始化文件指向本工程init/ip_ram_sram.dat，重新Generate。其余IP参数保持不变。
4. 四个工程重复上述步骤。不要操作原旧工程。
5. 生成完成后先告诉Codex检查；随后用户从各工程目录source ../../EdRV32-Competition-2026/fpga/scripts/import_board_<npu|vnpu|full|vrn>_top.tcl。脚本包含Compile，之后在GUI运行Synthesize ADS。
6. F/VRN综合后检查并生成FIC，使用add_fic注册；N/VN无FIC。
7. Map高扇出1000，完成后检查资源、ILA及约束再开始PnR。VN/F/VRN第40轮unrouted>18000按卡止损；旧其它任务不自动停止。
