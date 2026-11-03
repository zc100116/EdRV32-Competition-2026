# 任务卡 20261103-48-vrn-f-rnd1slim：精简 RND v1 的 VRN 与 F 实现并上板

## 1. 目标

把卡 45 的 VRN 和 F 换成精简 RND v1（rnd-spec v0.5，只保留 FILL / BORDER / GLYPH / BLIT / COPY 五条命令）后重新实现，并上板验证。

背景：
- 卡 46 中，精简 RND 在 B3R 上 29 min 布通，时序满足，自检 10/10。RND 资源从 LUT 18145 / FF 14712 / APM 82 / DRM 60 降到 16877 / 11296 / 68 / 58；LVGL 各场景平均帧率 23.4 fps，原版 v1 为 22.2 fps。
- 卡 45 的 VRN（原版 RND v1）布通，但 clk_mem 慢角有违例：WNS −0.474 ns，其中一组最差路径就在 RND 的 draw→read。
- 卡 45 的 F 在第 12 轮报 Route-0039，未布通。

**VRN 优先。** F 是在同样设置下再试一次，看看去掉部分 RND 后能否布通。

## 2. 输入

- **代码**：`origin/zc100116/b3` 上包含本卡的提交（task.md 所在提交）。由它拉出 `win/20261103-48-vrn-f-rnd1slim`，在 result.md 记录 `git rev-parse HEAD`。RTL 基线是 `e94aa0e2`：b3 + 精简 RND v1，NPU、CPU、ETH 与卡 43/45 相同。
- **两个工程**：

| 标识 | 新工程（`G:/codex_project/EdRV32-FPGA/` 下） | 复制来源 | 顶层 | 导入脚本 | FDC | 源文件数 |
|---|---|---|---|---|---|---|
| VRN | `EdRV32-B3F-VRN-RND1S` | 卡 45 `EdRV32-B3F-VRN-RND1-N-NOILA` | `edrv32_fpga_board_vrn_top` | `import_board_vrn_top.tcl` | `edrv32_fpga_board_full_top.fdc` | 139 |
| F | `EdRV32-B3F-RND1S` | 卡 45 `EdRV32-B3F-RND1-N-NOILA` | `edrv32_fpga_board_full_top` | `import_board_full_top.tcl` | `edrv32_fpga_board_full_top.fdc` | 156 |

  两个工程都不插 ILA，复制来源本身也没有 ILA。复制后要**重新导入并重新综合**，不能沿用卡 43 的综合数据库。
- **本卡 `src/`**：由 Linux 从 `e94aa0e2` 用 xPack GCC 15.2.0 构建。除 monitor 中未修改的第三方 CoreMark 有一条既有的 `-Wmaybe-uninitialized` 外，均 0 warning。

| 文件 | 用途 |
|---|---|
| `ip_rom_boot.dat`、`ip_ram_sram.dat` | BIOS ROM 和 SRAM monitor 的初始化内容 |
| `board_npu.elf` | NPU 自检 39 项（自带模型和参考数据） |
| `eth_diag.bin` | 网口诊断 |
| `demo_npu.bin` | 网口送图识别（VRN 和 F） |
| `demo_vision.bin` | 只用于 F 的图像/几何处理（需要 PIX/GEO） |
| `demo_vnpu.bin` | 只用于 F 的摄像头 + NPU，含卡 47 的批量卡死修复和 `camera` 切回命令（需要 PIX/GEO，VRN 不运行） |

  精简 RND 的自检和 showcase **直接使用卡 46 的** `tasks/win/20261103-46-b3r-rnd1slim/src/` 中的 `rnd_board.elf`、`rnd_board_expected.log`、`showcase-test.elf`，这些文件已在同一分支上。
  所有 `.bin` 的加载地址和入口都是 `0x10000000`；`.elf` 按段加载。
- **NPU 模型**：`tasks/win/20261029-09-b3-software/src/npu/`，与卡 43/45 相同。

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- 网络和外设同卡 43：PC 192.168.1.2/24，板 192.168.1.10:5000；HDMI、串口、千兆网口；F 另接 OV5640 摄像头。
- **实现期间不运行仿真虚拟机。** 同一时刻最多两个 PnR，也就是本卡的 VRN 和 F。

## 4. 需要的 IP

沿用复制来源工程的 IP，另做两处调整：

