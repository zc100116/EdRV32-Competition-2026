# NPU IP 核对（2026-10-27，重新生成后）

- 诊断 commit：8fa223700974d6fba66a421559a966b8012f15df（含已提交的七个 RAM FPGA 端口适配）。
- 工程：`G:/codex_project/EdRV32-FPGA/EdRV32-NPU-DP/EdRV32-NPU-DP.pds`；保存后的工程封装 FBB676。
- 依据：各 IP 的 `.idf`、生成顶层 `.v` 和 `generate.log`，原文件留在工程目录。
- 所有 9 个 IP 均为 Logos2 / PG2L200H / -6 / FBB676，生成日志均为 0 error / 0 warning。
- weight 已改为读写 256 位；七个 RAM 的容量及输出寄存器、读使能选项均符合创建说明。
- 两个量化乘法顶层实际 XYREG=1、MREG=1、PREG=0、INREG=0、OUTREG=0，配置为两级。
- residual 在 PDS IP Compiler 界面显示 Used DRM36K Number=4；其余 IP 的资源数未取得，生成日志显示 Synthesis is disabled。
- 原 ModelSim 检查仍 FAIL：5166 ns，u_chk_residual 读数据与参考不符；各检查器尚未完成。

## 包装模块适配

端口连接仅修改七个 `rtl/tech/edrv32_ram_npu_*.v` 的 FPGA 分支：

| 改动 | 原连接 | 实际连接 |
|---|---|---|
| 读使能 | `.rd_en(rd_en_i)` | `.rd_clk_en(rd_en_i)` |
| 写复位 | 无 | `.wr_rst(1'b0)` |
| 读复位 | 无 | `.rd_rst(1'b0)` |

对外端口、行为模型、生成 IP、检查程序均未修改。实际 IP 未提供独立 rd_oce 端口，RD_OCE_EN=false；生成顶层将内部输出寄存器使能置 1。

用户最终要求通过导入脚本设置 include 路径。全部 10 个包装模块保留原来的
`include "edrv32_build_mode.vh"` 引用；此前源码相对 include 改动已撤回。
脚本传入 rtl/include 和 FPGA 工程目录，独立 PDS 编译验证通过，细节见 result.md。

## 本次失败

```text
FAIL ram AW=9 DW=256 expected=19861f335c63fbb807c42b0f56592bacd4e63ca968758dd0285d9750a8227850 actual=524ee3a4cb789e96ac53b658f3565ae6988bd0310fce171f342ce768f499a8e9 time=5166000
Time: 5166 ns  Scope: npu_ip_check.u_chk_residual
```

尚未确认具体触发条件和根因。按任务卡 B4 停止 NPU 后续流程，不修改行为模型或检查程序。

## 每个 IP 的实际端口和选项

### ip_mul_npu_quant_high

| 项 | 实际值 |
|---|---|
| display_name | Simple Multiplier |
| family | Logos2 |
| device | PG2L200H |
| speedgrade | -6 |
| package | FBB676 |
| DRM/APM 实测占用 | 未取得；IP 生成未运行综合 |

| 端口 | 方向 | 位宽 |
|---|---|---|
| `a` | input | 16 |
| `b` | input | 16 |
| `clk` | input | 1 |
| `rst` | input | 1 |
| `ce` | input | 1 |
| `p` | output | 32 |

`.idf` 选项原值（乘法流水实际连接见后）：

```text
PIPEREG_EN_2=0
INREG_EN=0
CPO_REG=14'b00000000000000
APM4_BOOL=false
MREG_BOOL=true
APM3_BOOL=false
APM11_BOOL=false
PIPE_STATUS=2
APM5_BOOL=false
INREG_BOOL=false
APM2_BOOL=false
APM7_BOOL=false
OUTREG_BOOL=false
PIPEREG_EN_3=1
BSIZE=16
APM6_BOOL=false
APM14_BOOL=false
APM1_BOOL=false
APM9_BOOL=false
OUTREG_EN=0
ASIZE=16
XYREG_BOOL=true
APM12_BOOL=false
PIPEREG_EN_1=1
ADVANCED_BOOL=true
ASYNC_RST=1
APM10_BOOL=false
PIPELINE_TXT=0
ASYNC_RST_BOOL=true
APM13_BOOL=false
OPTIMAL_TIMING_BOOL=false
A_SIGNED=1
APM8_BOOL=false
OPTIMAL_TIMING=0
PREG_BOOL=false
B_SIGNED=1
```

