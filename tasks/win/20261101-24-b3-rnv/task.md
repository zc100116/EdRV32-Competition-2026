# 任务卡 20261101-24-b3-rnv：B3R、B3N、B3V 带入卡 23 之后的修复，重新实现并上板

## 1. 目标

用 b3 最新 RTL 和程序重做三个工程，确认下面五件事：

1. **B3N 时序**：卡 23 的 clk_npu slow WNS 为 −0.078 ns，唯一终点是 `weight_r[43]` → APM，走线 5.863 ns。本卡把 A5 权重改成 256 个 8 位寄存器，各自 `syn_preserve`，FF 数和周期都不变。需要确认：
   - WNS 是否 ≥ 0；
   - 补报这些寄存器 **D 端**（源 → `weight_r`）的路径：起点单元和位置、裕量。用于判断寄存器被放远的原因。
2. **ETH 发包间隔（eth-spec v0.3 `TX_GAP`）**：`demo_vision.bin`、`demo_npu.bin` 把相邻包的开始间隔设为 17 µs，一帧 1.84 MB 分散在约 30.6 ms 内发出。卡 23 是约 16 ms 线速突发，导致 PC 端丢帧严重。本卡测量调试工具显示的视频帧率和丢失计数。
3. **新 BIOS ROM**：
   - 切换波特率后等 100 ms 再用新速率打印菜单（SoC v0.22），修复 2 Mbaud 乱码；
   - `uart_tool.py` 网口烧录前先做 ARP 检查，不通时直接报错；
   - 卡 23 B3N 网口烧录卡住的原因还没定，本卡按 5.0 一次采集诊断数据。
4. **B3N 图片批量识别**：新版工具在回传缺包，或 1 s 内没收到结束包时，把该张记为失败，并继续下一张（卡 23 停在第一张）。
5. **B3R**：卡 23 的 B3R 上板发现两个软件问题，均已修复，本卡复测并完整做一遍：
   - S3 启动 LVGL WIDGETS 后 CPU store fault（`mepc=0x900663bc`）：菜单焦点回调访问已释放的卡片对象（调试记录 `docs/debug/2026-11-01-s3-widgets-fault.md`）；同时恢复 LVGL 软件帧率统计，benchmark 汇总的各场景 fps 不再是 0；
   - NES 键盘松开方向键后人物继续移动：NES 每帧才读一次串口，16 字节 FIFO 丢掉松键帧，已改为 UART 中断接收（调试记录 `docs/debug/2026-11-01-nes-key-release.md`）。

三个工程可以并行实现，上板逐个进行。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。从这里拉出 `win/20261101-24-b3-rnv`，在 `result.md` 中记录完整哈希。
- **本卡 `src/`**：Linux 端从 b3 `d5d16c34` 构建（`s3.elf`、`nes.elf` 从 `0046345e` 重新构建），GCC 15.2.0。各程序 0 warning；monitor 构建时 third_party/coremark 有一条既有的 `-Wmaybe-uninitialized`。

| 文件 | 用途 | 与卡 23 相比 |
|---|---|---|
| `ip_rom_boot.dat` | BIOS，三个工程的 `ip_rom_boot` 都用它重新生成 | **已更新**（100 ms 波特率等待） |
| `ip_ram_sram.dat` | SRAM 初始内容（monitor），三个工程的 `ip_ram_sram` 都用它重新生成 | 已更新（重新构建） |
| `rnd_board.elf`、`rnd_expected.log` | RND 自检 29 组和期望 CRC | 重新构建 |
| `s3.elf` | LVGL S3：WIDGETS、benchmark、RN-17、网口监控、虚拟输入、LAYERS | **修复 WIDGETS 崩溃；恢复 benchmark fps 统计** |
| `nes.elf` | NES（含虚拟输入） | **UART 中断接收虚拟输入（松键修复）** |
| `board_npu.elf` | NPU 39 项板级测试 | 重新构建 |
| `demo_npu.bin` | B3N 网口送图识别（入口 0x10000000） | **TX_GAP = 2125** |
| `demo_vision.bin` | B3V 图像处理演示，OV5640 720p30（入口 0x10000000） | **TX_GAP = 2125** |
| `eth_diag.bin` | 网口诊断（入口 0x10000000） | 不变 |

