# NPU 单独上板工程（B3N）：顶层和测试方法

| 项 | 内容 |
|---|---|
| 日期 | 2026-10-30 |
| 状态 | 已决定（用户 2026-10-30：单独验证 NPU 时顺便上板测试功能） |
| 关联 | `docs/design/2026-10-30-npu-apm-cascade.md`；`docs/spec/npu-spec.md` v0.5；`fpga/rtl/edrv32_fpga_board_vnpu_top.v`（B3VN）；`tools/npu/`（编译器、参考模型、小用例生成）；`tools/board/uart_tool.py`（BIOS 加载）；`docs/guides/pds-floorplan.md` 1.6 |

## 1. 背景和问题

NPU 改成 APM 级联累加后，需要先回答两个问题，再放回整片：
1. 级联链在 PDS 中能否合法、顺利地放置和布线，NPU 区域约束是否有效；
2. NPU 在板上的功能是否正确：逐层结果、整网结果与 Python 参考模型逐字节一致，以及实际帧率。

B3VN 把视频通路也包含在内，规模大，失败时难以区分原因。所以单独做一个只有 CPU、DDR 和 NPU 的工程。

## 2. 约束

- 不新建子系统，不改 SoC RTL；顶层只例化已有子系统，缺省的部分按 B3-10 的方式接死。
- 数据加载只用 UART 和 BIOS，已有 2 Mbaud 的 ELF 分段加载（`uart_tool.py`），不加网口。
- 期望结果全部由 Linux 端的 Python 参考模型生成，板上只做比较。
- 仿真只做连线冒烟（CLAUDE.md 和用户 2026-10-29：能在板上观察的功能不做整网仿真）。

## 3. 顶层 `edrv32_fpga_board_npu_top`（口径 B3N）

由 `edrv32_fpga_board_vnpu_top.v` 裁剪得到：

| 保留 | 去掉（按 B3-10 的方式接死） |
|---|---|
| `ip_pll_sys`、`ip_pll_npu`、`ip_ddr3` + `edrv32_fpga_ddr_adapter` | `ip_pll_video`、`edrv32_fpga_tmds`、`edrv32_fpga_rgmii` |
| `edrv32_cpu_subsys`、`edrv32_sys_subsys`（BIOS ROM、SRAM、UART0、GPIO 按键/LED、PLIC、CLINT、SYSCTRL） | `edrv32_vin`、`edrv32_pix`、`edrv32_geo`、`edrv32_disp`、`edrv32_eth`（RND 本来就没有） |
| `edrv32_mem_subsys`（xbar、DDR 网关、PERF_MON） | 去掉模块对应的 xbar 端口不发请求；媒体 APB 槽返回 PREADY=1、PSLVERR=1；对应 PLIC 源接 0 |
| `edrv32_npu` | |

- **引脚**：27 MHz 板钟 D18、复位键、UART、LED、DDR3。约束 `edrv32_fpga_board_npu_top.fdc` 由 B2 的 fdc 删掉 HDMI、摄像头、网口部分得到，时钟和异步组不变。
- **导入脚本**：`import_board_npu_top.tcl`，按 `fpga/scripts/README.md` 的统一写法。
- **区域约束**：第二轮再加，放在单独的 fdc 片段 `edrv32_fpga_board_npu_region.fdc` 中，便于对比有区域和无区域两次布局布线。NPU 放在 X1，即 `pds-floorplan.md` 1.6 中 x ≥ 124 的 5 条 APM 列和 5 条 DRM 列。

## 4. 测试程序 `sw/tests/board_npu`

DDR 程序（`ddr.ld`），由 BIOS 的 "2=Load" 按 ELF 段加载，测试数据作为只读段链接进 ELF。

| 部分 | 内容 | 期望值来源 | 判定 |
|---|---|---|---|
| A 寄存器 | NPU ID、SOFT_RST 后复位值、DESC_COUNT=0 立即 DONE | npu-spec 4 | 逐项相等 |
| B 小用例 | `tools/npu/gen_case.py` 生成，至少覆盖 CONV 1×1/3×3、S1/S2、C4 首层、LUT 激活、融合残差、POOL、UPSAMPLE、多层链；与模块级 NB/OP 用例同一组参数和种子 | 参考模型 `tools/npu/ref` | 输出区逐字节相等；打印 PERF0、MAC 有效拍 |
| C 整网 | `compile_yolo.py` 对 COCO128 `000000000009.jpg` 生成的整网镜像：描述符、权重（3.2 MB）、C4 输入（0.98 MB）；期望为参考模型的 OUTPUT 区（0.73 MB） | 参考模型 | OUTPUT 逐字节相等；打印 PERF0、换算 ms/帧和帧率（clk_npu 150 MHz） |
| D 稳定性 | 整网连续执行 20 次，每次比较 OUTPUT 的 CRC32 与 C 的结果 | C 的结果 | 20 次全部一致 |

- **输出**：每项打印一行 `NPU <项> PASS/FAIL ...`；失败时打印描述符号、首个不一致的地址、期望值和实际值。最后打印 `NPU board: PASS n/n` 或 `FAIL`，LED 显示结果。
- **数据量**：ELF 约 5 MB，2 Mbaud 加载约 25 s。
- **生成方式**：用例和整网镜像的生成命令写进 `sw/tests/board_npu/README.md`，生成物放在 `build/`，不入库。ELF 由 `sw/Makefile` 构建。

## 5. 仿真（只做连线冒烟）

`verif/soc/board_npu`：仿照 `verif/soc/board_vnpu`，在顶层下运行一个 SRAM 程序，内容是 NPU ID 读取，加上一个 B 类最小 CONV 用例（DDR 后门预加载），检查 DONE 中断和输出逐字节相等。不跑整网。

## 6. Windows 流程（后续任务卡）

1. 用户建 B3N 工程，用 T-NPU2 合入后的 RTL **单独**跑综合和布局布线，不和其他工程并行，回传时序、资源和布线进度；
2. 上板：BIOS 加载 `board_npu` 的 ELF，回传串口日志；
3. 第二轮：加上区域约束片段再跑一次，对比布线耗时、迭代次数和 WNS。

## 7. 影响

- **新增**：`fpga/rtl/edrv32_fpga_board_npu_top.v`、`fpga/constraints/edrv32_fpga_board_npu_top.fdc`、`fpga/scripts/import_board_npu_top.tcl`、`verif/soc/board_npu/`、`sw/tests/board_npu/`。
- **规格**：不改。SoC 规格 9 节的上板口径列表在定稿时补 B3N。
- **实施方案**：`board-plan.md` 增加 T-BN1（顶层和冒烟仿真）、T-BN2（测试程序和数据生成）、后续 Windows 卡。

## 8. 状态

已决定。
