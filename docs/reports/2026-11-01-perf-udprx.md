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


## T-UDPRX2：独立接收进程与剩余丢包（2026-10-31）

代码：`e7ef3642ffdad86d123f7ec560a0b8540574ad5d`；第一步接收代码基线：
`63a14aba35e3d1bd5843884a1443fd40ff078cf9`。
仅修改上位机工具；没有新增第三方依赖，没有修改 DDR 监控或布局。
发送端和接收端在同一台专用仿真 VM 上，以不同进程通过 Linux UDP 回环通信；
GUI 使用 offscreen，实际打开 MainWindow 的 SoC 视频页并显示收到的帧。
两侧都按任务要求串行运行，socket 请求 64 MiB，实际读回均为 **425984 B**。
这些结果不代表 Windows 实际网卡接收能力，也不是 FPGA 上板数据。

### 测量定义与发送脚本修正

每组运行约 30 s（当前帧发完后停止），目标 30 fps；完整帧率为完整帧数 / 实际发送秒数。
(a) 1280×720 RGB565，每帧独立 32 B EDVF 头加 1800 包，包起点至少相隔
18.518 µs；(b) 经协调者确认改用 1280×160 的完整帧（头加 400 包），按
116 MB/s 包间隔突发；(c) 与 (a) 相同并开 GUI。
线速组为完整 720p 每帧突发、帧间补足 1/30 s，复用原 T-UDPRX 限速方式。
发送端和接收端没有重传。

最初的 uniform 脚本按绝对 deadline 追赶调度暂停，暂停后会压缩包间隔，不能证明
均匀发送条件；协调者确认后改成最小包间隔、不追赶，并记录实际发送帧率。
当前脚本限时约 30 s，发送端不足时不强行补足 900 帧。
若发送端低于 29.5 fps，该组不能判定 30 fps 接收能力达标或不足。
“丢弃帧”沿用 README 协议规则；“缺失完整帧”包含连帧头等一起丢失的批次，
两者并不相等。“丢包”=成功发送的应用数据报数−接收统计包数，不含内部停止唤醒包。
第一步 CPU 为接收线程时间；第二步为独立接收进程时间 / 实际发送秒数，
不包括 Qt 主线程和主进程每帧复制、转发处理的 CPU。

### 第一步（最终修正的发送脚本）

| VM / 约 30 s | 发出帧 / 实际发送 fps | 完整帧 / 接收 fps | 丢弃帧 | 缺失完整帧 | 丢包 | 接收 CPU |
|---|---:|---:|---:|---:|---:|---:|
| (a) 均匀最小间隔 | 681 / 22.689 | 341 / 11.361 | 209 | 340 | 224877 | 60.64% |
| (b) 400 包突发 | 900 / 30.000 | 714 / 23.800 | 183 | 186 | 26901 | 10.91% |
| (c) 均匀最小间隔 + GUI | 714 / 23.791 | 322 / 10.729 | 277 | 392 | 231199 | 60.89% |

(a)(c) 实际发送端低于 29.5 fps，不能作为 30 fps 接收验收；(b) 并非缓冲内突发，
因为 400 包超过静置队列实测可容纳数量。

早期绝对 deadline 参考（各发送 900 帧，约 30 s，不能作为均匀发送验收）：

| VM 基线 | 完整帧 | 接收 fps | 丢弃帧 | 接收 CPU |
|---|---:|---:|---:|---:|
| (a) 绝对 deadline | 697 | 23.233 | 182 | 64.33% |
| (b) 400 包完整帧 | 658 | 21.923 | 240 | 10.74% |
| (c) 绝对 deadline + GUI | 434 | 14.461 | 448 | 57.36% |

本机参考（与 VM 分开，早期绝对 deadline 脚本）：(a) 24.466 fps / 156 丢弃 /
56.02% CPU，(b) 27.000 / 90 / 10.31%，(c) 17.733 / 341 / 48.03%。
(c) 最早一次脚本在打印结果后发生 Qt 析构异常；脚本现已显式关闭窗口，后续 GUI
运行正常退出。该次仅保留为早期参考。

补测本机静置 socket：请求 64 MiB、读回 425984 B，发送 400 个 1032 B 数据报后
才开始读取，仅读出 **185 包 / 190920 B UDP 数据**。因此“400 包能装进现有缓冲”
的前提不成立；Linux SO_RCVBUF 还计 skb 内存开销，不能只按有效负载换算。
这也说明 (b) 丢帧不能单独证明接收计算吞吐不足。

### 第二步及 YOLO 追加要求

视频接收与组帧使用独立 spawn 进程，recvfrom_into 写入共享内存接收区，
视频按 OFFSET 写三个共享帧槽；完成通知通过管道交付。主进程每帧复制一次为
独立只读快照后归还槽，之前持有的帧不会随共享槽重用而变化。
EDDT 视频检测、EDTM、普通文件转发原处理路径；文件模式保留原接收线程。
停止时唤醒阻塞接收、等待退出并释放共享内存。

