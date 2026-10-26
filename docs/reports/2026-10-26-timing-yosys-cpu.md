# CPU 与系统子系统 Yosys LUT6 结构测量（2026-10-26）

| 项 | 条件 |
|---|---|
| RTL commit | `10ca733884cb50d151cc4aed145ffcd213b20c3e`；本任务仅新增工具及本报告，未修改 RTL/IP 创建说明 |
| 工具 | OSS CAD Suite；Yosys 0.70+219（5053d0e26，Release，Clang 21.1.8） |
| ABC | UC Berkeley ABC 1.01，compiled Oct 24 2026 05:00:00 |
| Python / 主机 | Python 3.11.6；Linux 6.8.0-147-generic；3 核、8 GB；Yosys/ABC 串行运行 |
| 目标逻辑模型 | PG2L200H 按最多 6 输入 LUT 计；主测量无工艺库、速度等级、布线、IO 延时或时钟周期约束；XC7 代理另见后文 |
| 构建模式 | `FPGA_MODE`；7 种端口黑盒桩来自 `tools/synth/ip_stubs.v`，端口对应 `rtl/tech/` 与 `fpga/ip/*.md` |
| 前一版本对比 | 首份 Yosys LUT6 结构基线，尚无上一版同口径测量 |

## 测量口径

展平流程为 `hierarchy → synth -flatten -noabc → abc -lut 6 -dress → opt_clean → write_json`。
CPU 及包含 CPU 的顶层用生成于各 `build/synth/<对象>/wrapper.v` 的端口直通 wrapper 传递 `RVC_EN`，层次名增加 `u_target`。
这是协调者确认的 Yosys 0.70+219 工具缺陷绕开办法：直接修改目标顶层参数时，`hierarchy` 重处理模块触发 `rtlil_bufnorm.cc:679` 的 `modules_.count(module->name) == 0` 断言。
wrapper 未增加逻辑；`edrv32_sys_subsys` 直接作为顶层。

路径起点为 FF 输出、顶层输入、同步 IP 黑盒输出；终点为 FF 的非时钟输入（D、E、R/S）、顶层输出、黑盒非时钟输入。
每个终点 pin/bit 仅保留最长路径，按级数降序及终点 pin 名排序取前 50；同深度分支选择编号最小的前驱 net。
直方图只列非零分箱，是所有可由起点到达的终点 pin/bit 的最长级数分布，包含控制/复位输入的结构路径；常量终点另计，时钟输入不作为终点。
每个 `$lut` 为 1 级，残留 `$alu`/CARRY 类单元按映射单元为 1 级并另计 carry；本次 generic 各网表均无残留此类单元，算术逻辑已映射进 LUT。
此处未进行路径可敏化、时钟域、时序例外、建立/保持时间或寄生参数分析，级数不是纳秒或 Fmax，也不是 PDS 结果。

扇出按负载 pin/bit 次数计，包括顶层输出；常量、连接 FF 时钟/复位端口的网络及信号末级名称含独立 clk/clock/rst/reset 词干的网络从扇出表排除。
FF 终点优先显示目标寄存器的 RTL Q 信号名；ABC9 已删除原名时保留映射信号/pin 与源跨度，不猜测原寄存器名，并以终点 pin 区分 D/E/R；JSON 另存真实终点 net bit。

部分存储器展开及 FF 映射后的节点也没有 `src`，缺失时保留可用 RTL 名字。ABC 新生成的 LUT cell 没有 `src`；`-dress` 保留部分等价输出网的源属性。
路径源序列使用保留的 cell/output-net `src`，连续相同位置用 `×级数` 压缩，`<ABC:no-src>` 表示没有精确源位置的新节点；不推测缺失的 RTL 行。
源跨度来自 Yosys 原属性（可能是声明、表达式或 always 块），省略列号及 Yosys 自带 techmap 库位置。
展平源分布中的 `<ABC-unattributed>` 只是缺失归属的计数，不代表额外模块。

另以 `synth -noabc`（不加 `-flatten`）并 `abc -lut 6 -dress` 得到保留层次网表，逐实例递归统计模块自己拥有的 LUT/FF，再按模块及源文件汇总。
报告的资源分布表来自该独立综合；跨模块优化边界不同，不能用层次资源总数拆分展平资源总数。
`resources.json` 同时保留每个实例及其原始参数化模块名的直接拥有资源数。

## 复现命令

在包含本任务工具的分支根目录执行，命令按顺序串行运行：

```bash
. ~/.local/opt/edrv32/env.sh
source ~/.local/opt/oss-cad-suite/environment
yosys -V
yosys-abc -c version
python3 --version
python3 tools/synth/yosys_synth.py edrv32_cpu_core --rvc-en 1
python3 tools/synth/yosys_synth.py edrv32_cpu_core --rvc-en 0
python3 tools/synth/yosys_synth.py edrv32_cpu_subsys --rvc-en 1
python3 tools/synth/yosys_synth.py edrv32_sys_subsys
python3 tools/synth/yosys_synth.py edrv32_fpga_cpu_sys_top --rvc-en 1
python3 tools/synth/yosys_synth.py edrv32_cpu_core --rvc-en 1 --hierarchical
python3 tools/synth/yosys_synth.py edrv32_cpu_core --rvc-en 0 --hierarchical
python3 tools/synth/yosys_synth.py edrv32_cpu_subsys --rvc-en 1 --hierarchical
python3 tools/synth/yosys_synth.py edrv32_sys_subsys --hierarchical
python3 tools/synth/yosys_synth.py edrv32_fpga_cpu_sys_top --rvc-en 1 --hierarchical
for netlist in build/synth/*/netlist.json; do
    python3 tools/synth/netlist_paths.py "$netlist"
done
for netlist in build/synth/*/hierarchy.json; do
    python3 tools/synth/netlist_paths.py "$netlist" --hierarchical
done
python3 -m unittest discover -s tools/synth -p 'test_*.py' -v
```

文件列表递归读取 `-f` 与 `+incdir+`，依据目标使用 `cpu.f`、`cpu_subsys.f`（含 `cpu.f` 和 `cache.f`）、`sys_subsys.f`；板级顶层再加入 `fpga/rtl/edrv32_fpga_cpu_sys_top.v`。
读取时保持源文件相对路径；不修改 RTL。所有产物位于 `build/synth/`，不入库。

## 汇总

