# 任务卡 20261102-42-b3f-latest：完整 B3F 用最新 RTL（含 RND 扇出优化），布局布线并上板

## 1. 目标

完整 B3F（CPU、DDR、VIN/PIX/GEO、RND v2、DISP、NPU、ETH、CPU 计数器 ILA）用最新 b3 重新跑综合、插入 ILA、Device Map、布局布线、bitstream、上板冒烟。与卡 33 相比，RTL 多了：
- T-FANOUT-RND2：RND 剩余高扇出网络同拍拆分，周期逐项不变（`docs/reports/2026-11-02-fanout-rnd2.md`）；
- T-XBAR-SCHED：mem_xbar 调度 → 读缓冲空闲计数路径缩短，周期逐项不变（`docs/reports/2026-11-02-xbar-sched.md`）；卡 33 综合估算中 clk_mem 最差的就是这条路径。

和卡 37（去掉 PIX/GEO）、卡 39（RND 换回 v1）一起，作为初赛整版的候选。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡）。拉出 `win/20261102-42-b3f-latest`，在 result.md 中记录完整哈希。
- **工程**：复制卡 33 的工程目录，名字 `EdRV32-B3F-L`（变体 B'）和 `EdRV32-B3F-LA`（变体 A'，见第 5 节第 1 步）。执行 `import_board_full_top.tcl`，源文件数与卡 33 相同（RND 扇出优化没有新增文件）。IP 不重新生成。
- **变体 B' 约束**：本卡 `src/edrv32_fpga_board_full_top_left.fdc`（与卡 33 变体 B 相同：RND/VIN/PIX/GEO/DISP/ETH 放左半区 `fp_left (0,121,0,219)`）。
- **ROM/SRAM 初始化和上板程序**：同卡 33（`tasks/win/20261101-24-b3-rnv/src/`）。

## 3. 环境

PDS 2022.2-SP6.1；PG2L200H-6 FBB676。与卡 33 B、37、38、39 共用这台电脑，实现期间不要在这台电脑上运行仿真虚拟机。

## 4. 需要的 IP

沿用卡 33，另加调试核 `ila_cpu`（`fpga/ip/ila_cpu.md`）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261102-42-b3f-latest origin/zc100116/b3`；整理用户清单。 |
| 1 | C | 查看本机空闲内存和正在跑的 PnR，决定开几个变体：**优先 B'**（卡 33 第 17 轮 B 比 A 未布通少 32%）；还有余量再开 A'（不加新区域约束）。卡 33 B 已用旧 RTL 跑了很久，**不停**，等本卡 B' 跑到与它相同的轮次后，把同轮次的未布通/过用对比发给用户，由用户决定停哪个。决定和依据写进 result.md。 |
| 2 | 用户（U） | 复制工程，执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`。B' 把约束换成本卡 `src/edrv32_fpga_board_full_top_left.fdc`，**换约束后必须重新综合**（卡 33 B 的教训）。 |
| 3 | U 或 C | `synthesize -ads`，确认 A 组探针（同卡 33 第 3 步）；按 `fpga/ip/ila_cpu.md` 插入 ILA（同卡 33 第 4 步）。 |
| 4 | U 或 C | Device Map（`Number of Nets To Report` = 1000）、`pnr`、`report_timing`、`gen_bit_stream`。PnR 设置同卡 33（拥塞选项、Placement Decongestion Mode 2、线程数）。 |
| 5 | C | 把每一行 `Unrouted general nets at iteration …` 原样记到 `artifacts/<B或A>/pnr_progress.txt`，每小时补一次。**及时止损**：第 40 轮未布通 > 18000 就停止该变体，回传进度和布局后的时序摘要。 |
| 6 | C | 布线完成后收集第 6 节产物；两个变体都完成时用时序更好的上板。 |
| 7 | U + C | 上板冒烟：同卡 33 第 7 步全部 6 项（BIOS、CoreMark + ILA、网口接收、视频 S1、NPU、RND/S3）。 |

## 6. 产物

同卡 33 第 6 节，放在 `tasks/win/20261102-42-b3f-latest/artifacts/<B或A>/`。另加 `high_fanout.txt` 中 `u_rnd` 扇出 ≥ 300 的网络清单（与卡 33 的 32 个对比）。

## 7. 通过判据

同卡 33 第 7 节。

## 8. result.md 模板

同卡 33 第 8 节，标题改为 `20261102-42-b3f-latest 结果`；"并行变体"一行写 B'/A' 的选择和依据；另加一节"与卡 33 同轮次对比"（第 17/33/40 轮未布通、过用）和"RND 高扇出网络（≥300）数量：卡 33 / 本卡"。
