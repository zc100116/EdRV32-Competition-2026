# 任务卡 20261102-44-showcase-b3r：演示系统 showcase 首次上板（卡 24 B3R 比特流，不重新构建）

## 1. 目标

在卡 24 的 B3R 比特流（CPU + RND + DISP + ETH）上，经网口一次加载打包好的 showcase ELF。验证启动器、各应用进入/退出、调试工具自动建立网口连接，并记录加载耗时、静止 CPU、benchmark fps、NES fps，与旧 S3/NES 程序（卡 24/25）对比。设计依据 `docs/design/2026-11-02-showcase-software.md`，软件报告 `docs/reports/2026-11-02-showcase-core.md`。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。拉出 `win/20261102-44-showcase-b3r`，在 result.md 中记录完整哈希。
- **bitstream**：`G:/codex_project/EdRV32-FPGA/EdRV32-B3R/generate_bitstream/edrv32_fpga_board_render_top.sbit`（卡 24 生成，卡 35/36 用过的同一个）。
- **程序**（本卡 `src/`，由 b3 构建，不在 Windows 端编译）：
  - `showcase.elf`：不含游戏，用来打包用户本地游戏；
  - `showcase-test.elf`：已打包仓库自带的测试 ROM `nrom-template.nes`（`src/games/`），用户本地游戏不可用时用它。
- **用户本地游戏**（只在 Windows 本地，**不入库、不提交、不放进 artifacts**）：一个目录，里面有 ROM、可选的 PNG 图标，以及 `games.txt`。`games.txt` 每行一个游戏，格式为 `名字|ROM 文件名|可选 PNG 文件名`，UTF-8 编码。

## 3. 环境

PDS 2022.2-SP6.1（只用于下载 bitstream）；PG2L200H-6 FBB676。PC 有线网卡 192.168.1.2/24，板子 192.168.1.10；代理/虚拟网卡保持卡 36 时的状态，不改。调试工具上板前先 `git pull`，然后重启。

## 4. 需要的 IP

无。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261102-44-showcase-b3r origin/zc100116/b3`；整理用户清单；向用户要本地游戏目录的路径。 |
| 1 | C | 打包用户游戏：`py tools/sw/pack_games.py tasks/win/20261102-44-showcase-b3r/src/showcase.elf <游戏目录> <仓库外目录>/showcase-games.elf`。记录打包输出的游戏数和 ELF 大小。输出 ELF 放在仓库之外，不提交。 |
| 2 | 用户（U） | 下载 B3R bitstream，接好 HDMI 显示器、串口、网线，打开调试工具。 |
| 3 | U + C | **网口加载 ×3（测试包）**：每次先按 KEY1 复位，让板子停在 BIOS 菜单。在调试工具的烧录页选 ELF + 网口，加载 `src/showcase-test.elf`。记录：开始加载到串口出现 `Showcase:` 的时间、结果；`Showcase:` 出现后多久出现 PEER（板端 `ETH peer` 行或工具日志）；虚拟输入面板显示的通道（应为网口）。 |
| 4 | U + C | **网口加载（用户游戏包）**：同第 3 步，加载第 1 步生成的 `showcase-games.elf`，做 1 次，记录同样的数字和 ELF 大小。以下第 5–9 步都在这次加载上进行。 |
| 5 | U + C | **启动器静止**：不操作 30 s。串口每秒打印一行 `Showcase CPU idle=…% comm=…% app=…% gui=…% GUI fps=…`，取这 30 行的平均值和范围。拍一张启动器照片。 |
| 6 | U + C | **LVGL benchmark**：进入 benchmark 应用跑完。保存全部场景 fps、汇总平均值和 split 原始串口输出；同时记录 CPU 行。再分别进入并退出组件示例和图层示例，确认画面正常。 |
| 7 | U + C | **NES**：进入 NES，游戏选择页应列出全部打包游戏（名字和图标），拍照。选一个游戏，用调试工具的虚拟键盘玩 60 s，记录串口每秒统计中的模拟 fps、显示 fps 和 CPU。按 KEY4（或虚拟 ESC）退回游戏选择页，再选另一个游戏玩 10 s；再按一次 KEY4 回到启动器。 |
| 8 | U + C | **系统状态**：进入系统状态应用，记录页面上显示的各任务 CPU、空闲率、GUI 帧率、网口 link/PEER/收发包数、串口波特率，拍照；退出。 |
| 9 | U + C | **复位后自动重连**：按 KEY1 复位回 BIOS，此时工具虚拟输入应自动切回串口；再用网口加载一次 `showcase-games.elf`，确认 PEER 自动重新建立、通道回到网口，不手动点"连接"。 |
| 10 | C | 只用于对比：从卡 24/25 的 result.md 取旧 S3 benchmark 平均 fps（24/25）和旧 NES 的模拟/显示 fps（54.53/18.07），与本卡数字并列。 |

串口备用方式：如果网口加载失败，先把失败日志原样保存。然后用 `py tools/board/uart_tool.py <ELF> --elf --baud 921600 --port COM3 --log <日志>` 走串口加载一次，继续第 5–8 步，并在 result.md 中注明。不要用 2000000 波特率（卡 24 中该速率切换后乱码）。

## 6. 产物

放在 `tasks/win/20261102-44-showcase-b3r/artifacts/`（不放任何 ROM、游戏包 ELF 或游戏截图以外的游戏数据）：

| 产物 | 内容 |
|---|---|
| `uart/*.log` | 第 3–9 步串口全文 |
| `tool/*.log` | 调试工具日志（加载、PEER、虚拟输入通道） |
| `benchmark.txt` | 第 6 步全部场景 fps、汇总、split 原文 |
| `cpu.csv` | 第 5–7 步每秒 CPU 行，转成 CSV（时间、步骤、idle、comm、app、gui、GUI fps，NES 时加模拟/显示 fps） |
| `photos/*.jpg` | 启动器、游戏选择页、游戏画面、系统状态页 |

## 7. 通过判据

- 网口加载：测试包 3/3 成功；用户游戏包 1/1 成功；第 9 步复位后重新加载成功。每次 `Showcase:` 出现后 PEER 自动建立，不需要手动点"连接"，虚拟输入通道显示网口。
- 启动器、组件示例、benchmark、图层示例、NES（含两级退出）、系统状态都能进入和退出，画面正常，没有卡死或花屏。
- 数字照实记录：加载耗时、静止 CPU、benchmark fps、NES 模拟/显示 fps。是否达到预期由协调者判断，作为对照：旧 S3 静止 CPU ≥ 60%，旧 NES 显示 18 fps。
- 所有数字取自串口和工具输出原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261102-44-showcase-b3r 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| bitstream | 路径 |
| 用户游戏包 | 游戏数、ELF 大小（不列 ROM 文件名以外的信息） |

## 网口加载
| 次 | ELF | 大小 | 加载至 Showcase: 用时 | Showcase: 至 PEER 用时 | 通道 | 结果 |
|---|---|---|---|---|---|---|

## 启动器静止 30 s
| idle 平均（范围） | comm | app | gui | GUI fps |
|---|---|---|---|---|

## Benchmark
| 场景 | fps |
|---|---|
| 汇总平均 | |

## NES
| 游戏 | 模拟 fps 平均 | 显示 fps 平均 | CPU |
|---|---|---|---|

## 应用进入/退出
| 应用 | 进入 | 退出 | 备注 |
|---|---|---|---|

## 系统状态页

## 与旧程序对比
| 项 | 旧（卡 24/25） | 本卡 |
|---|---|---|

## 问题与偏离
```