| 对象 | RVC_EN | 展平 LUT | 展平 FF | 黑盒 | 最大级数 | 层次 LUT | 层次 FF | 层次黑盒 | 展平 LUT 无 src | 展平 FF 无 src |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| edrv32_cpu_core | 1 | 39695 | 8206 | 1 | 62 | 39093 | 8222 | 1 | 18086 | 3692 |
| edrv32_cpu_core | 0 | 34254 | 7774 | 1 | 45 | 31076 | 7884 | 1 | 15859 | 3524 |
| edrv32_cpu_subsys | 1 | 48295 | 9935 | 9 | 69 | 47284 | 9988 | 9 | 21026 | 3692 |
| edrv32_sys_subsys | — | 6849 | 2432 | 2 | 32 | 6583 | 2444 | 2 | 3021 | 283 |
| edrv32_fpga_cpu_sys_top | 1 | 52440 | 11711 | 11 | 68 | 53911 | 12427 | 11 | 21978 | 3975 |

## RVC_EN=1 / 0 对比

| 口径/指标 | RVC=1 | RVC=0 | 差值（1−0） | 差值 / RVC=0 |
|---|---:|---:|---:|---:|
| 展平 LUT | 39695 | 34254 | +5441 | +15.88% |
| 展平 FF | 8206 | 7774 | +432 | +5.56% |
| 展平 blackbox | 1 | 1 | +0 | +0.00% |
| 层次 LUT | 39093 | 31076 | +8017 | +25.80% |
| 层次 FF | 8222 | 7884 | +338 | +4.29% |
| 层次 blackbox | 1 | 1 | +0 | +0.00% |
| 最大级数 | 62 | 45 | +17 | +37.78% |

## CPU 模块资源与旁路逻辑锥

以下为 generic 保留层次综合。寄存器堆是 `edrv32_cpu_regfile` 自有资源；旁路为 `d_operand_w[0..3]` 输出的 LUT 并集，切在 `d_register_w`、`d_source_w`、`e/m/w_result_w` 以及各级 valid/write/rd/class 输入；FF 输出及子模块输出也是边界。旁路逻辑可能与其他功能共享，不是排他的模块面积，不能和模块统计相加。`d_bypass_w` 仅生成 Verilator 仿真观察用的 `trace_bypass_w`，未接顶层硬件输出，已被综合删除；没有为测量添加 keep。完整输出、切点及 LUT cell 名单见 `resources.json` 的 `bypass_cones`。

| 对象 | regfile LUT | regfile FF | regfile / 层次 LUT | 旁路逻辑锥 LUT | 旁路锥 / 层次 LUT |
|---|---:|---:|---:|---:|---:|
| edrv32_cpu_core_rvc1 | 3694 | 992 | 9.45% | 467 | 1.19% |
| edrv32_cpu_core_rvc0 | 3694 | 992 | 11.89% | 467 | 1.50% |
| edrv32_cpu_subsys_rvc1 | 3694 | 992 | 7.81% | 467 | 0.99% |
| edrv32_fpga_cpu_sys_top_rvc1 | 3694 | 992 | 6.85% | 467 | 0.87% |

## 层次资源分布（LUT/FF）

C1/C0=core RVC 1/0；CS=cpu_subsys；SYS=sys_subsys；TOP=板级顶层。每个源文件只有同名模块，模块名为文件名去掉 `.v`；参数变体与重复实例已累计，故合并显示模块/源文件统计。表仅列有 LUT 或 FF 的文件，零逻辑 IP 包装层及逐实例黑盒数见 `resources.json`；“—”表示未实例化。

| 源文件/同名模块 | C1 | C0 | CS | SYS | TOP |
|---|---:|---:|---:|---:|---:|
| `rtl/bus/edrv32_bus_apb_bridge.v` | — | — | — | 242/274 | 242/274 |
| `rtl/bus/edrv32_bus_apb_decoder.v` | — | — | — | 514/16 | 510/16 |
| `rtl/bus/edrv32_bus_rom.v` | — | — | — | 121/38 | 121/38 |
| `rtl/bus/edrv32_bus_sram.v` | — | — | — | 148/42 | 146/42 |
| `rtl/bus/edrv32_bus_sys_xbar.v` | — | — | — | 1403/208 | 1403/208 |
| `rtl/cache/edrv32_cache_ctrl.v` | — | — | 151/166 | — | 151/166 |
| `rtl/cache/edrv32_cache_pma.v` | — | — | 32/0 | — | 32/0 |
| `rtl/cache/edrv32_dcache.v` | — | — | 6088/1108 | — | 6059/1103 |
| `rtl/cache/edrv32_icache.v` | — | — | 2326/492 | — | 2326/492 |
| `rtl/common/edrv32_apb_async_bridge.v` | — | — | — | 11/126 | 11/126 |
| `rtl/common/edrv32_cdc_handshake.v` | — | — | — | 10/90 | 10/90 |
| `rtl/common/edrv32_cdc_sync_bit.v` | — | — | — | 0/82 | 0/82 |
| `rtl/common/edrv32_reset_sync.v` | — | — | — | 0/20 | 0/20 |
| `rtl/cpu/edrv32_cpu_alu.v` | 808/0 | 808/0 | 808/0 | — | 808/0 |
| `rtl/cpu/edrv32_cpu_branch.v` | 41/0 | 41/0 | 41/0 | — | 41/0 |
| `rtl/cpu/edrv32_cpu_core.v` | 2327/1104 | 2317/1104 | 2327/1104 | — | 2327/1104 |
| `rtl/cpu/edrv32_cpu_csr.v` | 3056/853 | 3051/852 | 3056/853 | — | 3056/853 |
| `rtl/cpu/edrv32_cpu_decode.v` | 150/0 | 150/0 | 150/0 | — | 150/0 |
| `rtl/cpu/edrv32_cpu_div.v` | 490/139 | 490/139 | 490/139 | — | 490/139 |
| `rtl/cpu/edrv32_cpu_frontend.v` | 22272/1225 | 14468/888 | 21741/1225 | — | 21831/1225 |
| `rtl/cpu/edrv32_cpu_ib.v` | 1639/723 | 1639/723 | 1639/723 | — | 1639/723 |
| `rtl/cpu/edrv32_cpu_mul.v` | 35/4 | 35/4 | 35/4 | — | 35/4 |
| `rtl/cpu/edrv32_cpu_predictor.v` | 4383/3182 | 4383/3182 | 4508/3182 | — | 4509/3182 |
| `rtl/cpu/edrv32_cpu_regfile.v` | 3694/992 | 3694/992 | 3694/992 | — | 3694/992 |
| `rtl/cpu/edrv32_cpu_rvc.v` | 198/0 | — | 198/0 | — | 198/0 |
| `rtl/periph/edrv32_periph_clint.v` | — | — | — | 564/260 | 563/260 |
| `rtl/periph/edrv32_periph_gpio.v` | — | — | — | 1946/520 | 1945/520 |
| `rtl/periph/edrv32_periph_i2c.v` | — | — | — | 199/73 | 199/73 |
| `rtl/periph/edrv32_periph_plic.v` | — | — | — | 504/192 | 494/192 |
| `rtl/periph/edrv32_periph_sysctrl.v` | — | — | — | 97/99 | 97/99 |
| `rtl/periph/edrv32_periph_uart.v` | — | — | — | 803/397 | 803/397 |
| `rtl/soc/edrv32_soc_reset_ctrl.v` | — | — | — | 21/7 | 21/7 |

