# Showcase 框架与集成验证

代码：`3bddba4b`；NES 来源 `bba8cec7`、`3cda5319`，已 cherry-pick；板级验收未完成。
工具：xPack GCC/readelf 15.2.0、主机 GCC 13.3、Python 3.12、Verilator 5.020；目标 PG2L200H/卡24 B3R，100 MHz；本轮未测器件时序。
依据：`docs/design/2026-11-02-showcase-software.md` 4.1–4.5；未访问仿真虚拟机、未修改 RTL/FPGA/旧应用。
三个任务按通信0、应用1、GUI2调度；deadline/事件唤醒，关 MIE 检查至 WFI，mtime 计账。
确认边界：LVGL RND同步回调以IRQ/WFI计空闲；正常翻页只改NEXT_BASE，SWITCH释放，首次FRAME建立front。
接口补充：app_wake_at/events/return/gui_pause/busy_ticks；platform_media_callbacks/display_idle/keys/pressed。
这些是 4.1/4.2 的桥接入口；struct sched_task、struct app 及既定接口字段/语义未改。
输入服务每次统一采样；Start 保持 NES Start，KEY4/VI_ESC 返回；UART 与 WIN2 同时接收。
启动输出 `Showcase:`；PEER 沿用原 ETH monitor；状态页显示最近接收接口、MDIO 实际 link。
字体：LVGL Source Han Sans SC 14/16；标题 Noto Sans SC 2.004（OFL），lv_font_conv 1.5.3。
24/32 号子集及生成命令在 fonts/title_*.c；字体原件仅 build/showcase，OFL 许可证随子集入库。
大块无零初值数据使用 .noinit；LVGL 堆初始化元数据，帧缓冲由初始绘制/明确清零后显示。

| ELF 段 | VMA | 大小（十六进制） |
|---|---|---|
| .text | 90000000 | 000c48ec |
| .rodata | 900c48f0 | 000be194 |
| .data | 90184550（LMA 90182a88） | 00001ac8 |
| .tohost | 90186040 | 00000048 |
| .bss | 90186088 | 00050240 |
| .noinit | 901d7000 | 02e08000 |
| .game_pack | 93000000 | 01000000 |

| DDR 区域（cached 地址；DMA 使用减 80000000 的物理地址） | 用途 |
|---|---|
| 80000000–89ffffff | Showcase 不使用；VIN/PIX/GEO/NPU 无缓冲占用 |
| 8a000000–8a00ffff / 8a010000–8a010007 | ETH WIN3 命令 / WIN2 虚拟输入 |
| 8a100000–8a10001f / 8a100800–8a101bff | ETH TX 描述符 / 16 条遥测打包 |
| 8a102000–8a151fff | ETH 遥测环 1024×320 B |
| 90000000–901d6fff | 程序、常量、初始化数据和 BSS（含 NES DMA 快照） |
| 901d7000–907d6fff | 图层 overlay / background |
| 907d7000–91fd6fff | LVGL 24 MiB 堆 |
| 91fd7000–926d6fff | RND scratch 6 MiB / 字形 cache |
| 926d7000–92a5afff / 92a5b000–92ddefff | GUI 双缓冲 / NES 双缓冲（DISP 直接扫描） |
| 92ddf000–92fdefff / 92fdf000–92ffffff | newlib 2 MiB 堆 / 向下生长的栈，顶93000000 |
| 93000000–93ffffff | 独立游戏包16 MiB（NOLOAD）；与上述全部区域无重叠 |

复现先 `. ~/.local/opt/edrv32/env.sh`；原始日志在 `build/showcase/`、`build/board_showcase/`。
`make -C sw PROGRAM=showcase`：当前版本完整构建无告警（build-final.log；测试构建可加 -j 4）。
`make -C sw/tests/sched test`：PASS（优先级、事件、deadline、空闲、IRQ/WFI边界）。
`python3 sw/tests/game_pack/{test_pack,check_frames,check_compile}.py`：分别执行均 PASS。
NES 连续/逐帧、停机重启各600帧/36,864,000像素一致；IRQ显示所有权/忙时丢帧、DONE后不额外等FRAME的提交 PASS。
board_showcase：独立稀疏DDR、真实ELF后门预载、ROM跳板、不改程序控制流；初版 lint/编译0告警。
验收3/4未执行：协调者 msg_714dd2dbb2b1 明确暂停新RTL仿真，至本次上报仍无恢复通知。
用例已写入：启动器像素08a4、状态应用往返、NES三次切换往返；初版lint/编译不能替代实际PASS。
命令：`flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/soc/board_showcase -j 1`。
游戏包仅包含仓库 `sw/apps/nes/roms/nrom-template.nes`；测试包/ELF留在 build/，商业ROM未使用。

Windows 上板步骤草稿（实测未执行；启动器CPU串口测量出口 msg_f861225ee54a 仍待范围确认）：
1. 加载卡24 B3R比特流；PC网卡192.168.1.2、板端192.168.1.10，串口记录启动和PEER。
2. 本地 games.txt 为“名字|ROM路径|可选PNG”；`python tools/sw/pack_games.py showcase.elf D:/games D:/showcase-games.elf`。
3. 主方式：`python tools/board/uart_tool.py D:/showcase-games.elf --elf --eth --port COM3 --baud 921600`。
4. 串口备用：同命令去掉 `--eth`；记录从开始加载至 `Showcase:` 的时间、ELF大小、加载方式。
5. 启动器静止后记录空闲CPU/三个任务占用；benchmark逐场景fps及split原始串口输出；NES模拟/显示fps与CPU。
6. 五个应用分别进入/退出、NES退出至游戏选择再返回启动器；记录网口link/PEER/包数、串口波特率和虚拟输入来源。
