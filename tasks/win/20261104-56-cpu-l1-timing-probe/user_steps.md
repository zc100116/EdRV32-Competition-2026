# 卡56：本机工程准备与操作

## 已准备

- R1源码：`G:/codex_project/EdRV32-Competition-2026`，分支`win/20261104-56-cpu-l1-timing-probe`，起点`98f4c3f0`，已快进更新到`b35f8349`（方向表分bank修正）。
- R2源码：`G:/codex_project/EdRV32-Competition-2026-r2`，固定在`e54e471e`。
- R1工程：`G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V015/EdRV32-PROBE-V015.pds`。
- R2工程：`G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-REL/EdRV32-PROBE-REL.pds`。
- 以当前保留的B1-ILA工程为配置模板，器件Logos2 / PG2L200H / FBB676 / -6，综合器ADS（原工程选项2）。
- 从当前保留的B3F-RND1S工程复制并加入四个Cache RAM和`ip_mul_s33x33`，未复制PLL、DDR、ROM、SRAM、ILA或旧流程结果。
- 顶层均为`edrv32_cpu_l1_timing_probe`，构建宏`FPGA_MODE`。
- R1源码26个，R2源码25个；共用R1任务卡的探针顶层和FDC。
- 已核对保存后的PDS源码条目、IP条目、器件、综合器及相对路径；没有执行Compile、Synthesize、Device Map、PnR。

2026-11-05修正：此前用`pds_shell -file check_project.tcl -project_name ...`验证时，工具实际新建默认空工程并覆盖目标PDS，导致GUI中没有源码、IP且器件回到默认值。已重新从保留的B1配置恢复两个工程；该命令不能用于验证现有工程。若GUI仍开着旧的空工程，关闭时不要保存，再通过File → Open Project重新打开下列PDS文件。

随后修正PDS语法：手工重组的`_file`条目不满足PDS解析器格式。两个最终PDS均改由PDS原生`tcl2prj`从各工程的`project_settings.tcl`生成；此命令只生成工程配置，脚本中的Compile和Synthesize行用于配置选项，不执行流程。两个工程生成成功，源码分别26/25个，五个IP和一份FDC齐全，include路径已检查。后续配置生成使用`build/card56/create_native_projects.py`。

## 路径和约束

| 工程 | include目录（相对于工程目录） | 约束文件 |
|---|---|---|
| R1 | `../../EdRV32-Competition-2026/rtl/include` | `../../EdRV32-Competition-2026/tasks/win/20261104-56-cpu-l1-timing-probe/src/edrv32_cpu_l1_timing_probe.fdc` |
| R2 | `../../EdRV32-Competition-2026-r2/rtl/include` | 同上 |

源码、IP源文件、FDC和RTL引用的头文件均已检查存在。时钟周期6.667ns，setup uncertainty 0.15ns；两个工程均不使用PLL。PnR未加入调优覆盖参数，首轮采用工具默认参数。

## 用户先完成R1的两个新IP

### 2026-11-05生成后检查发现的限制

- 两个新IP均已加入R1工程。BTB为58位、7位地址、无输出寄存器、无初始化，符合要求。
- 方向表初次生成实际为4位、10位地址（1024深度），无输出寄存器、HEX初始化；当时初始化文件2048行且全部为5。
- 生成模块明确标注`ADDR_WIDTH`支持范围为4–10，故任务卡要求的11位地址/2048深度超出该版本IP的配置范围。
- RTL包装仍为11位地址。现有`compile/run.log`在包装模块第20行和第30行分别报告wr_addr、rd_addr宽度不匹配，共四条Verilog-2019警告。高地址位无法传入当前IP，此R1配置不能作为正确的v0.15对照结果。
- 已于本轮同步协调者提交`b35f8349`：包装改成两个1024字bank，查询/更新各一份，共四个IP实例。现有1024×4 IP的端口与更新后的包装匹配。原始初始化文件已改为1024行5；用户需在IP Compiler重新选择该文件并生成方向表IP，替换IP内原来2048行的副本。BTB无需重新生成。

在PDS通过File → Open Project打开R1工程。在IP Compiler中选择Memory → Distributed Simple Dual Port RAM（分布式简单双口RAM），分别创建以下两个模块，生成位置使用本工程的`ipcore/`。

| 选项 | BTB | gshare方向表 |
|---|---|---|
| 模块名 | `ip_lutram_cpu_btb` | `ip_lutram_cpu_direction` |
| 存储资源 | 分布式RAM / LUTRAM | 分布式RAM / LUTRAM |
| 端口模式 | Simple Dual Port，独立写、读地址 | 同左 |
| 数据位宽 | 58位 | 4位 |
| 地址位宽 | 7位（深度128） | 10位（深度1024） |
| 写操作 | 上升沿同步写、整字写入 | 同左 |
| 字节写使能 | 不启用 | 不启用 |
| 输出寄存器 / OUT_REG | 不勾选，组合读，0拍延迟 | 同左 |
| 读地址寄存器 | 不启用 | 不启用 |
| 初始化 / INIT_ENABLE | 不启用 | 启用 |
| 文件格式 / FILE_FORMAT | 无 | HEX |
| 初始化文件 | 无 | `G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V015/init/ip_lutram_cpu_direction.dat` |
| 复位 | 若需选择类型，使用ASYNC；RTL将高有效rst接0 | 同左 |

方向表初始化文件已更新：1024行，每行`5`，即每字的两个2位计数器均为01。方向表IP只需生成一个模块，RTL会实例化四份（查询/更新各两个bank），逻辑容量仍为2048×4。

期望端口为`wr_clk`、`rd_clk`、`rst`、`wr_en`、`wr_addr`、`wr_data`、`rd_addr`、`rd_data`。生成后确认两个IDF已加入工程并保存，告诉Codex“两个IP已生成”，由Codex核对实际端口与配置。

如IP Compiler不提供初始化文件选项，按任务卡要求停止并反馈。

## 运行流程

2026-11-05日志检查：两个工程Compile均完成，但Synthesize都在约束检查阶段报`ConstraintEditor-0040: p:clk_i lack attribute PAP_IO_STANDARD`，尚未完成综合和Device Map。已在共用探针FDC中补充`PAP_IO_STANDARD=LVCMOS33`，与原B1工程D18/3.3V时钟接口一致，尚未重跑。

其余日志项：三个探针非时钟端口未指定物理I/O约束，当前为warning；R1/R2在Compile常量传播阶段分别有51/58条`Loop was found during constant probe`，日志未列环路节点，旧B1/完整版工程也存在该类警告，需综合完成后继续看实际环路诊断；两轮均有寄存器堆双写端口RAM推断警告及厂商IP内部未驱动、仿真系统任务被忽略等警告。这些均没有在Compile阶段报错。业务RTL和IP生成文件未修改。

1. R1完成新增IP核对后运行；R2的现成IP已齐全。
2. 在对应工程中依次运行Compile、Synthesize、Device Map、Place & Route、Report Timing。
3. 不添加ILA，不运行Generate Bitstream，不下载上板。
4. 首轮保持默认PnR参数。若某轮WNS低于-1.0ns，保存首轮结果后，再按任务卡要求补跑decongestion=2、pin cost increasing speed=600、LUT6D combining strategy=0。
5. 每轮结束告诉Codex工程名，整理时序、资源、LUTRAM延迟及参数。

## 本机准备说明

初赛技术文档的两份已修改Markdown暂存在git stash中，Word、图片等未跟踪文件仍保留本地。未创建备份分支，未改动业务RTL。
