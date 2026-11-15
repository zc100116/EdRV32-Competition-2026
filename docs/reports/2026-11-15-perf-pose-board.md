# 人体姿态页上板性能（卡 79、卡 81）

| 项 | 内容 |
|---|---|
| 日期 | 2026-11-15 |
| 比特流 | 卡 68 R2（clk_sys 125 MHz、clk_npu 180 MHz，无 NPU 硬件后处理） |
| 程序 | `SHOWCASE_POST=cpu` 构建：卡 79 为 b3 `095b17d4`，卡 81 为 b3 `1c1afbcb`（GUI 局部重画、CPU 实线连线） |
| 模型 | YOLOv8n-pose INT8（`sw/apps/showcase/models/yolov8n-pose/`），17 点 |
| 编译器 | xPack riscv-none-elf-gcc 15.2.0 |

## 结果

数据取自串口 `pose fps=` 行（每秒一行）的整段统计，列出中位数，括号内为范围。两次都没有取得分项的起止时间，测试场景（视频或真人、人数）不完全相同。

| 字段 | 卡 79（222 行） | 卡 81（492 行） |
|---|---:|---:|
| fps | 15（13–20） | 20（14–25） |
| npu ms | 39.2 | 39.0 |
| wait ms | 58.65 | 25.5 |
| decode ms（CPU 后处理） | 19.3 | 19.9 |
| kpt ms | 0.7 | 0.7 |
| gui ms | 53.65 | 35.85 |
| e2e ms | 190.4 | 137.85 |
| period ms | 63.55 | 48.65 |
| npu_gap ms | 24.3 | 9.7 |
| idle % | 19 | 19 |

字段说明：
- `gui`：从后处理结果交出，到包含该结果的画面完成显示为止。它包括等待 LVGL 刷新（周期 16 ms）、渲染和等待 60 Hz 翻页，不是纯渲染时间；
- `wait`：NPU 完成到 CPU 开始后处理的排队时间。

卡 81 的多人补测（246 行）按 `persons` 分组的中位数：

| 人数 | 1 | 2 | 4 | 6 | 8 |
|---|---:|---:|---:|---:|---:|
| fps | 18 | 19 | 17 | 15 | 13 |
| gui ms | 39.9 | 40.9 | 49.55 | 66.95 | 68.3 |
| e2e ms | 156.3 | 141.8 | 157.85 | 188.4 | 201.0 |

## 结论

- GUI 局部重画和改为实线之后：中位 fps 从 15 升到 20，`gui` 降 33%，`wait` 降 57%，e2e 从 190 降到 138 ms。
- 卡 68 R2 上剩下的大头：
  - CPU 后处理约 20 ms/帧，需要卡 75 的硬件后处理；
  - `gui` 中刷新和翻页的等待；
  - 每多一个人，`gui` 约增加 4 ms（标签和连线）。
- NPU 实测 39.0 ms/帧，离线估算为 36.9 ms。

## 限制

- 静止抖动、举手准确率、距离和两人骨架的目视结果都没有取得。`jit_*` 的整段统计混有运动，不能当作抖动。
- 两次会话结束后数秒都出现了 Boot ROM 输出，原因没有记录（可能是人为复位）。

## 原始数据

- 卡 79：`tasks/win/20261115-79-pose-r2/`（`result.md`、`artifacts/uart/pose-session.log`、`switch.log`）。
- 卡 81：`tasks/win/20261115-81-pose-gui-r2/`（`result.md`、`artifacts/uart/session.log`、`multiplayer-followup.log`、`marks.txt`）。
- GUI 优化的主机测量：`docs/reports/2026-11-15-pose-gui.md`。
