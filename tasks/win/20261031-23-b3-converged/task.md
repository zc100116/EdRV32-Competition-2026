# 任务卡 20261031-23-b3-converged：B3R、B3N、B3V 用收敛后的 RTL 重新实现并上板

## 1. 目标

用收敛后的 RTL 一次性重做三个工程，确认四件事：

1. **资源和时序**：Linux 端 Yosys 参考估计 LUT 明显下降，以本卡 PDS 报告为准，与卡 22 对比：
   - D$ 元数据移入 tag RAM；
   - 删除 PERF_MON；
   - RND 单 lane、窄几何；
   - NPU、xbar、各引擎去广播；
   - 统计计数器打拍、媒体 APB 本地寄存；
   - 复位按区域复制。
2. **复位副本是否生效**：综合后高扇出表中各复位副本单独出现、没有被合并，每个副本负载约 ≤ 1000；时序报告中的 recovery/removal 检查通过。
3. **功能**：
   - 本轮的 RTL 改动没有做仿真回归（用户决定上板验证），所以三个工程都按卡 22 的上板项目完整重测一遍；
   - 新增 S3 “LAYERS” 图层画面（DS-20、RN-30）。
4. **B3V 网口**：卡 22 中 B3V 网口不通，本卡执行网口诊断（5E）。

三个工程可以并行实现，上板逐个进行。B3VN 不在本卡，布局规划之后另出卡。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。从这里拉出 `win/20261031-23-b3-converged`，在 `result.md` 中记录完整哈希。
- **本卡 `src/`**：Linux 端从 b3 `506f07e4` 构建（之后的提交只改 RTL，不影响程序），GCC 15.2.0。程序本身 0 warning；monitor 构建时 third_party/coremark 有一条既有的 `-Wmaybe-uninitialized` 警告。

| 文件 | 用途 |
|---|---|
| `ip_rom_boot.dat` | BIOS，三个工程的 `ip_rom_boot` 都用它重新生成 |
| `ip_ram_sram.dat` | SRAM 初始内容（monitor），三个工程的 `ip_ram_sram` 都用它重新生成 |
| `rnd_board.elf`、`rnd_expected.log` | RND 自检 29 组和期望 CRC |
| `s3.elf` | LVGL S3：benchmark、RN-17、网口监控、虚拟输入，新增第 5 项 LAYERS |
| `nes.elf` | NES（含虚拟输入） |
| `board_npu.elf` | NPU 39 项板级测试 |
| `demo_npu.bin` | B3N 网口送图识别（入口 0x10000000） |
| `demo_vision.bin` | B3V 图像处理演示（入口 0x10000000） |
| `eth_diag.bin` | 网口诊断（入口 0x10000000） |

- **NPU 模型**：`tasks/win/20261029-09-b3-software/src/npu/`。
- **NES ROM**：同卡 18、21，ROM 不进仓库。

## 3. 环境

- PDS 2022.2-SP6.1；器件 PG2L200H-6 FBB676。
- JTAG、USB 串口、HDMI 显示器；B3V 另需 OV5640 摄像头。
- **网口准备**（同卡 22）：
  - PC 有线网卡设为 `192.168.1.2/24`，放行 UDP 6000；板端为 `192.168.1.10:5000`；
  - 关闭 Mihomo 等接管路由的代理或虚拟网卡；
  - 调试工具和 `uart_tool.py` 的本机地址都显式设为 192.168.1.2。

| 工程 | 目录 | 顶层 | 导入脚本 | 源文件数 | 时钟数 |
|---|---|---|---|---|---|
| B3R | `G:\codex_project\EdRV32-FPGA\EdRV32-B3R` | `edrv32_fpga_board_render_top` | `import_board_render_top.tcl` | 102 | 14 |
| B3N | `G:\codex_project\EdRV32-FPGA\EdRV32-B3N` | `edrv32_fpga_board_npu_top` | `import_board_npu_top.tcl` | 105 | 13 |
| B3V | `G:\codex_project\EdRV32-FPGA\EdRV32-B3V` | `edrv32_fpga_board_vision_top` | `import_board_vision_top.tcl` | 111 | 16 |

源文件数比卡 22 少：删除了 PERF_MON 和 P6 仲裁两个文件，新增复位副本原语一个文件。

## 4. 需要的 IP

逐个按 `fpga/ip/<IP>.md` 生成，模块名和端口名必须与说明一致。