生成顶层 `.v` 实际将 XYREG=1、MREG=1、PREG=0 分别连接到 PIPEREG_EN_1/2/3；INREG=0、OUTREG=0。不能仅按 `.idf` 中 PIPEREG_EN_* 字段判断实际延迟。

### ip_mul_npu_quant_low

| 项 | 实际值 |
|---|---|
| display_name | Simple Multiplier |
| family | Logos2 |
| device | PG2L200H |
| speedgrade | -6 |
| package | FBB676 |
| DRM/APM 实测占用 | 未取得；IP 生成未运行综合 |

| 端口 | 方向 | 位宽 |
|---|---|---|
| `a` | input | 18 |
| `b` | input | 16 |
| `clk` | input | 1 |
| `rst` | input | 1 |
| `ce` | input | 1 |
| `p` | output | 34 |

`.idf` 选项原值（乘法流水实际连接见后）：

```text
APM1_BOOL=false
ASYNC_RST=1
ASYNC_RST_BOOL=true
XYREG_BOOL=true
A_SIGNED=1
CPO_REG=14'b00000000000000
APM10_BOOL=false
OPTIMAL_TIMING=0
APM9_BOOL=false
APM4_BOOL=false
ADVANCED_BOOL=true
B_SIGNED=1
APM13_BOOL=false
APM5_BOOL=false
INREG_BOOL=false
PIPEREG_EN_2=0
INREG_EN=0
PIPE_STATUS=2
APM11_BOOL=false
PIPEREG_EN_3=1
MREG_BOOL=true
PREG_BOOL=false
OUTREG_BOOL=false
APM8_BOOL=false
APM12_BOOL=false
PIPELINE_TXT=0
APM7_BOOL=false
BSIZE=16
APM6_BOOL=false
OUTREG_EN=0
APM14_BOOL=false
ASIZE=18
PIPEREG_EN_1=1
APM3_BOOL=false
OPTIMAL_TIMING_BOOL=false
APM2_BOOL=false
```

生成顶层 `.v` 实际将 XYREG=1、MREG=1、PREG=0 分别连接到 PIPEREG_EN_1/2/3；INREG=0、OUTREG=0。不能仅按 `.idf` 中 PIPEREG_EN_* 字段判断实际延迟。

### ip_ram_npu_line

| 项 | 实际值 |
|---|---|
| display_name | DRM Based Simple Dual Port RAM |
| family | Logos2 |
| device | PG2L200H |
| speedgrade | -6 |
| package | FBB676 |
| DRM/APM 实测占用 | 未取得；IP 生成未运行综合 |

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_data` | input | 256 |
| `wr_addr` | input | 10 |
| `wr_en` | input | 1 |
| `wr_clk` | input | 1 |
| `wr_rst` | input | 1 |
| `rd_addr` | input | 10 |
| `rd_data` | output | 256 |
| `rd_clk` | input | 1 |
| `rd_clk_en` | input | 1 |
| `rd_rst` | input | 1 |

`.idf` 选项原值（乘法流水实际连接见后）：

```text
OUTPUT_REG=true
RST_VAL=0
CAS_MODE_SEL=AUTO
WR_ADDR_STROBE_EN=false
CAS_MODE=36K
FAB_REG=false
RD_DATA_WIDTH=256
WR_ADDR_WIDTH=10
POWER_OPT=false
RD_CLK_OR_POL_INV=false
RD_OCE_EN=false
INIT_FILE=NONE
INIT_FORMAT=BIN
RD_CLK_EN=true
WR_DATA_WIDTH=256
WR_CLK_EN=false
RESET_TYPE=ASYNC
WR_BYTE_EN=false
BE_WIDTH=1
SAMEWIDTH_EN=true
RD_BE_WIDTH=1
INIT_EN=false
RD_ADDR_WIDTH=10
RD_ADDR_STROBE_EN=false
BYTE_SIZE=8
RST_VAL_EN=false
```

### ip_ram_npu_lut

| 项 | 实际值 |
|---|---|
| display_name | DRM Based Simple Dual Port RAM |
| family | Logos2 |
| device | PG2L200H |
| speedgrade | -6 |
| package | FBB676 |
| DRM/APM 实测占用 | 未取得；IP 生成未运行综合 |

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_data` | input | 8 |
| `wr_addr` | input | 12 |
| `wr_en` | input | 1 |
| `wr_clk` | input | 1 |
| `wr_rst` | input | 1 |
| `rd_addr` | input | 12 |
| `rd_data` | output | 8 |
| `rd_clk` | input | 1 |
| `rd_clk_en` | input | 1 |
| `rd_rst` | input | 1 |

