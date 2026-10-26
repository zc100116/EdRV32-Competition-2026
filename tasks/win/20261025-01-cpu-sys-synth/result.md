# 20261025-01-cpu-sys-synth 结果

| 项 | 内容 |
|---|---|
| 输入基线 | f6d6b256aaad2f268f04c0d4536a44f6dba69359 |
| 本次 RTL / 检查源 commit | cb547cbe3bb6b2e4783800191cb57281aa6998f1 |
| 本轮 Compile commit | 157afa245359199cfa6bf7c18e2e21d165ae8203 |
| PDS 版本 | 2022.2-SP6.1，build 138931 |
| ModelSim | SE-64 2020.4 |
| 器件 | PG2L200H-6 FBB676（工程及 7 个 IP 的 .idf 已核对） |
| 完成情况 | RVC_EN=1 的 Compile、综合、器件映射、布局布线和时序报告均完成；150 MHz setup 未收敛；已另导出每角200条路径，并收集旧 CoreMark 对照；RVC_EN=0 对照未执行 |

## 从编译到布局布线的完整回传（2026-10-26）

用户要求详细整理全部日志、报告并推送，随后追加旧 CoreMark 工程对照，以及更多危险时序路径。
本次保留完整原始日志；旧工程的 `.pds` 和全部 `.idf` 按用户明确要求作为对照资料回传，
这些是通常不提交完整日志和工程文件规则的本次授权例外。两个工程的原生数据库、网表、bitstream 和 IP RTL 均不上传。

当前工程全部测量使用 `157afa245359199cfa6bf7c18e2e21d165ae8203` 的设计输入；
当前 `compile/run.log` 的实例参数明确 RVC_EN=1。
日志原文确认 Compile、Synthesize、Device Map、Place & Route、Report Timing 均完成。
流程完成不等于达到目标频率：最终报告写明 `Some Constraints Violated`。

### 流程状态与耗时

每阶段原始日志保存到 `artifacts/<阶段>/run.log`，项目总日志为 `artifacts/pds.log` 和 `project_run.log`。

| 阶段 | Real time | CPU time | Process CPU time | 峰值内存 | E: / W: 行数 |
|---|---|---|---|---|---|
| Compile | 11m00s | 1m44s | 1m44s | 2,394 MB | 0 / 1149 |
| Synthesize | 5m30s | 1m19s | 1m23s | 5,615 MB | 0 / 1500 |
| Device Map | 22s | 3s | 3s | 718 MB | 0 / 0 |
| Place & Route | 26m03s | 6m19s | 7m12s | 3,508 MB | 0 / 0 |
| Report Timing | 29s | 6s | 6s | 2,337 MB | 0 / 8 |

PDS 记录的 Compile 到 Report Timing 累计动作耗时为 43m24s，结束于 18:12:45；
这是工具各动作累计值，不包含用户在各动作之间的等待间隔。
全部 warning 分类和阶段原文统计见 `artifacts/flow_summary.txt`。
综合 1500 条 W: 包含 967 条 Public-4008 悬空实例清理、常量寄存器删除、扇出约束未满足等提示；
不将每条 warning 直接等同于独立硬件缺陷。器件映射和布局布线的日志虽无 E:/W:，最终 setup 仍违例。

### 原始报告及附加资料

- `compile/*.cmr`、`compile/run.log`、`compile/parse_design/run.log`、原有 logbackup 日志。
- `synthesize/*.snr`、`synthesize/run.log`、APM/DRM/分布式 RAM 映射、加减器进位链和 control sets 报告。
- `device_map/*.dmr`、`device_map/*_dmr.prt`、`device_map/run.log`。
- `place_route/*.prr`、`place_route/*_prr.prt`、clock utilization、路由消息和 `place_route/run.log`。
- `report_timing/*.rtr`、`report_timing/run.log`，以及 `constraint_check/*.ccr`。
- `multiseed_summary.csv`、项目完整会话日志；项目中既有的 Generate Bitstream 日志和 `.bgr` 也仅作为原始记录保留，未上传 bitstream。
- `resource_summary.txt`、`resource_hier.txt`、`timing_summary.txt` 为原报告数据的整理，不替代原文。
- 全部保存文件的位置和字节数见 `artifacts/artifact_index.md`。