YOLO WIN 0 / 1 / 2 同样在接收进程组装，完整 CH2 / OUTPUT 经共享槽一次交付，
主进程保存原回传文件。EDDT 结束已到但任一窗口缺包时，只将该图计为失败，
日志写窗口和缺失字节，文件夹继续，socket / EDTM 接收保持运行；协议 magic / 版本
错误仍明确停止。协调者额外授权：未见结束时从最后回传包起 1 s 失败，若一个包都
未收到则从图片发送完成起算，错误为“回传未结束（超时 1 s）”。超时不依赖 GUI。

| VM / 约 30 s | 发出帧 / 实际发送 fps | 完整帧 / 接收 fps | 丢弃帧 | 缺失完整帧 | 丢包 | 接收 CPU |
|---|---:|---:|---:|---:|---:|---:|
| (a) 均匀最小间隔 | 641 / 21.343 | 439 / 14.617 | 140 | 202 | 107533 | 57.04% |
| (c) 均匀最小间隔 + GUI | 608 / 20.258 | 345 / 11.495 | 187 | 263 | 147957 | 55.45% |
| 720p 线速突发，目标 30 fps | 900 / 29.989 | 570 / 18.993 | 284 | 330 | 194262 | 48.42% |

(a)(c) 仍受发送端不足影响，不构成 30 fps 接收能力验收；线速组源速率满足要求，
但没有达到零丢帧。三组均无接收错误，实际缓冲均为 425984 B。
相对上一份 T-UDPRX 的 VM 25.332 fps / 138 丢弃，新版本次线速组更差；
这些非同时测量有明显波动，不能把差值全部归因于进程改动，也没有把它隐去。

按 telemetry_sim 格式以线速包间隔连续回传 30 张（983040 B CH2 + 725760 B OUTPUT + EDDT）：
**完整 16 / 失败 14 / 未结束 0**，接收进程 CPU 0.508 s，socket 无接收错误。
授权超时之前一次中间测量为完整 15 / 失败 13 / 未结束 2；最终版将缺结束也按图片失败，
因此不再因该张没有 EDDT 而永久等待。没有放宽完整性要求，16/30 仍不是零丢失。

### 验证、限制与复现

101 项单元测试全部通过，包括乱序、缺包、重复、只读帧槽重用、重启计数、
YOLO 缺包后下一张正常、失败计数与文件夹推进、持续 EDTM 下的缺 EDDT 超时、
从发送完成起算的无包超时、协议错误仍停止，以及进程 / 共享内存回收。
Python 编译、git diff --check 通过；Verilog 风格检查为 0 warnings（本次无适用 RTL 文件），
Verilator lint 不适用。本机日志：`build/debug_tool/udprx2/tests-final-timeout.log`；
本机参考日志同目录。VM 仅记录以上数字总结，不回传原始文件或环境信息，测后清理。

线速突发需要 **≥ 2 MiB 接收缓冲，上板时记录 Windows 读回值**；Linux 还需计算
skb 开销，不能据此断言 2 MiB 的 Linux 读回值必然足够。独立进程消除了逐包接收
与 Qt 的 GIL 共用，但不扩大内核队列，也不能保证调度暂停期间不发生 UDP 溢出。
当前实测没有达到 30 fps 零丢帧，**T-UDPRX2 判定 failed**；不将发送端不足的 uniform
组当作接收性能失败证据，也不宣称已经证明剩余损失全部来自缓冲上限。
协调者已要求保留实际突发结果，后续讨论板端发送节流，不再为该数字调整接收端。

在仓库根目录运行（现有 edrv32-py 环境；两端是独立进程）：

```bash
mkdir -p build/debug_tool/udprx2
flock /tmp/edrv32-debugtool.lock env QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests -p 'test_*.py'
flock /tmp/edrv32-debugtool.lock ~/.local/opt/edrv32-py/bin/python tools/debug_tool/stress_test.py --udp-video --pattern uniform
flock /tmp/edrv32-debugtool.lock ~/.local/opt/edrv32-py/bin/python tools/debug_tool/stress_test.py --udp-video --pattern short
flock /tmp/edrv32-debugtool.lock env QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python tools/debug_tool/stress_test.py --udp-video --pattern uniform --gui
flock /tmp/edrv32-debugtool.lock ~/.local/opt/edrv32-py/bin/python tools/debug_tool/stress_test.py --udp-video --pattern line
flock /tmp/edrv32-debugtool.lock ~/.local/opt/edrv32-py/bin/python tools/debug_tool/stress_test.py --udp-yolo
flock /tmp/edrv32-debugtool.lock ~/.local/opt/edrv32-py/bin/python -m compileall -q tools/debug_tool
flock /tmp/edrv32-debugtool.lock python3 tools/check/verilog_style.py tools/debug_tool
git diff --check
```