`.idf` 选项原值（乘法流水实际连接见后）：

```text
OUTPUT_REG=true
RD_CLK_OR_POL_INV=false
SAMEWIDTH_EN=true
WR_ADDR_WIDTH=12
INIT_FILE=NONE
WR_DATA_WIDTH=8
RD_ADDR_STROBE_EN=false
RST_VAL=0
POWER_OPT=false
BE_WIDTH=1
BYTE_SIZE=8
WR_CLK_EN=false
WR_ADDR_STROBE_EN=false
WR_BYTE_EN=false
RESET_TYPE=ASYNC
CAS_MODE=36K
INIT_EN=false
RD_ADDR_WIDTH=12
RD_CLK_EN=true
CAS_MODE_SEL=AUTO
RD_DATA_WIDTH=8
RD_BE_WIDTH=1
FAB_REG=false
INIT_FORMAT=BIN
RD_OCE_EN=false
RST_VAL_EN=false
```

### ip_ram_npu_quant

| 项 | 实际值 |
|---|---|
| display_name | DRM Based Simple Dual Port RAM |
| family | Logos2 |
| device | PG2L200H |
| speedgrade | -6 |
| package | FBB676 |
| DRM/APM 实测占用 | 未取得；IP 生成未运行综合 |

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_data` | input | 64 |
| `wr_addr` | input | 9 |
| `wr_en` | input | 1 |
| `wr_clk` | input | 1 |
| `wr_rst` | input | 1 |
| `rd_addr` | input | 9 |
| `rd_data` | output | 64 |
| `rd_clk` | input | 1 |
| `rd_clk_en` | input | 1 |
| `rd_rst` | input | 1 |

`.idf` 选项原值（乘法流水实际连接见后）：

```text
OUTPUT_REG=true
RD_CLK_OR_POL_INV=false
SAMEWIDTH_EN=true
WR_ADDR_WIDTH=9
INIT_FILE=NONE
WR_DATA_WIDTH=64
RD_ADDR_STROBE_EN=false
RST_VAL=0
POWER_OPT=false
BE_WIDTH=1
BYTE_SIZE=8
WR_CLK_EN=false
WR_ADDR_STROBE_EN=false
WR_BYTE_EN=false
RESET_TYPE=ASYNC
CAS_MODE=36K
INIT_EN=false
RD_ADDR_WIDTH=9
RD_CLK_EN=true
CAS_MODE_SEL=AUTO
RD_DATA_WIDTH=64
RD_BE_WIDTH=1
FAB_REG=false
INIT_FORMAT=BIN
RD_OCE_EN=false
RST_VAL_EN=false
```

### ip_ram_npu_residual

| 项 | 实际值 |
|---|---|
| display_name | DRM Based Simple Dual Port RAM |
| family | Logos2 |
| device | PG2L200H |
| speedgrade | -6 |
| package | FBB676 |
| DRM/APM 实测占用 | PDS IP Compiler 界面 Used DRM36K Number=4 |

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_data` | input | 256 |
| `wr_addr` | input | 9 |
| `wr_en` | input | 1 |
| `wr_clk` | input | 1 |
| `wr_rst` | input | 1 |
| `rd_addr` | input | 9 |
| `rd_data` | output | 256 |
| `rd_clk` | input | 1 |
| `rd_clk_en` | input | 1 |
| `rd_rst` | input | 1 |

`.idf` 选项原值（乘法流水实际连接见后）：

