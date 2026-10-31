# B3-9 Linux 验证结果

RTL 提交：`11ed34f`（已 rebase 到 B3 `fd6b265`，包含 TMDS `7947278`、
DISP clk_pix 流水化 `5e9e6ee`）。
rebase 后已重新执行实际顶层 lint（0 告警）和 check_import（67 源文件、12 时钟）。
Verilator 5.020，Linux；所有构建使用 `-j 1`，各仿真串行执行。
本目录测试和 `../fpga_imgtest_cam/` 的测试随本报告所在的 `verif:` 提交交付。

## 命令、结果与日志

在仓库根目录执行：

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py fpga/rtl/edrv32_fpga_board_imgtest_top.v \
    fpga/rtl/edrv32_fpga_imgtest_*.v rtl/include/regs/*.vh
python3 verif/unit/fpga_imgtest_ctrl/run.py --lint-only
python3 tools/regress.py smoke --path verif/unit/fpga_imgtest_ctrl -j 1
python3 tools/regress.py smoke --path verif/unit/fpga_imgtest_cam -j 1
tclsh verif/unit/fpga_imgtest_ctrl/check_import.tcl
python3 tools/gen/regs.py
git diff --exit-code -- sw/bsp/include/regs/
```

| 检查 | 结果 | 数据位置 |
|---|---|---|
| RTL 风格 | 15 个文件、0 告警（6 个新 RTL、9 个生成头） | 上述风格命令 stdout |
| 实际板级顶层 lint | 0 告警，无命令行警告屏蔽 | `build/fpga_imgtest/top_lint.log`（空文件） |
| 配置器 smoke | PASS，17.82 s（回归入口显示 18 s） | `build/regress/smoke/unit/fpga_imgtest_ctrl/verilator/run.log` |
| SCCB smoke | PASS，24.97 s（回归入口显示 25 s） | `build/regress/smoke/unit/fpga_imgtest_cam/verilator/run.log` |
| 导入源文件 | 67 个 RTL 与约束全部存在 | `check_import.tcl` stdout |
| 约束 Tcl | PASS，12 个时钟定义 | `check_import.tcl` stdout |
| C 头再生成 | `git diff --exit-code` 返回 0，C 头逐字不变 | 上述生成与 diff 命令 |

`run.py --lint-only` 的核心命令为：

```text
verilator --lint-only --timing -Wall +define+SIM_MODE \
  --top-module edrv32_fpga_board_imgtest_top <expanded top_files.f>
```

`top_files.f` 经 `tools.regress.expand_files` 展开，包含真实 mem_subsys、VIN、PIX、
GEO、DISP、reset_ctrl、新板级 RTL，以及已有 DDR/视频 PLL/器件原语的行为模型。
没有 CPU、sys_subsys、NPU、RND、ETH 文件列表，没有整帧 SoC 仿真。
局部 lint 注释仅用于未使用的生成常量、未连接输出，以及沿用 reset_ctrl X8 的
复位同步/异步使用；不隐藏功能或宽度警告。

## 覆盖与板级交付

配置器测试逐笔比对 256 项 Gamma 和后续 20 项启动写入；APB 带等待周期，
检查等待期间地址/控制/负载稳定。随后模拟 VIN FRAME、DISP FRAME/SWITCH，
核对 pending 提交不得覆写、CUR_BASE 确认、REL_BASE 槽号释放和持续帧指示。
测试覆盖所有 PIX 档位及循环、两路摄像头选择、等待 VIN IDLE 时继续服务 DISP、
四档 GEO 循环、三个变换的完整 16 字描述符与 AXI64 通道/WSTRB、GEO DONE 前
不得显示输出、运行中丢弃的 VIN 完成不得替换活动源，以及四引擎 ERROR 仅点灯。
去抖以真实 125 MHz/10 ms 计数检查毛刺、长按只触发一次、释放后重新触发。

SCCB 测试使用真实上电计数和 100 kHz 分频，从两路 SCL/SDA 解码每笔事务，
对照运行时从 `sw/drivers/ov5640.c` 提取的 244 项表。两路各 244 笔全部一致，
同时检查 6.3 ms reset、21 ms settle 和第九位释放。期望表临时文件写到 build/，
不会把 legacy 加入综合/仿真源列表。

例化与接死、完整时钟/IP 清单、端口、配置寄存器写入表、KEY/LED、摄像头表来源
及与 B2 格式/帧率的一致性，见 [`fpga/rtl/README.md` 的 B3-9 节](../../../fpga/rtl/README.md)。
其中 KEY2 四档以及 `tools/gen/regs.py`/`rtl/include/regs/*.vh` 的归属扩展
均已通过本 Dispatch 的 coordinator ask/reply 确认。

物理 IO 的 120 个顶层端口位与新 FDC 的 PAP_IO_LOC 集合逐位相等（本次 Linux
只读检查）；引脚/DDR PHY 约束从 board_vision 裁剪，未改变保留项。
PDS 综合、布局布线、时序测量和实物摄像头/HDMI 验证尚待 Windows 执行，
Linux 不声称已证明板级时序或画面正确。

## 修改文件

- `fpga/rtl/edrv32_fpga_board_imgtest_top.v`
- `fpga/rtl/edrv32_fpga_imgtest_{ctrl,keys,cam_init,cam_rom,sccb}.v`
- `fpga/rtl/README.md`
- `fpga/constraints/edrv32_fpga_board_imgtest_top.fdc`
- `fpga/scripts/import_board_imgtest_top.tcl`
- `tools/gen/regs.py`
- `rtl/include/regs/edrv32_{vin,pix,geo,disp,rnd,npu,eth,mem_xbar}_regs.vh`
- `verif/unit/fpga_imgtest_ctrl/{README.md,files.f,top_files.f,test.yaml,run.py,check_import.tcl,edrv32_fpga_imgtest_ctrl_tb.sv}`
- `verif/unit/fpga_imgtest_cam/{files.f,test.yaml,edrv32_fpga_imgtest_cam_tb.sv}`

未改既有板级顶层、既有约束/脚本、IP、软件、legacy、规格、JSON 和 RTL 文件列表。