- **NPU 模型**：`tasks/win/20261029-09-b3-software/src/npu/`。
- **NES ROM**：同卡 18、21，ROM 不进仓库。
- **调试工具**：上板前 `git pull` 并重启。相对卡 23 的更新：
  - 视频和 YOLO 回传由独立接收进程处理；
  - YOLO 缺包或 1 s 未结束时，记为失败并继续；
  - DDR 带宽图可高亮、隐藏、拖动，纵轴自动缩放，可切满量程；
  - 中控台四个面板可以放大和复原。

## 3. 环境

- PDS 2022.2-SP6.1；器件 PG2L200H-6 FBB676。
- JTAG、USB 串口、HDMI 显示器；B3V 另需 OV5640 摄像头。
- **网口准备**（同卡 22、23）：
  - PC 有线网卡设为 `192.168.1.2/24`，放行 UDP 6000；板端为 `192.168.1.10:5000`；
  - 关闭 Mihomo/Clash 等接管路由的代理或 TUN 虚拟网卡；
  - 调试工具和 `uart_tool.py` 的本机地址都显式设为 192.168.1.2。

| 工程 | 目录 | 顶层 | 导入脚本 | 源文件数 | 时钟数 |
|---|---|---|---|---|---|
| B3R | `G:\codex_project\EdRV32-FPGA\EdRV32-B3R` | `edrv32_fpga_board_render_top` | `import_board_render_top.tcl` | 102 | 14 |
| B3N | `G:\codex_project\EdRV32-FPGA\EdRV32-B3N` | `edrv32_fpga_board_npu_top` | `import_board_npu_top.tcl` | 105 | 13 |
| B3V | `G:\codex_project\EdRV32-FPGA\EdRV32-B3V` | `edrv32_fpga_board_vision_top` | `import_board_vision_top.tcl` | 111 | 16 |

源文件数与卡 23 相同（本卡的改动都在已有文件内）。

## 4. 需要的 IP

逐个按 `fpga/ip/<IP>.md` 生成，模块名和端口名必须与说明一致。

| 动作 | IP | B3R | B3N | B3V |
|---|---|---|---|---|
| 用本卡 `ip_rom_boot.dat` 重新生成 | `ip_rom_boot` | ✓ | ✓ | ✓ |
| 用本卡 `ip_ram_sram.dat` 重新生成 | `ip_ram_sram` | ✓ | ✓ | ✓ |
| 宽度须为 20 位；卡 23 未在该工程重新生成时，本卡生成 | `ip_ram_dcache_tag` | ✓（卡 23 未完成 B3R，请核对） | 卡 23 已做 | 卡 23 已做 |