`synthesize/run.log` 约8.43MB，完整项目 pds.log 约10.27MB、project_run.log 约9.12MB；
扩展时序报告约13.25MB。单文件超过数MB的原因是用户明确要求完整原文，以供 VPS Claude 定位编译耗时、warning 和违例路径；未截断或筛掉重复内容。

### 扩展时序报告：每角200条

默认 report_timing 仅给每类每角3条。按用户追加要求，本次通过 PDS 的已验证命令选项
从现有 PnR DB 重新导出，不重跑综合或布局布线，不修改原工程报告。
导出脚本为 `src/export_timing_200.tcl`，执行命令：

```powershell
& G:/Program/pango/PDS_2022.2-SP6.1/bin/pds_shell.exe -file G:/codex_project/EdRV32-Competition-2026/tasks/win/20261025-01-cpu-sys-synth/src/export_timing_200.tcl -work_dir G:/codex_project/EdRV32-Competition-2026/build/win/20261025-01-cpu-sys-synth/timing_200 -project_name timing_200
```

脚本设置 max_path=200、nworst=1、input_pins=TRUE，直接读取原工程
`place_route/edrv32_fpga_cpu_sys_top_pnr.adf`。导出过程 Real=29s、CPU=4s、Process CPU=5s，
峰值内存2,365MB，19:05:54结束。
完整 `.rtr` 和导出日志位于 `artifacts/report_timing_expanded/`，总计1640条路径：

| 类别 | Slow corner | Fast corner |
|---|---:|---:|
| 顺序电路 setup | 200 | 200 |
| 顺序电路 hold | 200 | 200 |
| Recovery | 200 | 200 |
| Removal | 200 | 200 |
| 组合 max 路径（未约束 IO） | 10 | 10 |
| 组合 min 路径（未约束 IO） | 10 | 10 |

导出成功且时序汇总与原报告一致。父级 flow.log 末尾另有 `W: open run.log failed.`，
子步骤 run.log 和完整 `.rtr` 均正常生成；原文已保留，未屏蔽该提示。

`setup_top200.txt` 保留慢、快两角各200条起点、终点、裕量和级数；
`setup_top20_detail.txt`、`hold_top20.txt` 保留两角各20条逐级明细。
`report_timing_expanded/all_paths.tsv` 提供全部路径索引。

危险路径分析见 `artifacts/dangerous_paths.md`：慢角前200条全部违例，裕量 -7.708 至 -7.143 ns；
其中131条终止在 CSR、69条终止在 frontend。Fast setup 前200条也全部违例，-1.911 至 -1.528 ns。
这些计数只描述导出的最差200条，不等同于全设计全部违例端点。

工具仍提示8个 IO 没有 input/output delay 约束：key_n_i、rst_n_i、uart_rx_i、
led_o[0..3] 和 uart_tx_o。它们被作为 combinational input/output，不能用内部寄存器时序通过代替外部 IO 时序验证。
高扇出、复位和 CE 原始表与 PnR 时钟负载见 `high_fanout.txt`，不单凭扇出数认定逻辑错误。

### 旧 CoreMark 对照资料

旧工程目录：`G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark`。
旧测量报告日期为2026-10-07，工具、器件与本次一致；目标时钟为100MHz，当前为150MHz，设计和存储配置不同。

- 原始日志、报告和资源层次：`artifacts/old_coremark/`。
- 导入脚本、两个相关 `.pds`、`impl.tcl`、时钟和 IO 约束均已复制。
- `ipcore/` 下全部15份 `.idf` 已复制；导入脚本实际使用其中6个，不能把目录中全部IP都计入资源。
- 所有 `.idf` 参数原值见 `old_coremark/ip_configuration.md`。
- Compile阶段、CPU时间、warning、乘法流水、存储容量及资源消耗逐项对照见 `old_coremark/comparison.md`。

旧工程 Compile 为1m42s/CPU26s，数据库6,210,072字节；本次为11m/CPU1m44s、147,420,498字节。
旧工程 constant probe loop 为243条，本次110条，不能用loop数量单独解释本次编译偏慢。
旧 SRAM 为4096×64的简单双口32KiB，本次32768×64单口256KiB；资源层次中SRAM分别占8和64个DRM。
旧33×33主乘法IP为3级，本次为2级；旧主IP占4APM，加上低位乘法通路3APM共7APM，本次共4APM。

