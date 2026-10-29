# 寄存器复位值与位域调查

- 日期：2026-10-29
- 基线 commit：`fd34e4d7c4fa05b2563ccb0d22bfffca3de1f261`（本分支创建时 HEAD）
- 方法：只读检查 `rtl/include/regs/*.json`、对应寄存器 RTL 的异步复位赋值/APB 读数据组合逻辑、相关规格条款和现有测试中的 APB 读回断言。复位读回按复位已释放、`busy=0`、尚无软件访问或硬件事件；WO 位置记录 RTL 地址译码实际读回值。未运行仿真或测试。
- 工具及版本：Git、文本检索与文件查看；未取得工具版本（本报告为静态代码调查，无需器件或综合约束）。
- 器件/速度等级：不适用（未综合或测量器件）。
- 配置/条件：各模块复位输入已释放；外部 `busy`/错误/事件输入为 0。STATUS 对应此空闲状态。
- 与上一版本对比：无此前同类调查报告可供比较。
- 数据位置：表中列出 RTL、寄存器 JSON、规格及现有测试的仓库内路径和行号。

## 表 1：RTL 复位读回值

范围按寄存器 JSON 中 `reset: null` 的项目确定；明确列出的 mem_xbar `WEIGHT[P2]` 和 `RATE[P0,P1,P3,P4,P5]` 也纳入，因为其对应 JSON 数组元素的 reset 为 `null`。其他有明确 JSON reset 的寄存器不在表内。读回值均为 32 位；`—` 表示没有现成读回检查，结论仅依据代码。