| 动作 | IP | B3R | B3N | B3V |
|---|---|---|---|---|
| 用本卡 `ip_rom_boot.dat` 重新生成 | `ip_rom_boot` | ✓ | ✓ | ✓ |
| 用本卡 `ip_ram_sram.dat` 重新生成 | `ip_ram_sram` | ✓ | ✓ | ✓ |
| **重新生成，宽度 18 → 20 位**（D$ 有效位、脏位移入 tag RAM） | `ip_ram_dcache_tag` | ✓ | ✓ | ✓ |

其余 IP 沿用卡 22 的工程。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261031-23-b3-converged origin/zc100116/b3`。阅读本卡，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 打开工程，按第 4 节重新生成 IP。 |
| 2 | C + U | **源文件核对**，方法同卡 22：<br>1. Codex 给出“需要添加 / 需要移除”两张清单；用户照清单修改，或在工程目录下执行导入脚本；<br>2. 应移除 `edrv32_mem_perf_mon.v`、`edrv32_mem_p6_arb.v`，添加 `rtl/common/edrv32_reset_copy.v`；<br>3. 最终源文件数必须等于第 3 节，FDC 为对应顶层的 `.fdc`，宏为 `FPGA_MODE`。<br>数目不符就停下，回传两张清单原文。 |
| 3 | U，或 C 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。任何阶段报错就停下，回传报错原文。 |
| 4 | C | 按第 6 节收集报告，重点如下：<br>1. Device Map 资源与卡 22 对比；<br>2. 高扇出表里的复位网络：各 `u_reset_*` 副本（例如 `u_cpu/u_reset_sys_core_n`，共 41 个加 reset_ctrl 内 1 个）是否单独出现，以及各自的负载数；<br>3. 时序报告中有没有 recovery/removal 检查及其最差裕量（没有这类检查就写“未报告”）；<br>4. 布局布线耗时与卡 22 对比。 |
| 5 | U + C | 上板，见 5.0 和 5R / 5N / 5V / 5E。某项失败时保留日志和照片，继续下一项。 |

### 5.0 BIOS（每个工程都做）

同卡 22 第 5.0 节：KEY1 复位进入 BIOS，菜单行为 `BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud`。同一个程序先用串口烧一次，再用网口烧一次，记录两种方式的耗时和结果。`.bin` 程序用 `--addr 0x10000000 --entry 0x10000000`。

### 5R：B3R

1. **RND 自检**：烧录 `src/rnd_board.elf`，执行 `py sw/tests/rnd_board/expect.py build/board/c23-rnd.log`，应为 PASS。
2. **S3**：同卡 22 5R 第 2 步，benchmark 自然结束后取 `Benchmark Summary` 和 17 行 `LVGL split`；再跑 RN-17，“opa 容器”一帧预计 FAIL（约 2.3%，已知），其余应 PASS。
3. **LAYERS（新增）**：在 S3 主界面用 KEY2 或 UART `d` 选到 “05   LAYERS”，KEY3 或 `w` 进入；KEY1/KEY2 或 `a`/`d` 切换 5 个画面，KEY4 或 `p` 返回。每个画面：
   - 保存串口打印的预期文字；
   - 用户对照画面判断是否一致，并拍照（画面 2、3、4 是动画，可以拍短视频或多张照片）。
   - 画面 5 的串口行 `LAYERS 5 LAYER claimed=… unclaimed=…` 原文照记；预期 claimed 非零、unclaimed 为 0。
4. **NES**：同卡 21 的 5R 第 4 步，演示 ROM 和两个 SMB ROM。
5. **网口与 EDTM**：S3 benchmark 期间导出 `edtm_s3.csv`，NES 运行约 30 秒导出 `edtm_nes.csv`。
6. **虚拟输入**：同卡 22 5R 第 5 步。

### 5N：B3N

同卡 22 第 5N 节：
- `board_npu.elf` 应为 `NPU board: PASS 39/39`；
- `demo_npu.bin` 单张识别 3 张、连续识别 ≥ 20 张，记录平均往返时间、fps、每张的 NPU 周期和后处理周期；
- 连续识别期间导出 `edtm_npu.csv`。

### 5V：B3V

同卡 22 第 5V 节：
- `demo_vision.bin` 按 `sw/apps/demo/README.md` 的检查清单逐行执行；
- S2 各模式各保持约 10 秒，逐项拍照；
- 导出 `edtm_vision.csv`，并记下各模式的起止时间。

### 5E：B3V 网口诊断

同卡 22 第 5E 节：
- 先 `git pull` 并重启调试工具；
- 串口烧录 `src/eth_diag.bin`，保存全部串口输出（MDIO 扫描、BMCR/BMSR/PHYSR、RGMII 延迟位）；
- PC 运行 `py tools/board/eth_probe.py --local-ip 192.168.1.2`，同时做 ping、`arp -a`；
- 串口按 `d` 依次试 4 种延迟组合，每种记录 link/speed、PERF0、PERF3、PERF5、PEER、PC 是否收到 `EDRV32 DIAG` 广播；
- 如有 Wireshark，抓有线网卡的包并截图。

## 6. 产物

放在 `tasks/win/20261031-23-b3-converged/artifacts/<b3r|b3n|b3v>/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `sources.txt` | 最终源文件数和核对清单 |
| 2 | `flow_summary.txt` | 各阶段耗时、峰值内存、警告数、错误数 |
| 3 | `timing_summary.txt` | 各时钟域 WNS/TNS/WHS/THS 原文；另起一段写 recovery/removal 的最差裕量 |
| 4 | `timing_setup_top200.txt`、`timing_setup_top20_detail.txt`、`timing_hold_top20.txt` | 同卡 21 |
| 5 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总和按层次资源，含 cpu/cache、u_mem/u_xbar、u_rnd、u_npu、u_eth 及各图像引擎 |
| 6 | `high_fanout.txt` | Device Map 的高扇出、时钟、复位、CE 表全文 |
| 7 | `uart/*.log` | 各程序完整串口文本，包括 BIOS 两种烧录方式 |
| 8 | `edtm_*.csv` | 第 5 节要求的 EDTM 导出 |
| 9 | `lvgl_split.tsv`（B3R） | 同卡 21 |
| 10 | `photos/*` | LAYERS 5 个画面、B3N 叠框截图、B3V 各模式、网口诊断截图 |