旧测量commit未在报告中记录；采集时旧仓库HEAD为6028c445090f3bdb75ae753b0ca7fa0994304156，
不能绑定到10月7日测量。旧 edrv32_soc.pds 在10月24日修改，晚于报告，已明确标为配置快照。

## 本轮 Compile 最终报告（2026-10-26）

用户要求保存完整编译信息及最后的编译报告，推送后由 VPS Claude 审查编译耗时和 warning。
本次据此完整回传日志，作为仓库通常要求精简日志的用户授权例外。

PDS 项目主日志已打印 `Process "Compile" done.`，编译进程已结束。
当前 `compile/run.log` 中没有 `E:` 行；项目级 `pds.log` 包含此前失败尝试，
其中旧错误不能作为本轮 Compile 的错误统计。
最终报告原文为 `artifacts/compile/edrv32_fpga_cpu_sys_top.cmr`。

| 项 | 最终报告原文数据 |
|---|---|
| compile 输入 commit | 157afa245359199cfa6bf7c18e2e21d165ae8203 |
| 顶层 / 参数 | edrv32_fpga_cpu_sys_top，RVC_EN 默认 1 |
| 结束时间 | 2026-10-26 17:28:23（Windows 本地时间，Asia/Shanghai） |
| 实际耗时 | 0h:11m:0s |
| CPU 时间 | 0h:1m:44s |
| Process CPU 时间 | 0h:1m:44s |
| 峰值内存 | 2,394 MB |
| 生成数据库（留在本地，不入库） | compile/edrv32_fpga_cpu_sys_top_comp.adf，147,420,498 字节 |

复现时打开现有含 7 个 IP 的 PDS 工程，并从 FPGA 工程目录执行：

```tcl
source ../../EdRV32-Competition-2026/fpga/scripts/import_cpu_sys_top.tcl
```

本次最终 `.cmr` 中记录的实际 Flow Command（原文）为：

```text
Flow Command: compile -include_path {G:/codex_project/EdRV32-Competition-2026/rtl/include	G:/codex_project/EdRV32-FPGA/EdRV32} -compiler_directives {FPGA_MODE} -top_module edrv32_fpga_cpu_sys_top
```

### 阶段耗时

以下数值直接来自本次 `compile/run.log`，均为 wall time：

| 阶段 | 秒 |
|---|---:|
| rtl-analyze | 1.394 |
| rtl-elaborate | 0.291 |
| rtl-prep | 0.344 |
| rtl-infer | 37.660 |
| rtl-control-opt | 15.984 |
| rtl-data-opt | 74.895 |
| FSM inference | 7.213 |
| sdm2adm | 37.693 |

日志在 sdm2adm 完成后进入 `Saving design to DB.`，随后才打印最终 11 分钟耗时。
该保存阶段没有单独耗时统计，不编造独立测量数字。
观察期间数据库文件从 50,806,784 字节持续增长，最终为 147,420,498 字节；
这说明当时仍有输出进展，但不能据此确定保存偏慢的根因。
本次未做磁盘、杀毒软件或工具内部数据库性能分析，不把这些可能因素写成已确认结论。

### warning 汇总

逐行统计本次 `compile/run.log`：0 个 E:，1149 个 W:。
完整原文和行号见 `artifacts/compile/run.log`；分类及代表项见 `warnings_summary.txt`。

| 类别 | 次数 | 位置 / 说明 |
|---|---:|---|
| Public-4030 | 12 | 头文件重复处理、跳过提示 |
| Verilog-2008 | 269 | 厂商 IP 的 $display / $finish 被忽略 |
| Verilog-2036 | 4 | 厂商乘法器输入信号无驱动，接 0 |
| Verilog-2020 | 408 | 厂商 RAM / 乘法器内部无驱动信号，接 0 |
| Verilog-2039 | 15 | 厂商 RAM 模板中拼接重复次数为 0 |
| Verilog-2038 | 108 | 厂商 RAM 模板中 case 分支不适用 |
| Verilog-2023 | 142 | 厂商 RAM 未驱动端口的初值处理，包括 ECC 注入端口 |
| Sdm-2003 | 79 | 厂商乘法器内部数组无驱动 |
| Sdm-2010 | 2 | 自有 RTL：寄存器堆 registers_r、指令队列 entries_r 不支持同时多写的 RAM 推断 |
| Loop was found during constant probe | 110 | sdm2adm 常量探测；日志未提供信号 / 实例路径 |

