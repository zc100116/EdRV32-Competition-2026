# 卡 77：在卡 68 R2 的比特流上测调度优化后的 YOLO 帧率

## 1. 目标

用卡 68 R2 现成的比特流，在同一场景下对比两个 showcase 程序的实时识别帧率：
- **A**：卡 68 R2 上板时用的程序，原有协作式调度；
- **B**：调度优化后的程序，在 VIN 和 NPU 完成中断里直接启动下一帧，不等应用任务。

两个程序都由 CPU 做 YOLO 后处理，因为卡 68 R2 没有 NPU 硬件后处理。B 是临时构建 `SHOWCASE_POST=cpu`。

**卡 76 撤销**：视觉流水线已放弃，软件已回到原来的三页。

**背景**：卡 68 R2 上，A 的实时识别帧率中位数 21，范围 15–26。拆开看：
- NPU 每帧 35 ms，单独跑可达约 28 fps；
- 等待应用任务启动 NPU（`wait`）的中位数 10.9 ms，最大 23 ms；
- GUI 越忙，`wait` 越长，帧率越低。

B 去掉的就是这段等待。

| 项（卡 68 R2，A，53 行） | 最小 | 中位数 | 最大 |
|---|---:|---:|---:|
| fps | 15 | 21 | 26 |
| npu（ms） | 35.0 | 35.0 | 35.0 |
| wait（ms） | 2.6 | 10.9 | 23.0 |
| decode（ms，CPU 后处理） | 20.3 | 20.6 | 20.9 |
| gui（ms） | 18.5 | 26.7 | 41.0 |
| e2e（ms） | 100.7 | 115.0 | 144.4 |
| period（ms） | 37.5 | 46.4 | 61.8 |

**不需要 PDS 综合或布线**，可以和卡 75 的 PnR 同时进行，只要占用开发板。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交，从这里拉出 `win/20261114-77-sched-isr-r2`，记录 HEAD |
| 比特流 | 卡 68 R2 的 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-V021/generate_bitstream/edrv32_fpga_board_full_top.sbit`（9,188,552 字节），不重新生成 |
| 程序 A | `tasks/win/20261108-68-soc-v021-full/src/showcase-v021.elf`（板端版本 `48b84d67`） |
| 程序 B | 本卡 `src/showcase-isr-cpu.elf`（b3 `8a04a320`，`make -C sw PROGRAM=showcase SHOWCASE_POST=cpu`） |
| 调试工具 | 本分支 HEAD 的 `tools/debug_tool` |
| 板级连接 | 与卡 68 相同：PC 192.168.1.2/24，板 192.168.1.10:5000，HDMI、两个 OV5640、串口、网口 |

## 3. 环境

PG2L200H-6 FBB676 开发板；PDS 只用于下载比特流。

## 4. 需要的 IP

无。

## 5. 操作步骤

**公平性要求**：A、B 依次运行，期间摄像头位置、画面中的物体和光照都不变，例如对准固定摆放的 2–3 个人或物体。显示器不变。每换一个程序，都先按 KEY1 复位进入 BIOS，再加载程序。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261114-77-sched-isr-r2 origin/zc100116/b3`，记录 HEAD。 |
| 1 | 用户（U） | 下载卡 68 R2 的比特流，按 KEY1 复位进入 BIOS，记录 `CLK_SYS_HZ`，应为 125000000。 |
| 2 | U + C | 对 **A、B** 依次执行，加载方法同卡 68，经 BIOS 网口加载：<br>1. 记录 HELLO 中的板端程序版本：A 应为 `48b84d67`，B 应为 `8a04a320`；<br>2. 进入实时识别页，连续运行 **3 分钟**，保存全部 `vision fps=` 串口行。B 的行尾多出 `idle=` 和 `npu_gap=` 两个字段；<br>3. 拍一张实时识别画面的照片，检查检测框位置和类别是否正常；<br>4. 图片识别页跑 1 次：PC 端调试工具应能收到并显示候选。<br>记录死机、复位、画面错乱、检测框异常、明显卡顿等现象。 |
| 3 | C | 对 A、B 的 `vision fps=` 行分别统计 fps、npu、wait、decode、gui、e2e、period 的最小值、中位数和最大值；B 另外统计 idle 和 npu_gap。填写 result.md，推送 `win/20261114-77-sched-isr-r2`。 |

## 6. 产物

放在 `tasks/win/20261114-77-sched-isr-r2/artifacts/`：
- `uart/A-vision.log`、`uart/B-vision.log`：实时识别 3 分钟的串口原文；
- `uart/boot.log`：BIOS 启动和加载记录；
- `photos/A-live.jpg`、`photos/B-live.jpg`：实时识别画面；
- `screenshots/`：图片识别时 PC 端的结果。

## 7. 通过判据

- A、B 都运行满 3 分钟，没有死机或复位；
- B 的检测框位置和类别与 A 一致；
- 图片识别时，PC 端能收到并显示结果；
- 所有数字取自串口原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 77 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | |
| CLK_SYS_HZ | |
| A / B 板端版本（HELLO） | |

## 实时识别 3 分钟（最小 / 中位数 / 最大）
| 字段 | A（协作式） | B（中断重启） |
|---|---|---|
| 行数 | | |
| fps | | |
| npu ms | | |
| wait ms | | |
| decode ms | | |
| gui ms | | |
| e2e ms | | |
| period ms | | |
| idle % | — | |
| npu_gap ms | — | |

## 功能
| 项目 | A | B |
|---|---|---|
| 检测框位置和类别 | | |
| 图片识别 PC 端显示 | | |
| 异常（死机、复位、卡顿等） | | |

## 问题与偏离
```