基线复现使用 63a14aba 的接收代码和 e7ef3642 的发送脚本，唯一适配为用
`time.thread_time()` 包裹旧 EthernetTool._receive，并将 CPU 数字取自该线程计时，
而非新 rx.receiveCpuSeconds。协议、包内容、发送节奏和统计公式均相同。

本机第二步参考（不是 VM）：中间脚本 (a) 源 17.854 / 接收 17.021 fps，
37 丢弃，CPU 23.36%，900 帧实际发送 50.409 s；最终限时脚本 (c) 源 25.373 /
接收 24.973 fps，11 丢弃，CPU 37.87%，762 帧实际发送 30.032 s。
两组发送端也都未达到 29.5 fps，不能用于 30 fps 验收。

突发丢包分段补测（测量脚本 `d08de055`；接收代码仍为 e7ef3642）：
同机 VM、不同进程、SO_RCVBUF 实际 425984 B，再发 900 帧 / 30.016 s。
接收 611 帧 / 20.356 fps，269 丢弃，173136 丢包，接收 CPU 47.82%。
成功看到帧头的 880 帧中有 269 帧不完整；在下一帧头或停止时读取这批帧的位图，
按像素包 0–599、600–1199、1200–1799 分成等长三段：

| 突发位置 | 未收到的像素包 | 可定位缺包中的比例 |
|---|---:|---:|
| 前 1/3 | 39167 | 26.1% |
| 中 1/3 | 66676 | 44.4% |
| 后 1/3 | 44360 | 29.5% |

本次可定位缺包以**突发中段最多**，前后段也发生，不是仅末尾缺包。
这是逐帧位图在三段内的聚合，不能断言每一帧都主要丢在同一段；
未见帧头的 20 批无法按该方法定位，故表中 150203 个缺包不等于所有 173136 个
UDP 丢包。该补测没有改变接收实现，也未将其较高的 20.356 fps 替换主验收的 18.993 fps。

```bash
flock /tmp/edrv32-debugtool.lock ~/.local/opt/edrv32-py/bin/python tools/debug_tool/tests/measure_udp_segments.py
```

测后验证：VM 本任务测量进程剩余 0，共享内存段剩余 0，临时测量目录已删除。
定位经过见 [调试记录](../debug/2026-10-31-udprx2-receive.md)。

基线接收线程 CPU 适配的可执行复现：

```bash
mkdir -p build/debug_tool/udprx2/baseline
git archive 63a14aba tools/debug_tool tools/board sw/apps/demo docs/spec | tar -x -C build/debug_tool/udprx2/baseline
cp tools/debug_tool/stress_test.py build/debug_tool/udprx2/baseline/tools/debug_tool/stress_test.py
python3 - <<'PYBASE'
from pathlib import Path
path = Path('build/debug_tool/udprx2/baseline/tools/debug_tool/stress_test.py')
text = path.read_text()
anchor = "    ethernet.local_ip = '127.0.0.1'\n"
measure = """    measured = {}
    receive = ethernet._receive
    def measured_receive(*args):
        started = time.thread_time()
        try:
            receive(*args)
        finally:
            measured['cpu_seconds'] = time.thread_time() - started
    ethernet._receive = measured_receive
"""
text = text.replace(anchor, anchor + measure, 1)
text = text.replace("cpu_seconds = rx['receiveCpuSeconds']", "cpu_seconds = measured['cpu_seconds']")
path.write_text(text)
PYBASE
cd build/debug_tool/udprx2/baseline
flock /tmp/edrv32-debugtool.lock env QT_QPA_PLATFORM=offscreen PYTHONPATH="$PWD" ~/.local/opt/edrv32-py/bin/python tools/debug_tool/stress_test.py --udp-video --pattern uniform
flock /tmp/edrv32-debugtool.lock env QT_QPA_PLATFORM=offscreen PYTHONPATH="$PWD" ~/.local/opt/edrv32-py/bin/python tools/debug_tool/stress_test.py --udp-video --pattern short
flock /tmp/edrv32-debugtool.lock env QT_QPA_PLATFORM=offscreen PYTHONPATH="$PWD" ~/.local/opt/edrv32-py/bin/python tools/debug_tool/stress_test.py --udp-video --pattern uniform --gui
```

静置缓冲容量复现（400 包发完后才开始读）：

```bash
flock /tmp/edrv32-debugtool.lock python3 - <<'PYQUEUE'
import socket
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
    receiver.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 64 * 1024 * 1024)
    receiver.bind(('127.0.0.1', 0))
    for _ in range(400):
        sender.sendto(bytes(1032), receiver.getsockname())
    receiver.setblocking(False)
    queued = 0
    try:
        while True:
            receiver.recv(2048)
            queued += 1
    except BlockingIOError:
        pass
    print(receiver.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF), queued)
PYQUEUE
```
