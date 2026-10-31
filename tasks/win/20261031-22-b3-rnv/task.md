# 任务卡 20261031-22-b3-rnv：B3R、B3N、B3V 用最新 RTL 和新 BIOS 串行实现，上板确认各模块功能并记录 DDR 带宽

## 1. 目标

这一轮确认三件事，结果用来敲定功能模块，并作为下一步 B3F 布局规划的依据：

1. **时序修复**：
   - 卡 21 中 B3R 的 clk_eth（RGMII 接收）有违例，B3N 的 clk_mem → DDR PHY 有违例，两处原因都是寄存器离 IO 太远；
   - b3 在约束中加了两个区域约束：`fp_rgmii`（左边缘 BANKL3 旁）和 `fp_ddrphy`（右边缘 DDR bank 旁）；
   - B3V 也加了这两项。
2. **新功能上板**：
   - RND 2.0（三角形、粗线、圆弧、遮罩、仿射 BLIT 等）；
   - 新 BIOS（SoC 规格 v0.18 7.5(3a)）：串口或网口烧录，烧完自动运行；
   - B3N 网口送图识别；
   - 三板网口。
3. **DDR 使用情况**：每个负载都用调试工具导出 EDTM（DDR 各端口读写带宽和等待），记录各模块实际占用多少 DDR 带宽。

三个工程**串行**执行：B3R → B3N → B3V。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。从这里拉出 `win/20261031-22-b3-rnv`，在 `result.md` 中记录完整哈希。
- **本卡 `src/`**：Linux 端从 b3 `f4870fc3` 构建，GCC 15.2.0，0 warning。

| 文件 | 用途 |
|---|---|
| `ip_rom_boot.dat` | 新 BIOS（8884 B），三个工程的 `ip_rom_boot` 都用它重新生成 |
| `ip_ram_sram.dat` | SRAM 初始内容（monitor），三个工程的 `ip_ram_sram` 都用它重新生成 |
| `rnd_board.elf`、`rnd_expected.log` | RND 自检，共 29 组（原 16 组加 2.0 新增 13 组），以及参考模型给出的期望 CRC |
| `s3.elf` | LVGL S3（benchmark、RN-17、网口监控） |
| `nes.elf` | NES，ROM 槽 `nes_rom_slot` 0x905f61c0 |
| `board_npu.elf` | NPU 39 项板级测试 |
| `demo_npu.bin` | B3N 网口送图识别（SRAM 程序） |
| `demo_vision.bin` | B3V 图像处理演示（SRAM 程序） |

- **NPU 模型**：`tasks/win/20261029-09-b3-software/src/npu/`。
- **NES ROM**：同卡 18 和卡 21，ROM 不进仓库。
- **软件更新**：调试工具界面和 `demo_npu` 还在改，改完会更新到本卡 `src/` 和 b3。**每个工程上板前先 `git pull`**；`src/` 有新版本时用新版本，并在 `result.md` 中记下实际使用的文件和 commit。

## 3. 环境

- PDS 2022.2-SP6.1；器件 PG2L200H-6 FBB676。
- JTAG、USB 串口、HDMI 显示器；B3V 另需 OV5640 摄像头。
- **网口准备**：
  - PC 有线网卡设为 `192.168.1.2/24`，允许 UDP 6000；板端固定 `192.168.1.10:5000`；
  - **测试前关闭 Mihomo（或其他会接管路由的代理/虚拟网卡）**。卡 21 中工具把本机地址选成了 Mihomo 的 198.18.0.1，因此收不到板端数据；
  - 调试工具和 `uart_tool.py` 的本机地址都要显式设为 192.168.1.2。

### 工程

三个工程都在原工程目录上更新。导入脚本的相对路径要求工程目录和仓库位于同一父目录下。

| 工程 | 目录 | 顶层 | 导入脚本 | 源文件数 | 时钟数 |
|---|---|---|---|---|---|
| B3R | `G:\codex_project\EdRV32-FPGA\EdRV32-B3R` | `edrv32_fpga_board_render_top` | `import_board_render_top.tcl` | 103 | 14 |
| B3N | `G:\codex_project\EdRV32-FPGA\EdRV32-B3N` | `edrv32_fpga_board_npu_top` | `import_board_npu_top.tcl` | 106 | 13 |
| B3V | `G:\codex_project\EdRV32-FPGA\EdRV32-B3V` | `edrv32_fpga_board_vision_top` | `import_board_vision_top.tcl` | 112 | 16 |

## 4. 需要的 IP

逐个按 `fpga/ip/<IP>.md` 生成，模块名和端口名必须与说明一致。分布式 RAM IP 的 `rd_clk`、`rst` 端口已按卡 21 的结果接好。

