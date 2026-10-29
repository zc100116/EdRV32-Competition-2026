# 任务卡 20261029-04-b3r-software：在 B3R 上经 BIOS 运行 RND 自检、S3（LVGL + 游戏）和 NES

## 1. 目标

20261029-03 的 B3R（渲染验证）bitstream 点亮后，**不重新生成 bitstream**，经新 BIOS 把 DDR 程序下载运行：
- RND 自检：16 组图案的 CRC 与参考模型逐行比对；
- S3：LVGL 主界面，从界面启动自制游戏 Amber Run、LVGL widgets 演示、LVGL benchmark、RN-17 自比对；
- NES 模拟器：画面检查，实测帧率。

## 2. 输入

- 代码分支 `origin/zc100116/b3`（包含本卡的提交）。B3 尚未合入 `main`。
- 前置：20261029-03 中 B3R 已经能进入新 BIOS（`BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud`）。
- 本卡 `src/`：在 Linux 端构建（`rnd_board`、`nes*` 来自 9510c64，`s3.elf` 来自 911ec63），GCC 15.2.0，程序链接在 DDR 应用区（CPU 0x9000_0000）：

  | 文件 | 内容 |
  |---|---|
  | `rnd_board.elf` | RND 自检（`sw/tests/rnd_board/`）。8 条命令画 16 组图案，L0 RGB565 和 L1 ARGB8888 两块画面送 HDMI，每组打印一行 `RND <组名> crc=0x...` |
  | `rnd_expected.log` | 同一组命令由参考模型 `rnd_ref.py` 算出的期望 CRC（`python3 sw/tests/rnd_board/expect.py` 的输出） |
  | `s3.elf` | S3 程序（`sw/apps/s3/`，约 1.1 MB，2000000 波特率下加载约 6 s）。主界面四项：01 Amber Run、02 LVGL Widgets、03 Benchmark、04 RN-17 Compare |
  | `nes.elf` | NES 模拟器（`sw/apps/nes/`，nofrendo，内嵌公开 ROM nrom-template）。256×240 画面由 RND 放大 3 倍居中显示 |
  | `nes_nodisplay.elf` | 同一模拟器，不显示，只计时（`NES_DISPLAY=0`），用来对比显示的开销 |

- 加载工具：`tools/board/uart_tool.py --elf`，用法见 `tools/board/README.md`。它自动完成以下步骤：
  1. 切到 2000000 波特率（菜单 `4`）；
  2. 每段执行一次 `2` Load；
  3. 用 `3` Run 启动。

## 3. 环境

- B3R 工程的 bitstream、HDMI 显示器、USB 串口；Windows 上的 Python 3。

## 4. 需要的 IP

无（使用 20261029-03 的 B3R bitstream）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | 在 b3 检出中 `git fetch origin`，`git switch -c win/20261029-04-b3r-software origin/zc100116/b3`。阅读本卡、`tools/board/README.md`、`sw/tests/rnd_board/README.md`、`sw/apps/nes/README.md` 的上板检查清单。 |
| 1 | 用户（U） | 下载 B3R bitstream，接好 HDMI 和串口；告诉 Codex COM 口号。 |
| 2 | 用户（U） + Codex（C） | **RND 自检**：<br>1. 用户按住 KEY1 并复位进入 BIOS；<br>2. Codex 执行 `py tools/board/uart_tool.py tasks/win/20261029-04-b3r-software/src/rnd_board.elf --elf --port COMx --log build/board/rnd.log`；<br>3. 程序结束后执行 `py sw/tests/rnd_board/expect.py build/board/rnd.log`，结果应为 PASS；<br>4. 用户给 HDMI 画面拍照，对照 `sw/tests/rnd_board/README.md`“屏幕与上板检查清单”说明每组图案是否正常。<br>失败时保留实际 CRC、ERR_CODE/CUR_DESC、日志和照片，继续下一步。 |
| 2a | 用户（U） + Codex（C） | **S3**：<br>1. 复位并按住 KEY1 进入 BIOS；<br>2. 加载 `s3.elf`，日志 `build/board/s3.log`；<br>3. 按 `sw/apps/s3/README.md`“上板检查”逐项检查。键表见同一 README 的“输入与应用切换”：KEY1/`a` 前一项，KEY2/`d` 后一项，KEY3/`w` 启动，KEY4/`p` 返回或暂停。要做的检查：<br>• 主界面显示正常；<br>• 游戏：卷轴平滑无撕裂、精灵朝向、透明区、得分条，暂停后返回主界面；<br>• widgets 演示；<br>• benchmark：保存串口中各场景的帧率和平均帧率；<br>• RN-17 自比对：保存串口中的差异统计；<br>• 来回切换应用几次，画面恢复正常。<br>4. 用户给主界面、游戏、widgets 拍照。 |
| 3 | 用户（U） + Codex（C） | **NES（显示版）**：<br>1. 复位并按住 KEY1 进入 BIOS；<br>2. 用同样方式加载 `nes.elf`，日志 `build/board/nes.log`；<br>3. 按 `sw/apps/nes/README.md`“上板检查清单”逐项检查：启动信息、画面 768×720 居中、颜色、有无撕裂、UART 八键和 KEY1–4；<br>4. 保存至少 3 个窗口的 `NES fps=... shown=... cpu=... ppu=...` 行，第一个窗口丢弃；<br>5. 用户拍画面照片。 |
| 4 | 用户（U） + Codex（C） | **NES（只计时版）**：同样加载 `nes_nodisplay.elf`，日志 `build/board/nes_nodisplay.log`，保存至少 3 个窗口的 fps 行。 |
| 5 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261029-04-b3r-software results`，推送 `win/20261029-04-b3r-software`，告诉用户完成并给出分支名。 |

## 6. 产物

放在 `tasks/win/20261029-04-b3r-software/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/rnd.log`、`rnd_compare.txt` | 自检串口日志；`expect.py` 比对输出 |
| 2 | `uart/s3.log`、`uart/nes.log`、`uart/nes_nodisplay.log` | S3、NES 串口日志 |
| 3 | `photos/*.jpg` | RND 自检、S3 主界面/游戏/widgets、NES 画面 |
| 4 | `checklist.md` | 三份 README 上板检查清单逐项结果（正常 / 异常 + 现象） |

## 7. 通过判据

- RND：`expect.py` 16 组全部 PASS，ERR_CODE 为 0；画面与 README 描述一致。
- S3：主界面、游戏、widgets 显示正常，应用切换后恢复正常；benchmark 帧率和 RN-17 统计如实记录（RN-17 容差尚未定稿，不作为通过条件）。
- NES：画面居中、颜色正确，按键有响应；记录显示版和只计时版的实测帧率。帧率多少不作为通过条件，如实记录。
- 某项异常时记下现象继续，不调试；所有数字来自串口日志原文。

## 8. result.md 模板

```markdown
# 20261029-04-b3r-software 结果

| 项 | 内容 |
|---|---|
| 代码 commit（origin/zc100116/b3） | <完整哈希> |
| bitstream 来源 | 20261029-03 B3R（commit） |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## RND 自检
- expect.py 结果（PASS 组数 / 16）、失败组的实际 CRC：
- ERR_CODE / CUR_DESC：
- 画面检查：

## S3
- 主界面、游戏、widgets：
- benchmark 各场景帧率 / 平均：
- RN-17 自比对统计（摘录）：
- 应用切换：

## NES
| 版本 | fps（窗口 2–4） | shown | cpu% | ppu% |
|---|---|---|---|---|
| 显示 | | | | |
| 只计时 | | | | |

- 画面（居中、颜色、撕裂）：
- 按键：

## 备注
```
