# NES 串口虚拟输入松键失效

## 1. 现象

卡 23 B3R，用户在 NES 中按右方向键后松开，人物继续移动。结果分支
`origin/win/20261031-23-b3-converged`，commit `c1618c26`，原始数据在
`tasks/win/20261031-23-b3-converged/artifacts/b3r/uart/`。
`virtual_input_frames.tsv` 的 seq732/744、778/783 含 keys=8→0，说明发送日志记录了释放。
该日志没有板端收包确认，不能据此证明特定释放帧已被消费。

## 2. 复现

开发基线：`7826ec1b6b0ff30f85d38d89f2ada3faf1591e66`。
环境：Linux，GCC 13.3.0 主机 C11/O2/Wall/Wextra/Werror，xPack RISC-V GCC 15.2.0。
确定性主机模型，无随机种子、无 RTL 仿真器；采用 sys-subsys-spec 2.6 的
16 字节 FIFO、满时丢新字节行为，115200 8N1 每字节取整为 87 us。

```sh
mkdir -p build/nes-input-host
git show 7826ec1b6b0ff30f85d38d89f2ada3faf1591e66:sw/apps/nes/main.c \
    > build/nes-input-host/baseline.c
flock /tmp/edrv32-sim.lock python3 tools/s3/virtual_input_host_nes.py \
    build/nes-input-host/baseline.c
python3 tools/s3/virtual_input_host_nes.py
```

同一测试链接实际 NES main.c、virtual_input.c；基线命令只替换 main.c 为旧版。
首轮复现和修复测试使用共享锁；最终扩展测试等待 S3 长测试释放锁期间，协调者明确授权
不足 1 秒的主机回归不加锁运行，故上面最终命令未加 flock（实测 0.176 s）。
基线在 `repeat then release within one NES frame` 断言失败：
`expected=0 actual=128 time=37038 dropped=4`；修复后全部通过、`FIFO dropped=0`、接收中断 1282 次。
主机模型代替 CPU CSR 开关、PLIC 投递和 MMIO，不测量真实 CPU 中断延迟或 RTL。
实际的阈值/PLIC 配置、UART 排空、串口解析、legacy 脉冲和 NES 合并使用生产代码。

```sh
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sim.lock make -C sw PROGRAM=nes MEMORY=ddr_app -j1
QT_QPA_PLATFORM=offscreen flock /tmp/edrv32-debugtool.lock \
    ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests
git diff --check
```

NES DDR 构建退出 0，0 warning；工具 109 项测试通过（34.725 s），未修改工具。
日志：`build/nes-input-host/{baseline.log,fixed.log,nes-build.log,debug-tool.log}`。

## 3. 观察

- GUI `eventFilter()` 以实际键码持有/释放 token，忽略 auto-repeat；工具已有 Qt 测试验证
  别名键、输入框焦点、隐藏/失焦释放。`VirtualInput.update()` 状态改变立即发送完整状态；
  `_repeat()` 原有行为为按住时每 20 ms 发送，释放后退出。`send_frame()` 在未建立 PEER
  时串口发送 `1b 56` + 8 字节 `<HhhBB>`。每个串口状态帧共 10 字节。
- `virtual_input_serial()` 保留跨调用的 `serial_position`；收满 8 字节负载才替换完整状态，
  keys=0 能清空右键。`nes_merge_virtual()` 把 VI_RIGHT(bit3) 映射为 NES bit7；
  `osd_getinput()` 是完整赋值 `controller.data = nes_buttons()`，没有粘滞 OR。
- 旧版 NES 仅在 `osd_getinput()` → `nes_buttons()` 排空 UART；显示 18 fps 不等于
  轮询 18 Hz。卡 23 的模拟速率约 54 fps，对应平均轮询间隔约 18.5 ms；旧版每 60 帧
  同步打印性能统计也在两次输入轮询之间。没有测量每次真实轮询间隔。
