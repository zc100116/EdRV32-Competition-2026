# 任务卡 20261102-41-coremark-flags：GCC 15.2 tuned 基础上的编译选项对比（5 个程序），不重新构建

## 1. 目标

方法与卡 40 完全相同：同一块板、同一个 bitstream，依次下载 5 个 monitor，各跑一次 CoreMark，比较分数。目的是在卡 40 最好的 GCC 15.2 tuned（4.354 CoreMark/MHz）基础上再找提升。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡）。拉出 `win/20261102-41-coremark-flags`，在 result.md 中记录完整哈希。
- **bitstream**：卡 34 的 B1-ILA（与卡 40 相同）。
- **程序**：`src/<变体>/monitor.bin`；编译选项和大小见 `src/variants.md`（末尾"协调者评审"一节为准）。

| 变体 | 相对 t-base 的改动 |
|---|---|
| t-base | 卡 40 的 g15-tuned（同一次上板的基准） |
| t-al8 | 三个对齐值从 4 改为 8（取指为 8 字节组） |
| t-rocket | 加 `-mtune=rocket` |
| t-s5 | 加 `-mtune=sifive-5-series` |
| t-sched | 加 `-fschedule-insns -fsched-pressure` |

## 3. 环境

同卡 40。不综合、不布局布线，可与正在跑的布局布线同时进行。

## 4. 需要的 IP

无。

## 5. 操作步骤

同卡 40 第 5 节，变体按上表顺序；路径中的卡号改为 `20261102-41-coremark-flags`，日志 `build/board/cm41-<变体>.raw`。**t-base 跑两次**（第一个和最后一个各一次），用来确认同一程序在本次上板中的重复性。

## 6. 产物

`artifacts/uart/<变体>.log`（t-base 两次分别为 `t-base-1.log`、`t-base-2.log`）。

## 7. 通过判据

同卡 40。

## 8. result.md 模板

同卡 40 第 8 节，标题改为 `20261102-41-coremark-flags 结果`；表中每行另加 HPM 16 项（两轮合计的原文值）。