| 动作 | IP |
|---|---|
| 用本卡 `src/` 的两个 dat 重新生成初始化内容 | `ip_rom_boot`、`ip_ram_sram` |
| 移除（精简 RND 不再使用） | `ip_ram_rnd_window` |
| 沿用；实例数以导入后的网表为准 | `ip_ram_rnd_line`、`ip_ram_rnd_palette` 及其余全部 IP |

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261103-48-vrn-f-rnd1slim origin/zc100116/b3`，记录 HEAD。关闭旧调试工具，从这个 checkout 重启。整理用户操作清单。 |
| 1 | C | 记录空闲物理内存，以及当前是否还有其他 PnR 在跑。卡 45 还没结束的旧工程照常停止。 |
| 2 | 用户（U） | 按第 2 节复制两个工程，按第 4 节处理 IP。**清空**工程原有的源文件列表，**只保留**导入脚本加入的文件，以免原版 v1 的 blur/window 等文件残留。 |
| 3 | U 或 C | 在 PDS 控制台中，于各自工程目录下执行 `source ../../EdRV32-Competition-2026/fpga/scripts/<导入脚本>`，确认源文件数为 139 / 156，然后 `synthesize -ads`。记录综合资源。 |
| 4 | U | 两个工程的设置都与卡 45 相同：<br>- Device Map：`Number of Nets To Report` 1000；<br>- PnR：Placement Decongestion Mode **2**；Placement Logic Optimization 勾选；**LUT6D Packing Strategy 0**；**Slack Weight 40**；**Pin Cost Increasing Speed 600**；Multi-thread routing **5**；Dump Router Congestion Plot 勾选。<br>截图设置页。**先启动 VRN** 的 `dev_map`、`pnr`。VRN 进入布线后，如果空闲内存 ≥16 GB，再启动 F；否则等 VRN 结束后再启动 F。 |
| 5 | C | 每小时记录两个工程的轮次、未布通数、过用数和该轮 MT route time，并与卡 45 同轮次对照：VRN 卡 45 共 114 轮布通；F 卡 45 第 12 轮为 78933 / 430438。<br>**止损**：工具报 Route-0039 / Route-0008 即为失败。第 40 轮时未布通数仍大于 18000，也停止该工程。两个工程分别判定，一个失败不影响另一个。 |
| 6 | U + C | 布通的工程依次执行 `report_timing`、`gen_bit_stream`，按第 6 节收集产物。有时序违例也照常生成 bitstream 并上板，时序和功能分开报告。 |
| 7 | U + C | 有 bitstream 后，按下面的上板矩阵逐个测试。某一项失败时保存原文，然后继续后续可以执行的项。 |

### 上板项目矩阵

| 项目 | VRN | F |
|---|---|---|
| 5.0 BIOS、网口接收 5 次 | 做 | 做 |
| 5N NPU 自检 39 项 | 做 | 做 |
| 5E 网口送图识别（demo_npu） | 做 | 做 |
| 5R 精简 RND 自检 + showcase benchmark | 做 | 做 |
| 5C CoreMark（无 ILA） | 做 | 做 |
| 5F 图像/几何处理（demo_vision） | — | 做 |
| 5VN 摄像头 + NPU（demo_vnpu） | — | 做 |

以下日志命令以 VRN 为例，F 把目录中的 `VRN` 换成 `F`。先创建 `artifacts/<标识>/uart/`。

**5.0**：KEY1 复位进入 BIOS。串口以 2 Mbaud 加载 `eth_diag.bin`：
`python tools/board/uart_tool.py tasks/win/20261103-48-vrn-f-rnd1slim/src/eth_diag.bin --addr 0x10000000 --entry 0x10000000 --baud 2000000 --port COMx --log tasks/win/20261103-48-vrn-f-rnd1slim/artifacts/VRN/uart/eth_diag.log`
然后用调试工具网口加载一次。接收检查同卡 43 的 5.0 第 3 步：运行 `eth_probe.py`，做 5 次 `r`/`s`。不要执行 `d`。

**5N**：串口加载 `board_npu.elf`（`--elf --baud 2000000`）。完整执行 39 项，记录 `NPU board: PASS 39/39`、C-YOLO 的 PERF0/MAC/ms/frame/fps/CRC32，以及 D 组 20 行。

**5E**：用调试工具网口加载 `demo_npu.bin`。
1. **先上传模型**（第 2 节模型目录），确认串口打印模型加载成功。卡 45 中 VRN 的这一项失败了：当时没有上传模型就送图，NPU_PERF0=1。
2. 单张识别 3 张，记录框数、往返时间并截图。
3. 文件夹识别至少 20 张，记录完成数、失败数及原因、平均往返时间、每张的 NPU 周期和后处理周期。
4. **已知软件问题**：单张往返超过 1 s 时，工具会超时并改用另一个窗口发下一张，板端可能报 `RGB565 image length` 后停机。这是 demo_npu 的已知问题，下一轮软件修复。出现时记录到第几张、串口原文，复位后重新加载、上传模型，再做一次单张识别即可。不要改工具超时，也不要改程序。

**5R**：
1. 串口以 921600 加载卡 46 的 `rnd_board.elf`。10 行 CRC 与 `rnd_board_expected.log` 逐行比较，HDMI 拍照。
2. 用调试工具网口加载卡 46 的 `showcase-test.elf`，进入 benchmark 跑完全部场景，保存每个场景的 `LVGL split` 原文和 CPU 行。汇总行的 `fps=0` 是已知计数问题，照实记录即可。
3. 进入图层示例，拍照：卡 46 在 B3R 上看到红色区域有蓝紫竖线，记录这里是否同样出现。
4. 其他 showcase 问题（中文缺字、启动器外观等）已知，本卡不再记录。

**5C**：KEY1 复位进入 SRAM monitor，运行 CoreMark 5000 次，记录编译信息、CRC、分数和 HPM 行。

**5F（仅 F）**：同卡 43 的 5F，用本卡 `demo_vision.bin`。逐项测试摄像头帧率、CH0 overflow、PIX/GEO 模式、HDMI/ETH/both 输出，并截图。

**5VN（仅 F）**：用本卡 `demo_vnpu.bin`，上传模型。
1. S1 摄像头识别：至少 3 次 `status`，拍出框画面。
2. 文件夹识别 40 张。
3. 中途按"停止"一次，确认停下后可以立即单张识别。
4. 切回摄像头识别 3 次，确认不需要重新上传模型。

## 6. 产物

放在 `tasks/win/20261103-48-vrn-f-rnd1slim/artifacts/<VRN|F>/`，汇总写进一个 result.md。

| 产物 | 内容 |
|---|---|
| `settings/*.png` | PnR 设置截图 |
| `flow_summary.txt`、`pnr_progress.txt` | 各阶段耗时、CPU 时间、峰值内存；逐轮原文 |
| `congestion/` | 首轮和最后一轮的拥塞图 txt |
| `resource_summary.txt`、`resource_hier.txt` | Map 资源汇总；按模块层次的资源，至少包括 u_rnd、u_npu、u_cpu、u_mem、u_eth、u_vin、u_disp，F 另加 u_pix、u_geo |
| `timing_summary.txt`、`timing_violations.txt`、`timing_setup_top200.txt`、`timing_setup_top20_detail.txt`、`timing_hold_top20.txt` | 同卡 45；布通时提供 |
| `native_reports/` | CMR、SNR、DMR、PRR、RTR 原文（gzip） |
| `uart/*.log`、`photos/`、`benchmark.txt` | 上板串口原文、照片、showcase split 原文 |

不提交工程文件、IP 目录、bitstream 和完整日志；在 result.md 写明它们的本地路径。

## 7. 通过判据

- **实现**：0 未布通网络；setup/hold 不违例。RGMII 慢角 hold 为已知例外，单列实际值；其他违例照实报告，并与卡 45 VRN 对比（clk_mem −0.474、clk_npu −0.047、clk_eth −0.154）。
- **上板**：
  - 网口接收 5/5；NPU 39/39；
  - demo_npu 上传模型后单张识别正确；
  - RND 10 行 CRC 一致；showcase benchmark 跑完；CoreMark CRC 正确；
  - F 另加 5F 逐项有结果、5VN 的批量/停止/切换全部成功。
- 所有数字取自报告和日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261103-48-vrn-f-rnd1slim 结果

| 项 | VRN | F |
|---|---|---|
| 代码 commit | | |
| 工程路径 | | |
| 启动时空闲内存 / 同时运行的 PnR | | |
| 综合 LUT / FF / DRM / APM | | |
| Map LUT / FF / DRM / APM | | |
| PnR 结果（轮数 / 耗时 / 失败原文） | | |

## 布线进度
| 工程 | 轮 | 未布通 | 过用 | 该轮 MT route time | 卡 45 同轮对照 |
|---|---|---|---|---|---|

## 时序（慢角 WNS / TNS / 失败端点，与卡 45 VRN 对比）
| 时钟 | VRN | F | 卡 45 VRN |
|---|---|---|---|

## 层次资源（u_rnd 等）

## 上板
| 项目 | VRN | F |
|---|---|---|
| 5.0 网口接收 | | |
| 5N NPU 39 项 / C-YOLO fps | | |
| 5E 单张 / 批量 | | |
| 5R RND CRC / benchmark 平均每帧 ms / 图层竖线 | | |
| 5C CoreMark | | |
| 5F | — | |
| 5VN 批量 / 停止 / 切换 | — | |

## 问题与偏离
```