两条自有 RTL 警告分别位于 `rtl/cpu/edrv32_cpu_regfile.v:26` 和
`rtl/cpu/edrv32_cpu_ib.v:24`。源码确实存在两个写入口；实际映射和代价尚无综合报告可确认。

Loop 诊断之后日志明确记录 sdm2adm 成功完成。当前日志不足以判断这些回路来自
寄存器反馈、厂商 IP 内部结构还是实际组合回路，不将其直接认定为无害或已定位缺陷。
未修改 RTL 或厂商 IP 来消除这些警告。

### 完整回传文件与本地来源

本轮文件均原样复制，未截断或过滤：

| 仓库内位置（相对本任务目录） | 本地来源（相对 FPGA 工程目录） |
|---|---|
| artifacts/pds.log | pds.log，完整项目会话日志，含此前失败尝试 |
| artifacts/project_run.log | run.log，完整本轮流程日志 |
| artifacts/compile/run.log | compile/run.log，完整本轮编译日志 |
| artifacts/compile/parse_design/run.log | compile/parse_design/run.log |
| artifacts/compile/edrv32_fpga_cpu_sys_top.cmr | compile/edrv32_fpga_cpu_sys_top.cmr，最终编译报告 |
| artifacts/compile/error_info.txt | compile/error_info.txt，原文件为空 |
| artifacts/compile/include_relation.txt | compile/include_relation.txt，实际 include 关系 |
| artifacts/compile/warnings_summary.txt | 从上述完整日志整理的分类和阶段耗时 |

FPGA 工程目录仍为 `G:/codex_project/EdRV32-FPGA/EdRV32`。
PDS 工程文件、IP 生成文件、原生数据库及中间文件未提交。
上次阶段回传时仅 Compile 结束；本次已补充综合资源、布局布线时序及 Fmax 结果，见本报告前部。

## 用户确认与 IP 端口差异

### 第二阶段导入路径调整（2026-10-26）

输入 commit：`81163fe2e2136b8bc146909d65ae19bfed9ab58e`。
PDS 日志确认原脚本将源码根目录算为 `G:/`，报错：

```text
E: Flow-0046: Execute tcl command fail. Error message is 'couldn't open "G:/rtl/filelists/cpu_subsys.f": no such file or directory'.
```

按用户确认的目录布局，工程位于 `G:/codex_project/EdRV32-FPGA/<工程名>`，
源码位于 `G:/codex_project/EdRV32-Competition-2026`。
本次将根目录计算改为 `[file normalize ../../EdRV32-Competition-2026]`，
要求从 FPGA 工程目录执行，不再使用 `[info script]`，不写死盘符或绝对源码路径。
任务卡同步更新执行命令。当前工程的相对导入命令为：

```tcl
source ../../EdRV32-Competition-2026/fpga/scripts/import_cpu_sys_top.tcl
```

Tcl 路径检查：从 `G:/codex_project/EdRV32-FPGA/EdRV32` 执行，
42 个源码文件、约束、头文件目录均能定位，顶层及 FPGA_MODE 参数正确。
该项是导入前的路径检查；随后实际 PDS Compile 已完成，见上面的最终报告。

2026-10-26 用户授权 Windows Codex 修改包装模块，并转达 VPS Claude 确认：
其余包装模块复位统一接 `1'b0`、使能接实际端口；两个 Tag IP 用 512 深度，地址高位补零；
SRAM 使用单口；Windows 不要求运行 Verilator，结果推送后由 VPS Linux 执行 lint 和仿真回归。
因此本次不按原任务卡“端口不同就停止且不修改 RTL”处理，而是按上述用户确认适配并阶段回传。