## Frontend 保留源跨度计数

对 generic 层次网表，统计 LUT cell 或其等价输出 net 的 `src` 跨度覆盖 frontend 第 231/267/382 行的 LUT，并集去重。它是源属性归属计数，不能当作排他面积；未保留 src 的节点未计入，0 不表示该语句没有逻辑。

| 对象 | frontend LUT | 有 frontend src | L231 | L267 | L382 | 并集 | 并集占比 |
|---|---:|---:|---:|---:|---:|---:|---:|
| C1 | 22272 | 13606 | 9163 | 0 | 2841 | 12004 | 53.90% |
| C0 | 14468 | 8788 | 6931 | 0 | 780 | 7711 | 53.30% |
| CS | 21741 | 15358 | 10659 | 0 | 2886 | 13545 | 62.30% |
| TOP | 21831 | 15417 | 10692 | 0 | 2886 | 13578 | 62.20% |

## XC7 代理

命令按顺序执行：

```bash
python3 tools/synth/yosys_synth.py edrv32_cpu_core --rvc-en 1 --xc7
python3 tools/synth/netlist_paths.py build/synth/edrv32_cpu_core_rvc1/xc7.json
python3 tools/synth/yosys_synth.py edrv32_cpu_subsys --rvc-en 1 --xc7
python3 tools/synth/netlist_paths.py build/synth/edrv32_cpu_subsys_rvc1/xc7.json
```

代理执行 `synth_xilinx -family xc7 -flatten -noiopad -noclkbuf -nobram`，采用 Xilinx 7 系列库，保留默认 LUTRAM/SRL/DSP 推断；不是 PG2L 物理资源或延时结果。LUT/CARRY4/MUX/INV/未注册 DSP 各计 1 级；CARRY4 按实际 O/CO 位的 CI/CYINIT、S/DI 前缀建边。LUTRAM 地址→数据计 1 级，写数据/使能/写地址是终点，无写数据→读数据组合边；内部存储状态用负编号虚拟起点，经读选择到输出计 1 级。SRL 同样区分存储写入和异步读选择。

LUTRAM/SRL 按 primitive 数计（一个 RAM32M 计 1 个，不折算 LUT6），内部位不计 FF；generic 则将 RTL 存储全展开，因此两种口径的资源差异也包含存储映射。DSP 的 *REG 参数非零时直接报不支持，避免把内部 FF 当组合逻辑。

| 对象 | LUT | FF | CARRY4 | MUX | INV | DSP | LUTRAM | SRL | IP | 最深级数 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| edrv32_cpu_core | 47648 | 6219 | 412 | 12 | 221 | 6 | 13 | 0 | 1 | 62 |
| edrv32_cpu_subsys | 52290 | 7948 | 466 | 25 | 322 | 9 | 13 | 0 | 9 | 63 |

LUTRAM 对应数组，名称取自网表 cell 名；声明位置按该 RTL commit 核对，不能替代缺失的 Yosys src。

| RTL 数组声明 | core | cpu_subsys |
|---|---:|---:|
| `btb_tag_r` (cpu_predictor.v:45) | 4 | 4 |
| `btb_target_r` (cpu_predictor.v:46) | 6 | 6 |
| `btb_position_r` (cpu_predictor.v:47) | 1 | 1 |
| `btb_type_r` (cpu_predictor.v:48) | 1 | 1 |
| `btb_compressed_r` (cpu_predictor.v:49) | 1 | 1 |
| `direction_r` (cpu_predictor.v:50) | 0 | 0 |
| `registers_r` (cpu_regfile.v:26) | 0 | 0 |

## 路径、直方图与扇出

各表为前 20 条。实例简称：省略 wrapper 的 `u_target`；CPU/SYS=`u_cpu_subsys/u_sys_subsys`，C/F/BP/IB/CSR/DC/IC/PLIC/CLINT 分别为 `u_core/u_frontend/u_predictor/u_ib/u_csr/u_dcache/u_icache/u_plic/u_clint`，其他实例名保留。源位置用同名文件基本名（省略 `edrv32_` 和 `.v`）:行，完整路径见资源表及 JSON；`?`=没有精确 src。

每组 S/E/R 只在本组有效；源序仅给前 2 段及省略段/级数，完整 50 条和逐级 cell/net 在原始输出。`FFn` 是精确映射 cell `$auto$ff.cc:337:slice$n` 的简称（标量端口省略 `[0]`）；n 开头的扇出编号为 JSON net bit（没有保留公开 RTL 名），原始输出保留其完整映射名。XC7 分项 L/C/M/I/D/R=LUT/CARRY4/MUX/INV/DSP/存储读选择，通用流程级数全为 LUT。

### C1：edrv32_cpu_core，RVC=1

原始目录：`build/synth/edrv32_cpu_core_rvc1/`；终点 19169，常量终点 6。

直方图（级数:终点数）：

```text
0:3437, 1:12, 2:285, 3:140, 4:1737, 5:496, 6:163, 7:148, 8:207
9:469, 10:79, 11:588, 12:75, 13:75, 14:76, 15:654, 16:472, 17:264
18:677, 19:3018, 25:1, 26:1, 30:11, 31:19, 32:34, 33:108, 34:23
35:581, 36:137, 37:6, 38:4, 39:4, 40:16, 41:9, 42:51, 43:29
49:1054, 50:537, 51:36, 52:990, 53:922, 54:566, 55:172, 56:332, 57:56
58:209, 59:38, 60:56, 61:47, 62:48
```

