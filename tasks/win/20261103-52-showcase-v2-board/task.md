# 任务卡 20261103-52-showcase-v2-board：正式演示程序 showcase v2 上板

## 1. 目标

在 F CPU125 比特流上运行正式演示程序 showcase v2（设计记录 `docs/design/2026-11-03-showcase-ui.md` 第 4 节），逐页验收，测量调度、CoreMark 和代码布局数据。同时补齐卡 51 没取得的稳定性记录。

## 2. 输入

- **代码**：`origin/zc100116/b3` 上包含本卡的提交，拉出 `win/20261103-52-showcase-v2-board`，记录 HEAD。
- **比特流**：与卡 51 相同，即 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S-CPU125/generate_bitstream/edrv32_fpga_board_full_top.sbit`（`EdRV32-F-cpu125m.sbit`）。
- **程序**：`src/showcase-v2.elf`（9593328 字节，构建自 b3 72d79178）。程序中已经嵌入 30 款游戏。
  - SRAM 段：调度、中断，以及 CoreMark 的代码、数据和栈；
  - DDR 段：NES、LVGL、页面和其余代码。
- **NPU 模型**：`tasks/win/20261029-09-b3-software/src/npu/`，与卡 51 相同。
- **board_npu.elf**：卡 48 的 `tasks/win/20261103-48-vrn-f-rnd1slim/src/board_npu.elf`，用于补测卡 51 缺的 3 次 NPU 自检。
- **调试工具**：本 checkout 的 `tools/debug_tool`。它已经适配新协议，包括滚轮、游戏上传、回环测试，图片识别以板端的 DONE 为准。

## 3. 环境

同卡 51：PC 192.168.1.2/24，板 192.168.1.10:5000；HDMI、两个 OV5640、串口 115200、网口。本卡不运行 PnR。

## 4. 需要的 IP

无。

## 5. 操作步骤

**注意**：showcase v2 会改写 SRAM，覆盖比特流里的 monitor。下载 showcase 以后：
- 直接复位不会回到 monitor；
- 每次都要**按住 KEY1 复位进入 BIOS** 再烧录；
- 需要 monitor 时重新下载比特流。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261103-52-showcase-v2-board origin/zc100116/b3`；另外 `git fetch origin win/20261103-48-vrn-f-rnd1slim`，只用于取 board_npu.elf。关闭旧调试工具，从本 checkout 重启。 |
| 1 | 用户（U） | 下载比特流，KEY1 复位进入 BIOS，记录启动信息。 |
| 2 | U + C | **补测 NPU**：用 BIOS 网口烧录 board_npu.elf，完整跑 **3 次**（每次复位重新烧录），每次都要 39/39，D 组 20 帧 CRC 一致。 |
| 3 | U + C | 用调试工具的"设备与输出"选择 `src/showcase-v2.elf`，网口烧录，烧录后自动运行。保存串口原文。之后每秒一行的调度统计日志一直保存到 `artifacts/uart/showcase.log`。 |
| 4 | U + C | 按下面第 6 节的矩阵逐项执行。某项失败时保存原文和照片，然后继续后面的项目。 |
| 5 | C | 整理 result.md，推送 `win/20261103-52-showcase-v2-board`。 |

## 6. 测试矩阵

