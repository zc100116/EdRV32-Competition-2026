# NPU 模块级验证（NB，N-V1）

依据 `docs/spec/npu-spec.md` v0.2 和 `docs/testplan/npu-testplan.md` v0.2，
独立编写；开发期间未读取 `rtl/npu/`。30 个 NB 项各有一个目录和
`test.yaml/files.f`，编号与验证方案 3.2–3.7 一一对应。
`selftest/` 是任务要求的环境自检，不作为额外的 DUT 测试项。

`tb_npu.sv` 提供两个独立时钟、分别释放的复位、APB4 驱动、寄存器编程与读回、
门铃、DONE/ERROR/ABORT 流程、中断检查，以及按 `check.txt` 对 `ref_out.hex`
逐字节比对。失配输出描述符号、区名、字节地址、期望、实际和时刻，随后非零退出。
`edrv32_axi256_checker` 和 `edrv32_apb_checker` 始终开启。
存储模型为 `verif/models/npu_axi256_mem.sv`，装载目录内存在的
model/desc/input/work/output/state 六种 `mem_*.hex`，地址均为绝对 beat 地址。
未初始化字节为 0；不按区名推断地址归属。参考输出有独立比对存储，不混入 DUT 内存。

`cases.py` 枚举激励；`prepare.py` 只通过文件格式和 CLI 调用编译器/参考模型。
错误 OP、原始容量字段、定向输入/LUT 在生成目录中按规格打包后修改，
非法描述符不会交给参考模型执行；另保存正常恢复用例。
`run.py` 串行运行各变体，Verilator 构建固定 `-j 1`，生成工具限制 BLAS/OMP 为单线程。
所有生成物和日志在 `build/npu/`；这里没有 RTL 或运算结果的替代实现。

## 运行和自检