| 模块 | 寄存器 | 偏移 | RTL 复位读回值 | RTL 依据（文件:行） | 测试佐证（文件:行） |
|---|---|---:|---:|---|---|
| disp | CTRL | 0x004 | 0x00000000 | `rtl/media/disp/edrv32_disp_regs.v:105-110,129-135` | `verif/unit/disp_regs/tb.sv:75-78` |
| disp | STATUS | 0x008 | 0x00000002 | `rtl/media/disp/edrv32_disp_regs.v:105-110,129-135` | `verif/unit/disp_regs/tb.sv:75-78` |
| disp | IRQ_EN | 0x00C | 0x00000000 | `rtl/media/disp/edrv32_disp_regs.v:105-112,129-135` | —（该测试行 83 起先写入 IRQ_EN） |
| disp | IRQ_STAT | 0x010 | 0x00000000 | `rtl/media/disp/edrv32_disp_regs.v:105-113,129-135` | `verif/block/disp/tb.sv:500-507` |
| disp | ERR_CODE | 0x014 | 0x00000000 | `rtl/media/disp/edrv32_disp_regs.v:105-114,129-135` | —（复位读回在 block 测试 `verif/block/disp/tb.sv:500-507`） |
| disp | DOORBELL（读回） | 0x028 | 0x00000000 | `rtl/media/disp/edrv32_disp_regs.v:105-126`（未列地址保持默认 0） | `verif/block/disp/tb.sv:518-525`（写后读回 0） |
| disp | DONE_COUNT | 0x02C | 0x00000000 | `rtl/media/disp/edrv32_disp_regs.v:105-115,129-145` | `verif/unit/disp_regs/tb.sv:75-82` |
| disp | PERF0–4 | 0x040–0x050 | 0x00000000 | `rtl/media/disp/edrv32_disp_regs.v:105-119,129-145` | `verif/unit/disp_regs/tb.sv:75-79` |
| disp | PERF5–15 | 0x054–0x07C | 0x00000000 | `rtl/media/disp/edrv32_disp_regs.v:105-126`（未列地址默认 0） | `verif/unit/disp_regs/tb.sv:79`（逐地址检查至 0x07C） |
| eth | CTRL | 0x004 | 0x00000000 | `rtl/eth/edrv32_eth_regs.v:114-141,253-279` | `verif/unit/eth_regs/tb.sv:132-134` |
| eth | STATUS | 0x008 | 0x00000002 | `rtl/eth/edrv32_eth_regs.v:114-141,253-258` | `verif/unit/eth_regs/tb.sv:132-134` |
| eth | IRQ_STAT | 0x010 | 0x00000000 | `rtl/eth/edrv32_eth_regs.v:128-141,253-259` | `verif/unit/eth_regs/tb.sv:132-134` |
| eth | ERR_CODE | 0x014 | 0x00000000 | `rtl/eth/edrv32_eth_regs.v:129-141,253-260` | `verif/unit/eth_regs/tb.sv:132-134` |
| eth | DESC_BASE | 0x020 | 0x00000000 | `rtl/eth/edrv32_eth_regs.v:117-141,253-270` | `verif/unit/eth_regs/tb.sv:132-134` |
| eth | DESC_COUNT | 0x024 | 0x00000000 | `rtl/eth/edrv32_eth_regs.v:118-141,253-270` | `verif/unit/eth_regs/tb.sv:132-134` |
| eth | DOORBELL（读回） | 0x028 | 0x00000000 | `rtl/eth/edrv32_eth_regs.v:253-303`（未列地址保持默认 0） | `verif/unit/eth_regs/tb.sv:133-134` |
| eth | DONE_COUNT | 0x02C | 0x00000000 | `rtl/eth/edrv32_eth_regs.v:130-141,253-260` | `verif/unit/eth_regs/tb.sv:132-134` |
| eth | MDIO_CMD（读回） | 0x180 | 0x00000000 | `rtl/eth/edrv32_eth_regs.v:253-303`（未列地址保持默认 0） | `verif/unit/eth_regs/tb.sv:188-189` |
| geo | CTRL | 0x004 | 0x00000000 | `rtl/media/geo/edrv32_geo_regs.v:58-69,80-90` | `verif/unit/geo_regs/tb.sv:102-105`（地址区间检查含 CTRL） |
| geo | STATUS | 0x008 | 0x00000002 | `rtl/media/geo/edrv32_geo_regs.v:58-64,80-90` | `verif/unit/geo_regs/tb.sv:102-104` |
| geo | IRQ_STAT | 0x010 | 0x00000000 | `rtl/media/geo/edrv32_geo_regs.v:58-66,80-90` | `verif/unit/geo_regs/tb.sv:104`（地址区间检查） |
| geo | ERR_CODE | 0x014 | 0x00000000 | `rtl/media/geo/edrv32_geo_regs.v:58-66,80-90` | `verif/unit/geo_regs/tb.sv:104`（地址区间检查） |
| geo | DESC_BASE | 0x020 | 0x00000000 | `rtl/media/geo/edrv32_geo_regs.v:58-69,80-90` | `verif/unit/geo_regs/tb.sv:105` |
| geo | DESC_COUNT | 0x024 | 0x00000000 | `rtl/media/geo/edrv32_geo_regs.v:58-69,80-90` | `verif/unit/geo_regs/tb.sv:104`（地址区间检查） |
| geo | DOORBELL（读回） | 0x028 | 0x00000000 | `rtl/media/geo/edrv32_geo_regs.v:58-77`（未列地址默认 0） | `verif/unit/geo_regs/tb.sv:104`（地址区间检查） |
| geo | DONE_COUNT | 0x02C | 0x00000000 | `rtl/media/geo/edrv32_geo_regs.v:58-69,80-90` | `verif/unit/geo_regs/tb.sv:104`（地址区间检查） |
| geo | PERF0–5 | 0x040–0x054 | 0x00000000 | `rtl/media/geo/edrv32_geo_regs.v:58-75,80-90` | `verif/unit/geo_regs/tb.sv:104`（地址区间检查） |
| geo | PERF6–15 | 0x058–0x07C | 0x00000000 | `rtl/media/geo/edrv32_geo_regs.v:58-77`（未列地址默认 0） | `verif/unit/geo_regs/tb.sv:104`（地址区间检查） |
| mem_xbar | STATUS | 0x008 | 0x00000002 | `rtl/mem/edrv32_mem_xbar_regs.v:120-127,219-238` | `verif/unit/mem_xbar/tb.sv:1037-1041` |
| mem_xbar | IRQ_EN | 0x00C | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:120-127,219-229` | —（代码依据） |
| mem_xbar | IRQ_STAT | 0x010 | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:120-127,219-229` | —（代码依据） |
| mem_xbar | ERR_CODE | 0x014 | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:120-127,219-229`（读 ERR_TYPE 寄存器） | —（代码依据） |
| mem_xbar | DOORBELL（读回） | 0x028 | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:120-215`（未列地址默认 0） | —（代码依据） |
| mem_xbar | STAT_CTRL（读回） | 0x110 | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:120-215`（未列地址默认 0） | —（代码依据） |
| mem_xbar | WEIGHT[P2] | 0x248 | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:135-162,219-238` | `verif/unit/mem_xbar/tb.sv:1052-1057` |
| mem_xbar | RATE[P0] | 0x20C | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:138-162,219-238` | `verif/unit/mem_xbar/tb.sv:1052-1057` |
| mem_xbar | RATE[P1] | 0x22C | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:142-162,219-238` | `verif/unit/mem_xbar/tb.sv:1052-1057` |
| mem_xbar | RATE[P3] | 0x26C | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:150-162,219-238` | `verif/unit/mem_xbar/tb.sv:1052-1057` |
| mem_xbar | RATE[P4] | 0x28C | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:154-162,219-238` | `verif/unit/mem_xbar/tb.sv:1052-1057` |
| mem_xbar | RATE[P5] | 0x2AC | 0x00000000 | `rtl/mem/edrv32_mem_xbar_regs.v:158-162,219-238` | `verif/unit/mem_xbar/tb.sv:1052-1057` |
| npu | DOORBELL（读回） | 0x028 | 0x00000000 | `rtl/npu/edrv32_npu_regs.v:66-89`（未列地址保持默认 0） | —（代码依据） |
| npu | STATUS（核对项） | 0x008 | 0x00000002 | `rtl/npu/edrv32_npu_regs.v:66-74,92-106` | `verif/unit/npu_regs/tb_npu_regs.sv:100-102` |
| npu | ID（核对项） | 0x000 | 0x00060001 | `rtl/npu/edrv32_npu_regs.v:66-70` | `verif/unit/npu_regs/tb_npu_regs.sv:100-101` |
| perf_mon | CTRL | 0x004 | 0x00000000 | `rtl/mem/edrv32_mem_perf_mon.v:274-288,516-524` | —（代码依据） |
| perf_mon | STATUS | 0x008 | 0x00000002 | `rtl/mem/edrv32_mem_perf_mon.v:442-450,516-524` | —（代码依据） |
| perf_mon | IRQ_EN | 0x00C | 0x00000000 | `rtl/mem/edrv32_mem_perf_mon.v:274-288,516-524` | —（代码依据） |
| perf_mon | IRQ_STAT | 0x010 | 0x00000000 | `rtl/mem/edrv32_mem_perf_mon.v:442-450,516-524` | —（代码依据） |
| perf_mon | ERR_CODE | 0x014 | 0x00000000 | `rtl/mem/edrv32_mem_perf_mon.v:442-450,516-524` | —（代码依据） |
| perf_mon | DOORBELL（读回） | 0x028 | 0x00000000 | `rtl/mem/edrv32_mem_perf_mon.v:516-562`（未列地址默认 0） | —（代码依据） |
| perf_mon | DONE_COUNT | 0x02C | 0x00000000 | `rtl/mem/edrv32_mem_perf_mon.v:442-450,516-525` | —（代码依据） |
| pix | STATUS | 0x008 | 0x00000002 | `rtl/media/pix/edrv32_pix_regs.v:78-86,97-109` | —（代码依据） |
| pix | IRQ_STAT | 0x010 | 0x00000000 | `rtl/media/pix/edrv32_pix_regs.v:78-86,97-109` | —（代码依据） |
| pix | DOORBELL（读回） | 0x028 | 0x00000000 | `rtl/media/pix/edrv32_pix_regs.v:78-94`（未列地址默认 0） | —（代码依据） |
| pix | DONE_COUNT | 0x02C | 0x00000000 | `rtl/media/pix/edrv32_pix_regs.v:78-89,97-109` | —（代码依据） |
| pix | GAMMA_WR（读回） | 0x10C | 0x00000000 | `rtl/media/pix/edrv32_pix_regs.v:78-94`（未列地址默认 0） | —（代码依据） |
| vin | CTRL | 0x004 | 0x00000000 | `rtl/media/vin/edrv32_vin_regs.v:83-92,127-145` | —（代码依据） |
| vin | STATUS | 0x008 | 0x00000002 | `rtl/media/vin/edrv32_vin_regs.v:83-91,127-145` | `verif/unit/vin_regs/tb.sv:105-106` |
| vin | IRQ_EN | 0x00C | 0x00000000 | `rtl/media/vin/edrv32_vin_regs.v:83-90,127-132` | —（代码依据） |
| vin | IRQ_STAT | 0x010 | 0x00000000 | `rtl/media/vin/edrv32_vin_regs.v:83-91,127-132` | —（代码依据） |
| vin | ERR_CODE | 0x014 | 0x00000000 | `rtl/media/vin/edrv32_vin_regs.v:83-92,127-132` | —（代码依据） |
| vin | DOORBELL（读回） | 0x028 | 0x00000000 | `rtl/media/vin/edrv32_vin_regs.v:83-124`（未列地址默认 0） | —（代码依据） |
| vin | DONE_COUNT | 0x02C | 0x00000000 | `rtl/media/vin/edrv32_vin_regs.v:83-93,200-205` | —（代码依据） |
| vin | PERF0–15 | 0x040–0x07C | 0x00000000 | `rtl/media/vin/edrv32_vin_regs.v:120-123,183-205` | —（代码依据） |
| vin | MSRC_CTRL（读回） | 0x11C | 0x00000000 | `rtl/media/vin/edrv32_vin_regs.v:83-124`（未列地址默认 0） | —（代码依据） |

