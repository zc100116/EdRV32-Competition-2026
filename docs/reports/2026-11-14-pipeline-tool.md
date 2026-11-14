# PC 视觉流水线工具交付（2026-11-14）

- 实现提交：`0da79130`；已 rebase 到 `zc100116/b3` 的 `0a395b8a`。
- 依据：视觉流水线设计第 4、7.1、7.3 节，包含来源原图 `view=0xFE` 扩展。
- 新增 CHAIN / PRESET / CHAIN_STATE / PIPE_STATS，删除 PROCESS；STATE 偏移 20 为 chain_rev。
- 合并处理、检测页；支持库拖入、链内拖动、删除、全部参数、来源和 8 个预设。
- 来源“看此级”、看原图、看选中积木和最终输出均可用；拒绝时显示中文规则。
- 展示各跳引擎、积木范围、耗时，以及端到端、帧率、NPU、框滞后和 DDR 预算条。
- 每张图片先 APP(1)，再 CHAIN(source=1，保留积木)；返回摄像头也同步修改来源。
- REST/CLI 改用 pipeline；模拟板端支持新消息和 7.1 全部链规则，拒绝保持原链。

## 验证

环境：Linux / Python 3.12 / PySide6 6.12.0 / QT_QPA_PLATFORM=offscreen。
主机 Python：`~/.local/opt/edrv32-py/bin/python`；先初始化 `third_party/lvgl` 字体依赖。

- `python -m unittest discover -s tools/debug_tool/tests`：144 项中 142 通过，2 项定时失败。
- `python -m unittest discover -s tools/debug_tool/tests -p test_pipeline.py`：新增 7 项全部通过。
- `PYTHONPATH=tools/debug_tool/tests python -m unittest -v test_virtual_input.VirtualInputTest.test_udp_loopback_repeat`：单独运行仍在既有 0.5 秒首包等待处超时。
- `PYTHONPATH=tools/debug_tool/tests python -m unittest -v test_showcase_detection.ShowcaseDetectionTest.test_three_second_return_waits_for_done_without_auto_advance`：单独运行仍失败，高负载下 capture_pending 提前结束。
- 按协调者回复，两项各隔离执行一次后停止重跑；未改既有超时，未增加重试。
- `python3 -m compileall -q tools/debug_tool`、`git diff --check`：通过。
- `python3 tools/check/verilog_style.py tools/debug_tool`：0 个 RTL 文件，0 告警；无 RTL lint 对象。
- 流程测试实际启动 `telemetry_sim.run_pipeline` UDP 端：HELLO → 点击预设 → Qt 拖放 → CHAIN_STATE / PIPE_STATS → 非法链中文拒绝，原链保持不变。
- 截图：`python tools/debug_tool/render_shot.py build/debug_tool/pipeline/pipeline-WxH.png --state pipeline --width W --height H`，分别取 1366×768、1920×1080，均成功。

## 产物与限制

- 日志与两张 PNG：本工作树 `build/debug_tool/pipeline/`，生成物未入库。
- 目录绝对路径：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-pipe-tool/build/debug_tool/pipeline/`。
- 模拟端的画面、帧率、每跳耗时和 DDR 数字均为演示值，不是实板测量。
- 全套定时测试的上述两项未通过；其余测试以已通过结果为准，未声称全套通过。
- 未运行 SoC 仿真、未访问仿真虚拟机；真实硬件执行和性能留待上板验收。