| 编号 | 页面 / 功能 | 操作 | 记录 |
|---|---|---|---|
| S0 | 启动、首页 | 看首页和状态栏 | 首页照片；F 上 8 个应用都可用，没有置灰 |
| S1 | 输入 | KEY1–4（← → 确认 返回）；调试工具的虚拟键盘；鼠标指针（箭头光标，5 s 不动隐藏）；**滚轮**（焦点移动或数值调节）与**中键**（确认）；串口虚拟输入 | 每种输入是否可用，问题描述 |
| S2 | 系统监控 | 静止 30 s，然后在视觉识别、NES、benchmark 运行期间各看一次 | 三个任务的 CPU 占用和**最长单次耗时**（通信应 ≤1 ms、应用应 ≤5 ms），DDR 各端口带宽，NPU/RND 忙碌率；照片和串口统计行 |
| S3 | 视觉识别 | 摄像头识别**连续 15 分钟**，每 5 分钟拍一张照片并记录 fps / NPU ms / 后处理 ms | 是否死机、画面错乱、帧率下降 |
| S3b | 检测设置 | 进入"检测设置"：默认门槛 0.50；改为 0.70；全不选后只选"人"等 2–3 类；再全选 | 每种设置的照片；框是否按设置过滤 |
| S4 | 图片识别 | 工具上传模型 → 发送图 A → 发送**另一张图 B** → 批量 40 张的文件夹 → 中途停止 → 再发 1 张 → 切回摄像头，再重复 2 次（共 3 次切换） | 每步结果：板端和工具是否都有框、工具显示的是不是本次发送的图、40 张中成功和失败的张数、错误原文 |
| S5 | 图像处理 | 7 种模式逐一切换 | 每种模式的照片 |
| S6 | 图形引擎 | benchmark 完整跑一遍，图层演示 | benchmark 结果页照片和串口原文（fps 应不为 0）；硬件/软件对比 |
| S7 | 游戏 | 依次运行：超级马里奥、超级马里奥3、魂斗罗、热血物语、松鼠大作战、赤色要塞，每个约 1 分钟；其中一个运行 **5 分钟**。按两次返回退出 | 能否启动、画面和声音以外的问题；封面和名字显示是否正常 |
| S7b | 游戏上传 | 工具"游戏"页选一个**不在内置 30 款中**的 ROM，可选封面，上传；再上传第二个 | 工具显示的序号；板上列表末尾是否出现，能否运行 |
| S8 | CoreMark | 芯片信息页运行 CoreMark **3 次** | 每次的 Iterations/Sec、CoreMark/MHz、运行时长，以及串口 CRC 原文。参考值：卡 40 同配置为 4.354 CoreMark/MHz |
| S8b | 芯片信息 | 查看页面 | I$/D$ 应显示各 32 KiB |
| S9 | 调试助手 | 串口页收发；网口页从工具做 100 次 ECHO 回环 | 板端的收到/回复次数；工具上的往返 ms 和丢失数 |
| S10 | 代码热度采样 | 在串口输入 `prof 10` 三次，分别在：视觉识别运行时、NES 运行时、benchmark 运行时 | 三段串口输出原文（`artifacts/uart/prof_*.log`），供协调者调整代码布局 |

## 7. 产物

放在 `tasks/win/20261103-52-showcase-v2-board/artifacts/`：
- `uart/*.log`：showcase 全程日志、board_npu 3 次、prof 3 段；
- `photos/`：各项的照片，文件名标明编号；
- `tool/`：调试工具的回环统计、批量识别统计（截图或导出）。

## 8. 通过判据

- S0–S9 全部可用；
- 3 次 board_npu 都是 39/39，CRC 一致；
- 摄像头识别 15 分钟无异常；
- S4 中图 B 的显示和识别都正确；
- CoreMark 3 次 CRC 正确；
- 所有数字取自原文，找不到的写"未取得"。

## 9. result.md 模板

```markdown
# 20261103-52-showcase-v2-board 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 比特流 | |
| CLK_SYS_HZ | |

## board_npu 补测
| 次 | 39 项 | D 组 CRC | fps |
|---|---|---|---|

## showcase v2
| 编号 | 结果 | 关键数字 / 现象 |
|---|---|---|
| S0 首页 | | |
| S1 输入 | | |
| S2 监控（最长 step：通信 / 应用 / GUI） | | |
| S3 视觉识别 15 min | | |
| S3b 检测设置 | | |
| S4 图片识别 A/B/批量/切换 | | |
| S5 图像处理 | | |
| S6 benchmark | | |
| S7 游戏 6 款 / 5 min | | |
| S7b 游戏上传 | | |
| S8 CoreMark ×3 | | |
| S8b 芯片信息 | | |
| S9 调试助手 / ECHO | | |
| S10 prof | | |

## 问题与偏离
```
