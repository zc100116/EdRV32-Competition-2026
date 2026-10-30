# B3N 上板 board_npu 首个卷积用例失败

状态：定位中（根因为推测，待第二次上板确认）

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

## 3. 观察

- 失败只出现在硬件上，仿真（行为模型）和 EQ-01（包装模块对照厂商仿真模型）都通过，说明差异来自仿真模型没有体现的物理行为。
- `edrv32_mac_npu_int8_chain` 的 8 级都配置 `MODEZ=4'b0011`（后加器 Z 取 CPI），第 0 级把 `cpi_i` 接常数 0（设计记录 `2026-10-30-npu-apm-cascade.md` 第 5 节的决定）。
- 厂商 IP 源码（卡 12 `artifacts/ip_rtl/ipm2l_mult_v1_3.v.xml`、`ipm2l_multadd_v1_3.v.xml`）的第一级一律 `modez_in[0] = 3'd0`（加零），CPI 只接上一级的 CPO。
- 卡 13 的 APM 布局（`artifacts/apm_placement.pcf`）中，32 条链里至少 12 条的第 0 级与同列另一条链的末级相邻。

## 4. 根因（推测）

CPI 是专用级联走线，"选 CPI 并把 CPI 接常数 0"在硬件上可能没有生效，第 0 级把相邻 APM 的 CPO 加进了累加结果。仿真模型按端口值计算，看不到这一点。

## 5. 修复（进行中）

T-NPU3：新增链头包装 `edrv32_mac_npu_int8_head`（`MODEZ=4'b0000`，不用 CPI），每条链第 0 级用它；EQ-01 改为给厂商模型第 0 级的 CPI 驱动随机非零值，证明链头忽略 CPI。`board_npu` 改为 B 类失败不停止，并打印出错的输出通道，便于对照 APM 布局判断。

## 6. 防回归

EQ-01 第 0 级 CPI 随机非零的比对。

## 7. 同类排查

其他 APM 用法（`ip_mul_npu_quant_low/high`、`ip_mul_s33x33`）均由 IP Compiler 生成，第一级为 MODEZ=0，不受影响。
