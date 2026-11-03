# 任务卡 20261103-51-f125-board：F CPU125 比特流上板测试

## 1. 目标

在卡 48 归档的完整 F（CPU 125 MHz）比特流上，执行卡 48 原定的 F 上板项目，并增加几项能暴露时序违例的稳定性测试，判断这个版本能否作为后续演示系统的主力硬件。

**背景**：F CPU125 第 117 轮布通。慢角 setup 违例为：
- clk_sys −0.033 ns（5 个端点，CPU 返回地址栈的使能）；
- clk_npu −0.120 ns（4 个端点，APM → 累加器进位链）；
- clk_mem −0.010 ns（DDR IP 内部的复位相位调整）；
- 另有 RGMII 输入 hold −0.242 ns，为已知例外。

详见 `tasks/win/20261103-48-vrn-f-rnd1slim/f_cpu125_results.md`（在 `win/20261103-48-vrn-f-rnd1slim` 分支上）。

## 2. 输入

- **代码**：`origin/zc100116/b3` 上包含本卡的提交，拉出 `win/20261103-51-f125-board`，记录 HEAD。
- **比特流**：`G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S-CPU125/generate_bitstream/edrv32_fpga_board_full_top.sbit`。即 `fpga/bitstreams/EdRV32-F-cpu125m.sbit`，9188552 字节。
- **程序**：
  - 卡 48 的 `tasks/win/20261103-48-vrn-f-rnd1slim/src/`：eth_diag.bin、board_npu.elf、demo_npu.bin、demo_vision.bin、demo_vnpu.bin；
  - 卡 46 的 `tasks/win/20261103-46-b3r-rnd1slim/src/`：rnd_board.elf、rnd_board_expected.log、showcase-test.elf。
  - 程序都在运行时从 SYSCTRL 读取 CLK_SYS_HZ，不需要为 125 MHz 重新编译。BIOS 和 SRAM monitor 是比特流里的初始化内容（与卡 48 相同）。
- **NPU 模型**：`tasks/win/20261029-09-b3-software/src/npu/`。

## 3. 环境

同卡 48：PC 192.168.1.2/24，板 192.168.1.10:5000；HDMI、两个 OV5640、串口、网口。本卡不运行 PnR。

## 4. 需要的 IP

无（使用已有比特流）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261103-51-f125-board origin/zc100116/b3`；另外 `git fetch origin win/20261103-48-vrn-f-rnd1slim`，只用于读取卡 48 的 src 和说明。关闭旧调试工具，从本 checkout 重启。 |
| 1 | 用户（U） | 下载第 2 节的比特流。KEY1 复位进入 BIOS，记录串口启动信息，其中 `CLK_SYS_HZ` 应为 125000000。 |
| 2 | U + C | 按卡 48 第 5 节"上板项目矩阵"中 **F 一列**逐项执行：5.0、5N、5E、5R、5C、5F、5VN。命令和判据见卡 48 的 task.md，日志目录改为本卡 `artifacts/uart/`。5E 先上传模型。某一项失败时保存原文，然后继续后面的项目。 |
| 3 | U + C | **稳定性测试**（针对时序违例）：<br>- 5N 的 board_npu 完整跑 **3 次**，每次都要 39/39，D 组 20 帧 CRC 全部一致；<br>- 5C 的 CoreMark 跑 **3 次**，记录每次的 CRC 和分数（125 MHz 下的分数和 CoreMark/MHz）；<br>- 5VN 的摄像头识别连续运行 **15 分钟**，每 5 分钟发一次 `status`；<br>- showcase-test.elf 的 benchmark 完整跑一遍，NES 游戏运行 5 分钟。<br>记录是否出现死机、复位、画面错乱、CRC 不一致等异常。 |
| 4 | C | 整理 result.md 并推送 `win/20261103-51-f125-board`。 |

## 6. 产物

放在 `tasks/win/20261103-51-f125-board/artifacts/`：
- `uart/*.log`：各项目的串口原文；
- `photos/`：HDMI 画面；
- `benchmark.txt`：showcase split 原文；
- `edtm_*.csv`：视频和识别负载下的遥测（如果有）。

## 7. 通过判据

- 卡 48 的 F 列各项按原判据给出结果；
- 稳定性测试 3 次 NPU 全部 39/39、3 次 CoreMark CRC 正确、15 分钟摄像头识别无异常；
- 所有数字取自日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261103-51-f125-board 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 比特流 | |
| CLK_SYS_HZ | |

## 卡 48 F 列项目
| 项目 | 结果 | 关键数字 |
|---|---|---|
| 5.0 网口接收 | | |
| 5N NPU 39 项 / C-YOLO fps | | |
| 5E 单张 / 批量 | | |
| 5R RND CRC / benchmark | | |
| 5C CoreMark | | |
| 5F 图像/几何处理 | | |
| 5VN 摄像头识别 / 批量 / 停止 / 切换 | | |

## 稳定性
| 测试 | 次数 / 时长 | 结果 | 异常 |
|---|---|---|---|
| board_npu | 3 次 | | |
| CoreMark | 3 次 | | |
| 摄像头识别 | 15 min | | |
| showcase benchmark + NES | | | |

## 问题与偏离
```