其余 IP 沿用卡 23 的工程。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261101-24-b3-rnv origin/zc100116/b3`。阅读本卡，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 打开工程，按第 4 节重新生成 IP。 |
| 2 | C + U | **源文件核对**，方法同卡 23：最终源文件数必须等于第 3 节，FDC 为对应顶层的 `.fdc`，宏为 `FPGA_MODE`。B3N 要确认 `edrv32_npu_window.v` 是本卡版本，文件中有 `g_weight_byte`。数目不符就停下，回传“需要添加 / 需要移除”两张清单原文。 |
| 3 | U，或 C 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。任何阶段报错就停下，回传报错原文。 |
| 4 | C | 按第 6 节收集报告，重点如下：<br>1. 时序汇总和资源，与卡 23 对比；<br>2. **B3N 权重路径**：导出终点为 `u_npu` 下 `g_weight_byte[*].weight_r` 寄存器 D 端的最差 20 条 setup 路径（起点、起点单元位置、终点单元位置、裕量、逻辑级数），以及从这些寄存器出发的最差 20 条路径（含 APM 位置），在 PDS 时序控制台中用 `report_timing` 的起点/终点过滤选项导出；<br>3. 复位副本仍单独出现（同卡 23 第 4 步）；<br>4. 布局布线耗时与卡 23 对比。 |
| 5 | U + C | 上板，见 5.0 和 5R / 5N / 5V / 5E。某项失败时保留日志和照片，继续下一项。 |

### 5.0 BIOS（每个工程都做；B3N 另做诊断采集）

1. 同卡 23 第 5.0 节：KEY1 复位进入 BIOS，菜单为 `BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud`。同一个程序先用串口烧一次，再用网口烧一次，记录两种方式的耗时和结果。`.bin` 程序用 `--addr 0x10000000 --entry 0x10000000`。
2. **2 Mbaud**：每个工程做一次 `--baud 2000000` 的串口烧录，保存原始串口文件。依次应收到旧速率的 `Baud result`、新速率的菜单，并且之后的烧录正常。仍乱码时再用 921600 复测，并记录 USB 串口芯片型号和驱动版本。
3. **网口烧录失败时的诊断**（任何一个工程网口烧录不成功都做）：按 `docs/debug/2026-11-01-bios-eth-load.md` 第 7 节第 1–4 步采集：
   - 网卡、路由和 ARP 表；
   - 新版 CLI 的报错原文和原始串口；
   - `eth_probe.py` 的收发记录；
   - 能抓包时附上有线网卡的抓包。

   注意：BIOS 不回 UDP 包，所以 probe 没有收到回包不能判定失败；probe 还可能使 BIOS 打印 FAIL，做完后要重新进入菜单 2。

### 5R：B3R

同卡 23 第 5R 节全部 6 步，另外：

- S3 菜单 5 项逐个进入、按 KEY4 返回，各做两轮，不得出现 `S3 CPU mcause`；WIDGETS 停留约 30 秒并拍照；
- benchmark 汇总表各场景 fps 应为非 0；RN-17 预期 15/16，“opa 容器”一帧 FAIL（约 2.25%，已知）；
- NES：键盘按住方向键 1~2 秒后松开，人物应立即停下，左右各做 5 次，并用鼠标点击按钮重复一次；S3 中同样检查一次，记录结果（S3 的输入路径本卡未改）。

卡 23 第 5R 节的 6 步：

1. RND 自检；
2. S3 benchmark 与 RN-17；
3. LAYERS 5 个画面；
4. NES；
5. 网口与 EDTM；
6. 虚拟输入，含键盘映射和按下反馈的检查。

RND 期望日志用本卡的 `rnd_expected.log`。

### 5N：B3N

- `board_npu.elf` 应为 `NPU board: PASS 39/39`，记录 C-YOLO 行原文。
- `demo_npu.bin` 图片识别（新版工具）：
  1. 上传模型；
  2. 单张识别 3 张，核对检测框是否画在目标上，并截图；
  3. 文件夹连续识别 ≥ 20 张，记录完成张数、失败张数（工具显示的失败原因原文）、平均往返时间、fps，以及每张的 NPU 周期和后处理周期。
- 连续识别期间导出 `edtm_npu.csv`。

### 5V：B3V

同卡 23 第 5V 节：

- 摄像头帧率：两次 `status` 的 camera0/1 frames，应约 30 fps；
- `VIN CH0 overflow` 保持 0；
- `demo_vision.bin` 按 `sw/apps/demo/README.md` 检查清单逐行执行；
- S2 各模式拍照；
- 导出 `edtm_vision.csv`。

### 5E：B3V 网口视频

demo_vision 运行时，调试工具填本机地址 192.168.1.2，建立网口连接：

- 输出设为 ETH，保持约 60 秒，记录：
  - 工具显示的视频帧率，开始和结束各记一次；
  - 工具的丢失计数，开始和结束各记一次；
  - 板端 `Video skips`；
  - 画面是否流畅，有没有成片残缺；
- 输出设为 both，重复一次；
- 在任务管理器中记录调试工具进程（含接收子进程）的 CPU 占用；
- 不通时按卡 22 第 5E 节用 `src/eth_diag.bin` 诊断。

## 6. 产物

放在 `tasks/win/20261101-24-b3-rnv/artifacts/<b3r|b3n|b3v>/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `sources.txt` | 最终源文件数和核对清单 |
| 2 | `flow_summary.txt` | 各阶段耗时、峰值内存、警告数、错误数 |
| 3 | `timing_summary.txt` | 各时钟域 WNS/TNS/WHS/THS 原文；recovery/removal 最差裕量 |
| 4 | `timing_setup_top200.txt`、`timing_setup_top20_detail.txt`、`timing_hold_top20.txt` | 同卡 23 |
| 5 | `npu_weight_paths.txt`（B3N） | 第 5 节第 4 步第 2 项的两组路径 |
| 6 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总和按层次资源 |
| 7 | `high_fanout.txt` | Device Map 的高扇出、时钟、复位、CE 表全文 |
| 8 | `uart/*.log`、`uart/*.raw` | 各程序完整串口文本，含 BIOS 两种烧录方式和 2 Mbaud |
| 9 | `bios_eth_diag/*`（如做了 5.0 第 3 步） | 网卡/路由/ARP 输出、CLI 报错、probe 收发、抓包（只保留 BIOS 会话相关的包） |
| 10 | `edtm_*.csv` | 第 5 节要求的 EDTM 导出 |
| 11 | `lvgl_split.tsv`（B3R） | 同卡 21 |
| 12 | `photos/*` | LAYERS 5 个画面、B3N 叠框截图、B3V 各模式、网口视频截图 |

