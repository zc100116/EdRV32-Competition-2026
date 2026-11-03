# VN 连续图片识别停止推进与图片/摄像头切换

## 1. 现象

卡 43 结果分支 `origin/win/20261102-43-npu-rnd1-boards`，取证 commit
`d608d6a4629a71a4d9bd93616c4d091b1a14eb8c`，原始文件位于
`tasks/win/20261102-43-npu-rnd1-boards/artifacts/VN/image_batch_issue/`。
`result.md` / `session.log` 表明单图三张成功，文件夹前七张成功；
第八张 `000000015278.jpg` 上传 1,843,200 B 后未出现 `YOLO image window`，
此后每张均超时，串口 `status` 无回复。`ethernet_status.json` 的接收进程仍 active、
error=null，最后接收通道是 3（遥测）；这些快照没有板端 PC 或调用栈。

## 2. 复现

修改前基线：`effcfa47a7fe37979e780b69dc00eeee6eb42e01`。
修复和新增测试由本记录所在的 `demo: bound telemetry flush and restore camera over WIN3`
提交标识。测试不使用仿真、随机数或虚拟机；主机 GCC 13.3.0、Python 3.12.3，
C 测试启用 `-Wall -Wextra -Werror` 和 UBSan。

```sh
mkdir -p build
make -C sw/apps/demo test > build/vn-host-test.log 2>&1
QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python \
  -m unittest discover -s tools/debug_tool/tests -v > build/vn-tool-all.log 2>&1
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=demo_vnpu -j 1 > build/vn-build.log 2>&1
```

为验证新增测试确实拒绝旧实现，在上述主机测试后只替换链接输入中的 `monitor.c`：

```sh
python3 - <<'PY'
from pathlib import Path
import shlex
import subprocess
root = Path.cwd()
old = root / 'build/vn-monitor-before.c'
old.write_bytes(subprocess.check_output([
    'git', 'show', 'effcfa47a7fe37979e780b69dc00eeee6eb42e01:sw/apps/demo/monitor.c']))
log = (root / 'build/vn-host-test.log').read_text()
command = log[log.index('gcc '):log.index('\n' + str(root / 'build/sw/demo/host_test'))]
args = shlex.split(command.replace('\\\n', ' '))
args[args.index('monitor.c')] = str(old)
args[args.index('-o') + 1] = str(root / 'build/sw/demo/host_test_before')
subprocess.run(args + ['-I.'], cwd=root / 'sw/apps/demo', check=True)
result = subprocess.run([str(root / 'build/sw/demo/host_test_before')])
assert result.returncode != 0
PY
```

实测旧版触发 `demo_irq_unlock` 中 `++flush_samples <= 64u` 断言，退出为 SIGABRT；
修复版打印 `PASS demo VN batch: finite monitor flush, alternating windows, WIN3 camera/peer`。
完整 demo 主机入口全部 PASS（含 27,496 张 Gamma 边界表和 3,600 角度矩阵测试）；
工具测试 121 项全部 PASS，无跳过；固件构建成功、无 warning，产出
`build/sw/demo_vnpu/demo_vnpu.bin`。日志分别为上述三个 build 文件及
`build/vn-reproducer.log`（旧版失败输出，本地生成物不入库）。

## 3. 观察

`session.log` 的关键顺序：

| 序号 | 事件 |
|---|---|
| 203–206 | 第七张 `000000014888.jpg` 上传，打印 window=1，FRAME 9 完整回传，262.28 ms |
| 207–208 | 第八张 `000000015278.jpg` 上传完成；没有 window=0 打印；随后 1 s 超时 |
| 209 起 | 工具逐张推进剩余文件，每张上传完成后超时 |
| 256 | 串口发送 `status`，后面无状态应答 |

`demo_network_receive()` 在打印窗口编号前依次验证长度、`demo_pipeline_stop()`、
`demo_monitor_flush()`、设置 checking/image_window、配置 VIN_MEMORY、发 START。
所以没有窗口打印本身不能区分这些阶段，也不能证明末包已经被板端接收。

新增主机测试运行实际 `monitor.c`、`network_video_npu.c`、pipeline/scene/network 代码，
在每次外层 IRQ unlock 时注入一次定时采样，并模拟 ETH 列表完成。
这是一种确定性的中断交错反例，不是卡 43 的实测采样时刻或性能模型。
旧版刷新期间持续发送记录、持续追加记录而不返回；修复版只消费入口快照的一个记录，
新增记录留在环里，完成最后在途 TX 后返回。