起点：S1=`e_operand_a_r[0][0]`@cpu_core:672-742 (FF)。

下表 RTL 终点的公共实例前缀为 `CSR`；终点源位置：E1=cpu_csr:131-195。

| # | 起点 | 终点@源 | 级数 | 源序 |
|---:|---|---|---:|---|
| 1 | S1 | counter_r[7][58]/D@E1 | 62 | R1 |
| 2 | S1 | counter_r[7][59]/D@E1 | 62 | R1 |
| 3 | S1 | counter_r[7][60]/D@E1 | 62 | R1 |
| 4 | S1 | counter_r[7][61]/D@E1 | 62 | R1 |
| 5 | S1 | counter_r[7][62]/D@E1 | 62 | R1 |
| 6 | S1 | counter_r[7][63]/D@E1 | 62 | R1 |
| 7 | S1 | counter_r[6][58]/D@E1 | 62 | R1 |
| 8 | S1 | counter_r[6][59]/D@E1 | 62 | R1 |
| 9 | S1 | counter_r[6][60]/D@E1 | 62 | R1 |
| 10 | S1 | counter_r[6][61]/D@E1 | 62 | R1 |
| 11 | S1 | counter_r[6][62]/D@E1 | 62 | R1 |
| 12 | S1 | counter_r[6][63]/D@E1 | 62 | R1 |
| 13 | S1 | counter_r[5][58]/D@E1 | 62 | R1 |
| 14 | S1 | counter_r[5][59]/D@E1 | 62 | R1 |
| 15 | S1 | counter_r[5][60]/D@E1 | 62 | R1 |
| 16 | S1 | counter_r[5][61]/D@E1 | 62 | R1 |
| 17 | S1 | counter_r[5][62]/D@E1 | 62 | R1 |
| 18 | S1 | counter_r[5][63]/D@E1 | 62 | R1 |
| 19 | S1 | counter_r[4][58]/D@E1 | 62 | R1 |
| 20 | S1 | counter_r[4][59]/D@E1 | 62 | R1 |

源序前 2 段（末尾为省略段数/级数）：

- R1: cpu_core:593×15 → cpu_core:141×1 …(+29段/46级)

| # | 扇出驱动 RTL 信号/映射 bit | 源位置 | 负载 pin/bit |
|---:|---|---|---:|
| 1 | F.consume_w[1] | cpu_frontend:111 | 2054 |
| 2 | F.consume_w[0] | cpu_frontend:111 | 1993 |
| 3 | n27770 | ? | 1512 |
| 4 | n27791 | ? | 1225 |
| 5 | n9916 | ? | 1215 |
| 6 | n22613 | cpu_predictor:96-97 | 1045 |
| 7 | n27730 | ? | 1040 |
| 8 | n22612 | ? | 1024 |
| 9 | n22616 | cpu_predictor:96-97 | 1023 |
| 10 | F.f1_pc_r[3] | cpu_frontend:342-379 | 1009 |
| 11 | n9965 | ? | 961 |
| 12 | n10085 | ? | 945 |
| 13 | n9963 | ? | 866 |
| 14 | n481 | cpu_core:420-421 | 835 |
| 15 | n10091 | ? | 798 |
| 16 | n38546 | ? | 751 |
| 17 | n38540 | ? | 744 |
| 18 | n10273 | ? | 737 |
| 19 | n38523 | ? | 728 |
| 20 | n29418 | ? | 676 |

### C0：edrv32_cpu_core，RVC=0

原始目录：`build/synth/edrv32_cpu_core_rvc0/`；终点 18304，常量终点 6。

直方图（级数:终点数）：

```text
0:3383, 1:11, 2:268, 3:1159, 4:1036, 5:106, 6:140, 7:248, 8:195
9:762, 10:269, 11:170, 12:77, 13:115, 14:399, 15:327, 16:362, 17:230
18:678, 19:2990, 20:5, 21:4, 22:6, 23:4, 24:34, 26:3, 28:2
29:851, 30:19, 31:496, 32:16, 33:79, 34:39, 35:601, 36:226, 37:122
38:1339, 39:720, 40:420, 41:91, 42:142, 43:68, 44:91, 45:1
```

起点：S1=`m_class_r[0][2]`@cpu_core:672-742 (FF)。

下表 RTL 终点的公共实例前缀为 `CSR`；终点源位置：E1=cpu_csr:131-195。

| # | 起点 | 终点@源 | 级数 | 源序 |
|---:|---|---|---:|---|
| 1 | S1 | counter_r[7][4]/D@E1 | 45 | R1 |
| 2 | S1 | counter_r[7][32]/D@E1 | 44 | R2 |
| 3 | S1 | counter_r[7][33]/D@E1 | 44 | R2 |
| 4 | S1 | counter_r[7][35]/D@E1 | 44 | R2 |
| 5 | S1 | counter_r[7][36]/D@E1 | 44 | R2 |
| 6 | S1 | counter_r[7][0]/D@E1 | 44 | R2 |
| 7 | S1 | counter_r[7][1]/D@E1 | 44 | R2 |
| 8 | S1 | counter_r[7][3]/D@E1 | 44 | R2 |
| 9 | S1 | counter_r[6][32]/D@E1 | 44 | R2 |
| 10 | S1 | counter_r[6][33]/D@E1 | 44 | R2 |
| 11 | S1 | counter_r[6][35]/D@E1 | 44 | R2 |
| 12 | S1 | counter_r[6][36]/D@E1 | 44 | R2 |
| 13 | S1 | counter_r[6][0]/D@E1 | 44 | R2 |
| 14 | S1 | counter_r[6][1]/D@E1 | 44 | R2 |
| 15 | S1 | counter_r[6][3]/D@E1 | 44 | R2 |
| 16 | S1 | counter_r[6][4]/D@E1 | 44 | R2 |
| 17 | S1 | counter_r[5][32]/D@E1 | 44 | R2 |
| 18 | S1 | counter_r[5][33]/D@E1 | 44 | R2 |
| 19 | S1 | counter_r[5][35]/D@E1 | 44 | R2 |
| 20 | S1 | counter_r[5][36]/D@E1 | 44 | R2 |

源序前 2 段（末尾为省略段数/级数）：

- R1: ?×2 → cpu_core:199×1 …(+12段/42级)
- R2: ?×2 → cpu_core:199×1 …(+11段/41级)

