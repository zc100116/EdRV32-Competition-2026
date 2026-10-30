# B3N 上板 board_npu 首个卷积用例失败

状态：已修复（卡 15 上板 PASS 39/39）；根因由板上前后对比支持，没有直接的信号观测

## 1. 现象

卡 13（`origin/win/20261030-13-b3n-npu`，`tasks/win/20261030-13-b3n-npu/result.md`）B3N 上板运行 `board_npu`（115200 波特率加载，Load result PASS）：

```text
NPU A-ID PASS
NPU A-empty PASS
NPU A-reset PASS
NPU B-OP-01-c16_32 FAIL desc=0 addr=1102000d expected=00000002 actual=00000001 mismatches=160 PERF0=522 MAC=32 passed=3
NPU board: FAIL 1/39
```

同一 RTL 的仿真（`verif/block/npu` OP-01 9 个变体、`verif/soc/board_npu` smoke）和主机参考模型自检全部通过。布线后时序全部满足（clk_npu slow 角 WNS +0.157 ns）。

## 2. 复现

- RTL `b5dc9469`（b3），工程 B3N，PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- 程序 `tasks/win/20261030-13-b3n-npu/src/board_npu.elf`（Linux 端由 `b5dc9469` 构建）。

T-NPU4：仿真源基线 `d3b83117`，新增入口及结果见本记录同次提交；
Verilator 5.020，确定性 DDR stall 序列（初值 `0x1234abcd`），无外部随机种子。
以下命令均在指定仿真主机串行执行，厂商模型目录由 `EDRV32_PANGO_SIM_DIR` 指定：

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/soc/board_npu/program/run.py --mac sim
python3 verif/soc/board_npu/program/run.py --mac vendor
```

不重编译 ELF 或 ROM；PT_LOAD 后门装入 DDR，采用卡 13 的 `src/ip_rom_boot.dat`，
经真实 BIOS `3=Run` 进入 `0x80000000`。CPU 执行原程序的数据复制、clean/invalidate、比较。
测试侧生成稀疏字节 DDR，`MEMORY_BYTES=1073741824`，覆盖 NPU 区和原 ELF 栈顶
`0xc0000000` 对应的物理区末端 `0x3fffffff`。公共 DDR 模型和 RTL 均未修改。
沿用已有 board_npu 的 UART 6.25 Mbaud 和 CLINT 按键窗口加速。
厂商变体仅将 MAC 链 tech 包装切至 FPGA 分支，使用外部 `GTP_APM_E2.v` 及 EQ-01
相同的 GRS 常量引用，其余均为 SIM_MODE。

两个变体的 `--lint-only -Wall`、构建均为 0 告警；厂商源文件按文件豁免编码告警，
MAC 包装仅豁免三个有意悬空输出的 `PINCONNECTEMPTY`。新增 SV 格式检查为 0 告警，
`python3 -m py_compile verif/soc/board_npu/program/run.py`、`git diff --check` 通过。
UART 由入口写入 `build/board_npu_program/{sim,vendor}/simulation.log`，
运行器逐字段对照本记录原样引用的板端日志。按任务要求，未回传主机文件，运行后清理工作目录及厂商模型。

## 3. 观察

- **SoC 级仿真不复现**：原 ELF 在行为 MAC 和 FPGA MAC 包装加厂商模型两变体均 PASS，
  A-ID、A-empty、A-reset 均 PASS；每个变体只输出一条 B 类结果，收到该行即结束，未执行后续用例、整网或连续帧。

| 字段 | 卡 13 上板 | SoC 行为 MAC | SoC 厂商 MAC |
|---|---|---|---|
| B-OP-01-c16_32 | FAIL | PASS | PASS |
| desc | 0 | 未打印（PASS） | 未打印（PASS） |
| 首错地址 | `1102000d` | 无 | 无 |
| expected / actual | `00000002` / `00000001` | 未打印（PASS） | 未打印（PASS） |
| mismatches | 160 | 未打印（PASS） | 未打印（PASS） |
| PERF0 | 522 | 439 | 439 |
| MAC | 32 | 32 | 32 |
| 结束时刻 | — | 1,870,875 ns | 1,870,875 ns |

两种仿真 MAC 结果和计数相同；相对板端，PERF0 少 83 个 NPU 周期，MAC 相同。
这些结果尚不能确认板端差异的根因。

T-NPU4b：经协调者确认，使用 `d3b83117` RTL（与卡 13 一致，未含 T-NPU3 链头修复），
覆盖本记录同次提交的 `verif/soc/board_npu/program/` 入口；行为 MAC、原 ELF/ROM 不变。
Verilator 5.020；命令为 `python3 verif/soc/board_npu/program/run.py --mac sim --ddr-latency N`，
依次取 `N=20,40,80`；第四点取 `N=40` 并加 `--ddr-read-gaps`，四点串行运行。
时延单位为 `clk_mem` 周期；保留原模型 LFSR 空拍，随机点额外按 `[7:3]` 插入 0–31 周期读 beat 间隔；种子 `0x1234abcd`。

| COMMAND_LATENCY | 额外随机读间隔 | B-OP-01 | PERF0 | MAC |
|---|---|---|---|---|
| 20 | 无 | PASS | 786 | 32 |
| 40 | 无 | PASS | 1168 | 32 |
| 80 | 无 | PASS | 1896 | 32 |
| 40 | 0–31 周期 | PASS | 1683 | 32 |

四个采样点在 20–80 周期命令时延下不复现，PERF0 均大于板上 522；此结果尚不能确定板端根因。
各点仅收到一条 B 类结果便结束，退出码均 0，`--lint-only -Wall` 和构建均 0 告警；Python 语法和 `git diff --check` 通过。
仅入口生成的 DDR shell/稀疏模型改变时序，公共模型及仓库 RTL/程序未改；日志原在 `build/board_npu_program/sim/`，运行后已清理进程和工作目录，未回传主机文件。

- `edrv32_mac_npu_int8_chain` 的 8 级都配置 `MODEZ=4'b0011`（后加器 Z 取 CPI），第 0 级把 `cpi_i` 接常数 0（设计记录 `2026-10-30-npu-apm-cascade.md` 第 5 节的决定）。
- 厂商 IP 源码（卡 12 `artifacts/ip_rtl/ipm2l_mult_v1_3.v.xml`、`ipm2l_multadd_v1_3.v.xml`）的第一级一律 `modez_in[0] = 3'd0`（加零），CPI 只接上一级的 CPO。
- 卡 13 的 APM 布局（`artifacts/apm_placement.pcf`）中，32 条链里至少 12 条的第 0 级与同列另一条链的末级相邻。

