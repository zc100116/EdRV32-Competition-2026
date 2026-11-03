# 卡52开始前及上板清单

输入babc61d38b7c8ba497ac2c86d45a1f9764f20523。已切换win/20261103-52-showcase-v2-board，并启动此checkout的新版调试工具，COM7@115200。

沿用卡51已下载的F CPU125归档比特流，不跑PDS。需要重新下载时使用G:/codex_project/EdRV32-Competition-2026/build/board/card51/EdRV32-F-cpu125m.sbit；文件仍在本地。

1. 按住KEY1复位进入BIOS；确认CLK_SYS_HZ=125000000、MEM_READY=1。
2. 网口加载G:/codex_project/EdRV32-Competition-2026/tasks/win/20261103-48-vrn-f-rnd1slim/src/board_npu.elf，完整3次；每次复位重新加载，分别保存39/39与D20CRC原文。
3. 网口以ELF模式加载G:/codex_project/EdRV32-Competition-2026/tasks/win/20261103-52-showcase-v2-board/src/showcase-v2.elf，自动运行。不是卡46的showcase-test.elf。
4. 此程序会覆盖SRAM monitor；后续均KEY1加复位回BIOS，不能直接复位期望回monitor。恢复monitor需要重新下载bitstream。
5. 按task.md的S0～S10逐项验收：四键/虚拟键鼠/滚轮/中键、监控、摄像头15分钟、置信度0.50→0.70及类别选择、图片A/B与40张批量/停止/恢复/切摄像头、7种图像处理、benchmark及图层、6款游戏与5分钟长测、2个额外ROM上传、CoreMark3次、100次ECHO、三个负载下prof10。
6. 模型目录G:/codex_project/EdRV32-Competition-2026/tasks/win/20261029-09-b3-software/src/npu/；先上传确认成功再识别。使用新版工具，不能沿用卡51时的旧进程。

## Cache容量核实（纠正最初判断）

S8b要求I/D-cache各32KiB，实际IP和F125综合网表均确认各32KiB，页面数值正确。最初仅根据卡51启动打印8192字节怀疑不一致的判断错误：旧BIOS基线92b38fd2的sw/boot/info.h将SYSTEM_ICACHE_BYTES和SYSTEM_DCACHE_BYTES固定写为8192，非运行时探测。实际每路数据RAM为2048×64bit=16KiB，I/D各有u_data0、u_data1两路，共32KiB/每个cache；Tag为512项，cache line32B。详细证据见cache_capacity_correction.md。无需为此更改IP或重新综合。

照片、主观画面和输入操作由用户反馈；每秒统计、性能、CRC、协议结果由串口及工具原文记录。模拟器通过不替代板上验收。