- 即使每次轮询严格相隔 18.519 ms，也能复现：0 ms 首次右键，18.519 ms 轮询，
  20 ms 重发右键，紧随该帧到达释放帧，37.038 ms 再轮询。两帧合计 20 字节，
  FIFO 只保留前 16 字节，释放帧末 4 字节丢失。此时解析器只收齐右键重发帧，
  释放帧仍不完整，右键状态保持 8。
- 现场发送时间也存在紧邻帧：seq743→744 的时间戳是 1793497670744→1793497670745 ms，
  seq782→783 均为 1793497675040 ms。它们与“重发紧接释放”的复现条件一致；
  时间戳是主机日志时间，不是板端字节到达时间，仍不能证明具体硬件 FIFO 溢出。
- 主机测试另验证每个拆分点（1–9 字节）、一帧内短按/松开、55.556 ms 轮询间隔、
  中断前完整帧已缓冲、连续 101 帧以及原有 legacy 字符 100 ms 脉冲。

## 4. 根因

基线 `sw/apps/nes/port.c:82` 每个模拟帧才调用一次 `nes_buttons()`；
基线 `sw/apps/nes/main.c:85–92` 仅在这里读取 16 字节 UART FIFO。
输入是异步串流，两个 10 字节帧完全可能在相邻轮询之间到达，帧间轮询不能保证无丢字节。
`docs/spec/sys-subsys-spec.md` 2.6 明确规定满时丢弃新字节，4.3 提供 RX_THRESH 中断。
这是主机模型已复现的接收调度缺陷，不是释放键值无法表达或 NES 位映射问题。
卡 23 未记录 RX_OVERRUN 或板端解析进度，因此不能断言上述时序就是该次现场的逐字节经过。

## 5. 修复

- `main.c:67` 将原有排空/解析及 legacy 字符处理提取为 `nes_uart_receive()`，
  由 `input.c` 的 machine external interrupt handler 在 UART0 PLIC 源到达时调用。
- `main.c:79` 明确设置 RX_THRESH=1、UART RX 阈值中断、UART0 PLIC 优先级和使能。
  初始化在获得系统时钟后立即执行，使 PHY 等待、显示初始化和 NES 运行期间均可收输入。
  DISP/RND/ETH 继续按原有路径轮询；PLIC 仅使能 UART0。
- `input.c` 保存/恢复中断允许位；foreground 读取 legacy 64 位截止时间和虚拟状态，
  以及网络替换虚拟状态时使用短临界区，避免与串口 ISR 交错写读。
  异步共享的 `release_at`、`virtual_input.c` 的 state 使用 volatile。
- 不增加超时松键、重发、校验、状态确认或协议字段。原有 legacy 字符脉冲保留。

## 6. 防回归

新增 `tools/s3/virtual_input_host_nes.py` 和 `sw/apps/nes/tests/input_{release.c,mmio.h}`。
测试运行应用初始化及实际 `nes_buttons()`，有限 FIFO 模型根据生产代码写入的阈值、
IRQ_EN 和 PLIC 使能投递接收；旧版未配置 IRQ，因此同一激励能直接复现丢失释放尾字节。
修复版按字节中断排空，与模拟/显示帧率解耦；最后完整帧决定最终手柄状态。
构建反汇编含 UART handler → `nes_uart_receive` 调用及 `mret`。
主机测试不替代板上确认；仍需用修复 ELF 在卡 23 重测松键和运行帧率。

## 7. 同类排查

- 检查了 GUI、VirtualInput 线程锁与串口发送路径、解析器、NES 八键转换和
  `controller.data` 写入，没有发现必须改动发送协议或映射的证据。
- S3 `sw/apps/s3/s3_platform.c` 的 `s3_input()` 同样在 foreground 排空 UART；
  当前 S3 中断 owner 只处理原有媒体/定时来源，未修改该目录（另一 worker 负责）。
  S3 是否会丢包取决于实际输入调用间隔，此处未运行其 FIFO 复现，不能记为已修复。
- 网络输入是收到 RX_NOTIFY2 后覆盖窗口中的最新完整状态，保持现有路径；本次现场
  未建立网口 PEER，本次根因复现限定于串口 FIFO 接收调度。
