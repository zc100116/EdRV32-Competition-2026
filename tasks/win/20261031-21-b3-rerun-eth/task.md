# 任务卡 20261031-21-b3-rerun-eth：B3R、B3N、B3VN 用最新 RTL 串行重新实现，三板都带 ETH，上板测功能和时序

## 1. 目标

卡 14/15/09 之后，RTL 有以下改动，需要重新综合、布局布线、上板确认：

1. **I$、D$ 各扩到 32 KiB**（cache-spec v0.8）。D$ 维护改为只访问覆盖的组，整体 clean 跳过干净组段：1 行维护 768→4 周期，512 行 768→515 周期。
2. **浅存储改用分布式 RAM**（设计记录 `docs/design/2026-10-31-drm-lutram.md` 方案 B）：
   - mem_xbar 写缓冲；
   - NPU 量化参数、残差、结果环；
   - NPU 激活表改为 2048 深。
3. **B3R、B3N 加入 ETH**，接法与 B3VN 相同。
4. **软件**：
   - cache 维护等待改为一次可缓存读；
   - CPU 只写的命令改放非缓存别名；
   - B3R/B3N 的 ETH 监控（报告 `docs/reports/2026-10-31-board-eth-sw.md`）。

三个工程**串行**执行：B3R → B3N → B3VN。前一个上板完成后再开始下一个。

## 2. 输入

- **代码分支**：`origin/zc100116/b3`（包含本卡的提交）。从这里拉出 `win/20261031-21-b3-rerun-eth`，在 `result.md` 中记录完整哈希。
- **本卡 `src/`**：Linux 端从 b3 `6890ac7e` 构建，GCC 15.2.0，0 warning。

| 文件 | 工程 | 说明 |
|---|---|---|
| `s3.elf` | B3R | LVGL S3（DDR 应用区），含 benchmark、RN-17 和 ETH 监控 |
| `nes.elf` | B3R | NES 显示版，不含 ROM；ROM 槽 `nes_rom_slot` 0x905f61c0 |
| `rnd_board.elf`、`rnd_expected.log` | B3R | RND 自检和参考模型期望 CRC |
| `board_npu.elf` | B3N | NPU 39 项板级测试，含 ETH 监控 |
| `demo_vnpu.bin` | B3VN | 图像 + NPU 演示（SRAM），通过 BIOS 烧录 |

- **NPU 模型**：沿用 `tasks/win/20261029-09-b3-software/src/npu/`。
- **NES ROM**：与卡 16/18 相同。
  - 演示 ROM：`sw/apps/nes/roms/nrom-template.nes`。
  - 用户本地的两个 SMB ROM：卡 18 的“超级马里奥1超级版”（带 trainer）和“超级马里奥1”。
  - 取法同卡 18。ROM 不复制进本分支，不提交，`result.md` 不写路径。

## 3. 环境

- PDS 与前几张卡相同；器件 PG2L200H-6 FBB676。
- JTAG、USB 串口、HDMI 显示器；B3VN 另需 OV5640 摄像头。
- ETH：PC 有线网卡接板网口，设为 `192.168.1.2/24`，允许 UDP 6000；板端固定 `192.168.1.10:5000`。
- 调试工具：`tools/debug_tool`。

### 工程

每个工程都**复制旧工程目录**得到新工程，旧目录保留不动。新目录与旧目录放在同一父目录下，导入脚本的相对路径才能保持有效。

| 新工程 | 复制自 | 顶层 | 导入脚本 | 源文件数 | 时钟数 |
|---|---|---|---|---|---|
| `G:\codex_project\EdRV32-FPGA\EdRV32-B3R-r3` | `EdRV32-B3R-r2`（卡 14） | `edrv32_fpga_board_render_top` | `import_board_render_top.tcl` | 98 | 14 |
| `G:\codex_project\EdRV32-FPGA\EdRV32-B3N-r2` | `EdRV32-B3N`（卡 15） | `edrv32_fpga_board_npu_top` | `import_board_npu_top.tcl` | 106 | 13 |
| `G:\codex_project\EdRV32-FPGA\EdRV32-B3VN-r2` | `EdRV32-B3VN`（卡 09） | `edrv32_fpga_board_vnpu_top` | `import_board_vnpu_top.tcl` | 145 | 17 |

## 4. 需要的 IP

逐个按 `fpga/ip/<IP>.md` 的选项生成，模块名和端口名必须与说明一致。

**注意**：PDS 分布式 RAM 最宽 256 位。`ip_lutram_mem_xbar_w` 按 16 × 144 生成，`ip_lutram_npu_result` 按 32 × 256 生成；包装模块各例化两份拼成 288 位、512 位（b3 当前提交起）。按 288、512 宽已经生成失败或生成过的，按新宽度重新生成。