| # | 扇出驱动 RTL 信号/映射 bit | 源位置 | 负载 pin/bit |
|---:|---|---|---:|
| 1 | F.IB.push_count_i[0] | cpu_ib:11 | 1360 |
| 2 | F.IB.flush_i | cpu_ib:19 | 1123 |
| 3 | n16003 | ? | 1063 |
| 4 | n12642 | ? | 1060 |
| 5 | n31652 | ? | 1024 |
| 6 | n31655 | cpu_predictor:96-97 | 1023 |
| 7 | n16348 | ? | 1016 |
| 8 | n16010 | ? | 973 |
| 9 | n16012 | ? | 956 |
| 10 | n16005 | ? | 942 |
| 11 | n16087 | ? | 936 |
| 12 | n13191 | ? | 797 |
| 13 | n15986 | ? | 736 |
| 14 | n16112 | ? | 729 |
| 15 | n13222 | ? | 725 |
| 16 | n16007 | ? | 722 |
| 17 | n15991 | ? | 700 |
| 18 | n16017 | ? | 698 |
| 19 | n31666 | cpu_predictor:96-97 | 685 |
| 20 | n16091 | ? | 647 |

### CS：edrv32_cpu_subsys，RVC=1

原始目录：`build/synth/edrv32_cpu_subsys_rvc1/`；终点 23872，常量终点 49。

直方图（级数:终点数）：

```text
0:5247, 1:37, 2:504, 3:1273, 4:1235, 5:300, 6:171, 7:328, 8:332
9:189, 10:636, 11:635, 12:105, 13:685, 14:296, 15:72, 16:10, 17:7
18:106, 19:4, 20:1, 21:166, 22:337, 23:184, 24:672, 25:2, 27:3
28:70, 29:402, 30:146, 31:20, 32:3087, 33:61, 34:288, 35:203, 36:256
37:86, 38:3, 39:7, 40:4, 41:18, 42:41, 43:51, 44:29, 45:2
46:483, 47:4, 48:5, 57:2, 59:1560, 60:211, 61:545, 62:789, 63:303
64:487, 65:319, 66:184, 67:280, 68:223, 69:166
```

起点：S1=`DC.addr_r[5]`@dcache:339-383 (FF)。

下表 RTL 终点的公共实例前缀为 `C.CSR`；终点源位置：E1=cpu_csr:131-195。

| # | 起点 | 终点@源 | 级数 | 源序 |
|---:|---|---|---:|---|
| 1 | S1 | counter_r[4][34]/D@E1 | 69 | R1 |
| 2 | S1 | counter_r[4][36]/D@E1 | 69 | R1 |
| 3 | S1 | counter_r[4][37]/D@E1 | 69 | R1 |
| 4 | S1 | counter_r[4][38]/D@E1 | 69 | R1 |
| 5 | S1 | counter_r[4][39]/D@E1 | 69 | R1 |
| 6 | S1 | counter_r[4][40]/D@E1 | 69 | R1 |
| 7 | S1 | counter_r[4][41]/D@E1 | 69 | R1 |
| 8 | S1 | counter_r[4][42]/D@E1 | 69 | R1 |
| 9 | S1 | counter_r[4][45]/D@E1 | 69 | R1 |
| 10 | S1 | counter_r[4][49]/D@E1 | 69 | R1 |
| 11 | S1 | counter_r[4][51]/D@E1 | 69 | R1 |
| 12 | S1 | counter_r[4][52]/D@E1 | 69 | R1 |
| 13 | S1 | counter_r[4][53]/D@E1 | 69 | R1 |
| 14 | S1 | counter_r[4][57]/D@E1 | 69 | R1 |
| 15 | S1 | counter_r[4][58]/D@E1 | 69 | R1 |
| 16 | S1 | counter_r[4][59]/D@E1 | 69 | R1 |
| 17 | S1 | counter_r[4][60]/D@E1 | 69 | R1 |
| 18 | S1 | counter_r[4][61]/D@E1 | 69 | R1 |
| 19 | S1 | counter_r[4][62]/D@E1 | 69 | R1 |
| 20 | S1 | counter_r[4][63]/D@E1 | 69 | R1 |

源序前 2 段（末尾为省略段数/级数）：

- R1: dcache:191×1 → ?×4 …(+57段/64级)

| # | 扇出驱动 RTL 信号/映射 bit | 源位置 | 负载 pin/bit |
|---:|---|---|---:|
| 1 | C.F.consume_w[0] | cpu_frontend:111 | 2047 |
| 2 | C.F.consume_w[1] | cpu_frontend:111 | 1923 |
| 3 | n26539 | ? | 1257 |
| 4 | n25881 | ? | 1174 |
| 5 | n41997 | ? | 1040 |
| 6 | n20844 | ? | 1024 |
| 7 | n20847 | cpu_predictor:99-100 | 1023 |
| 8 | n45383 | ? | 997 |
| 9 | n28187 | ? | 968 |
| 10 | n25999 | ? | 945 |
| 11 | n28234 | ? | 874 |
| 12 | n28439 | ? | 857 |
| 13 | n28188 | ? | 854 |
| 14 | n28235 | ? | 835 |
| 15 | n31902 | ? | 789 |
| 16 | n28440 | ? | 771 |
| 17 | n31830 | ? | 760 |
| 18 | n51162 | ? | 743 |
| 19 | n31908 | ? | 717 |
| 20 | n25912 | ? | 697 |

### SYS：edrv32_sys_subsys，RVC=—

原始目录：`build/synth/edrv32_sys_subsys/`；终点 6390，常量终点 18。

直方图（级数:终点数）：

```text
0:2754, 1:341, 2:311, 3:216, 4:423, 5:325, 6:200, 7:469, 8:396
9:397, 10:108, 11:379, 12:12, 13:9, 14:2, 15:3, 29:5, 30:5
31:29, 32:6
```

起点：S1=`PLIC.threshold_r[2]`@periph_plic:190-228 (FF)。

下表 RTL 终点的公共实例前缀为 `PLIC`；终点源位置：E1=periph_plic:190-228。

