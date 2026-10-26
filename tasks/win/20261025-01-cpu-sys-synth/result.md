# 20261025-01-cpu-sys-synth 结果

| 项 | 内容 |
|---|---|
| 输入基线 | f6d6b256aaad2f268f04c0d4536a44f6dba69359 |
| 本次 RTL / 检查源 commit | cb547cbe3bb6b2e4783800191cb57281aa6998f1 |
| 本轮 Compile commit | 157afa245359199cfa6bf7c18e2e21d165ae8203 |
| PDS 版本 | 2022.2-SP6.1，build 138931 |
| ModelSim | SE-64 2020.4 |
| 器件 | PG2L200H-6 FBB676（工程及 7 个 IP 的 .idf 已核对） |
| 完成情况 | Compile 已结束，当前编译日志 0 个 E:、1149 个 W:；按用户要求回传完整编译信息，等待 VPS Claude 审阅；尚未执行综合、布局布线和 RVC_EN=0 对照 |

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
本次仅 Compile 结束，没有综合资源、布局布线时序或 Fmax 结果。

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

| 端口 | 引脚 | 出处 |
|---|---|---|
| clk_i | 未取得 | 待用户提供对应板卡的厂商 demo 约束文件 |
| rst_n_i | 未取得 | 同上 |
| uart_rx_i | 未取得 | 同上 |
| uart_tx_o | 未取得 | 同上 |
| key_n_i | 未取得 | 同上 |
| led_o[3:0] | 未取得 | 同上 |

## 时序（RVC_EN=1）

| 时钟 | WNS | TNS | WHS | THS | Fmax（推算） |
|---|---|---|---|---|---|
| clk_sys | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |

最差路径前 5 条：未取得，尚未运行顶层综合和布局布线。

## 资源（RVC_EN=1）

| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|
| 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |

按层次（主要模块）：未取得。乘法器实际 APM 占用亦尚未取得。

## RVC_EN=0 对照

| 项 | RVC_EN=1 | RVC_EN=0 |
|---|---|---|
| WNS / Fmax | 未取得 | 未取得 |
| LUT / FF | 未取得 | 未取得 |

顶层参数默认值未修改，仍为 RVC_EN=1。

## 完整报告在 Windows 本地的路径

- 工程：`G:\codex_project\EdRV32-FPGA\EdRV32\EdRV32.pds`。
- ModelSim 日志：`G:\codex_project\EdRV32-Competition-2026\build\win\20261025-01-cpu-sys-synth\check_ip_wrappers.log`。
- PDS Compile 完整日志和最终 .cmr 已回传至 artifacts/compile/；综合、布局布线报告尚未生成。

## 后续工作

- VPS Claude：执行 Linux lint / 回归，审阅包装适配；据实际端口和物理 Tag 深度更新 IP 创建说明。
- Windows：按用户要求先回传本轮完整 Compile 日志和最终报告，等待 VPS Claude 审阅后再继续综合、布局布线和 RVC_EN=0 对照。导入脚本和 150 MHz 约束已由协调者提供。
- 配置截图尚未归档；ROM/SRAM 外部初始化文件格式尚未实测加载。

## 备注

原 Git SSH 22 端口在认证前被关闭；本仓库 origin 已切换到
`ssh://git@ssh.github.com:443/zc100116/EdRV32-Competition-2026.git`，fetch 已成功。
本机提交身份仅在当前仓库配置，沿用现有提交作者 `zc100116`。
本次用户明确要求完整编译信息，故回传本轮完整日志及最终报告；不提交 PDS 工程、厂商 IP、原生数据库或 bitstream。
