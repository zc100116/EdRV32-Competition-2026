# 卡 78：在初赛版本比特流（NPU 150 MHz）上测两种调度的 YOLO 帧率

## 1. 目标

与卡 77 相同的两个 showcase 程序，换到初赛版本的比特流上运行（clk_npu 150 MHz），在同一场景下对比实时识别帧率：
- **A**：原有协作式调度，NPU 由应用任务启动；
- **B**：在 VIN 和 NPU 完成中断里直接启动下一帧。

两个程序都由 CPU 做 YOLO 后处理。

**与卡 77（卡 68 R2，NPU 180 MHz）的差别**：

| 项 | 卡 77（卡 68 R2） | 本卡（初赛版本） |
|---|---|---|
| clk_npu | 180 MHz | 150 MHz（预期 NPU 每帧约 41.7 ms） |
| clk_sys | 125 MHz | 125 MHz |
| CPU | v0.21（含分支预测） | v0.15 |

所以这次比较中 NPU 频率和 CPU 版本都不同；A、B 之间只差调度方式。

**兼容性**（已在仓库中核对）：
- 初赛版本到卡 68 R2 之间，寄存器头文件、Boot ROM、链接脚本都没有改动；
- VIN、PIX、GEO、RND、DISP、ETH 的 RTL 没有改动，NPU 只做了时序修改；
- 两个程序都按 `rv32im_zicsr` 编译，初赛版本的 CPU 可以运行。

**卡 77 的结果**（卡 68 R2，中位数）：

| 项 | A | B |
|---|---:|---:|
| fps | 21 | 23 |
| npu ms | 35.0 | 35.1 |
| period ms | 46.0 | 41.2 |
| wait ms | 10.6 | 15.1 |
| decode ms | 20.2 | 20.0 |
| npu_gap ms | — | 6.1 |
| idle % | — | 8 |

**不需要 PDS 综合或布线**，可以和卡 75 的 PnR 同时进行，只要占用开发板。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交，从这里拉出 `win/20261114-78-sched-m1-npu150`，记录 HEAD |
| 比特流 | 初赛版本 `m1-competition-release`：分支 `origin/win/20261103-48-vrn-f-rnd1slim` 中的 `fpga/bitstreams/EdRV32-F-cpu125m-r2.sbit`（9,188,552 字节）。导出方法见第 5 节第 0 步 |
| 程序 A | `tasks/win/20261108-68-soc-v021-full/src/showcase-v021.elf`（板端版本 `48b84d67`） |
| 程序 B | `tasks/win/20261114-77-sched-isr-r2/src/showcase-isr-cpu.elf`（板端版本 `8a04a320`） |
| 调试工具 | 本分支 HEAD 的 `tools/debug_tool` |
| 板级连接 | 与卡 68、77 相同：PC 192.168.1.2/24，板 192.168.1.10:5000，HDMI、两个 OV5640、串口、网口 |

## 3. 环境

PG2L200H-6 FBB676 开发板；PDS 只用于下载比特流。

## 4. 需要的 IP

无。

## 5. 操作步骤

**公平性要求**：A、B 依次运行，期间摄像头位置、画面中的物体和光照都不变，例如对准固定摆放的 2–3 个人或物体。场景尽量与卡 77 相同。每换一个程序，都先按 KEY1 复位进入 BIOS，再加载程序。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | 1. `git fetch origin`，`git switch -c win/20261114-78-sched-m1-npu150 origin/zc100116/b3`，记录 HEAD。<br>2. 用 cmd 导出比特流，放到仓库外。不要用 PowerShell 重定向，它会损坏二进制文件：<br>`cmd /c "git show origin/win/20261103-48-vrn-f-rnd1slim:fpga/bitstreams/EdRV32-F-cpu125m-r2.sbit > G:\codex_project\EdRV32-FPGA\m1-release.sbit"`<br>3. 确认文件大小为 9,188,552 字节。 |
| 1 | 用户（U） | 下载 `m1-release.sbit`，按 KEY1 复位进入 BIOS。记录 `CLK_SYS_HZ`（应为 125000000），以及 Boot ROM 打印的构建版本。 |
| 2 | U + C | 对 **A、B** 依次执行，加载方法同卡 68、77，经 BIOS 网口加载：<br>1. 记录 HELLO 中的板端程序版本：A 应为 `48b84d67`，B 应为 `8a04a320`；<br>2. 进入实时识别页，**连续运行满 3 分钟**（不少于 170 行 `vision fps=`），保存全部串口行。`npu=` 应约为 41.7 ms；如果约为 35 ms，说明下载的不是初赛比特流，停下回报。B 的行尾多出 `idle=` 和 `npu_gap=` 两个字段；<br>3. 拍一张实时识别画面的照片，检查检测框位置和类别是否正常；<br>4. 图片识别页跑 1 次：PC 端调试工具应能收到并显示候选。<br>记录死机、复位、画面错乱、检测框异常、明显卡顿等现象。 |
| 3 | C | 对 A、B 的 `vision fps=` 行分别统计 fps、npu、wait、decode、gui、e2e、period、cpu_app、cpu_gui 的最小值、中位数和最大值；B 另外统计 idle 和 npu_gap。填写 result.md，推送 `win/20261114-78-sched-m1-npu150`。 |

## 6. 产物

放在 `tasks/win/20261114-78-sched-m1-npu150/artifacts/`：
- `uart/boot.log`：BIOS 启动和两次加载的记录；
- `uart/A-vision.log`、`uart/B-vision.log`：实时识别 3 分钟的串口原文；
- `photos/A-live.jpg`、`photos/B-live.jpg`：实时识别画面；
- `screenshots/`：图片识别时 PC 端的结果。

## 7. 通过判据

- A、B 都运行满 3 分钟，没有死机或复位；
- `npu=` 约为 41.7 ms；
- 检测框位置和类别正常，A、B 一致；
- 图片识别时，PC 端能收到并显示结果；
- 所有数字取自串口原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 78 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | |
| 比特流 | m1-competition-release（EdRV32-F-cpu125m-r2.sbit） |
| Boot ROM 构建版本 | |
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
| cpu_app % | | |
| cpu_gui % | | |
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
