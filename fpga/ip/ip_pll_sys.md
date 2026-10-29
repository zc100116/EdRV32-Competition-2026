# ip_pll_sys

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Clock → 28nm PLL（厂商例程 `2_Demo/2_5_pll_test` 使用的同一 IP，版本 1.4） |
| 模块名 | `ip_pll_sys` |
| 例化位置 | 板级顶层 `fpga/rtl/edrv32_fpga_board_b1_top.v` 及 B2 `edrv32_fpga_board_b2_top.v`（板级 IP，不经 `rtl/tech/` 包装；仿真用 `verif/models/ip_pll_sys.sv` 行为模型，模块名和端口相同） |
| 用途 | 上板阶段 B1/B2（`docs/plan/board-plan.md`）：由板载 27 MHz 时钟产生 clk_sys（CLKOUT0）和 clk_npu（CLKOUT1，B2 起） |
| 依据 | 板载晶振 27 MHz，引脚 D18（厂商 demo `.fdc`：`create_clock -period 37.000`，`PAP_IO_LOC D18`）；clk_sys 上板暂定 100 MHz（用户 2026-10-28） |
| 器件 | PG2L200H-6 FBB676 |

## 选项

| 选项 | 取值 |
|---|---|
| 输入时钟频率（CLKIN_FREQ） | 27.000 MHz |
| 输入时钟来源（CLKIN1_SOURCE） | No Buffer（与例程相同，时钟从 D18 引脚直接进 PLL） |
| 动态切换输入（DYNAMIC_CLKIN_EN） | 不勾选 |
| CLKOUT0 | 勾选，频率 **100.000 MHz**，占空比 50%，相位 0 |
| CLKOUT0 输出缓冲 | 选全局时钟缓冲（clk_sys 驱动约 8000 个寄存器）；如果选项中没有全局缓冲，保持 NO BUFFER，PDS 会自动插入 `GTP_CLKBUFG`，在 `clock_utilization.txt` 中确认 |
| CLKOUT1 | 勾选，频率 **150.000 MHz**，占空比 50%，相位 0（clk_npu，B2 起；B1 顶层不使用此输出）；输出缓冲同 CLKOUT0 |
| CLKOUT2–CLKOUT6 | 不勾选 |
| 内部复位（RST_INNER_EN） | 不勾选（不生成复位端口） |
| lock 输出 | 保留（例程默认有 `lock` 端口） |
| 锁定模式（LOCK_MODE） | 默认 0 |

IP Compiler 显示的实际输出频率必须是 CLKOUT0 100.000 MHz、CLKOUT1 150.000 MHz。

**必须手动指定分频，不能让工具按 CLKOUT0 自动计算。**
- 原因：这个 PLL 只有 CLKOUT0 和反馈分频 F 支持小数（1/8 步进），CLKOUT1–6 只能整数分频。
- 工具按 100 MHz 自动选出的 VCO 是 1012.5 MHz（B1：I=1、M=2、F=18.75、O0=10.125）。1012.5 / 150 不是整数，CLKOUT1 就设不出 150 MHz。

两路共用的 VCO 必须是 150 MHz 的整数倍，同时等于 27 × M × F（F 为 1/8 的倍数，PFD = 27 MHz）。满足条件的最小值是 1350 MHz：

| 参数 | 取值 |
|---|---|
| `STATIC_RATIOI` | 1（PFD 27 MHz） |
| `STATIC_RATIOM` | 2 |
| `STATIC_RATIOF` | 25（VCO = 27 × 2 × 25 = 1350 MHz） |
| `STATIC_RATIO0` | 13.5 → CLKOUT0 = 100.000 MHz |
| `STATIC_RATIO1` | 9 → CLKOUT1 = 150.000 MHz |

在 IP Compiler 的高级页（advanced page）填这些分频值。

**如果工具不接受 1350 MHz 的 VCO，或者不能手动填分频**，停下来，把工具给出的 VCO 范围和报错原文告诉协调者，不要自行改成别的频率。协调者届时会改回 clk_npu 单独一个 PLL（`ip_pll_npu`）。

板级顶层里的 `CLK_SYS_HZ` 必须等于 clk_sys 的实际频率（SYSCTRL `CLK_SYS_HZ`，CoreMark 计时依赖它）。

## 期望端口

| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| `clkin1` | in | 1 | 27 MHz 板钟 |
| `clkout0` | out | 1 | clk_sys 100 MHz |
| `clkout1` | out | 1 | clk_npu 150 MHz |
| `lock` | out | 1 | 高有效，锁定后为 1；板级顶层把它与按键复位一起作为系统复位输入 |

## 生成后需要回传的信息

在 Windows 任务卡的 `result.md` 记录模块名、实际端口列表、IP Compiler 显示的实际输出频率和分频参数（N/M/O），以及选项截图（放 `artifacts/`）。实际端口与期望端口不一致时，由协调者修改板级顶层，不修改生成文件。
