# 任务卡 20261031-18-nes-trainer：NES 修复带 trainer 的 ROM 灰屏后上板复测

## 1. 目标

卡 16 补测时，"超级马里奥1超级版"能加载、能识别为 mapper 0，但画面全灰。

- **原因**：nofrendo 上游跳过 trainer 时，只把函数里的局部变量往后挪了，调用者手里的 ROM 读取位置没动。结果 PRG 从 trainer 内部开始读，游戏一上电就跑飞。所有带 trainer 的 ROM 都会这样（iNES 头字节 6 的 bit2 为 1）。
- **修复**：b3 `2f5e6909`，新增补丁 `sw/apps/nes/patches/rom-trainer-cursor.patch`。
- **Linux 主机验证**：同一个 ROM 打补丁前全灰，打补丁后正常显示中文标题画面。

本卡只换程序，在板上确认修复有效。

## 2. 输入

- **代码分支**：`origin/zc100116/b3`，从这里拉出 `win/20261031-18-nes-trainer`，在 `result.md` 中记录完整哈希。
- **bitstream**：卡 14 的 B3R。和卡 17 用的是同一个，可以在同一次上电里连着跑。
- **程序**：`src/nes.elf`，由 b3 `b3dfeec3` 构建，不含 ROM。
- **ROM**：用户本地 `third_party/nes/` 目录，该目录只在 `win/20261030-16-b3r-lvgl-nes` 分支上：
  - `FC改版hack 390款 含封面/超级马里奥1超级版.nes`（带 trainer，卡 16 中灰屏的那个）
  - `FC游戏 536款 含封面/超级马里奥1/超级马里奥1.nes`（不带 trainer，作对照）

## 3. 环境

与卡 16 相同。

## 4. 需要的 IP

无。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261031-18-nes-trainer origin/zc100116/b3`。ROM 从用户本地已有的 `third_party/nes` 目录读取，不在本分支中提交 ROM。 |
| 1 | 用户（U） | 下载 B3R bitstream，接好 HDMI 和串口；按住 KEY1 复位，进入 BIOS。 |
| 2 | Codex（C） | 加载超级版：`py tools/board/uart_tool.py tasks/win/20261031-18-nes-trainer/src/nes.elf --elf --rom "<本地路径>/超级马里奥1超级版.nes" --baud 115200 --port COMx --log build/board/nes-smb-hack.log`。串口应依次出现 `Read in trainer at $7000` 和 `NES ROM prg=32 chr=8 mapper=0`。 |
| 3 | 用户（U） | 确认标题画面显示正常（不是灰屏），用 KEY4（Start）开始游戏，KEY1/KEY2 左右移动，KEY3 跳，试玩约 1 分钟，记下主观感受，包括速度是否偏慢。 |
| 4 | Codex（C） + 用户（U） | 停止采集，复位后按步骤 2 的方式加载原版 `超级马里奥1.nes`，日志写到 `nes-smb-orig.log`。用户同样确认画面和按键。 |
| 5 | Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息为 `win: 20261031-18-nes-trainer results`，推送。 |

## 6. 产物

| # | 产物 | 内容 |
|---|---|---|
| 1 | `artifacts/uart/nes-smb-hack.log`、`artifacts/uart/nes-smb-orig.log` | 串口原文 |
| 2 | `artifacts/checklist.md` | 每个 ROM 的画面、按键、速度和用户反馈 |

## 7. 通过判据

两个 ROM 都能显示标题画面并进入游戏，按键有响应。帧率如实记录，不作为通过条件。

## 8. result.md 模板

```markdown
# 20261031-18-nes-trainer 结果

| ROM | NES ROM 行 | trainer 行 | 画面 | 按键 | fps（第 2–4 窗口） | 用户反馈 |
|---|---|---|---|---|---|---|
| 超级马里奥1超级版 | | | | | | |
| 超级马里奥1 | | | | | | |
```