备注：`disp` 的 JSON 将 PERF 描述为 16 项，RTL 对 PERF0–4 有显式读回，其余地址由默认分支读 0；`geo` JSON 同样描述 16 项，RTL 显式实现 PERF0–5，其余默认读 0。表中按 APB 可观察读值列出，而非推断不存在的计数器状态。WO 地址没有存储复位状态，表中仅记录读数据逻辑的值。

## 表 2：多段 VALUE 位域的 RTL 含义

| 模块.寄存器.位域 | 位段 | RTL 信号/表达式 | 含义 |
|---|---:|---|---|
| disp.ID.VALUE_31_16 | [31:16] | 常量 `32'h0005_0001[31:16]`，`rtl/media/disp/edrv32_disp_regs.v:108` | 模块类型码（RTL 值为 0x0005） |
| disp.ID.VALUE_15_0 | [15:0] | 常量 `32'h0005_0001[15:0]`，同上 | RTL 版本值（0x0001） |
| eth.ID.VALUE_31_16 | [31:16] | 常量 `32'h0007_0001[31:16]`，`rtl/eth/edrv32_eth_regs.v:256` | 模块类型码（0x0007） |
| eth.ID.VALUE_15_0 | [15:0] | 常量 `32'h0007_0001[15:0]`，同上 | 版本值（0x0001） |
| geo.ID.VALUE_31_16 | [31:16] | 常量 `32'h0003_0001[31:16]`，`rtl/media/geo/edrv32_geo_regs.v:61` | 模块类型码（0x0003） |
| geo.ID.VALUE_15_0 | [15:0] | 常量 `32'h0003_0001[15:0]`，同上 | 版本值（0x0001） |
| mem_xbar.ID.VALUE_31_16 | [31:16] | 常量 `32'h0008_0001[31:16]`，`rtl/mem/edrv32_mem_xbar_regs.v:123` | 模块类型码（0x0008） |
| mem_xbar.ID.VALUE_15_0 | [15:0] | 常量 `32'h0008_0001[15:0]`，同上 | 版本值（0x0001） |
| mem_xbar.ERR_TYPE.VALUE_0 | [0] | `err_type_r[0]`，`rtl/mem/edrv32_mem_xbar_regs.v:127,134,229,275` | 最近一次违规是否跨越 4 KiB 边界；`err_type_i[0]` 由 mem_xbar 错误上报接口提供 |
| mem_xbar.ERR_TYPE.VALUE_2 | [2] | `err_type_r[2]`，同上 | 最近一次违规是否未对齐；`err_type_i[2]` 由 mem_xbar 错误上报接口提供 |
| npu.ID.VALUE_31_16 | [31:16] | 常量 `32'h0006_0001[31:16]`，`rtl/npu/edrv32_npu_regs.v:69` | 模块类型码（0x0006） |
| npu.ID.VALUE_15_0 | [15:0] | 常量 `32'h0006_0001[15:0]`，同上 | 版本值（0x0001） |
| perf_mon.ID.VALUE_31_16 | [31:16] | 常量 `32'h0009_0001[31:16]`，`rtl/mem/edrv32_mem_perf_mon.v:519` | 模块类型码（0x0009） |
| perf_mon.ID.VALUE_15_0 | [15:0] | 常量 `32'h0009_0001[15:0]`，同上 | 版本值（0x0001） |
| pix.ID.VALUE_31_16 | [31:16] | 常量 `32'h0002_0001[31:16]`，`rtl/media/pix/edrv32_pix_regs.v:81` | 模块类型码（0x0002） |
| pix.ID.VALUE_15_0 | [15:0] | 常量 `32'h0002_0001[15:0]`，同上 | 版本值（0x0001） |
| vin.ID.VALUE_31_16 | [31:16] | 常量 `32'h0001_0001[31:16]`，`rtl/media/vin/edrv32_vin_regs.v:86` | 模块类型码（0x0001） |
| vin.ID.VALUE_15_0 | [15:0] | 常量 `32'h0001_0001[15:0]`，同上 | 版本值（0x0001） |
| vin.CH_DONE_INFO.VALUE_1_0 | [1:0] | `ch_done_info_i[1:0]`，`rtl/media/vin/edrv32_vin_regs.v:106,116` | 最近完成帧的槽号 |
| vin.CH_DONE_INFO.VALUE_3_2 | [3:2] | `ch_done_info_i[3:2]`，同上 | 最近完成帧的源编码（与 CHn_CTRL.SRC 编码相同） |
| vin.CH_WR_STAT.VALUE_2_1 | [2:1] | `ch_wr_stat_i[2:1]`，`rtl/media/vin/edrv32_vin_regs.v:108,118` | 正在写出的槽号；bit0 另接 `ACTIVE` 状态 |

