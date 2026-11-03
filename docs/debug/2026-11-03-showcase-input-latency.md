# Showcase 输入延迟与虚拟设备通道

## 1. 现象

卡 52 上板反馈：NES 按键延迟；虚拟设备一直走串口，进入串口调试页后失效。
上板现象由用户和协调者提供，本记录没有新增板上测量值。

## 2. 复现

修改前代码：`d5be6996`。主机验证命令：

```sh
make -C sw/tests/showcase test
```

`nes_input.c` 直接链接 showcase 的 `nes/port.c`，在模拟帧入口检查输入已经采样，
并检查帧尾回调不重复采样。`uart_input.c` 用有限 UART FIFO 模型同时发送普通字符和
完整虚拟设备帧，检查串口检查器仍收到普通字符，虚拟键盘、鼠标和滚轮仍更新。
协议测试检查窗口 3 的单字节零连接请求不产生 DONE，EDSC 请求照常回复。

## 3. 观察

- `nes/patches/single-frame.patch` 中，`nes_emulate_frame()` 先运行
  `nes_renderframe(true)`，后调用 `system_video(true)`；上游 `system_video()` 在帧尾
  调用 `osd_getinput()`。
- 原 `nes/port.c` 仅在 `osd_getinput()` 更新 `controller.data`。
- 原 `virtual_input_uart_receive()` 在安装 raw 回调后直接绕过虚拟设备帧解析。
- 原 `board/protocol.c` 把不足 12 字节的消息一律回复 DONE(status 2)。
- 原程序没有 `Showcase:` 启动行和 `ETH peer IP:` / `ETH peer port:` 输出。
- 原 `platform_input_source()` 在虚拟状态 active 后固定标为 ETH，不能区分实际通道。

## 4. 根因

NES 本帧执行时使用上一帧末尾采样的手柄状态，造成额外一帧延迟。
串口调试页的 raw 接管绕过了解析器，导致串口虚拟设备失效。
协调者确认调试工具依赖启动行及 PEER 行来切换网口；缺少这些输出使输入继续走串口，
而连接请求还被错误回复为格式错误。

## 5. 修复

- `nes_step()` 在调用模拟帧前读取最新手柄状态，帧尾只更新模拟帧计数。
- UART 总是先解析保留的 ESC V 虚拟设备帧，普通字符再送当前检查器或普通命令处理器。
- 增加指定启动行；连接请求不回复；学习到的 PEER 变化时输出指定格式。
  PEER 与周期统计串行写入 UART FIFO，通信 step 不等待发送完成。
- 在实际消费 UART/ETH 输入帧时记录来源；按键状态变化时记录 CLINT 时间和序号。
  NES 帧入口记录变化到读取的延迟，串口每秒分别输出两通道最大值和平均值，单位 ms。
- 返回键一次退出 NES，并由 shell 恢复游戏列表和原焦点。

## 6. 防回归

`sw/tests/showcase/nes_input.c`、`uart_input.c`、`main.c` 分别覆盖帧入口顺序、
串口检查器中的虚拟输入与连接请求。模拟器截图测试覆盖游戏到列表再到首页，
并验证列表焦点恢复。

## 7. 同类排查

普通串口命令与网口输入共用完整状态更新逻辑；两条输入路径分别记录来源。
NES 与 GUI 都读取同一份最新状态，GUI 的按下边沿仍按应用 step 消费。
板上还需分别确认 UART/ETH 的 `max_ms`、`avg_ms`，目标为最大值不超过 16.7 ms；
本地未取得这两组板上数字，主机时间不能代替目标 CPU 的实测。