```text
OUTPUT_REG=true
RD_CLK_OR_POL_INV=false
SAMEWIDTH_EN=true
WR_ADDR_WIDTH=9
INIT_FILE=NONE
WR_DATA_WIDTH=256
RD_ADDR_STROBE_EN=false
RST_VAL=0
POWER_OPT=false
BE_WIDTH=1
BYTE_SIZE=8
WR_CLK_EN=false
WR_ADDR_STROBE_EN=false
WR_BYTE_EN=false
RESET_TYPE=ASYNC
CAS_MODE=36K
INIT_EN=false
RD_ADDR_WIDTH=9
RD_CLK_EN=true
CAS_MODE_SEL=AUTO
RD_DATA_WIDTH=256
RD_BE_WIDTH=1
FAB_REG=false
INIT_FORMAT=BIN
RD_OCE_EN=false
RST_VAL_EN=false
```

### ip_ram_npu_result

| 项 | 实际值 |
|---|---|
| display_name | DRM Based Simple Dual Port RAM |
| family | Logos2 |
| device | PG2L200H |
| speedgrade | -6 |
| package | FBB676 |
| DRM/APM 实测占用 | 未取得；IP 生成未运行综合 |

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_data` | input | 512 |
| `wr_addr` | input | 9 |
| `wr_en` | input | 1 |
| `wr_clk` | input | 1 |
| `wr_rst` | input | 1 |
| `rd_addr` | input | 9 |
| `rd_data` | output | 512 |
| `rd_clk` | input | 1 |
| `rd_clk_en` | input | 1 |
| `rd_rst` | input | 1 |

`.idf` 选项原值（乘法流水实际连接见后）：

```text
OUTPUT_REG=true
RD_CLK_OR_POL_INV=false
SAMEWIDTH_EN=true
WR_ADDR_WIDTH=9
INIT_FILE=NONE
WR_DATA_WIDTH=512
RD_ADDR_STROBE_EN=false
RST_VAL=0
POWER_OPT=false
BE_WIDTH=1
BYTE_SIZE=8
WR_CLK_EN=false
WR_ADDR_STROBE_EN=false
WR_BYTE_EN=false
RESET_TYPE=ASYNC
CAS_MODE=36K
INIT_EN=false
RD_ADDR_WIDTH=9
RD_CLK_EN=true
CAS_MODE_SEL=AUTO
RD_DATA_WIDTH=512
RD_BE_WIDTH=1
FAB_REG=false
INIT_FORMAT=BIN
RD_OCE_EN=false
RST_VAL_EN=false
```

### ip_ram_npu_scratch

| 项 | 实际值 |
|---|---|
| display_name | DRM Based Simple Dual Port RAM |
| family | Logos2 |
| device | PG2L200H |
| speedgrade | -6 |
| package | FBB676 |
| DRM/APM 实测占用 | 未取得；IP 生成未运行综合 |

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_data` | input | 256 |
| `wr_addr` | input | 9 |
| `wr_en` | input | 1 |
| `wr_clk` | input | 1 |
| `wr_rst` | input | 1 |
| `rd_addr` | input | 9 |
| `rd_data` | output | 256 |
| `rd_clk` | input | 1 |
| `rd_clk_en` | input | 1 |
| `rd_rst` | input | 1 |

`.idf` 选项原值（乘法流水实际连接见后）：

```text
OUTPUT_REG=false
RD_CLK_OR_POL_INV=false
SAMEWIDTH_EN=true
WR_ADDR_WIDTH=9
INIT_FILE=NONE
WR_DATA_WIDTH=256
RD_ADDR_STROBE_EN=false
RST_VAL=0
POWER_OPT=false
BE_WIDTH=1
BYTE_SIZE=8
WR_CLK_EN=false
WR_ADDR_STROBE_EN=false
WR_BYTE_EN=false
RESET_TYPE=ASYNC
CAS_MODE=36K
INIT_EN=false
RD_ADDR_WIDTH=9
RD_CLK_EN=true
CAS_MODE_SEL=AUTO
RD_DATA_WIDTH=256
RD_BE_WIDTH=1
FAB_REG=false
INIT_FORMAT=BIN
RD_OCE_EN=false
RST_VAL_EN=false
```