| 动作 | IP | B3R | B3N | B3VN |
|---|---|---|---|---|
| 重新生成（模块名不变） | `ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`、`ip_ram_dcache_data` | ✓ | ✓ | ✓ |
| 新生成 | `ip_lutram_mem_xbar_w` | ✓ | ✓ | ✓ |
| 从工程中删除 | `ip_ram_mem_xbar_w` | ✓ | ✓ | ✓ |
| 新生成 | `ip_lutram_npu_quant`、`ip_lutram_npu_residual`、`ip_lutram_npu_result` | — | ✓ | ✓ |
| 从工程中删除 | `ip_ram_npu_quant`、`ip_ram_npu_residual`、`ip_ram_npu_result` | — | ✓ | ✓ |
| 重新生成（改为 2048 深） | `ip_ram_npu_lut` | — | ✓ | ✓ |
| 新加入（与 B3VN 工程设置相同） | `ip_pll_eth`、`ip_ram_eth_buf`、`ip_ram_eth_fifo` | ✓ | ✓ | 已有 |

## 5. 操作步骤

每个工程依次执行步骤 1–5，顺序为 B3R → B3N → B3VN。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261031-21-b3-rerun-eth origin/zc100116/b3`。阅读本卡和 `docs/reports/2026-10-31-board-eth-sw.md` 的“卡 21 实板 ETH 检查步骤”。把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 复制旧工程目录为新工程（第 3 节），打开新工程，按第 4 节生成、删除 IP。 |
| 2 | Windows Codex（C） + 用户（U） | **源文件核对**：<br>1. Codex 列出新工程 Designs 中的源文件，与导入脚本展开的文件列表比较（展开方法同脚本本身：按 `rtl/filelists/` 递归、去重，再加板级文件），给出“需要添加”“需要移除”两张清单；<br>2. 用户照清单在 GUI 中增删，或在 PDS Tcl 控制台中、当前目录为工程目录时执行 `source ../../EdRV32-Competition-2026/fpga/scripts/<导入脚本>`；<br>3. 最终源文件数必须等于第 3 节的值，FDC 为对应顶层的 `.fdc`，宏为 `FPGA_MODE`，Designs 中没有游离的顶层模块。数目不符时停下，把两张清单原文交给协调者。 |
| 3 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`，记录各阶段耗时和峰值内存。报错就停下，回传原文。 |
| 4 | Windows Codex（C） | 按第 6 节收集时序和资源报告。 |
| 5 | 用户（U） + Codex（C） | **上板**，见下面的 5R / 5N / 5VN。<br>某项失败时，保留日志和照片，继续下一项；整个工程上板失败时，照常回传，然后开始下一个工程。 |

### 5R：B3R

1. **RND 自检**：
   1. 用户按住 KEY1 并复位进入 BIOS；
   2. Codex 执行 `py tools/board/uart_tool.py tasks/win/20261031-21-b3-rerun-eth/src/rnd_board.elf --elf --port COMx --log build/board/c21-rnd.log`；
   3. Codex 执行 `py sw/tests/rnd_board/expect.py build/board/c21-rnd.log`，应为 PASS；
   4. 用户对照 `sw/tests/rnd_board/README.md` 的检查清单看 HDMI 画面。
2. **S3 benchmark**：
   1. 加载 `src/s3.elf`，GUI 或命令行均可（115200），方法同卡 17；
   2. 在主界面选择 benchmark，等它自然跑完，串口打印出 `Benchmark Summary` 和 `LVGL split scene="ALL"` 后再停；中途不按 KEY4；
   3. 回到主界面，运行一次 RN-17 自比对，记下 PASS/FAIL 那一行。
3. **ETH**：
   1. S3 运行期间，按 ETH 检查步骤 1–4 选择 B3R，建立网口连接；
   2. 确认 DDR 页收到 EDTM，七个端口的计数和曲线持续更新；
   3. 导出 EDTM CSV（约 30 秒）。
4. **NES**：同卡 16 步骤 3–4 和卡 18，只用命令行，因为 GUI 不支持 `--rom`：
   `py tools/board/uart_tool.py tasks/win/20261031-21-b3-rerun-eth/src/nes.elf --elf --rom <ROM> --baud 115200 --port COMx --log build/board/c21-nes-<名>.log`。
   1. 演示 ROM 运行约 30 秒，至少要有 3 行 `NES fps=`；
   2. 两个 SMB ROM 各试玩约 1 分钟，记录画面、按键和速度的主观感受。

### 5N：B3N

1. 用户按住 KEY1 并复位进入 BIOS。
2. Codex 执行 `py tools/board/uart_tool.py tasks/win/20261031-21-b3-rerun-eth/src/board_npu.elf --elf --baud 2000000 --port COMx --log build/board/c21-npu.log`。
   - 用命令行，不用 GUI；
   - 2 Mbaud 失败时改用 `--baud 115200`，并记下 2 Mbaud 时的现象。
3. 等程序打印 `NPU board: PASS n/n` 或 `FAIL k/n`。
4. 测试结束后，按 ETH 检查步骤 1–4 选择 B3N，建立网口连接，确认监控仍在更新，导出约 30 秒 EDTM CSV。
5. 用户报告 LED4/LED5 的状态。