| 动作 | IP | B3R | B3N | B3V |
|---|---|---|---|---|
| 用本卡 `ip_rom_boot.dat` 重新生成 | `ip_rom_boot` | ✓ | ✓ | ✓ |
| 用本卡 `ip_ram_sram.dat` 重新生成 | `ip_ram_sram` | ✓ | ✓ | ✓ |
| 新生成（RND 2.0 源窗口） | `ip_ram_rnd_window` | ✓ | — | — |
| 重新生成，32 KiB（同卡 21） | `ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`、`ip_ram_dcache_data` | 已有 | 已有 | ✓ |
| 新生成，16 × 144（同卡 21） | `ip_lutram_mem_xbar_w` | 已有 | 已有 | ✓ |
| 从工程中删除 | `ip_ram_mem_xbar_w` | 已删 | 已删 | ✓ |

## 5. 操作步骤

每个工程依次执行步骤 1–5。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261031-22-b3-rnv origin/zc100116/b3`。阅读本卡、`sw/boot/README.md`（v0.18 BIOS）、`tools/board/README.md`、`docs/reports/2026-10-31-board-eth-sw.md` 的 ETH 检查步骤。把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 打开工程，按第 4 节生成和删除 IP。 |
| 2 | Windows Codex（C） + 用户（U） | **源文件核对**，方法同卡 21：<br>1. Codex 给出 Designs 与导入脚本展开结果的“需要添加 / 需要移除”两张清单；用户照清单修改，或在工程目录下执行导入脚本；<br>2. 最终源文件数必须等于第 3 节的值，FDC 为对应顶层的 `.fdc`（本次新增 `PAP_REGION`），宏为 `FPGA_MODE`，Designs 中没有游离的顶层模块。<br>数目不符就停下，回传两张清单原文。 |
| 3 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。<br>任何阶段报错（包括 `PAP_REGION` 不被接受）就停下，回传报错原文。 |
| 4 | Windows Codex（C） | 按第 6 节收集时序和资源报告。重点：clk_eth 和 clk_mem → phy_dq_sysclk_* 是否通过；u_rgmii、u_ddr3/u_ddrphy_top 的寄存器是否落在区域内（从 PRR/布局报告查站点）。 |
| 5 | 用户（U） + Codex（C） | 上板，见 5.0 和 5R / 5N / 5V。<br>某项失败时，保留日志和照片，继续下一项。 |

### 5.0 新 BIOS（每个工程都做）

1. 用户按住 KEY1 并复位进入 BIOS。菜单行应为 `BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud`。
2. **串口烧录**：`py tools/board/uart_tool.py <ELF> --elf --baud 2000000 --port COMx --log build/board/c22-<名>.log`。应依次看到 `Load result: PASS`、`Run: 0x...`，程序自动运行。
3. **网口烧录**：同一个程序再用网口烧一次。`py tools/board/uart_tool.py <ELF> --elf --eth --local-ip 192.168.1.2 --port COMx --log ...`，参数以 `tools/board/README.md` 为准。
   - 应看到 `ETH link: up`、`ETH load ready 192.168.1.10:5000`、`Load result: PASS`，程序自动运行；
   - 记录两种方式的烧录耗时；
   - 出现 `ETH load result: FAIL bytes ...` 时原文记下（工具会整份重发一次）。
4. `.bin` 程序（demo_npu、demo_vision）用 `--addr 0x10000000 --entry 0x10000000`。
5. 网口烧录不通时，先确认第 3 节的网口准备，再记录现象。PHY 地址 0 是按 RTL8211F 的广播地址设定的；如果怀疑这里，请用户告知板上 PHY 地址的跳线或丝印。

### 5R：B3R

1. **RND 自检（29 组）**：
   - 烧录 `src/rnd_board.elf`；
   - `py sw/tests/rnd_board/expect.py build/board/c22-rnd.log`，应为 PASS；
   - 用户对照 `sw/tests/rnd_board/README.md` 的检查清单看 HDMI 画面，并给新增 13 组拍照。
2. **S3**：
   - 烧录 `src/s3.elf`，运行 benchmark，自然结束后取 `Benchmark Summary` 和 17 行 `LVGL split`；
   - 再跑 RN-17。按设计记录，“opa 容器”一帧预计 FAIL，约 2.3%，原因是 LVGL 5 位混合舍入，不算故障，原文照记，其余帧应 PASS。
3. **NES**：同卡 21 的 5R 第 4 步，演示 ROM 和两个 SMB ROM。
4. **网口与 EDTM**：
   - S3 benchmark 运行时，调试工具建立网口连接，从开始到结束导出 EDTM CSV（`edtm_s3.csv`）；
   - NES 运行时导出约 30 秒（`edtm_nes.csv`）。

### 5N：B3N

1. 烧录 `src/board_npu.elf`，应为 `NPU board: PASS 39/39`。
2. **网口送图识别**：
   - 烧录 `src/demo_npu.bin`；调试工具建立网口连接，用目标检测（B3N）页加载模型，等串口打印 `EDNM: loaded`；
   - **单张**：选 3 张不同的图片，各识别一次，工具应显示比对一致，叠框截图；
   - **连续**：选一个文件夹（≥ 20 张），连续识别，记下工具统计的平均往返时间和 fps，以及串口每张的 NPU 周期和后处理周期。
3. **EDTM**：连续识别期间导出 EDTM CSV（`edtm_npu.csv`）。

### 5V：B3V

1. 烧录 `src/demo_vision.bin`。按 `sw/apps/demo/README.md` 的上板检查清单中 demo_vision 的部分逐行执行。
2. **S2 各模式**：PIX 的 bypass、brightness、gamma、gaussian、sobel，GEO 的 off、rotate、scale，各保持约 10 秒；输出分别试 HDMI、ETH、both。
3. **EDTM**：上述过程连续导出一份 EDTM CSV（`edtm_vision.csv`），并在 `result.md` 中写下每种模式的起止时间，用来对照曲线。

## 6. 产物

放在 `tasks/win/20261031-22-b3-rnv/artifacts/<b3r|b3n|b3v>/`，内容同卡 21：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `sources.txt` | 最终源文件数和核对清单 |
| 2 | `flow_summary.txt` | 各阶段耗时、峰值内存、警告数、错误数 |
| 3 | `timing_summary.txt` | 各时钟域 WNS/TNS/WHS/THS，原文 |
| 4 | `timing_setup_top200.txt`、`timing_setup_top20_detail.txt`、`timing_hold_top20.txt` | 同卡 21 |
| 5 | `region_check.txt` | u_rgmii、u_ddr3/u_ddrphy_top 中寄存器的实际站点（摘录），以及卡 21 违例的两条路径在本次的裕量 |
| 6 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总和按层次的资源，含 u_rnd、u_npu、u_eth、cpu/cache、u_mem/u_xbar |
| 7 | `uart/*.log` | 各程序的完整串口文本，包括 BIOS 的两种烧录方式 |
| 8 | `edtm_*.csv` | 第 5 节要求的 EDTM 导出 |
| 9 | `lvgl_split.tsv`（B3R） | 同卡 21 |
| 10 | `photos/*.png` | RND 新增组、B3N 叠框截图、B3V 各模式 |

不提交：ROM 文件、bitstream、PDS 工程文件、IP 生成目录、完整原始日志。

## 7. 通过判据

- 三个工程的源文件数分别为 103、106、112，全部完成综合、布局布线和 bitstream。
- 每个工程全部时钟域 WNS ≥ 0、WHS ≥ 0。不满足时照常上板，如实回传。
- BIOS：三个工程的串口和网口烧录都自动运行。
- 上板：

| 工程 | 判据 |
|---|---|
| B3R | RND 29/29 PASS；benchmark 跑完；RN-17 除“opa 容器”外 PASS；NES 演示 ROM 正常 |
| B3N | 39/39 PASS；单张识别比对一致；连续识别取得 fps |
| B3V | 检查清单逐行通过 |

- 三个工程都取得 EDTM CSV。
- 所有数字取自报告和日志原文，找不到的写“未取得”。

## 8. result.md 模板

```markdown
# 20261031-22-b3-rnv 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 实际使用的 src 文件和 commit | |
| 源文件数 | B3R / B3N / B3V |
| 完成情况 | |

## 时序（每工程）
| 工程 | 时钟 | WNS | TNS | WHS | THS |
|---|---|---|---|---|---|

卡 21 违例路径本次的裕量；区域约束是否生效：

## 资源
| 工程 | LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|---|

| 工程 | 层次 | LUT | FF | DRM | APM |
|---|---|---|---|---|---|

## 实现耗时
| 工程 | synth | map | pnr | timing | bitgen | 峰值内存 |
|---|---|---|---|---|---|---|

## BIOS
| 工程 | 程序 | 串口烧录 耗时/结果 | 网口烧录 耗时/结果 | 备注 |
|---|---|---|---|---|

## B3R
- RND：expect.py 结果，新增组画面
- Benchmark Summary 原文；split 摘要
- RN-17 原文
- NES 表（同卡 21）
- EDTM 文件

## B3N
- 39/39 结果
- 单张识别：图片、检测数、比对结果
- 连续识别：张数、平均往返时间、fps、NPU 周期/后处理周期范围
- EDTM 文件

## B3V
- 检查清单逐行结果
- 各模式起止时间（对照 EDTM）

## 问题与偏离
```
