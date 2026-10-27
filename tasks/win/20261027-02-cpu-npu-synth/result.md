# 20261027-02-cpu-npu-synth 结果

| 项 | 内容 |
|---|---|
| commit | CPU 原测量源版本 335bb0fddc9f3f31eb8486390ece1a584d52c9e5；NPU B4 诊断 8fa223700974d6fba66a421559a966b8012f15df（含已提交的七个 RAM 适配） |
| PDS 版本 | 2022.2-SP6.1，build 138931（工程及 IP 生成日志） |
| ModelSim 版本 | ModelSim SE-64 2020.4 |
| 要求器件 | PG2L200H-6 FBB676 |
| A 工程路径 | G:/codex_project/EdRV32-FPGA/EdRV32/EdRV32.pds |
| B 工程路径 | G:/codex_project/EdRV32-FPGA/EdRV32-NPU-DP/EdRV32-NPU-DP.pds |
| 完成情况 | A：本次未收集本轮报告；B：B4a/B4b 诊断完成，七个 RAM 均有失配，乘法独立检查 PASS；NPU 后续流程按任务卡暂停 |

## A. CPU 第二轮

### SRAM IP

2026-10-27 读取实际 `.idf`：ADDR_WIDTH=13、DATA_WIDTH=64、BE_WIDTH=8、
WR_BYTE_EN=true、BYTE_SIZE=8、CLK_EN=true、OUTPUT_REG=false、INIT_EN=false。
容量为 8192×64（64 KiB），符合任务要求。没有修改 CPU 工程、脚本或正在运行的流程。

### 时序与资源

本轮时序、资源和关键路径：未取得，等待用户运行结束后收集。

上一轮（20261025-01）：WNS −7.708 ns，估计 69.6 MHz，19008/46871 个端点违例；
约 24.4K LUT、9.1K FF、74 DRM、4 APM。

## B. NPU 数据通路

### IP 生成与包装模块

实际端口、全部 `.idf` 选项及适配差异见 `artifacts/npu/ip_ports.md`。

| 项 | 实际值 | 要求 | 状态 |
|---|---|---|---|
| 工程及全部 9 个 IP 的封装 | FBB676 | FBB676 | 配置符合；工程已保存 |
| ip_ram_npu_weight 读写宽度 | 256 位 | 256 位 | 已修正；地址宽度 9、输出寄存器开启正确 |
| 其余 6 个 RAM | 容量、读使能、输出寄存器选项符合说明 | 各创建说明 | 配置核对通过；完整语义仿真尚未通过 |
| ip_mul_npu_quant_low | 18×16 signed，XYREG=1、MREG=1 | 两拍 | 已修正配置；全测试未完成 |
| ip_mul_npu_quant_high | 16×16 signed，XYREG=1、MREG=1 | 两拍 | 已修正配置；全测试未完成 |
| 每 IP DRM/APM 占用 | residual：界面报告 4 DRM36K；其余未取得 | 实际报告值 | 生成日志显示 Synthesis is disabled |

七个 RAM 包装模块仅修改 `ifdef EDRV32_FPGA_MEMORY_MODE` 分支：

| 文件 | 改动 |
|---|---|
| rtl/tech/edrv32_ram_npu_line.v | rd_en 改为 rd_clk_en；增加 wr_rst=0、rd_rst=0 |
| rtl/tech/edrv32_ram_npu_weight.v | 同上 |
| rtl/tech/edrv32_ram_npu_quant.v | 同上 |
| rtl/tech/edrv32_ram_npu_lut.v | 同上 |
| rtl/tech/edrv32_ram_npu_residual.v | 同上 |
| rtl/tech/edrv32_ram_npu_result.v | 同上 |
| rtl/tech/edrv32_ram_npu_scratch.v | 同上 |

未修改包装模块对外端口、行为模型、IP 生成文件和检查程序。

### ModelSim 等价性检查

命令（仓库根目录 PowerShell）：

```powershell
& 'G:\Program\modeltech64_2020.4\win64\vsim.exe' -c `
  -l 'G:/codex_project/EdRV32-Competition-2026/tasks/win/20261027-02-cpu-npu-synth/artifacts/npu/check_npu_ip.log' `
  -do 'do G:/codex_project/EdRV32-Competition-2026/tasks/win/20261027-02-cpu-npu-synth/src/check_npu_ip.do'
```

重新生成后结果：FAIL，进程退出码 1。未打印 `PASS npu_ip_check`，各检查器最终 checks
计数未取得。日志已更新为本次运行，见 `artifacts/npu/check_npu_ip.log`。首个 fatal 原文：

