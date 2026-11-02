# 任务卡 20261102-37-b3f-vrn：去掉 PIX/GEO 的整版（B3F-VRN），布局布线并上板

## 1. 目标

用新顶层 `edrv32_fpga_board_vrn_top`（B3F 去掉 PIX 和 GEO，保留 CPU、DDR、VIN、RND、DISP、NPU、ETH 和 CPU 计数器 ILA）跑一遍综合、插入 ILA、Device Map、布局布线、bitstream、上板冒烟。看去掉这两个模块后，整版能不能在可接受的时间内布通。

背景：卡 33 的变体 A（不加新区域约束）第 33 轮未布通 50396、过用 168083，走势与卡 31 基本重合；变体 B（左半区约束）第 17 轮未布通 84538，单轮约 9 分钟。两者都可能过不了第 40 轮 18000 的止损线。

顶层的改动（`fpga/rtl/README.md` "B3F-VRN" 一节）：
- 删去 `u_pix`、`u_geo`；
- VIN 送往 PIX 的像素流直接连回 VIN，等同于 PIX 关闭（pix-spec 2.6）；
- GEO 的 DDR 端口 P5 接死，APB 槽 2/3 返回 SLVERR，PLIC 源 9/10 接 0。

其余例化、端口、时钟、ILA 探针路径都与 B3F 相同，约束文件直接用 B3F 的 `edrv32_fpga_board_full_top.fdc`。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。拉出 `win/20261102-37-b3f-vrn`，在 result.md 中记录完整哈希。
- **工程**：把卡 33 变体 A 的 B3F 工程目录复制一份，命名为 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-VRN`（IP 都在里面，不重新生成；PIX/GEO 用的 `ip_ram_geo_src` 留在工程里不用即可）。在新工程中执行 `import_board_vrn_top.tcl`。脚本输出的源文件数应比卡 33 少 17。
- **ROM/SRAM 初始化和上板程序**：同卡 33，用 `tasks/win/20261101-24-b3-rnv/src/`。

## 3. 环境

- PDS 2022.2-SP6.1；PG2L200H-6 FBB676。
- **与卡 33 变体 B 同时跑**（用户确认本机 CPU 只用了 40%，内存充足）。卡 33 变体 A 到第 40 轮按卡 33 的止损规则处理。
- 实现期间不要在这台电脑上运行仿真虚拟机。

## 4. 需要的 IP

沿用卡 33，另加调试核 `ila_cpu`（Inserter 插入，见 `fpga/ip/ila_cpu.md`）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261102-37-b3f-vrn origin/zc100116/b3`；整理用户清单。 |
| 1 | 用户（U） | 复制卡 33 变体 A 的工程目录为 `EdRV32-B3F-VRN`，打开工程。在 Tcl 控制台中执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_vrn_top.tcl`，确认最后一行是 `top edrv32_fpga_board_vrn_top`，记下源文件数。 |
| 2 | U 或 C | `synthesize -ads`。确认 A 组探针都在（同卡 33 第 3 步），记下实例名。找不到就停下，回传原文。 |
| 3 | U（C 协助） | 按 `fpga/ip/ila_cpu.md` 插入 ILA，设置与卡 33 相同（clk_sys，A 组 400 位，触发探针 `minstret`、`mcycle`，深度 1024，触发位置 10%）。顶层名变了，卡 33 的 .fic 不能直接套用时就重新插入。保存 .fic 并截图。 |
| 4 | U 或 C | Device Map 设置中把 `Number of Nets To Report` 设为 1000。PnR 设置与卡 33 变体 A 完全相同（拥塞相关选项、Placement Decongestion Mode 2、线程数），写进 result.md。依次执行 `dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。 |
| 5 | C | PnR 期间把 PnR 日志中每一行 `Unrouted general nets at iteration …` 原样记到 `artifacts/pnr_progress.txt`，每小时补一次。**及时止损**：到第 40 轮时未布通 > 18000，就停止，回传进度和布局后的时序摘要。 |
| 6 | C | 布线完成后收集第 6 节的产物。 |
| 7 | U + C | 上板冒烟，见下表。 |

### 第 7 步上板冒烟

同卡 33 第 7 步，但**不做视频 S1**（`demo_vision.bin` 依赖 PIX/GEO）。

| # | 项 | 方法 | 记录 |
|---|---|---|---|
| 1 | BIOS | 同卡 33 第 7 步第 1 项（串口烧录一次；网口用 CLI 一次、调试工具一次） | 菜单、两种烧录的结果和耗时、等待网卡行 |
| 2 | CoreMark + ILA | 同卡 33 第 7 步第 2 项（触发 `minstret == 0x0055E44C09`，两轮冻结值与串口逐项对比；再抓一次运行中 1024 周期窗口） | 串口全文；ILA 截图和 CSV |
| 3 | 网口接收 | 同卡 24 第 5.0 节第 4 步（`eth_diag.bin`，5 次） | 成功次数 |
| 4 | NPU | 同卡 24 第 5N 节（`board_npu.elf`，39 项） | 通过数 |
| 5 | RND | 同卡 24 第 5R 节（`rnd_board.elf` 自检，然后 `s3.elf`）。S3 启动后直接在调试工具中连接遥测 | 自检 CRC 结果、S3 各场景 fps、遥测 60 s 记录数和 lost |

任何一项失败都继续做后面的项，把失败现象和串口原文记下来。

## 6. 产物

放在 `tasks/win/20261102-37-b3f-vrn/artifacts/`：

| 产物 | 内容 |
|---|---|
| `flow_summary.txt`、`pnr_progress.txt` | 各阶段耗时、CPU 时间、峰值内存；每轮未布通/过用原文 |
| `timing_summary.txt` | 每个时钟域的 WNS/TNS/WHS/THS（slow/fast） |
| `paths_<clock>.txt`、`paths_top20_detail.txt`、`levels_count.txt` | 同卡 33 |
| `resource_summary.txt`、`resource_hier.txt`、`high_fanout.txt` | Device Map 资源、按层次资源、高扇出四张表（1000 条） |
| `placement_by_module.txt`、`congestion.txt` | 同卡 33 |
| `ila/` | .fic、插入截图、上板截图和 CSV |
| `uart/*.log` | 上板各程序的串口全文 |
| `native_reports/` | CMR、SNR、DMR、PRR、RTR 原文 |

不提交：工程文件、IP 目录、数据库、网表、bitstream。

## 7. 通过判据

- 布线完成，0 未布通网络；clk_sys、clk_mem、clk_npu、clk_pix、clk_eth 的 setup/hold 不违例（RGMII RX 慢角 hold 按卡 30 的已知例外处理，单独列出）。
- ILA 抓到的 A 组计数与串口一致。
- 第 7 步 5 项全部给出结果。
- 所有数字取自报告原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261102-37-b3f-vrn 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 源文件数 | |
| PnR 设置、线程数 | |
| 各阶段耗时、布线轮数 | |
| 第 17/33/40 轮未布通与过用 | （与卡 33 A/B 同轮次对比） |

## 时序
| 时钟 | WNS | TNS | WHS | THS | 最差路径级数 | 级数 ≥ 8 的条数 |
|---|---|---|---|---|---|---|

## 资源（含 ILA）
| 项 | LUT | FF | DRM | APM | 分布式 RAM |
|---|---|---|---|---|---|

## 各模块放置范围

## 拥塞

## ILA
探针实际实例名；两轮计数与串口对比；窗口截图位置。

## 上板冒烟
| # | 项 | 结果 |
|---|---|---|

## 问题与偏离
```