不提交：ROM 文件、bitstream、PDS 工程文件、IP 生成目录、完整原始日志。

## 7. 通过判据

- 三个工程的源文件数分别等于第 3 节的值，全部完成综合、布局布线和 bitstream。
- 每个工程全部时钟域 WNS ≥ 0、WHS ≥ 0。不满足时照常上板，如实回传。
- 高扇出表中的复位副本单独出现，没有被合并成一根网络。
- 上板：

| 工程 | 判据 |
|---|---|
| B3R | RND 29/29 PASS；benchmark 跑完；RN-17 除“opa 容器”外 PASS；LAYERS 5 个画面与串口预期一致，画面 5 claimed 非零、unclaimed 为 0；NES 演示 ROM 正常；虚拟输入可用 |
| B3N | 39/39 PASS；单张识别比对一致；连续识别取得 fps |
| B3V | 检查清单逐行通过；网口诊断 4 种组合都有记录 |

- BIOS：三个工程的串口和网口烧录都自动运行（B3V 网口不通时如实记录）。
- 所有数字取自报告和日志原文，找不到的写“未取得”。

## 8. result.md 模板

```markdown
# 20261031-23-b3-converged 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 源文件数 | B3R / B3N / B3V |
| 完成情况 | |

## 时序（每工程）
| 工程 | 时钟 | WNS | TNS | WHS | THS |
|---|---|---|---|---|---|

recovery/removal 最差裕量：

## 资源（与卡 22 对比）
| 工程 | LUT | FF | DRM | APM | 分布式 RAM | IO | PLL | 卡 22 LUT / FF |
|---|---|---|---|---|---|---|---|---|

| 工程 | 层次 | LUT | FF | DRM | APM |
|---|---|---|---|---|---|

## 复位副本
| 工程 | 复位网络 | 负载 |
|---|---|---|

## 实现耗时（与卡 22 对比）
| 工程 | synth | map | pnr | timing | bitgen | 峰值内存 |
|---|---|---|---|---|---|---|

## BIOS
| 工程 | 程序 | 串口烧录 耗时/结果 | 网口烧录 耗时/结果 | 备注 |
|---|---|---|---|---|

## B3R
- RND：expect.py 结果
- Benchmark Summary 原文；split 摘要
- RN-17 原文
- LAYERS：5 个画面逐项是否与预期一致；画面 5 的 claimed/unclaimed 原文
- NES 表（同卡 21）
- EDTM 文件
- 虚拟输入逐项结果

## B3N
- 39/39 结果；单张识别；连续识别（张数、往返时间、fps、NPU/后处理周期）；EDTM 文件

## B3V
- 检查清单逐行结果；各模式起止时间；EDTM 文件
- 网口诊断：每种延迟组合一行（组合、link/speed、PERF0、PERF3、PERF5、PEER、PC 是否收到广播）

## 问题与偏离
```