| IP | 差异 | 本次实现 |
|---|---|---|
| ip_rom_boot | en → clk_en，必带 rst | en_i 接 clk_en，rst 接 0 |
| ip_ram_icache_tag、ip_ram_dcache_tag | rd_en → rd_clk_en；必带读写复位；物理深度变为 512 | 复位接 0，读写地址均为 {2'b00, 原7位地址} |
| ip_ram_icache_data、ip_ram_dcache_data | rd_en → rd_clk_en，必带读写复位 | 重接读使能，复位接 0；D-cache 字节使能保留 |
| ip_ram_sram | clk_en；1 位 wr_en 加 8 位 wr_byte_en；必带 rst | clk_en 接 en_i，wr_en 接原8位写使能的 OR，wr_byte_en 接原8位写使能，rst 接 0 |
| ip_mul_s33x33 | 必带 rst，厂商内部流水配置不同于原创建说明 | rst 接 0；实际流水延迟和 CE 行为通过本机定向检查 |

修改了上述 7 个 `rtl/tech/` 包装模块的 FPGA 分支。对外接口与行为模型保持不变，
未修改厂商生成文件、规格或共享 IP 创建说明。
实际端口、参数、初始化格式见 `artifacts/ip_ports.md`。

Tag 原 7 位地址的 `04030101` 诊断在两个 IP 重生成为 9 位地址后未再出现。
逻辑 Tag 容量仍为 128×20，仅使用物理 IP 的前 128 项。

## 本次验证

RTL 与检查源 commit：`cb547cbe3bb6b2e4783800191cb57281aa6998f1`。
生成 IP 来自上述本机工程，不入库。

1. 风格检查：7 个包装模块，0 告警。

   ```powershell
   python tools/check/verilog_style.py rtl/tech/edrv32_ram_icache_tag.v rtl/tech/edrv32_ram_icache_data.v rtl/tech/edrv32_ram_dcache_tag.v rtl/tech/edrv32_ram_dcache_data.v rtl/tech/edrv32_rom_boot.v rtl/tech/edrv32_ram_sram.v rtl/tech/edrv32_mul_s33x33.v
   ```

2. 实际生成 IP 的 ModelSim 编译、加载及定向检查：通过。

   ```powershell
   & G:/Program/modeltech64_2020.4/win64/vsim.exe -c -do 'do G:/codex_project/EdRV32-Competition-2026/tasks/win/20261025-01-cpu-sys-synth/src/check_ip_wrappers.do'
   ```

   - vlog 编译：Errors 0，Warnings 0。
   - Cache：`PASS cache_ram`；检查读出、同址读旧数据、字节写使能及读禁用保持。
   - 乘法器：`PASS multiplier checks=23`；检查两次使能上升沿延迟、CE 暂停保持、有符号极值。
   - SRAM：`PASS SRAM checks=7`；检查首尾地址、按字节写入、禁用端口时不写入且输出保持。
   - ROM：实际端口编译与加载；外部初始化内容未验证。
   - 最终检查中 Cache 优化时有一条厂商 `GTP_DRM36K_E1.v:746` 的 `vopt-2250` 警告：
     `Function "mem_read_a" has no return value assignment.` 未屏蔽，未修改厂商模型。
     重复运行时 vlib 另提示本地工作库已存在。不能把全部流程描述成“零告警”。

3. 此前现有 ROM 行为模型单元仿真：`PASS memory checks=20`。
   当前 FPGA 连接变更不修改该行为模型。

按用户确认，Verilator lint 和完整仿真回归交给 VPS Linux；本阶段不声称完整回归或完整 IP 等价性通过。

## 引脚

下表已由最终 PnR `.prr` 的 IO Port Info 核对，均为 LVCMOS33、BANKL3。
协调者入库约束文件注明厂商 uart_test/key_led_test demo 来源；原厂 demo 的行号本机未取得。

| 端口 | 最终引脚 |
|---|---|
| clk_i | D18 |
| rst_n_i | C22 |
| key_n_i | C23 |
| uart_rx_i | B24 |
| uart_tx_o | C24 |
| led_o[0] | A20 |
| led_o[1] | C18 |
| led_o[2] | C19 |
| led_o[3] | E18 |

## 时序（RVC_EN=1）

| 时钟 / 角 | WNS ns | TNS ns | WHS ns | THS ns |
|---|---:|---:|---:|---:|
| clk_sys / Slow | -7.708 | -86183.305 | 0.153 | 0.000 |
| clk_sys / Fast | -1.911 | -7980.510 | 0.107 | 0.000 |

Performance Summary 原文 Estimated Frequency = **69.5652 MHz**，目标约150MHz未达到。
任务公式：1000 / (6.667 - (-7.708)) = 69.565217 MHz。

最差 setup 前5条（Slow corner）：

| 排名 | 起点 | 终点 | 裕量 ns | 级数 |
|---:|---|---|---:|---:|
| 1 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][62]/opit_0_inv_L6Q_perm/I5 | -7.708 | 30 |
| 2 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][61]/opit_0_inv_L6Q_perm/I1 | -7.677 | 30 |
| 3 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[1][62]/opit_0_inv_L6Q_perm/I5 | -7.649 | 30 |
| 4 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][60]/opit_0_inv_L6Q_perm/I5 | -7.632 | 30 |
| 5 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[1][61]/opit_0_inv_L6Q_perm/I1 | -7.620 | 30 |

