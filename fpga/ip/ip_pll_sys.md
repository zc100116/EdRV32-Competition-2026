# ip_pll_sys

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Clock → 28nm PLL（厂商例程 `2_Demo/2_5_pll_test` 使用的同一 IP，版本 1.4） |
| 模块名 | `ip_pll_sys` |
| 例化位置 | 板级顶层 `fpga/rtl/edrv32_fpga_board_b1_top.v`（板级 IP，不经 `rtl/tech/` 包装；仿真用 `verif/models/ip_pll_sys.sv` 行为模型，模块名和端口相同） |
| 用途 | 上板阶段 B1（`docs/plan/board-plan.md`）：由板载 27 MHz 时钟产生 clk_sys |
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
| CLKOUT1–CLKOUT6 | 不勾选 |
| 内部复位（RST_INNER_EN） | 不勾选（不生成复位端口） |
| lock 输出 | 保留（例程默认有 `lock` 端口） |
| 锁定模式（LOCK_MODE） | 默认 0 |

IP Compiler 显示的实际输出频率必须是 100.000 MHz。27 MHz 可以由 N = 3、M = 100、O = 9 得到（PFD 9 MHz、VCO 900 MHz），由 IP Compiler 计算。**如果显示的实际频率不是 100.000 MHz，停下来，把显示的频率和分频参数告诉协调者**：板级顶层里的 `CLK_SYS_HZ` 必须等于实际频率（SYSCTRL `CLK_SYS_HZ`，CoreMark 计时依赖它）。

## 期望端口

| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| `clkin1` | in | 1 | 27 MHz 板钟 |
| `clkout0` | out | 1 | clk_sys 100 MHz |
| `lock` | out | 1 | 高有效，锁定后为 1；板级顶层把它与按键复位一起作为系统复位输入 |

## 生成后需要回传的信息

在 Windows 任务卡的 `result.md` 记录模块名、实际端口列表、IP Compiler 显示的实际输出频率和分频参数（N/M/O），以及选项截图（放 `artifacts/`）。实际端口与期望端口不一致时，由协调者修改板级顶层，不修改生成文件。