### 5VN：B3VN

1. 在调试工具的“烧录 SRAM”页烧录 `src/demo_vnpu.bin`（方法见 `sw/apps/demo/README.md`）。启动日志应出现 `demo_vnpu (B3VN vision + NPU)`，有 NPU ID，没有 RND ID。
2. 按 `sw/apps/demo/README.md` 的“上板检查清单”**逐行全部执行**，模型用第 2 节的 `src/npu/`。
3. S1 运行时执行 `status` 至少 3 次，记录 `Overlay CPU cycles`、NPU 推理次数和检测数。
4. 按 ETH 检查步骤 5–8 执行：S2 三种输出档（HDMI、ETH、同时），S1 的 EDDT 框，WIN0/1 图像检查，恢复摄像头，导出 EDTM CSV。

## 6. 产物

放在 `tasks/win/20261031-21-b3-rerun-eth/artifacts/<b3r|b3n|b3vn>/`，每个工程一套：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `sources.txt` | 步骤 2 的最终源文件数，以及核对时的“添加/移除”清单 |
| 2 | `flow_summary.txt` | 各阶段耗时、峰值内存，工具报的警告数和错误数 |
| 3 | `timing_summary.txt` | 每个时钟域的 WNS/TNS/WHS/THS，原文表格 |
| 4 | `timing_setup_top200.txt` | 每个时钟域最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 5 | `timing_setup_top20_detail.txt`、`timing_hold_top20.txt` | 最差 20 条 setup 路径的逐级明细；最差 20 条 hold 路径 |
| 6 | `resource_summary.txt` | LUT、FF、DRM、APM、分布式 RAM、IO、PLL |
| 7 | `resource_hier.txt` | 按层次的资源分布；至少包括 cpu、icache、dcache、u_mem、u_xbar，以及工程中有的 u_npu、u_rnd、u_eth |
| 8 | `uart/*.log` | 各上板程序的完整串口文本（NES 日志要有 `NES ROM` 行和全部 `NES fps=` 行） |
| 9 | `edtm.csv` | 调试工具导出的 EDTM，约 30 秒 |
| 10 | `lvgl_split.tsv`（仅 B3R） | 一个场景一行，每个 `key=value` 一列，列名就用 key，数值照抄原文 |
| 11 | `photos/*.png` | 必要的 HDMI 照片：RND 自检、NES、B3VN 的 S1 框 |

不提交：ROM 文件、bitstream、PDS 工程文件、IP 生成目录、完整原始日志。

## 7. 通过判据

- 三个工程的源文件数分别为 98、106、145，全部完成综合、布局布线和 bitstream。
- 每个工程的全部时钟域 WNS ≥ 0、WHS ≥ 0。不满足时照常上板，如实回传。
- 上板：

| 工程 | 判据 |
|---|---|
| B3R | RND 自检 PASS；benchmark 跑完；RN-17 PASS；NES 演示 ROM 正常运行 |
| B3N | `NPU board: PASS 39/39` |
| B3VN | 上板检查清单逐行通过 |

- 三个工程的 ETH 都能建立连接，DDR 页持续更新。
- 数字都来自 PDS 报告和串口日志原文，找不到的写“未取得”，不推算。

## 8. result.md 模板

```markdown
# 20261031-21-b3-rerun-eth 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 工程路径 | B3R / B3N / B3VN |
| 源文件数 | B3R / B3N / B3VN |
| 完成情况 | |

## 时序（每工程一张）
| 工程 | 时钟 | WNS | TNS | WHS | THS |
|---|---|---|---|---|---|

clk_sys 最差 5 条 setup 路径（起点 → 终点，裕量，级数）：

## 资源
| 工程 | LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|---|

| 工程 | 层次 | LUT | FF | DRM | APM |
|---|---|---|---|---|---|

## 实现耗时
| 工程 | synth | map | pnr | timing | bitgen | 峰值内存 |
|---|---|---|---|---|---|---|

## B3R
- RND 自检：expect.py 结果；画面
- Benchmark Summary 原文
- split 摘要（完整见 lvgl_split.tsv）

| 场景 | render_ms | rnd_ms | sw_ms | clean_ms | wait_ms | finish_ms | cache_ops | ipc | icache_mpki | dcache_mpki |
|---|---|---|---|---|---|---|---|---|---|---|

- RN-17：
- NES

| ROM | NES ROM 行 | fps（各窗口） | shown | cpu% | ppu% | 画面/按键 |
|---|---|---|---|---|---|---|

- ETH：连接结果，EDTM 速率

## B3N
- 结果行；ms/frame、fps；LED
- ETH：

## B3VN
- 检查清单逐行结果
- Overlay CPU cycles / 推理次数 / 检测数
- ETH：步骤 5–8 逐项结果；PHY；视频丢帧

## 问题与偏离
```
