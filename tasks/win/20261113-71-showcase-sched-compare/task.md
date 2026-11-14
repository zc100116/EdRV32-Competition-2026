# 卡 71：showcase 调度方式上板对比（只换程序，用卡 73 的比特流）

## 1. 目标

在卡 73 的比特流上，依次运行三个 showcase 程序，比较实时识别的帧率、NPU 空等、端到端延迟和 CPU 占用，判断 FreeRTOS 的收益是否高于它自身的 CPU 开销。

| 代号 | 程序 | 调度方式 | 来源 |
|---|---|---|---|
| A | 卡 70 的 `src/showcase-post.elf` | 现有协作式 | b3 `1bfcb123` |
| B | 本卡 `src/showcase-isr.elf`（12,940,664 B） | 协作式 + NPU 完成中断里直接启动下一帧 | b3 `0685a52e`，报告 `docs/reports/2026-11-13-perf-vision-isr.md` |
| C | 本卡 `src/showcase-rtos.elf`（12,968,512 B） | FreeRTOS 抢占式，视觉任务优先于 GUI；不含 B 的中断重启 | 分支 `zc100116/task-vis-rtos` `7a54602b`（基线 `ea11656c`） |

**前提**：卡 73 已生成比特流并上板通过（卡 73 取代卡 72、卡 70）。三个程序都使用硬件后处理（POST_CTRL.EN=1）。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交，拉出 `win/20261113-71-showcase-sched-compare`，记录 HEAD |
| 比特流 | 卡 73 生成的比特流，不重新综合 |
| 程序 | A：`tasks/win/20261108-70-soc-npu-post/src/showcase-post.elf`；B、C：本卡 `src/` |
| 调试工具 | 本 checkout 的 `tools/debug_tool` |

## 3. 环境

PG2L200H-6 FBB676 开发板、OV5640 摄像头、HDMI 显示器、网口。仿真虚拟机可以关机。

## 4. 需要的 IP

无。

## 5. 操作步骤

**公平性要求**：三个程序依次运行，期间摄像头位置、画面中的物体、光照都不变（例如对准固定摆放的 2–3 个物体），显示器不变。每换一个程序，都先 KEY1 复位进入 BIOS，再加载。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261113-71-showcase-sched-compare origin/zc100116/b3`，记录 HEAD。 |
| 1 | 用户（U） | 下载卡 73 的比特流，KEY1 复位进入 BIOS，记录 `CLK_SYS_HZ`。 |
| 2 | U + C | 对 **A、B、C** 依次做下面几项（加载方法同卡 68/70）：<br>1. 进入实时识别页，连续运行 **3 分钟**，保存全部 `vision fps=` 串口行。B、C 的行尾多了 `idle=`、`npu_gap=`，C 另有 `ctxsw=`、`kern=`。<br>2. 芯片信息页运行 CoreMark **1 次**，记录 Iterations/Sec、CoreMark/MHz。<br>3. benchmark 完整跑 1 次，记录平均 fps。<br>4. 图片识别页跑 1 次：PC 端调试工具能收到并显示结果。<br>5. NES 运行 **1 分钟**。<br>记录死机、复位、画面错乱、检测框异常、卡顿等现象。 |
| 3 | C | 整理 result.md，推送分支。 |

## 6. 产物

放在 `tasks/win/20261113-71-showcase-sched-compare/artifacts/`：
- `uart/A.log`、`uart/B.log`、`uart/C.log`：每个程序的完整串口日志；
- `vision_summary.csv`：每个程序的 `vision fps=` 行逐行解析成表，列为原字段名，没有的字段留空；
- `photos/`：每个程序的实时识别画面各 1 张。

## 7. 通过判据

- 三个程序都能完成第 5 节第 2 步的全部项目，或写明在哪一项出现什么异常；
- 所有数字都取自串口日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 71 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | |
| 比特流来源（卡 73 的 HEAD） | |
| CLK_SYS_HZ | |
| 场景描述（画面中的物体） | |

## 实时识别（3 分钟，每列给 平均 / 最小 / 最大）
| 字段 | A 协作式 | B 中断重启 | C FreeRTOS |
|---|---|---|---|
| fps | | | |
| npu | | | |
| wait | | | |
| decode | | | |
| post_span | | | |
| gui | | | |
| e2e | | | |
| period | | | |
| cpu_app / cpu_gui | | | |
| idle | 无 | | |
| npu_gap | 无 | | |
| ctxsw | 无 | 无 | |
| kern | 无 | 无 | |

## 其他
| 项目 | A | B | C |
|---|---|---|---|
| CoreMark Iterations/Sec、CoreMark/MHz | | | |
| benchmark 平均 fps | | | |
| 图片识别 | | | |
| NES 1 分钟 | | | |

## 问题与偏离
```
