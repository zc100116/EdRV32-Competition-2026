# 卡51上板步骤

分支win/20261103-51-f125-board，输入ff96efc918694eb0dae28aced0fcb447739f8b65。使用已归档的F CPU125MHz第117轮结果，不运行PDS实现流程。

原工程generate_bitstream/edrv32_fpga_board_full_top.sbit当前不存在。已从origin/win/20261103-48-vrn-f-rnd1slim的fpga/bitstreams/EdRV32-F-cpu125m.sbit提取到：
G:/codex_project/EdRV32-Competition-2026/build/board/card51/EdRV32-F-cpu125m.sbit（9188552字节）。下载此归档版本，避免用正在重跑工程之后的新版本替代卡51输入。

1. 用户下载以上比特流，连接HDMI、两路OV5640、串口和网口；KEY1加复位进入BIOS。调试工具串口先115200，确认CLK_SYS_HZ=125000000。
2. 重启本checkout的调试工具前先保存已有会话。PC192.168.1.2/24，板192.168.1.10。Clash/已配置的物理路由沿用既有有效配置。
3. 卡48src路径：G:/codex_project/EdRV32-Competition-2026/tasks/win/20261103-48-vrn-f-rnd1slim/src/；所有BIN按0x10000000加载和运行，ELF按段加载。
4. eth_diag.bin：串口、网口加载，并做5轮接收检查；不修改PHY延迟。
5. board_npu.elf完整跑3轮，各39/39、每轮D组20帧CRC一致。
6. demo_npu.bin：先上传模型G:/codex_project/EdRV32-Competition-2026/tasks/win/20261029-09-b3-software/src/npu/，确认模型成功后识别3张，再批量至少20张。已知图片长度错误按卡48保留原文后复位恢复，不改工具超时。
7. 卡46src路径：G:/codex_project/EdRV32-Competition-2026/tasks/win/20261103-46-b3r-rnd1slim/src/。加载rnd_board.elf，比较10行CRC并拍照；加载showcase-test.elf，完整benchmark、图层竖线检查、NES5分钟。这里是现有板端showcase，不是卡50的PC模拟器新页面。
8. SRAM monitor运行CoreMark5000次，重复3轮，记录CRC、分数、CoreMark/MHz和HPM。无ILA，不抓Debugger。
9. demo_vision.bin：摄像头、PIX/GEO模式及HDMI/ETH/both输出逐项检查。
10. demo_vnpu.bin：先上传模型；S1摄像头识别至少3次status，批量40张，中途停止一次后立即单张，图片/摄像头切换3次且无需重传模型；摄像头识别再连续15分钟，每5分钟status一次。

不同程序之间复位回BIOS。测试失败先保留原文，再继续能执行的项目；上板稳定性不能替代时序通过。本卡不自行修改RTL、PLL或实现参数。
