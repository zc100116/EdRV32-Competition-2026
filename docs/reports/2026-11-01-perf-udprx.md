# UDP 视频接收测量

代码：`08c48f238b5f4729e21c3d550c9792923de3fb69`；基线：`9b54c70431f9a8d8c9159d1a5231fc5f0922de8b`。
工具：Python 3.12.3、标准库 UDP；1280×720 RGB565，900 帧，目标 30 fps。
每帧独立 32 B EDVF 头和 1800 个 1024 B 像素包；发送和接收分进程。
发送包起点至少间隔 1024/116000000 秒，帧间按 30 fps 定时；CPU 为接收线程 CPU 秒/发送秒。
本机 `net.core.rmem_max=212992`；基线 socket 读回 212992 B，优化后请求 64 MiB、读回 425984 B。

| 限速回环 | 接收完整帧 | 接收 fps | 丢弃帧 | 未收完整帧 | 接收 CPU 秒 / 占用 | 发送秒 |
|---|---:|---:|---:|---:|---:|---:|
| 本机改前 | 101 | 3.367 | 790 | 799 | 15.662 / 52.21% | 30.000 |
| 本机改后 | 691 | 23.033 | 202 | 209 | 13.457 / 44.86% | 30.000 |
| VM 改前 | 1 | 0.033 | 843 | 899 | 14.984 / 49.95% | 30.001 |
| VM 改后 | 760 | 25.332 | 138 | 140 | 14.602 / 48.67% | 30.001 |

结论：两处均未达到 0 丢帧、≥29.5 fps；本机发送忙等占用 CPU，接收缓冲受系统上限限制。
未取得调整上限的权限，未执行 64 MiB 无限速对照；未放宽验收指标。
丢弃数不含连头尾一起丢失的整批；“未收完整帧”=900−完整帧数。
以上均为 Linux 回环，最终以 Windows 网卡上板为准，须记录 Windows 的缓冲读回值。
本机原始数据：`build/debug_tool/udprx/{before-final-paced,after-final-paced,tests}.log`；VM 仅保留上述数字总结，临时进程与数据已清理。

实现：WIN 0 预分配缓冲、memoryview 直写、包位图、只读完整帧交付；统计批量更新，按可读事件排空 socket。
单列显示瓶颈：原画面随状态每 500 ms 刷新；现用独立 16 ms 定时器，状态页显示接收/显示帧率、丢弃和实际缓冲。
验证：89 项单元测试通过，含乱序、单包缺失、重复、丢帧头、帧缓冲生命周期和独立画面刷新；`git diff --check`、Python 编译通过；未改 RTL。
1366×768 离屏画面检查通过，统计文字完整：`build/debug_tool/udprx/video-1366.png`。

```bash
QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests -p 'test_*.py'
~/.local/opt/edrv32-py/bin/python tools/debug_tool/stress_test.py --udp-video
mkdir -p build/debug_tool/udprx/baseline
git archive 9b54c704 tools/debug_tool tools/board | tar -x -C build/debug_tool/udprx/baseline
cp tools/debug_tool/stress_test.py build/debug_tool/udprx/baseline/tools/debug_tool/stress_test.py
PYTHONPATH="$PWD" ~/.local/opt/edrv32-py/bin/python build/debug_tool/udprx/baseline/tools/debug_tool/stress_test.py --udp-video
```
本机并发工作时，每条测试/测量命令外加 `flock /tmp/edrv32-debugtool.lock`，避免工具测试争用 UDP 6000。