### ip_ram_npu_weight

| 项 | 实际值 |
|---|---|
| display_name | DRM Based Simple Dual Port RAM |
| family | Logos2 |
| device | PG2L200H |
| speedgrade | -6 |
| package | FBB676 |
| DRM/APM 实测占用 | 未取得；IP 生成未运行综合 |

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_data` | input | 256 |
| `wr_addr` | input | 9 |
| `wr_en` | input | 1 |
| `wr_clk` | input | 1 |
| `wr_rst` | input | 1 |
| `rd_addr` | input | 9 |
| `rd_data` | output | 256 |
| `rd_clk` | input | 1 |
| `rd_clk_en` | input | 1 |
| `rd_rst` | input | 1 |

`.idf` 选项原值（乘法流水实际连接见后）：

```text
RD_OCE_EN=false
WR_BYTE_EN=false
WR_ADDR_STROBE_EN=false
WR_CLK_EN=false
RESET_TYPE=ASYNC
CAS_MODE_SEL=AUTO
RD_CLK_OR_POL_INV=false
WR_ADDR_WIDTH=9
INIT_FILE=NONE
POWER_OPT=false
BE_WIDTH=1
SAMEWIDTH_EN=true
OUTPUT_REG=true
RD_ADDR_STROBE_EN=false
RD_BE_WIDTH=1
WR_DATA_WIDTH=256
BYTE_SIZE=8
INIT_FORMAT=BIN
CAS_MODE=36K
RST_VAL=0
INIT_EN=false
RD_CLK_EN=true
RD_ADDR_WIDTH=9
RD_DATA_WIDTH=256
FAB_REG=false
RST_VAL_EN=false
```

## B4b：CAS_MODE、输出寄存器使能与冲突选项

七个 RAM `.idf` 的 CAS_MODE 均为 36K，CAS_MODE_SEL 均为 AUTO，RD_OCE_EN 均为 false。
OUTPUT_REG 在 scratch 为 false，其余六个为 true。各 `.idf` 均没有 WRITE_MODE、READ_FIRST
或 WRITE_FIRST 参数。

通过 PDS 工程 Files → IPs → ip_ram_npu_residual.idf 只读打开 IP Compiler：

- DRM Based Simple Dual Port RAM 1.10，Logos2-PG2L200H-FBB676--6。
- DRM Resource Mode=AUTO；Actual DRM Resource Mode=DRM36K。
- Used DRM36K Number=4（该单个 residual IP 的界面报告；其余 IP 尚未从 GUI 读取资源数）。
- Enable rd_clk_en 勾选；Enable rd_oce 未勾选；Enable Output Register 勾选。
- 界面没有 Write Mode / Read First / Write First / No Change 冲突模式选项。
- 查看后关闭，未保存或重新生成 IP。

七个 RAM 使用同一版 GUI 定义：
`G:/Program/pango/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_ram/ipm2l_flex_ram_eval/ipm2l_sdpram/ui.tcl`。
完整界面定义亦无上述冲突模式选项。

### 四候选模型诊断计数

| RAM | CAS_MODE | RD_OCE_EN | 冲突模式选项 | checks | collisions | m0_spec | m1_write_first | m2_oce_gated | m3_both |
|---|---|---|---|---|---|---|---|---|---|
| line | 36K | false | 无可选项 | 6002 | 525 | 428 | 310 | 2047 | 1971 |
| weight | 36K | false | 无可选项 | 6002 | 507 | 418 | 292 | 2035 | 1960 |
| quant | 36K | false | 无可选项 | 6001 | 530 | 478 | 283 | 2083 | 1948 |
| lut | 36K | false | 无可选项 | 6002 | 501 | 407 | 333 | 2063 | 1992 |
| residual | 36K | false | 无可选项 | 6001 | 519 | 443 | 313 | 2052 | 1957 |
| result | 36K | false | 无可选项 | 6002 | 552 | 460 | 315 | 2090 | 1988 |
| scratch | 36K | false | 无可选项 | 6003 | 545 | 437 | 318 | 437 | 318 |

所有候选模型均有失配，完整诊断日志见 diag_npu_ram.log，首失配与解释见 result.md。