```text
** Fatal: FAIL ram AW=9 DW=256 expected=19861f335c63fbb807c42b0f56592bacd4e63ca968758dd0285d9750a8227850 actual=524ee3a4cb789e96ac53b658f3565ae6988bd0310fce171f342ce768f499a8e9 time=5166000
Time: 5166 ns  Scope: npu_ip_check.u_chk_residual
```

位置：`src/npu_ip_check.sv:63`。残差 RAM 实际选项为 WR/RD_ADDR_WIDTH=9、
WR/RD_DATA_WIDTH=256、OUTPUT_REG=true、RD_CLK_EN=true、RD_OCE_EN=false、
WR_CLK_EN=false、WR_BYTE_EN=false、FAB_REG=false、CAS_MODE=36K、INIT_EN=false、
RESET_TYPE=ASYNC。生成顶层内部 rd_oce_mux2d 为 1，读时钟使能连接 rd_en_i，复位接 0。
尚未确认具体触发条件和根因；未将本次失败归因于同址读写或输出保持中的某一种。
按任务卡 B4 停止 NPU 后续流程；没有修改行为模型、检查程序或生成 IP。

本次不再出现 weight 的 32/256 位端口警告；有既存工作库、两个乘法 IP 共同辅助模块
重复编译，以及厂商 GTP_DRM36K_E1 的 mem_read_a 无返回值赋值告警，原文保留在日志。

历史首轮失败：weight 为 32 位、量化乘法仅 MREG=1，16 ns 时 high 检查输出不符
（expected=c0008000、actual=ffff8000）。用户重新生成后，9 个 IP 封装全部修正，
weight 已改为 256 位，两个乘法的生成顶层实际为 XYREG=1、MREG=1、PREG=0、
INREG=0、OUTREG=0。本次运行推进到 5166 ns，尚不能声称各乘法完成全部检查。

### B4 诊断

执行版本：`8fa223700974d6fba66a421559a966b8012f15df`（已 rebase 到新增诊断任务的 origin/main）。
`diag_npu_ram.do` 的 ip_root 原本即为实际路径，无须修改。检查程序、诊断程序、行为模型、IP 均未修改。
诊断进程退出码 0，先打印 `DIAG DONE`，后打印 `PASS npu_mul_only`。该退出码表示诊断执行完成，不表示 RAM 等价性通过。

命令（仓库根目录 PowerShell）：

```powershell
& 'G:\Program\modeltech64_2020.4\win64\vsim.exe' -c `
  -l 'G:/codex_project/EdRV32-Competition-2026/tasks/win/20261027-02-cpu-npu-synth/artifacts/npu/diag_npu_ram.log' `
  -do 'do G:/codex_project/EdRV32-Competition-2026/tasks/win/20261027-02-cpu-npu-synth/src/diag_npu_ram.do'
```

各 m0–m3 列为失配次数，0 才表示对应候选模型完整匹配。

| RAM | CAS_MODE | RD_OCE_EN | 冲突模式选项 | checks | collisions | m0_spec | m1_write_first | m2_oce_gated | m3_both |
|---|---|---|---|---|---|---|---|---|---|
| line | 36K | false | 无可选项 | 6002 | 525 | 428 | 310 | 2047 | 1971 |
| weight | 36K | false | 无可选项 | 6002 | 507 | 418 | 292 | 2035 | 1960 |
| quant | 36K | false | 无可选项 | 6001 | 530 | 478 | 283 | 2083 | 1948 |
| lut | 36K | false | 无可选项 | 6002 | 501 | 407 | 333 | 2063 | 1992 |
| residual | 36K | false | 无可选项 | 6001 | 519 | 443 | 313 | 2052 | 1957 |
| result | 36K | false | 无可选项 | 6002 | 552 | 460 | 315 | 2090 | 1988 |
| scratch | 36K | false | 无可选项 | 6003 | 545 | 437 | 318 | 437 | 318 |

七个 RAM 的 CAS_MODE、RD_OCE_EN 来自各 IP 的 PDS `.idf` 保存参数。另只读打开 residual 的 IP Compiler 配置界面，
确认 DRM36K、Enable rd_oce 未勾选、输出寄存器勾选、读时钟使能勾选；未保存或重新生成。
同版本 1.10 的界面定义 ui.tcl 无 Write Mode / Read First / Write First / No Change 选项，七个 `.idf` 亦无冲突模式参数。
具体路径和界面核对结果见 `artifacts/npu/ip_ports.md`。

每个 RAM 第一次 m0 失配原文（包含 edge-0..3 和 actual matches）：