不提交：ROM 文件、bitstream、PDS 工程文件、IP 生成目录、完整原始日志。

## 7. 通过判据

- 三个工程的源文件数分别等于第 3 节的值，全部完成综合、布局布线和 bitstream。
- 每个工程全部时钟域 WNS ≥ 0、WHS ≥ 0（重点：B3N clk_npu）。不满足时照常上板，如实回传。
- 上板：

| 工程 | 判据 |
|---|---|
| B3R | RND 29/29 PASS；S3 五项均可进入退出、无 CPU 异常；benchmark 跑完且各场景 fps 非 0；RN-17 除“opa 容器”外 PASS；NES 松键立即停止；LAYERS 5 个画面与串口预期一致，画面 5 claimed 非零、unclaimed 为 0；NES 演示 ROM 正常；虚拟输入可用 |
| B3N | 39/39 PASS；单张识别检测框正确；文件夹连续识别不会停在某一张，取得 fps 和失败张数 |
| B3V | 检查清单逐行通过；摄像头约 30 fps；网口视频帧率接近 30、丢失计数与卡 23 对比明显下降 |

- BIOS：三个工程的串口烧录（115200 和 2 Mbaud）和网口烧录都能自动运行；网口不通时有第 5.0 第 3 步的诊断数据。
- 所有数字取自报告和日志原文，找不到的写“未取得”。

## 8. result.md 模板

```markdown
# 20261101-24-b3-rnv 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 源文件数 | B3R / B3N / B3V |
| 完成情况 | |

## 时序（每工程）
| 工程 | 时钟 | WNS | TNS | WHS | THS |
|---|---|---|---|---|---|

recovery/removal 最差裕量：

## B3N 权重路径
- 到 weight_r D 端最差路径：起点、起点位置、终点位置、裕量
- 从 weight_r 出发最差路径：终点 APM 位置、走线延迟、裕量

## 资源（与卡 23 对比）
| 工程 | LUT | FF | DRM | APM | 分布式 RAM | IO | PLL | 卡 23 LUT / FF |
|---|---|---|---|---|---|---|---|---|

## 实现耗时（与卡 23 对比）
| 工程 | synth | map | pnr | timing | bitgen | 峰值内存 |
|---|---|---|---|---|---|---|

## BIOS
| 工程 | 程序 | 串口 115200 耗时/结果 | 串口 2 Mbaud 结果 | 网口烧录 耗时/结果 | 备注 |
|---|---|---|---|---|---|

网口烧录诊断（如做）：

## B3R
- RND：expect.py 结果
- Benchmark Summary 原文；split 摘要
- RN-17 原文
- LAYERS：5 个画面逐项是否与预期一致；画面 5 的 claimed/unclaimed 原文
- NES 表（同卡 21）
- EDTM 文件
- 虚拟输入逐项结果

## B3N
- 39/39 结果、C-YOLO 原文
- 单张识别（检测框是否正确）
- 连续识别：张数、完成/失败数及原因、往返时间、fps、NPU/后处理周期；EDTM 文件

## B3V
- 检查清单逐行结果；各模式起止时间；EDTM 文件
- 摄像头帧率：两次 status 的 camera0/1 frames 与时间、每秒增量

## 网口视频（5E）
| 输出 | 工具帧率（始/末） | 丢失计数（始/末） | Video skips | CPU | 画面 |
|---|---|---|---|---|---|

## 问题与偏离
```