| # | 起点 | 终点@源 | 级数 | 源序 |
|---:|---|---|---:|---|
| 1 | S1 | pending_r[1]/D@E1 | 32 | R1 |
| 2 | S1 | pending_r[1]/E@E1 | 32 | R2 |
| 3 | S1 | pending_r[2]/D@E1 | 32 | R1 |
| 4 | S1 | pending_r[2]/E@E1 | 32 | R2 |
| 5 | S1 | claimed_r[1]/D@E1 | 32 | R1 |
| 6 | S1 | claimed_r[2]/D@E1 | 32 | R1 |
| 7 | S1 | pending_r[5]/D@E1 | 31 | R3 |
| 8 | S1 | pending_r[5]/E@E1 | 31 | R4 |
| 9 | S1 | pending_r[6]/D@E1 | 31 | R3 |
| 10 | S1 | pending_r[6]/E@E1 | 31 | R4 |
| 11 | S1 | pending_r[8]/D@E1 | 31 | R3 |
| 12 | S1 | pending_r[8]/E@E1 | 31 | R4 |
| 13 | S1 | pending_r[9]/D@E1 | 31 | R3 |
| 14 | S1 | pending_r[9]/E@E1 | 31 | R4 |
| 15 | S1 | pending_r[10]/D@E1 | 31 | R3 |
| 16 | S1 | pending_r[10]/E@E1 | 31 | R4 |
| 17 | S1 | pending_r[11]/D@E1 | 31 | R5 |
| 18 | S1 | pending_r[11]/E@E1 | 31 | R6 |
| 19 | S1 | pending_r[12]/D@E1 | 31 | R3 |
| 20 | S1 | pending_r[12]/E@E1 | 31 | R4 |

源序前 2 段（末尾为省略段数/级数）：

- R1: periph_plic:167×1 → ?×1 …(+25段/30级)
- R2: periph_plic:167×1 → ?×1 …(+24段/30级)
- R3: periph_plic:167×1 → ?×1 …(+25段/29级)
- R4: periph_plic:167×1 → ?×1 …(+24段/29级)
- R5: periph_plic:167×1 → ?×1 …(+23段/29级)
- R6: periph_plic:167×1 → ?×1 …(+22段/29级)

| # | 扇出驱动 RTL 信号/映射 bit | 源位置 | 负载 pin/bit |
|---:|---|---|---:|
| 1 | u_media_apb_async.request_r[49] | apb_async_bridge:122-129 | 169 |
| 2 | u_media_apb_async.request_r[48] | apb_async_bridge:122-129 | 163 |
| 3 | CLINT.read_accept_w | periph_clint:65 | 79 |
| 4 | n1863 | ? | 77 |
| 5 | n2436 | ? | 77 |
| 6 | n3663 | ? | 77 |
| 7 | n1965 | ? | 74 |
| 8 | n2100 | ? | 74 |
| 9 | u_media_apb_async.request_r[51] | apb_async_bridge:122-129 | 73 |
| 10 | n2103 | ? | 69 |
| 11 | n2112 | ? | 69 |
| 12 | n1632 | ? | 68 |
| 13 | n1634 | ? | 68 |
| 14 | n1756 | ? | 68 |
| 15 | n1761 | ? | 68 |
| 16 | n4814 | ? | 68 |
| 17 | n4870 | ? | 68 |
| 18 | n8169 | ? | 64 |
| 19 | n8340 | ? | 64 |
| 20 | u_sys_xbar.aw_fire_w | bus_sys_xbar:383 | 61 |

### TOP：edrv32_fpga_cpu_sys_top，RVC=1

原始目录：`build/synth/edrv32_fpga_cpu_sys_top_rvc1/`；终点 27971，常量终点 12。

直方图（级数:终点数）：

```text
0:6621, 1:53, 2:429, 3:1422, 4:1214, 5:621, 6:824, 7:953, 8:709
9:876, 10:819, 11:943, 12:411, 13:175, 14:107, 15:72, 16:11, 17:110
18:7, 19:1, 20:134, 21:304, 22:184, 23:672, 24:2, 25:2, 26:1
27:70, 28:370, 29:146, 30:5, 31:3095, 32:9, 33:88, 34:398, 35:69
36:152, 37:185, 38:2, 39:4, 40:5, 41:48, 42:11, 43:51, 44:512
45:5, 46:3, 56:2, 58:1553, 59:216, 60:811, 61:469, 62:675, 63:483
64:342, 65:41, 66:218, 67:75, 68:181
```

起点：S1=`CPU.DC.addr_r[5]`@dcache:339-383 (FF)。

下表 RTL 终点的公共实例前缀为 `CPU.C.CSR`；终点源位置：E1=cpu_csr:131-195。

| # | 起点 | 终点@源 | 级数 | 源序 |
|---:|---|---|---:|---|
| 1 | S1 | counter_r[7][34]/D@E1 | 68 | R1 |
| 2 | S1 | counter_r[7][36]/D@E1 | 68 | R1 |
| 3 | S1 | counter_r[7][37]/D@E1 | 68 | R1 |
| 4 | S1 | counter_r[7][38]/D@E1 | 68 | R1 |
| 5 | S1 | counter_r[7][39]/D@E1 | 68 | R1 |
| 6 | S1 | counter_r[7][40]/D@E1 | 68 | R1 |
| 7 | S1 | counter_r[7][41]/D@E1 | 68 | R1 |
| 8 | S1 | counter_r[7][42]/D@E1 | 68 | R1 |
| 9 | S1 | counter_r[7][45]/D@E1 | 68 | R1 |
| 10 | S1 | counter_r[7][49]/D@E1 | 68 | R1 |
| 11 | S1 | counter_r[7][51]/D@E1 | 68 | R1 |
| 12 | S1 | counter_r[7][52]/D@E1 | 68 | R1 |
| 13 | S1 | counter_r[7][53]/D@E1 | 68 | R1 |
| 14 | S1 | counter_r[7][54]/D@E1 | 68 | R1 |
| 15 | S1 | counter_r[7][55]/D@E1 | 68 | R1 |
| 16 | S1 | counter_r[7][56]/D@E1 | 68 | R1 |
| 17 | S1 | counter_r[7][57]/D@E1 | 68 | R1 |
| 18 | S1 | counter_r[7][58]/D@E1 | 68 | R1 |
| 19 | S1 | counter_r[7][59]/D@E1 | 68 | R1 |
| 20 | S1 | counter_r[7][60]/D@E1 | 68 | R1 |

源序前 2 段（末尾为省略段数/级数）：

- R1: dcache:191×1 → ?×3 …(+57段/64级)

