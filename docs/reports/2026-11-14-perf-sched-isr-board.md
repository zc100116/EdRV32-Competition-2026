# 实时识别调度：中断重启 NPU 的上板帧率（卡 77、卡 78）

| 项 | 内容 |
|---|---|
| 日期 | 2026-11-14 |
| 对象 | showcase 实时识别页的两种调度方式 |
| 器件 | PG2L200H-6 FBB676 |
| 编译器 | xPack riscv-none-elf-gcc 15.2.0，`rv32im_zicsr` |
| 关联 | 主机测试报告 `2026-11-13-perf-vision-isr.md`；设计记录 `2026-11-02-showcase-software.md` 4.2 |

## 1. 被测配置

| 程序 | 调度 | 板端版本 | 文件 |
|---|---|---|---|
| A | 协作式：NPU 由应用任务启动 | `48b84d67` | `tasks/win/20261108-68-soc-v021-full/src/showcase-v021.elf` |
| B | VIN 和 NPU 完成中断里直接启动下一帧（`0685a52e`） | `8a04a320` | `tasks/win/20261114-77-sched-isr-r2/src/showcase-isr-cpu.elf` |

- 两个程序都由 CPU 做 YOLO 后处理：类别选择、DFL、阈值、排序和 NMS。
- B 是临时构建 `SHOWCASE_POST=cpu`，卡 75 上板验收后删除。

| 比特流 | 代码 | clk_sys | clk_npu | CPU | 卡 |
|---|---|---:|---:|---|---|
| 卡 68 R2 | b3 `49448d0c` | 125 MHz | 180 MHz | v0.21 | 77 |
| 初赛版本 | `m1-competition-release`（`EdRV32-F-cpu125m-r2.sbit`） | 125 MHz | 150 MHz | v0.15 | 78 |

两张卡的 Boot ROM 构建版本都是 `92b38fd2`。

## 2. 结果

数据取自 `vision fps=` 串口行，每秒一行，列出中位数，括号内为范围。

| 项 | 卡 78 A | 卡 78 B | 卡 77 A | 卡 77 B |
|---|---:|---:|---:|---:|
| 行数 | 54 | 44 | 70 | 42 |
| fps | 17（14–21） | 21（17–22） | 21（16–23） | 23（19–25） |
| npu ms | 41.2 | 41.2 | 35.0 | 35.1 |
| period ms | 56.35（46.2–62.8） | 46.0（43.8–50.8） | 46.0（41.3–57.7） | 41.2（39.0–45.1） |
| npu_gap ms | — | 4.7（2.5–9.5） | — | 6.1（3.9–9.9） |
| period − npu ms | 15.2 | 4.8 | 11.0 | 6.1 |
| wait ms | 11.0 | 12.85 | 10.6 | 15.05 |
| decode ms | 23.8 | 23.7 | 20.2 | 20.0 |
| gui ms | 30.4 | 26.55 | 27.4 | 29.2 |
| e2e ms | 129.85 | 120.3 | 115.6 | 113.55 |
| cpu_app / cpu_gui % | 49 / 33.5 | 61 / 25.5 | 51 / 33 | 58 / 29 |
| idle % | — | 8（6–22） | — | 8（6–21） |

字段说明：
- `npu_gap`：NPU 完成到下一次启动的间隔，只有 B 输出；A 用 period − npu 近似；
- `wait`：NPU 完成到 CPU 开始后处理的时间，是结果的排队时间，不是 NPU 的空闲。

卡 77 另测了 LVGL benchmark：A、B 平均都是 24 fps，ALL 渲染时间 42.3 / 41.8 ms。

## 3. 结论

- 中断重启消除了 NPU 等待应用任务调度的时间：
  - 初赛版本：fps 中位数 17 → 21（+24%），NPU 每帧空闲约 15.2 → 4.7 ms，端到端 129.9 → 120.3 ms；
  - 卡 68 R2：fps 21 → 23（+10%），NPU 每帧空闲约 11.0 → 6.1 ms。
- CPU 越慢，原调度下 NPU 等应用任务越久，因此中断重启的收益越大：初赛 CPU 的解码时间比 v0.21 长 18%。
- 两个比特流上，B 的 CPU 空闲都只有 8%，瓶颈是 CPU 后处理（每帧 20–24 ms）：
  - 剩余的 NPU 空闲，是在等 CPU 释放结果缓冲；
  - NPU 从 150 MHz 提到 180 MHz，同时 CPU 换为 v0.21，B 的 fps 只从 21 升到 23。
- 进一步提高帧率要靠 NPU 硬件后处理（卡 75 的比特流）。硬件版本的帧率由卡 71 测量。

## 4. 限制

- 识别样本为 42–70 s，任务卡要求的连续 3 分钟没有取得；
- 两张卡的拍摄场景不能保证完全一致；
- 检测框的板上观察和图片识别没有取得。B 的 CPU 解码只在主机上对参考模型做过比对（`2026-11-14-pipeline-cpupost.md`）；
- A 的板端版本没有从 HELLO 取得，按加载顺序归属。

## 5. 原始数据

- 卡 77：`tasks/win/20261114-77-sched-isr-r2/`，含 `result.md`、`artifacts/uart/{A,B}-vision.log`、`{A,B}-lvgl.log`、`boot.log`。代码 `f31f765c`。
- 卡 78：`tasks/win/20261114-78-sched-m1-npu150/`，含 `result.md`、`artifacts/uart/{A,B}-vision.log`、`boot.log`、`artifacts/programming.log`。代码 `d8fffbc7`。
- 卡 68 R2 的历史基线（同一 A 程序，53 行）：`origin/win/20261108-68-soc-v021-full` 的 `artifacts/R2/uart/showcase_vision.log`，fps 中位数 21（15–26）。
