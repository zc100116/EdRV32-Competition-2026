# 任务卡 20261030-16-b3r-lvgl-nes：在 B3R 上测 LVGL 分场景耗时，并用外部 ROM 跑 NES

## 1. 目标

这张卡只换软件，不重新综合，直接用卡 14 生成的 B3R bitstream。做两件事：

1. **LVGL 分场景耗时**：跑带分场景耗时拆分的 S3 benchmark，确认板上 LVGL 慢在哪里。卡 14 中，Empty screen 一条全屏 FILL 用了 15 ms，仿真只要 0.507 ms。新版 S3 每个场景结束时打印一行 `LVGL split`，内容包括：
   - render 拆成 RND、SW、其余三部分；
   - RND PERF0–5；
   - mem_xbar 的 RND/DISP 端口统计。
2. **NES 外部 ROM**：NES 模拟器与游戏 ROM 已经分开。ELF 不带游戏，加载时用 `--rom` 把 `.nes` 文件写进 DDR 的 ROM 槽。先用仓库里的自制演示 ROM 确认流程，再跑用户自备的超级马里奥。

## 2. 输入

- **代码分支**：`origin/zc100116/b3`（包含本卡的提交）。Windows Codex 从这里拉出 `win/20261030-16-b3r-lvgl-nes`，在 `result.md` 中记录完整哈希。
- **bitstream**：卡 14（`win/20261030-14-b3r-rnd`）在 `G:\codex_project\EdRV32-FPGA\EdRV32-B3R-r2\` 生成的 B3R bitstream。此后 RTL 没有变化，不需要重新综合。
- **程序**：本卡 `src/`，由 b3 `b64814aa` 构建：

| 文件 | 内容 |
|---|---|
| `src/s3.elf` | 新版 S3：benchmark 分场景耗时拆分；`LV_DRAW_LAYER_SIMPLE_BUF_SIZE` 改为 96 KiB |
| `src/nes.elf` | NES 显示版，不含 ROM，ROM 槽符号为 `nes_rom_slot` 0x905e91c0，大小 1 MiB |

- **ROM**：
  - 仓库自带的 `sw/apps/nes/roms/nrom-template.nes`；
  - 用户自备的超级马里奥 ROM（iNES 格式，mapper 0）。**只放在 Windows 本地，不复制进仓库，不提交，不写进 artifacts**；`result.md` 里只写"用户自备 SMB ROM"，不写文件路径。

## 3. 环境

PDS 2022.2-SP6.1 只用来下载 bitstream；PG2L200H-6 FBB676，JTAG，USB 串口，HDMI 显示器，Python 3 和 pyserial。

## 4. 需要的 IP

无。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261030-16-b3r-lvgl-nes origin/zc100116/b3`。把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 下载卡 14 的 B3R bitstream，接好 HDMI 和串口，告诉 Codex COM 口号。 |
| 2 | 用户（U）或 Codex（C） | **S3 benchmark**。加载 `src/s3.elf`：可以用 GUI（115200），也可以用命令行 `py tools/board/uart_tool.py tasks/win/20261030-16-b3r-lvgl-nes/src/s3.elf --elf --baud 115200 --port COMx --log build/board/s3.log`。在主界面选择 benchmark，等它自然跑完，串口打印出 `Benchmark Summary` 和 `LVGL split scene="ALL"` 两部分后再停。中途不要按 KEY4。 |
| 3 | 用户（U） + Codex（C） | **NES 演示 ROM**。只能用命令行，因为 GUI 不支持 `--rom`：`py tools/board/uart_tool.py tasks/win/20261030-16-b3r-lvgl-nes/src/nes.elf --elf --rom sw/apps/nes/roms/nrom-template.nes --baud 115200 --port COMx --log build/board/nes-template.log`。确认串口打印 `NES ROM prg=16 chr=8 mapper=0`，画面里人物能动。运行约 30 秒，保证至少有 3 行 `NES fps=`，然后停止，复位板子。 |
| 4 | 用户（U） + Codex（C） | **NES 超级马里奥**。同步骤 3，把 `--rom` 换成用户本地的 SMB 文件，日志写到 `build/board/nes-smb.log`。确认串口打印 `NES ROM prg=32 chr=8 mapper=0`。用户用板上按键试玩约 1 分钟：KEY1 左、KEY2 右、KEY3 跳（A）、KEY4 Start；B 键只能在串口发 `k`，本卡不要求。记录画面、按键和速度的主观感受。出现 `NES ROM slot empty or invalid` 或 mapper 报错时，原文记下并停止。 |
| 5 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交信息 `win: 20261030-16-b3r-lvgl-nes results`，推送 `win/20261030-16-b3r-lvgl-nes`。中途停下时，已完成的部分照常回传。 |

## 6. 产物

放在 `tasks/win/20261030-16-b3r-lvgl-nes/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/s3.log` | 从启动到 benchmark 结束的完整串口文本，必须包含全部 `LVGL split` 行、`Benchmark Summary` 和 `RND type=` 统计 |
| 2 | `lvgl_split.tsv` | 从 `LVGL split` 行提取的表格，一个场景一行，每个 `key=value` 一列，列名就用 key，数值照抄原文 |
| 3 | `uart/nes-template.log`、`uart/nes-smb.log` | NES 串口文本，含 `NES ROM` 行和全部 `NES fps=` 行 |
| 4 | `checklist.md` | 每一步是否完成、画面和按键是否正常、用户的主观感受 |

不提交：ROM 文件、bitstream、截图以外的二进制文件。

## 7. 通过判据

- S3 benchmark 跑完，16 个场景加 ALL 共 17 行 `LVGL split` 都已取得。
- 演示 ROM 能用 `--rom` 加载并正常运行。
- SMB 能加载并进入游戏。帧率如实记录，不作为通过条件。
- 所有数字照抄串口原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261030-16-b3r-lvgl-nes 结果

| 项 | 内容 |
|---|---|
| 代码 commit（origin/zc100116/b3） | |
| bitstream | 卡 14 B3R（工程路径） |
| 加载方式与波特率 | S3：GUI / 命令行；NES：命令行 |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## LVGL
Benchmark Summary 原文：

`LVGL split` 每个场景的 render_ms、rnd_ms、sw_ms、other_ms、perf0_ms、perf4_rd_wait_cycles、perf5_wr_wait_cycles、copy_rnd_ms（完整字段见 artifacts/lvgl_split.tsv）：

| 场景 | frames | render_ms | rnd_ms | sw_ms | other_ms | perf0_ms | perf4 | perf5 | copy_rnd_ms |
|---|---|---|---|---|---|---|---|---|---|

## NES
| ROM | NES ROM 行 | fps（各窗口） | shown | cpu% | ppu% | 画面/按键 |
|---|---|---|---|---|---|---|
| nrom-template | | | | | | |
| 用户自备 SMB | | | | | | |

用户试玩感受：

## 备注
```