## 4. 根因

**已确认的代码缺陷**：旧 `monitor.c:demo_monitor_flush()` 用
`while (demo.monitor_produced != demo.monitor_consumed)` 等待一个移动目标；
定时中断 `demo_monitor_tick()` 同时递增 produced。
`demo_monitor_send()` 清掉 flush 标志后，不足 16 条的新增记录又要等待下一整批。
只要采样在每次退出临界区后先于循环判定追加记录，循环就不能结束，仍可持续发送遥测。
测试的 64 次采样上限仅用于测试失败判定，产品代码没有新增超时、重试或看门狗。

**推测**：卡 43 第八张在 `demo_monitor_flush()` 内遇到该活锁；“没有窗口日志、
status 不响应但遥测继续”的组合与此路径吻合。现有材料无法确认实板 PC，
也无法证明第八张由此而非其他停机等待导致，因此不能把这条关联写成已证实根因。
上板复测应连续运行相同文件夹并验证每张均有窗口日志和最终 EDDT、批间 status 有应答、
遥测 seq 继续推进；若再次挂起，应采集 PC/栈以确定是否位于刷新循环或停机等待。

工具端已确认没有批量停止入口，且超时后 `_next_image()` 继续推进，因而放大为后续所有图失败。
此前队列在回传 generation 改变时直接发下一张，未等待本地上传线程清 tx.active；
返回包早于线程收尾时可能撞到 `UDP file send is already active`，新增测试覆盖这一顺序。

## 5. 修复

刷新先在 IRQ 锁内采样并记下 produced 快照；只发送快照前剩余记录，最后等待已有 TX 完成。
期间新采样照常入环，不延长本次刷新，不改变正常 16 条批发规则。

工具“停止批量”清空未发队列并结束批量调度，保留在途上传/回传；成功或原有 1 s 超时后
恢复单图、文件夹及切换按钮。没有新增重试，未停止时仍按现有策略逐张报错并继续。
队列只在本地 tx.active 清零且本张回传成功/失败后推进。

`demo` / `demo_vnpu` 新增 WIN3 偏移 0 的精确 ASCII `camera`，6 B，无换行，末包 NOTIFY。
命令完整停止内存流水线、刷新入口遥测、设置 scene=1、配置 VIN_CAM0，模型保持不变；
工具图片页和视频画面共用该命令，并选择视频显示。空包和单字节 NUL 仍只建立对端，
其他内容明确打印 Input error。协议表和适用程序见 `sw/apps/demo/README.md`。

## 6. 防回归

- `switch_host_test.c:demo_test_batch()` 由 `host_test.c` 现有入口调用：
  持续采样的有限刷新、十张交替窗口、TX 释放 checking/CH2/窗口计数、NUL 探测、camera 恢复 CH0/CH2。
- `test_detection.py`：停止后在途成功/超时两种分支均不发队列下一张，恢复操作可用；
  两个按钮发送精确 WIN3 内容；回传先到时等上传结束再发下一张。
- 原有工具 UDP 字节/交替窗口、缺包超时、文件夹正常完成/失败继续及 GUI 双分辨率测试保持通过。

## 7. 同类排查

检查了 WIN0/1 复用：原始窗口只在最终列表 DONE_COUNT 完成后清计数，checking/image_window
在下一张前由完整停机流程重置；主机依据 WIN2 NOTIFY 结束本张，不依据上传完成提前推进。
在最终包发出与 DONE 软件处理之间存在先后差异，但交替窗口和停机中的 network_wait 保持旧对象所有权；
没有证据将第八张归因于窗口覆盖，未增加保护门禁。

同一个刷新函数还用于串口场景/输出切换和收到图片，均使用有限快照修复。
已有串口 `s1` / `s2` 实际会配置 VIN_CAM0，并非只有模型重载能回摄像头；
原 WIN3 只用于 PEER 建立，没有其他合法控制命令，status/场景控制走串口。
`demo_npu` 无摄像头，仍保留其 WIN3 仅建立对端的行为；模型加载路径未改。
未改 RTL、规格、FPGA 或 showcase，未使用 SoC 仿真或访问暂停的仿真虚拟机；实板复测留给卡 43 后续任务。