```text
# diag residual first m0 mismatch time=5166000 expected=19861f335c63fbb807c42b0f56592bacd4e63ca968758dd0285d9750a8227850 actual=524ee3a4cb789e96ac53b658f3565ae6988bd0310fce171f342ce768f499a8e9
# diag residual   edge-0 we=1 wa=106 re=1 ra=180
# diag residual   edge-1 we=1 wa=387 re=1 ra=387
# diag residual   edge-2 we=1 wa=377 re=1 ra=377
# diag residual   edge-3 we=1 wa=455 re=1 ra=288
# diag residual   actual matches m1=1 m2=0 m3=1

# diag result first m0 mismatch time=5256000 expected=775bf9ee382dcb7018dcdb31f94b54f2c6fd5a8d8fb66c1fc435da88b448aa68b6bef86dffd7a8ff7a42edf4381ef7707785edef6e74e9dc4a9d8b954a028594 actual=1e401d3c9690e42dd0efdaa15652cdac20836d4120db1f418bebf817fd7528fa1138d92283ae4e0799f90633f72fdaee39137b722ae3e555ceae849de11d30c2
# diag result   edge-0 we=0 wa=144 re=0 ra=422
# diag result   edge-1 we=1 wa=270 re=1 ra=270
# diag result   edge-2 we=1 wa=41 re=0 ra=24
# diag result   edge-3 we=1 wa=180 re=1 ra=267
# diag result   actual matches m1=1 m2=0 m3=0

# diag scratch first m0 mismatch time=5286000 expected=15932f2bec9b08d95e6543bcfd6ba4fa0942c91295c0a02b51f051a321019942 actual=3ab58d75c733568e756c2deab05fd460ee35f2dc6e893fddb8660870dffee6bf
# diag scratch   edge-0 we=1 wa=340 re=1 ra=340
# diag scratch   edge-1 we=1 wa=384 re=0 ra=384
# diag scratch   edge-2 we=0 wa=128 re=1 ra=212
# diag scratch   edge-3 we=0 wa=354 re=1 ra=250
# diag scratch   actual matches m1=1 m2=0 m3=1

# diag quant first m0 mismatch time=5376000 expected=b2c7de652cc46759 actual=ce318c9c2d946b5b
# diag quant   edge-0 we=0 wa=32 re=1 ra=217
# diag quant   edge-1 we=1 wa=202 re=1 ra=202
# diag quant   edge-2 we=0 wa=341 re=1 ra=404
# diag quant   edge-3 we=0 wa=355 re=1 ra=355
# diag quant   actual matches m1=1 m2=0 m3=1

# diag weight first m0 mismatch time=5506000 expected=238f0147bc33f6784dfd719bc26ad684f0e788e132977b65ad4d105ac049be80 actual=aff4845fd54494aad6f76ead21289b423706496ea8931a518fe5f81fdf3bc2be
# diag weight   edge-0 we=0 wa=214 re=1 ra=411
# diag weight   edge-1 we=1 wa=381 re=1 ra=381
# diag weight   edge-2 we=0 wa=502 re=1 ra=502
# diag weight   edge-3 we=0 wa=511 re=1 ra=0
# diag weight   actual matches m1=1 m2=0 m3=1

# diag line first m0 mismatch time=10356000 expected=499d279312a6c7252bb29b57a7fd104f6f1805de32278b64b532506af63514ec actual=23c2c7474b38f396121c9b248e5c941c47291b8e2bedd7571600112caed02c5d
# diag line   edge-0 we=0 wa=28 re=1 ra=1023
# diag line   edge-1 we=1 wa=812 re=1 ra=812
# diag line   edge-2 we=0 wa=72 re=1 ra=532
# diag line   edge-3 we=0 wa=644 re=1 ra=234
# diag line   actual matches m1=1 m2=0 m3=1

# diag lut first m0 mismatch time=41576000 expected=4f actual=25
# diag lut   edge-0 we=0 wa=4015 re=0 ra=4015
# diag lut   edge-1 we=1 wa=2670 re=1 ra=2670
# diag lut   edge-2 we=0 wa=4095 re=1 ra=0
# diag lut   edge-3 we=1 wa=4095 re=1 ra=0
# diag lut   actual matches m1=1 m2=0 m3=0

```

乘法器独立检查：两路 INT8 各 4026 次，quant_low 4026 次，quant_high 4026 次；`PASS npu_mul_only`。