## 4. 根因

CPI 是专用级联走线，"选 CPI 并把 CPI 接常数 0"在硬件上可能没有生效，第 0 级把相邻 APM 的 CPO 加进了累加结果。仿真模型按端口值计算，看不到这一点。

T-NPU4 未复现失败，未取得支持或否定上述物理级联推测的直接信号证据；未定位到已确认的 RTL 根因，未修改 RTL 或 board_npu 程序。

卡 15（`origin/win/20261030-15-b3n-rerun`，RTL `3a344936`）的唯一 RTL 差异是链头改用 `MODEZ=4'b0000` 的 head 包装（综合层次 `g_lane[0].g_cascade` → `g_head`）。同一工程、同一个卡 13 ELF、同样 115200 加载，B-OP-01-c16_32 由 FAIL 变为 PASS，全部 39 项 PASS，资源和各时钟 WNS 与卡 13 一致。据此认定根因是第 0 级用 `MODEZ=4'b0011` 加 CPI、CPI 接常数 0 在硬件上不等于加 0。这是板上前后对比得出的结论，没有观测内部信号。

## 5. 修复

T-NPU3：新增链头包装 `edrv32_mac_npu_int8_head`（`MODEZ=4'b0000`，不用 CPI），每条链第 0 级用它；EQ-01 改为给厂商模型第 0 级的 CPI 驱动随机非零值，证明链头忽略 CPI。`board_npu` 改为 B 类失败不停止，并打印出错的输出通道，便于对照 APM 布局判断。合入 b3 `2f7cc24b`；上板验证见 `docs/reports/2026-10-30-board-b3n.md`。

## 6. 防回归

EQ-01 第 0 级 CPI 随机非零的比对。

T-NPU4 新增 `verif/soc/board_npu/program/test.yaml`（tier=`directed`，不进 smoke），
复用原始 ELF、CPU/cache/mem_xbar/DDR 网关和板级顶层，收到首个 B-OP-01 完整结果行后立即退出；
用例 FAIL 返回非零退出码，PASS 返回 0。

## 7. 同类排查

其他 APM 用法（`ip_mul_npu_quant_low/high`、`ip_mul_s33x33`）均由 IP Compiler 生成，第一级为 MODEZ=0，不受影响。