从仓库根目录执行：

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/block/npu/check_style.py
make smoke REGRESS_ARGS='-j 1 --path verif/unit/npu_axi256_mem'
make smoke REGRESS_ARGS='-j 1 --path verif/block/npu/selftest'
```

自检用手工构造的最小镜像，不依赖编译工具或参考模型。
`SELFTEST=1` 的 generate 分支不例化 DUT；仅在 tb 内提供 APB 寄存器读回，
验证六个配置寄存器的读写、五个初始镜像的全部 64 字节和字节序，
将 `ref_out.hex` 装入模型输出区，再走同一门铃、DONE、中断与比对路径。
正例比对两个不连续区间、合计 96 字节；负例仅翻转 `0x05000000` 的一个 bit，
必须非零退出并报告 `FAIL desc=0 ... expected=03 actual=02`。
运行器检查正例成功和负例确实报错之后才输出 PASS；负例诊断留在 `corrupt.log`。

2026-10-27 自检结果：存储模型 zero/latency/bw 三档 3 PASS；NB 自检 1 PASS，
包含上述正例与故意改错的负例。模型和 tb 的 `--lint-only --timing -Wall` 为 0 告警，
SV 风格检查为 3 文件、0 告警；`lint.vlt` 只豁免行为代码的 BLKSEQ、
现有公共 BFM 的未使用打包字段，以及 APB 公共 16 槽接口未连接的槽。

单独重跑环境正例/负例：

```sh
python3 verif/block/npu/run.py --test SELFTEST
build/npu/sim_selftest/sim +CASE_DIR=build/npu/selftest +TEST_ID=SELFTEST
# 本命令必须失败：
build/npu/sim_selftest/sim +CASE_DIR=build/npu/selftest +TEST_ID=SELFTEST +SELFTEST_CORRUPT
```

## DUT 接入和回归

当前真实 DUT 文件列表由 N-I1 在 `dut.f` 接入；此文件现在只有接入说明。
`SELFTEST` 缺省为 0，真实 NB 测试缺少 DUT 时会明确编译失败。
自检通过不表示 DUT 测试通过。真实 NB 回归留待 N-I1。
每个目录的 `files.f` 包含公共 sources 和真实 DUT 列表；其 `test.yaml`
的 runner 自动准备该编号的全部变体后运行同一 tb。

```sh
# 接入 DUT 后，单项：
make smoke REGRESS_ARGS='-j 1 --path verif/block/npu/op_04'
# 按验证方案第 6 节选择 S/F/P；full 也包含 smoke：
make smoke REGRESS_ARGS='-j 1 --path verif/block/npu'
make full REGRESS_ARGS='-j 1 --path verif/block/npu'
python3 tools/regress.py perf -j 1 --path verif/block/npu
```

## 测试项、目录和生成命令

下表目录均相对于 `verif/block/npu/`。每行的准备命令不需要 DUT；
去掉 `--prepare-only` 即生成并运行该项全部变体。S/F/P 分别为 smoke/full/perf。
所有小用例用 bw 档，SQ-01/02 的 B 延迟为 200。

| 编号 | 目录 | 档位 | 激励 | 生成命令（`python3 verif/block/npu/run.py` 后接） |
|---|---|---|---|---|
| RG-01 | rg_01/ | S | 复位、ID、RW/RO、CTRL 触发位 | `--test RG-01 --prepare-only` |
| RG-02 | rg_02/ | S | 3 描述符、BUSY、逐条 CUR_DESC、DONE_COUNT、中断屏蔽/RW1C | `--test RG-02 --prepare-only` |
| RG-03 | rg_03/ | F | 混合链两次门铃、PERF 清零和计数 | `--test RG-03 --prepare-only` |
| RG-04 | rg_04/ | S | 4 描述符、两帧不同输入/输出基址，只写这两个寄存器 | `--test RG-04 --prepare-only` |
| OP-01 | op_01/ | S | Cin 16/32/48 × Cout 32/64/96，9 组 | `--test OP-01 --prepare-only` |
| OP-02 | op_02/ | S | K3 S1，宽 4/8/12，补零边界 | `--test OP-02 --prepare-only` |
| OP-03 | op_03/ | S | K3 S2，奇偶高 4/5/6/7 | `--test OP-03 --prepare-only` |
| OP-04 | op_04/ | S | C4 K3 S2，Cout 16/32 × LUT/RES，8 组 | `--test OP-04 --prepare-only` |
| OP-05 | op_05/ | S | 定向随机排列 LUT，开/关各一次 | `--test OP-05 --prepare-only` |
| OP-06 | op_06/ | S | WORK/OUTPUT 残差，输出不同址 | `--test OP-06 --prepare-only` |
| OP-07 | op_07/ | S | Cout 16/80，非 C4 半块 | `--test OP-07 --prepare-only` |
| OP-08 | op_08/ | S | INT32 bias 极值、符号乘数、shift 0/47、四个 LUT 下标 | `--test OP-08 --prepare-only` |
| OP-09 | op_09/ | S | 全负 POOL，20×12，1/3 平面 | `--test OP-09 --prepare-only` |
| OP-10 | op_10/ | S | UPSAMPLE，全部偶数宽 2..40 | `--test OP-10 --prepare-only` |
| OP-11 | op_11/ | S | 四基址、偏移、宽松 stride、3 条零拷贝拼接 | `--test OP-11 --prepare-only` |
| OP-12 | op_12/ | F | 20 种子、4–8 条随机多算子链，随机标志与基址 | `--test OP-12 --prepare-only` |
| CP-01 | cp_01/ | F | L7 40×24×128→20×12×256，294912 B 权重 | `--test CP-01 --prepare-only` |
| CP-02 | cp_02/ | F | K3 row=204、K1 row=512、L15.split 80×48×192→64 | `--test CP-02 --prepare-only` |
| CP-03 | cp_03/ | S | COUT_BLOCKS=8 | `--test CP-03 --prepare-only` |
| SQ-01 | sq_01/ | S | 依赖链、B 栅栏、延迟可见 | `--test SQ-01 --prepare-only` |
| SQ-02 | sq_02/ | S | 重叠依赖输入的 B 栅栏；记录下一条权重预取 | `--test SQ-02 --prepare-only` |
| SQ-03 | sq_03/ | F | 同一种子，150/125、125/125、100/125 | `--test SQ-03 --prepare-only` |
| ER-01 | er_01/ | S | 第 2 描述符输入读错误、清错、正常重启 | `--test ER-01 --prepare-only` |
| ER-02 | er_02/ | S | 第 2 描述符输出写错误、清错、正常重启 | `--test ER-02 --prepare-only` |
| ER-03 | er_03/ | S | OP 3/15，无数据读写，恢复 | `--test ER-03 --prepare-only` |
| ER-04 | er_04/ | S | row 204/205、512/513，块 8/9，权重 294912/294913 | `--test ER-04 --prepare-only` |
| ER-05 | er_05/ | S | 空闲/权重读/写回中 ABORT、排空、200 拍安静窗口、重启 | `--test ER-05 --prepare-only` |
| NET-01 | net_01/ | F | 真实 68 描述符整网，bw | `--test NET-01 --prepare-only` |
| NET-02 | net_02/ | P | 同一整网 zero/latency/bw；统计和周期模型比较 | `--test NET-02 --prepare-only` |
| NET-03 | net_03/ | S | L0/L7/L15.split/POOL/UPSAMPLE/检测头，6 个单层快照 | `--test NET-03 --prepare-only` |

已实际生成全部 118 个小用例变体；正常用例和错误用例的正常恢复镜像均已执行独立参考模型。
非法描述符仅修改原始字段，不作为正常参考模型输入。
生成日志为 `build/npu/prepare_checks.log`。
真实整网为 68 = 63 CONV + 3 POOL + 2 UPSAMPLE，六个代表层快照也已生成并执行参考模型，
日志为 `build/npu/prepare_net03.log`。这些是数据链路检查，没有执行真实 DUT。
OP 配方覆盖所有 40 种合法 CONV 标志组合（C4 仅 K3/S2）。

## 原始工具命令和文件

准备脚本实际执行以下公共 CLI（具体 JSON 字段见 `tools/npu/README.md`）：

```sh
~/.local/opt/edrv32-py/bin/python tools/npu/gen_case.py \
    --config build/npu/op_01/c16_32/config.json --seed 1 --out build/npu/op_01/c16_32
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/op_01/c16_32
PYTHONPATH="$PWD/third_party/ultralytics" ~/.local/opt/edrv32-py/bin/python \
    tools/npu/compile_yolo.py \
    --image ~/.local/share/edrv32/npu/coco128/images/train2017/000000000009.jpg \
    --out build/npu/yolo
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/yolo
# 第 N 条执行前的完整状态，输出目录必须是新的：
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/yolo \
    --split-at 25 --out build/npu/example_layer
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/example_layer
```

`regs.txt` 写 MODEL_BASE/WORK_BASE/INPUT_BASE/OUTPUT_BASE/DESC_BASE/DESC_COUNT；
`check.txt` 每行名称/绝对字节地址/字节数；所有数值均为十六进制。
参考输出和 `mem_*.hex` 均为 `@绝对beat地址` 加 256 位数据行。
`NET-03` 按描述符形状定位 L0、最大权重 L7、80×48/C192→C64 的 L15.split、
首个 POOL、首个 UPSAMPLE、最后一个检测头 CONV，再调用 `--split-at`。

NET-02 完成真实 RTL 运行后，保存三档日志及 `build/npu/net_02_perf.csv`，
含 PERF[0..15]、门铃到中断周期数、读写拍数、平均带宽、模型周期数、周期偏差。
RTL 周期数以 PERF[0] 为主；存储占用拍数为
`mem_cycles = last_response_cycle − first_request_cycle + 1`（含两端，空事务为 0），
平均带宽为 `(read_beats + write_beats) × 32 × 125 / mem_cycles` MB/s。
估算使用现有 `datapath_model.network` 的 C0+D2+D3b（内部复用 `npu_model.py`），
历史固定计划来自现有 `legacy_plan.analysis`，显式传仓库内 YOLO YAML，
不依赖旧环境绝对路径或旧仿真日志。zero/latency/bw 的模型延迟参数为 0/94/94、
带宽为 4.0/4.0/1.4 GB/s；4.0 对应 125 MHz × 32 B。
该历史估算仍含原 C3 首层、旧流水和延迟口径差异，因此偏差只记录，不作为通过判据。
尚未接入 DUT，不提供 RTL 性能测量结论。

## 协调者确认的契约

2026-10-27 通过本 Dispatch 的 `ask` 确认：

- 顶层 `edrv32_npu`：`clk_npu_i/rst_npu_n_i/clk_mem_i/rst_mem_n_i/irq_o`。
- APB 位于 clk_mem：`apb_paddr_i[11:0]`、`apb_psel_i`、`apb_penable_i`、
  `apb_pwrite_i`、`apb_pwdata_i[31:0]`、`apb_pstrb_i[3:0]`；
  `apb_pready_o`、`apb_prdata_o[31:0]`、`apb_pslverr_o`。
- AXI 位于 clk_mem：`axi_awid_o[0:0]`、`axi_awaddr_o[31:0]`、`axi_awlen_o[3:0]`、
  `axi_awvalid_o/axi_awready_i`；`axi_wdata_o[255:0]`、`axi_wstrb_o[31:0]`、
  `axi_wlast_o/axi_wvalid_o/axi_wready_i`；`axi_bid_i[0:0]`、`axi_bresp_i[1:0]`、
  `axi_bvalid_i/axi_bready_o`；`axi_arid_o[0:0]`、`axi_araddr_o[31:0]`、
  `axi_arlen_o[3:0]`、`axi_arvalid_o/axi_arready_i`；`axi_rid_i[0:0]`、
  `axi_rdata_i[255:0]`、`axi_rresp_i[1:0]`、`axi_rlast_i/axi_rvalid_i/axi_rready_o`。
  无 SIZE/BURST/urgent；irq 为 clk_npu 域电平。
- ID=0x00060001；公共配置、计数器及私有寄存器复位 0，STATUS=2。
  RO 写忽略；CTRL 仅 ENABLE 保持，START 忽略、ABORT/SOFT_RST 读 0；
  DOORBELL 不受 ENABLE 门控。只测试已定义的位，不测试 WO 读值。
- 正常 DONE/IDLE 后 CUR_DESC 保持 DESC_COUNT−1，下一次门铃从 0 开始。
  RG-02 的每层使用 32×8 图以明显长于 APB 轮询时间，检查 0/1/2 均曾出现。
- RG-03 用黑盒窗口 W：DOORBELL APB 写完成到 irq 上升沿的 clk_npu 拍数；
  `W−16 ≤ PERF0 ≤ W`，PERF1≤PERF0，1–7 非零；两次启动检查总周期和读写拍数清零。
- CP-02/ER-04 的可表达边界为 K3 的 row 204/205、K1 的 512/513，
  COUT_BLOCKS 8/9，权重容量 294912/294913；K3 的 5×整数无法恰等于 1024。
- OP-08 用 bias 极值使 acc+bias 跨 32 位，NB 不伪造不可达的原始 INT32 acc 极值；
  后者留给 TL-01 与 result_quant 单元测试。
- ER-05 允许 ABORT 后异步桥既有事务排空；IDLE 时读写在途均 0、无未完成写突发、
  DONE_COUNT 不变，随后 200 个 clk_mem 周期不出现新 AR/AW，再正常启动。