诊断结论：七个 RAM 均不完全匹配任何一个候选模型。七个首次 m0 失配均匹配 m1（写优先），
但整段激励的 m1 仍有 283–333 次失配；因此不能将实际行为定为单一写优先，也不能归因为输出寄存器门控。
具体根因尚未确认，需协调者判断下一步；按任务卡暂停 B5 之后的 NPU 流程。

补充测量范围：scratch 不由当前 datapath 例化；本轮资源比较基准按新任务卡改为 148 DRM。

### 时序与资源

未取得。本次没有继续 NPU 综合、布局布线。PDS GUI 已显示正确顶层，头文件路径问题已由用户重跑导入后消失；编译测量报告本次未收集。

## 完整报告在 Windows 本地的路径

- CPU：G:/codex_project/EdRV32-FPGA/EdRV32/，用户正在执行本轮流程，报告待收集。
- NPU IP：G:/codex_project/EdRV32-FPGA/EdRV32-NPU-DP/ipcore/，各 IP 的 .idf、.v、generate.log。
- ModelSim：tasks/win/20261027-02-cpu-npu-synth/artifacts/npu/check_npu_ip.log。

## 备注

用户要求核对 NPU 导入脚本路径。已将 `fpga/scripts/import_npu_dp_top.tcl` 的仓库根目录
计算改为从 FPGA 工程目录出发的 `file normalize ../../EdRV32-Competition-2026`，
避免使用上一轮 PDS 控制台曾出现错误结果的 `info script` 方式。
源码路径没有写死绝对路径，没有增加备用路径。CPU 导入脚本未修改。

在标准 Tcl 中从 `G:/codex_project/EdRV32-FPGA/EdRV32-NPU-DP` 执行相对 source，
将 add_design/add_constraint/compile 替换为空操作后验证：根目录解析正确，展开 25 个源文件，
全部存在。这是路径静态检查，并未执行 PDS 编译。

修正 IP 并通过检查后，PDS Tcl 控制台先进入 NPU 工程目录，再执行：

```tcl
source ../../EdRV32-Competition-2026/fpga/scripts/import_npu_dp_top.tcl
```

### NPU include 路径修正（用户最终要求）

用户要求撤回对 RTL 头文件引用的修改，改由导入脚本设置 include 路径。
全部 10 个 NPU 包装模块已恢复原来的 `include "edrv32_build_mode.vh"` 写法；
原先授权的七个 RAM FPGA 端口适配保留，对外接口和行为模型均未改动。
此前尝试的源码相对头文件路径已全部撤销，不属于最终改动。

核对上一轮已完成的 Windows 结果分支 4517fe7 的 result.md：成功 Flow Command
包含源码 rtl/include 和 FPGA 工程目录两项 include 搜索目录。
本次只在 `fpga/scripts/import_npu_dp_top.tcl` 中按同样方式设置：

```tcl
set edrv32_include_dirs [list \
    [file join $edrv32_repo rtl include] \
    [file normalize .]]
```

由原有 `compile -include_path $edrv32_include_dirs` 传给 PDS，源码根目录继续以
`../../EdRV32-Competition-2026` 计算，未硬编码源码绝对路径。

独立 PDS 验证：将原样的全部 10 个 NPU 包装源文件加入临时工程，
按上述脚本设置 include 搜索目录，执行
`compile -top_module edrv32_ram_npu_scratch -include_path $edrv32_include_dirs`。
进程退出码 0，各源文件均找到 edrv32_build_mode.vh，无 E: 行。
此验证使用行为分支，只验证脚本的头文件搜索设置；随后只读查看 PDS GUI 时，层次显示正确顶层且控制台已打印 added 25 sources，
也不代表完整 NPU FPGA_MODE 编译或 ModelSim 语义检查通过。

复现命令：

```powershell
& 'G:\Program\pango\PDS_2022.2-SP6.1\bin\pds_shell.exe' `
  -file 'G:/codex_project/EdRV32-Competition-2026/build/win/20261027-02-cpu-npu-synth/header_path_check/check_script_include.tcl' `
  -work_dir 'G:/codex_project/EdRV32-Competition-2026/build/win/20261027-02-cpu-npu-synth/header_path_check' `
  -project_name header_script_include_check
```

完整本机验证日志：
`build/win/20261027-02-cpu-npu-synth/header_path_check/check_script_include_console.log`。
此前 residual RAM 的 ModelSim 数据不符仍待处理。

同步记录：先以用户指定信息提交七个 RAM 适配（原 c371cbb），fetch 后 rebase 到 origin/main，
得到适配提交 8fa2237。check_npu_ip.do 的 ip_root 与仓库原值一致，因此无差异。
既有导入脚本和结果文件暂存后已恢复，未建立备份分支。