## 资源（RVC_EN=1）

最终 `.prr` 的逻辑层次顶层行（不是 CLMA/CLMS 物理站点 LUT 明细的求和）：

| LUT | FF | DRM | APM | 分布式 RAM | IO | GPLL / PPLL |
|---:|---:|---:|---:|---:|---:|---|
| 24441 | 9121 | 74 | 4 | 39 | 9 | 0 / 0 |

器件映射阶段原文为 LUT=24347、FF=9099；阶段和统计口径不同，不混用。

| 主要模块（PnR逻辑层次） | LUT | FF | 分布式RAM | APM | DRM |
|---|---:|---:|---:|---:|---:|
| u_cpu_subsys | 22746 | 7951 | 31 | 4 | 6 |
| u_cpu_subsys/u_core | 19628 | 6209 | 31 | 4 | 0 |
| u_cpu_subsys/u_core/u_frontend | 12776 | 3161 | 31 | 0 | 0 |
| u_cpu_subsys/u_icache | 682 | 462 | 0 | 0 | 3 |
| u_cpu_subsys/u_dcache | 2389 | 1119 | 0 | 0 | 3 |
| u_sys_subsys | 1694 | 1170 | 8 | 0 | 68 |
| u_sys_subsys/u_sram | 342 | 43 | 0 | 0 | 64 |
| u_sys_subsys/u_rom | 60 | 30 | 0 | 0 | 4 |
| u_sys_subsys/u_sys_xbar | 241 | 137 | 0 | 0 | 0 |

完整层次包括外设、reset_ctrl等见 `artifacts/resource_hier.txt`；原始表与各阶段指标见
`resource_summary.txt`、`.snr`、`.dmr`、`.prr`。

## RVC_EN=0 对照

| 项 | RVC_EN=1 | RVC_EN=0 |
|---|---|---|
| WNS / Fmax | -7.708 ns / 69.5652 MHz | 未取得 |
| LUT / FF（PnR逻辑层次） | 24441 / 9121 | 未取得 |

本次仅整理已完成流程，未修改默认参数或启动RVC_EN=0流程；现有编译实例参数确认RVC_EN=1。

## 完整报告在 Windows 本地的路径

- 工程：`G:\codex_project\EdRV32-FPGA\EdRV32\EdRV32.pds`。
- ModelSim 日志：`G:\codex_project\EdRV32-Competition-2026\build\win\20261025-01-cpu-sys-synth\check_ip_wrappers.log`。
- PDS 各阶段原始报告和完整日志均已回传；扩展时序临时输出位于本地 `build/win/20261025-01-cpu-sys-synth/timing_200/`。

## 后续工作

- VPS Claude：执行 Linux lint / 回归，审阅包装适配；据实际端口和物理 Tag 深度更新 IP 创建说明。
- VPS Claude：审阅当前setup违例、危险路径、warning及旧工程对照，明确后续处理；本次不自行修改RTL或约束。
- Windows：RVC_EN=0对照尚未运行，按后续任务继续。
- 配置截图尚未归档；ROM/SRAM 外部初始化文件格式尚未实测加载。

## 备注

原 Git SSH 22 端口在认证前被关闭；本仓库 origin 已切换到
`ssh://git@ssh.github.com:443/zc100116/EdRV32-Competition-2026.git`，fetch 已成功。
本机提交身份仅在当前仓库配置，沿用现有提交作者 `zc100116`。
本次用户明确要求完整流程和旧工程配置，故回传全文日志、报告及旧工程.pds/.idf元数据；不提交原生数据库、网表、bitstream或厂商IP RTL。