| # | 扇出驱动 RTL 信号/映射 bit | 源位置 | 负载 pin/bit |
|---:|---|---|---:|
| 1 | CPU.C.F.consume_w[0] | cpu_frontend:111 | 2048 |
| 2 | CPU.C.F.consume_w[1] | cpu_frontend:111 | 1910 |
| 3 | n28335 | ? | 1209 |
| 4 | n28880 | ? | 1149 |
| 5 | n44336 | ? | 1040 |
| 6 | n47948 | ? | 1024 |
| 7 | n47951 | cpu_predictor:96-97 | 1023 |
| 8 | n28216 | ? | 1018 |
| 9 | n30577 | ? | 906 |
| 10 | n30624 | ? | 905 |
| 11 | n30625 | ? | 848 |
| 12 | n30829 | ? | 840 |
| 13 | n34291 | ? | 786 |
| 14 | n34305 | ? | 777 |
| 15 | n30578 | ? | 743 |
| 16 | n55636 | ? | 718 |
| 17 | n28248 | ? | 711 |
| 18 | n30830 | ? | 703 |
| 19 | n34315 | ? | 699 |
| 20 | n47962 | cpu_predictor:96-97 | 685 |

### XC7：edrv32_cpu_core

原始目录：`build/synth/edrv32_cpu_core_rvc1/`；终点 14761，常量终点 4292。

直方图（级数:终点数）：

```text
0:608, 1:2254, 2:6, 3:82, 4:2068, 5:19, 6:101, 7:48, 8:44
9:390, 10:261, 11:852, 12:443, 13:1040, 14:31, 15:22, 16:866, 17:45
18:476, 19:111, 20:180, 21:69, 22:8, 23:4, 28:8, 38:850, 39:555
40:883, 41:377, 42:139, 43:83, 44:224, 45:257, 46:643, 47:233, 48:61
49:32, 50:32, 51:32, 52:32, 53:32, 54:32, 55:32, 56:32, 57:32
58:32, 59:32, 60:32, 61:32, 62:4
```

起点：S1=`e_operand_a_r[0][0]`@cpu_core:672-742 (FF)。

终点源位置：E1=cpu_csr:131-195。

| # | 起点 | 终点@源 | 级数 | 源序 |
|---:|---|---|---:|---|
| 1 | S1 | FF13348.D@E1 | 62(38L+24C) | R1 |
| 2 | S1 | FF13349.D@E1 | 62(38L+24C) | R1 |
| 3 | S1 | FF13350.D@E1 | 62(38L+24C) | R1 |
| 4 | S1 | FF13351.D@E1 | 62(38L+24C) | R1 |
| 5 | S1 | FF12722.D@E1 | 61(37L+24C) | R2 |
| 6 | S1 | FF12723.D@E1 | 61(37L+24C) | R2 |
| 7 | S1 | FF12724.D@E1 | 61(37L+24C) | R2 |
| 8 | S1 | FF12725.D@E1 | 61(37L+24C) | R2 |
| 9 | S1 | FF12803.D@E1 | 61(37L+24C) | R2 |
| 10 | S1 | FF12804.D@E1 | 61(37L+24C) | R2 |
| 11 | S1 | FF12805.D@E1 | 61(37L+24C) | R2 |
| 12 | S1 | FF12806.D@E1 | 61(37L+24C) | R2 |
| 13 | S1 | FF12891.D@E1 | 61(37L+24C) | R2 |
| 14 | S1 | FF12892.D@E1 | 61(37L+24C) | R2 |
| 15 | S1 | FF12893.D@E1 | 61(37L+24C) | R2 |
| 16 | S1 | FF12894.D@E1 | 61(37L+24C) | R2 |
| 17 | S1 | FF13056.D@E1 | 61(37L+24C) | R2 |
| 18 | S1 | FF13057.D@E1 | 61(37L+24C) | R2 |
| 19 | S1 | FF13058.D@E1 | 61(37L+24C) | R2 |
| 20 | S1 | FF13059.D@E1 | 61(37L+24C) | R2 |

源序前 2 段（末尾为省略段数/级数）：

- R1: ?×1 → cpu_core:593×8 …(+7段/53级)
- R2: ?×1 → cpu_core:593×8 …(+7段/52级)

| # | 扇出驱动 RTL 信号/映射 bit | 源位置 | 负载 pin/bit |
|---:|---|---|---:|
| 1 | n12162 | cpu_frontend:267 | 2187 |
| 2 | n11741 | cpu_frontend:267 | 2087 |
| 3 | n1156 | cpu_frontend:382 | 1442 |
| 4 | n740 | cpu_frontend:382 | 1415 |
| 5 | n1221 | cpu_frontend:382 | 1351 |
| 6 | n7150 | cpu_frontend:382 | 1254 |
| 7 | n7121 | cpu_frontend:382 | 1219 |
| 8 | n7100 | cpu_frontend:382 | 1140 |
| 9 | n7107 | cpu_frontend:382 | 1100 |
| 10 | n362 | ? | 1058 |
| 11 | n7099 | cpu_frontend:382 | 1044 |
| 12 | n11748 | cpu_frontend:267 | 1036 |
| 13 | n3233 | ? | 1024 |
| 14 | n21375 | ? | 973 |
| 15 | n21447 | ? | 950 |
| 16 | n16630 | cpu_frontend:267 | 791 |
| 17 | n21703 | ? | 721 |
| 18 | n16654 | cpu_frontend:267 | 672 |
| 19 | n27753 | ? | 634 |
| 20 | n11771 | cpu_frontend:267 | 618 |

### XC7：edrv32_cpu_subsys

原始目录：`build/synth/edrv32_cpu_subsys_rvc1/`；终点 18878，常量终点 6013。

直方图（级数:终点数）：

```text
0:1254, 1:3594, 2:141, 3:348, 4:1837, 5:49, 6:109, 7:383, 8:504
9:82, 10:397, 11:800, 12:368, 13:314, 14:343, 15:993, 16:190, 17:1545
18:103, 19:633, 20:224, 21:14, 22:4, 23:4, 33:8, 41:789, 42:1036
43:387, 44:498, 45:84, 46:172, 47:216, 48:750, 49:128, 50:37, 51:124
52:64, 53:32, 54:32, 55:32, 56:32, 57:32, 58:32, 59:32, 60:32
61:32, 62:32, 63:32
```

起点：S1=`FF124732.Q`@cpu_frontend:342-379 (FF)。

终点源位置：E1=cpu_csr:131-195。