上述 VALUE 含义中，ID 的高/低半字按 SoC 规格 7.1 的类型码/版本划分；ERR_TYPE 与 VIN 状态字段的含义见 `docs/spec/mem-subsys-spec.md:120`、`docs/spec/vin-spec.md:200-205`。

## 表 3：RTL 与已有规格不一致之处

1. **DISP ID**：规格 `docs/spec/disp-spec.md:137` 写为 `0x0005_0002`，JSON reset 为 `0x0005_0001`，RTL `rtl/media/disp/edrv32_disp_regs.v:108` 读回 `0x0005_0001`。按本 Task 要求以 RTL 事实记录，ID 与规格条款不一致。
2. **DISP 双层寄存器/IRQ**：规格 `docs/spec/disp-spec.md:140,150-163` 已定义 L1 的 SWITCH1 和 0x114–0x138 私有寄存器；当前 RTL `rtl/media/disp/edrv32_disp_regs.v:105-125` 没有这些读地址，默认读 0，且 `irq_set_w`/`IRQ_MASK` 仅包含单层相关位（同文件 43,100-103）。这是规格与实现的功能/寄存器映射差异，不是复位值推断。
3. **VIN CH2**：规格 `docs/spec/vin-spec.md:184-200` 定义 CHn 的 n=0、1、2，JSON 对应通道维度为 3；当前 RTL `rtl/media/vin/edrv32_vin_regs.v:99-118` 只实现 CH0、CH1 地址，CH2 地址命中默认分支（读 0）。

以上列为 3 项不一致。其余本次核对的明确复位条款与表 1 读回值一致；未发现 NPU STATUS/ID 不符：规格明确 STATUS=0x2、ID=0x0006_0001，RTL 与单元测试均读回相同值。
