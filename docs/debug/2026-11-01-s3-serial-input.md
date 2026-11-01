# S3 串口虚拟输入丢帧与菜单误选

## 1. 现象

卡 25 B3R 未建立网口 PEER，调试工具经串口发送虚拟输入；用户反馈鼠标迟钝、
飘移、按键不灵，点程序 2 却打开程序 5（LAYERS），最后一项经常自行选中。
现场反馈来自任务描述；本次没有板上逐字节接收记录。

## 2. 复现

基线 commit：`3a1f14635bea2dfc7a416241434f1d8b4dc99245`；修复见本记录所在提交。
Linux 主机 GCC 13.3.0，C11/O2/Wall/Wextra/Werror；交叉编译 xPack GCC 15.2.0。
确定性主机模型，无随机种子、无 RTL 仿真器；UART 115200 8N1，每字节取整 87 us，
FIFO 16 字节、满时丢新字节（sys-subsys-spec 2.6），采样之间额外延迟 100 ms。

```sh
mkdir -p build/s3-input-host
git show 3a1f1463:sw/apps/s3/s3_platform.c > build/s3-input-host/baseline.c
flock /tmp/edrv32-sim.lock python3 tools/s3/virtual_input_host_s3.py build/s3-input-host/baseline.c
flock /tmp/edrv32-sim.lock python3 tools/s3/virtual_input_host_s3.py
flock /tmp/edrv32-sim.lock python3 tools/s3/virtual_input_host_nes.py
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sim.lock make -C sw PROGRAM=s3 MEMORY=ddr_app -j1
flock /tmp/edrv32-sim.lock make -C sw PROGRAM=nes MEMORY=ddr_app -j1
flock /tmp/edrv32-sim.lock python3 tools/s3/widgets_check.py
flock /tmp/edrv32-sim.lock python3 tools/s3/lvgl_host.py
flock /tmp/edrv32-sim.lock python3 sw/apps/s3/host/layers_check.py
git diff --check
```

基线失败：`keys expected=0 actual=6 pointer=97,22043/0 ... dropped=4`。
修复通过：`FIFO dropped=0 interrupts=3245`；NES 回归通过，丢字节 0、中断 1282 次。
S3/NES DDR 构建通过，0 warning；主机 LVGL 512 源文件构建通过。
Widgets ASan/UBSan 生命周期通过：60 帧、18442 条命令、103554052 像素。
Layers 回归通过：24000 次 Surface 提交与真实 LVGL layer 的 rnd_ref 执行。
日志位于 `build/s3-input-host/`：`baseline.log`、`fixed.log`、`nes-host.log`、
`s3-build.log`、`nes-build.log`、`widgets.log`、`lvgl-host.log`、`layers.log`。

## 3. 观察

两个 10 字节帧在首次采样前到达，旧路径只保留 16 字节，第二帧尾 4 字节被丢弃。
下一帧的 ESC/V/keys 被用于填满残帧，坐标 100/119（0x64/0x77）被返回为 d/w，
实际输入为 RIGHT|JUMP（6），且指针状态被残帧污染。连续激励还含 97/112（a/p）。
测试使用实际平台初始化、PLIC UART 分派、阈值配置、排空、解析和输入合并代码；
仅 CPU CSR/入口、PLIC 投递与硬件 MMIO 被主机替代，不测量真实中断响应时间。

## 4. 根因

基线 `sw/apps/s3/s3_platform.c:s3_input()` 每次 foreground 采样才排空 UART。
慢 LVGL 帧间超过 16 字节的输入导致 FIFO 溢出；`sw/lib/virtual_input.c` 保留解析位置，
丢头或截断后续帧会使负载作为普通字符返回，触发 S3 的 a/d/w/p 菜单动作。
这是接收调度缺陷；现场具体每次误选的字节经过仍需板上验证。

## 5. 修复

`sw/lib/virtual_input_uart.c` 统一 NES/S3 的 RX_THRESH=1、PLIC UART0 使能与排空解析。
使能保留现有媒体源，应用保留各自 trap owner 与 legacy 字符处理。
`virtual_input_irq.c` 统一保存/恢复 MSTATUS.MIE；S3 消费并清空 legacy 位及读取
虚拟状态时短暂关中断，LVGL 指针/键盘和主循环均读取完整快照。
网络状态在原有 timer ISR 中更新，与 UART ISR 串行；非中断异常仍打印
`S3 CPU mcause=... mepc=...` 并停止，主机回归验证该输出和停止行为。
不改协议、解析器字符语义，不增加超时、重发或校验。

## 6. 防回归

新增 `tools/s3/virtual_input_host_s3.{py,c}`：连续绝对坐标帧跨慢采样、9 个拆帧点、
鼠标左右键与虚拟按键按下/释放、关中断期间完整缓冲帧、legacy 消费与异常入口。
同一测试只替换平台源文件即可复现旧版失败；NES 回归改为链接同一公共接收实现。

## 7. 同类排查

NES 已迁移到公共接收和锁实现，原有 100 ms legacy 脉冲与虚拟手柄映射保持。
S3 主循环、LVGL 键盘/指针以及 game/layers 共用平台输入；媒体中断和 timer owner 保留。
本次未改 RTL、寄存器头、规格或发送端；主机模型通过不能替代卡 25 的鼠标/菜单复测。