| # | 起点 | 终点@源 | 级数 | 源序 |
|---:|---|---|---:|---|
| 1 | S1 | FF25580.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 2 | S1 | FF25581.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 3 | S1 | FF25582.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 4 | S1 | FF25583.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 5 | S1 | FF28558.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 6 | S1 | FF28559.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 7 | S1 | FF28560.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 8 | S1 | FF28561.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 9 | S1 | FF28639.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 10 | S1 | FF28640.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 11 | S1 | FF28641.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 12 | S1 | FF28642.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 13 | S1 | FF28720.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 14 | S1 | FF28721.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 15 | S1 | FF28722.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 16 | S1 | FF28723.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 17 | S1 | FF28801.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 18 | S1 | FF28802.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 19 | S1 | FF28803.D@E1 | 63(32L+27C+3I+1D) | R1 |
| 20 | S1 | FF28804.D@E1 | 63(32L+27C+3I+1D) | R1 |

源序前 2 段（末尾为省略段数/级数）：

- R1: ?×1 → cpu_frontend:229×2 …(+8段/60级)

| # | 扇出驱动 RTL 信号/映射 bit | 源位置 | 负载 pin/bit |
|---:|---|---|---:|
| 1 | n17005 | cpu_frontend:250 | 2190 |
| 2 | n6255 | cpu_frontend:250 | 2087 |
| 3 | n776 | cpu_frontend:382 | 1461 |
| 4 | n1655 | cpu_frontend:382 | 1388 |
| 5 | n1698 | cpu_frontend:382 | 1278 |
| 6 | n7147 | cpu_frontend:382 | 1227 |
| 7 | n7062 | cpu_frontend:382 | 1172 |
| 8 | n7032 | cpu_frontend:382 | 1156 |
| 9 | n7046 | cpu_frontend:382 | 1081 |
| 10 | n7037 | cpu_frontend:382 | 1043 |
| 11 | n6266 | cpu_frontend:267 | 1038 |
| 12 | n2395 | ? | 1024 |
| 13 | n767 | ? | 1012 |
| 14 | n22699 | cpu_frontend:250 | 836 |
| 15 | n22786 | cpu_frontend:250 | 714 |
| 16 | n34445 | ? | 711 |
| 17 | n34660 | ? | 633 |
| 18 | n34955 | ? | 628 |
| 19 | n6278 | cpu_frontend:267 | 619 |
| 20 | n34814 | ? | 612 |

## 观察


XC7 core 的 6 个纯组合 DSP48E1，保留 src 对应 frontend.v:231（4 个）、267（1 个）、382（1 个）：均为变量索引乘 `HALFWORD_BITS` 的位选/移位，包括 `merged_w[append_slot * HALFWORD_BITS +: HALFWORD_BITS]`、预测信息上半条可变位选及 `merged_w >> (consume_w * HALFWORD_BITS)`。数据及控制注册参数均为 0；与 `ip_mul_s33x33` 黑盒分别计数。

CS 的 9 个组合 DSP 的保留 src 为 frontend.v:231（7 个）、250（1 个）、382（1 个）。C1 的 generic frontend 中，覆盖 L231/267/382 的保留源跨度 LUT 并集为 12004/22272（53.90%），按前述归属规则计数。

- C1: 最深 62 级，`e_operand_a_r[0][0]` → `CSR.counter_r[7][58]`；最大非时钟/复位扇出 2054。
- C0: 最深 45 级，`m_class_r[0][2]` → `CSR.counter_r[7][4]`；最大非时钟/复位扇出 1360。
- CS: 最深 69 级，`DC.addr_r[5]` → `C.CSR.counter_r[4][34]`；最大非时钟/复位扇出 2047。
- SYS: 最深 32 级，`PLIC.threshold_r[2]` → `PLIC.pending_r[1]`；最大非时钟/复位扇出 169。
- TOP: 最深 68 级，`CPU.DC.addr_r[5]` → `CPU.C.CSR.counter_r[7][34]`；最大非时钟/复位扇出 2048。

## 原始输出与验证

每个 `build/synth/<top>[_rvc0或_rvc1]/` 内：`netlist.ys/.log/.json` 为展平流程；`paths.json/paths.md` 为全直方图、最深 50 条路径（完整源序与逐级 cell/net）、最大扇出 50 条及保留 src 的资源归属；`hierarchy.ys/.log/.json` 与 `resources.json/resources.md` 为独立层次综合、模块/源文件与逐实例资源、旁路锥及 frontend 源跨度计数。两个代理对象另有 `xc7.ys/.log/.json` 和 `xc7_paths.json/xc7_paths.md`；`version.txt/commit.txt` 记录版本/运行提交，有 CPU 的目录另有 `wrapper.v`。这些产物均不入库，以上命令重新生成。

`python3 -m unittest discover -s tools/synth -p "test_*.py" -v`：9 项通过，覆盖已知 LUT 链/扇出、FF/IP 边界、carry/缺失 src、层次实例、旁路并集、XC7 单元、LUTRAM 读写边界、INV、DSP 与注册 DSP 明确失败、源跨度并集；日志 `build/synth/unit-tests.log`。

`python3 tools/check/verilog_style.py rtl/`：47 文件、0 告警（`build/synth/style.log`）。Verilator 5.053 devel（v5.052-586-g1838b6ed0），四顶层以下命令均 0 告警（`build/synth/lint.log`）：

```bash
(
  cd rtl/filelists
  ../../tools/check/lint.sh -DSIM_MODE --top-module edrv32_cpu_core -f cpu.f
  ../../tools/check/lint.sh -DSIM_MODE --top-module edrv32_cpu_subsys -f cpu_subsys.f
  ../../tools/check/lint.sh -DSIM_MODE --top-module edrv32_sys_subsys -f sys_subsys.f
  ../../tools/check/lint.sh -DSIM_MODE --top-module edrv32_fpga_cpu_sys_top -f cpu_subsys.f -f sys_subsys.f ../../fpga/rtl/edrv32_fpga_cpu_sys_top.v
)
```

IP 桩是外部接口声明，按 IP 既定端口命名，未应用业务 RTL 命名检查。

Yosys proc 在 SYS/TOP 的 PLIC 循环变量 `read_idx`（`rtl/periph/edrv32_periph_plic.v:174`）上提示 3 项临时 latch 推断；最终 10 份 generic 网表 latch 数均为 0。默认 ABC 脚本的组合分区另有 `The network is combinational` 诊断，原样保留在综合日志。
