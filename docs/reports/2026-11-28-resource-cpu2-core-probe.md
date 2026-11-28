# CPU v2 整核探针：临时 Yosys 参考（不是 PDS）

日期 2026-11-28；测量读取时 HEAD core1=`8d0fe9038236e59a55fdd474358c3b5979e2d12d`、core2=`bdb44511f15bc24e271317cc246199b5b905cc42`；共享 LSU 尚未提交，数字为 worktree 临时参考，稳定提交后必须重跑。
工具 Yosys 0.70+219（5053d0e26），`read_slang --allow-use-before-declare`；`synth_xilinx -family xc7 -flatten -noiopad -noclkbuf -nobram`；LUTRAM 使用固定几何行为模型，DRM 和 DSP 引脚为深度边界。
目标 PDS 器件 PG2L200H-6/FBB676、单时钟 6.061 ns（165 MHz），两顶层分别固定 ISSUE_WIDTH=1/2、FPU_FORMAT=NONE；XC7 资源和级数不能换算真实 PDS 时序或 CLM。
复现：`. ~/.local/opt/edrv32/env.sh` 后分别运行 `python3 fpga/scripts/measure_probe_cpu2_core.py 1` 和 `python3 fpga/scripts/measure_probe_cpu2_core.py 2`（串行）。
原始数据：`build/probe_cpu2_core/core{1,2}/{synth.ys,synth.log,xc7.json,paths.json,paths.md,version.txt,commit.txt}`；未取得 PDS WNS/TNS、资源、CLM 或物理扇出。

| 顶层 | 逻辑LUT | FF | LUTRAM原语（RAM32M/RAM64M） | LUTRAM占用LUT6 | SRL16E | DSP48E1 | DRM IP | 最大级数 | 最大映射扇出 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| core1 | 15522 | 10568 | 280（48/232） | 1120 | 17 | 4 | 10 | 26 | 2169 |
| core2 | 38932 | 19600 | 398（102/296） | 1592 | 17 | 4 | 30 | 34 | 4802 |
LUTRAM 的每个 RAM32M/RAM64M 计 4 个 XC7 LUT6；逻辑LUT列不含 LUTRAM、SRL、MUXF 或 CARRY4；所有统计含探针寄存器；深度每个 LUT/MUX/CARRY4/INV/RAM 计一级，DSP/DRM 内部不展开。

| 排名 | core1 起点→终点（含模块路径） | 级数 | core2 起点→终点（含模块路径） | 级数 |
|---:|---|---:|---|---:|
| 1 | `u_core.u_issue.entry_channel_w[6]` → `u_core.u_issue.entry_src2_w[29]` | 26 | `u_core.u_issue.entry_channel_w[6]` → `u_core.branch_redirect_ras_count_w[0]` | 34 |
| 2 | `u_core.u_issue.entry_channel_w[6]` → `u_core.u_issue.entry_src1_w[29]` | 26 | `u_core.u_issue.entry_channel_w[6]` → `u_core.branch_redirect_ras_count_w[1]` | 34 |
| 3 | `u_core.u_issue.entry_channel_w[6]` → `u_core.u_completion.data_w[28]` | 26 | `u_core.u_issue.entry_channel_w[6]` → `u_core.branch_redirect_ras_count_w[2]` | 34 |
| 4 | `u_core.u_issue.entry_channel_w[6]` → `u_core.u_completion.data_w[29]` | 26 | `u_core.u_issue.entry_channel_w[6]` → `u_core.branch_redirect_ras_count_w[3]` | 34 |
| 5 | `u_core.u_issue.entry_channel_w[6]` → `u_core.u_completion.data_w[61]` | 26 | `u_core.u_issue.entry_channel_w[6]` → `u_core.branch_redirect_ras_ptr_w[0]` | 34 |
| 6 | `u_core.u_issue.entry_channel_w[6]` → `u_core.u_completion.data_w[62]` | 26 | `u_core.u_issue.entry_channel_w[6]` → `u_core.branch_redirect_ras_ptr_w[1]` | 34 |
| 7 | `u_core.u_issue.entry_channel_w[6]` → `u_core.u_completion.data_w[92]` | 26 | `u_core.u_issue.entry_channel_w[6]` → `u_core.branch_redirect_ras_ptr_w[2]` | 34 |
| 8 | `u_core.u_issue.entry_channel_w[6]` → `u_core.u_completion.data_w[93]` | 26 | `u_core.u_issue.entry_channel_w[6]` → `u_core.branch_redirect_ras_data_w[0]` | 34 |
| 9 | `u_core.u_issue.entry_channel_w[6]` → `u_core.u_completion.data_w[125]` | 26 | `u_core.u_issue.entry_channel_w[6]` → `u_core.branch_redirect_ras_data_w[1]` | 34 |
| 10 | `u_core.u_issue.entry_channel_w[6]` → `u_core.u_completion.data_w[126]` | 26 | `u_core.u_issue.entry_channel_w[6]` → `u_core.branch_redirect_ras_data_w[2]` | 34 |

core2 的 `branch_redirect_ras_*` 是顶层别名，捕获FF属于 `edrv32_cpu2_branch`（branch.v:1486）；core1 起点/终点分别为 issue→issue/completion。

| IP 模块 | 几何 | core1/core2 展开数量（优化前） | 创建说明（均在 README 有索引） |
|---|---|---:|---|
| `ip_lutram_cpu2_rf` | 32×32 | 3/10 | [说明](../../fpga/ip/ip_lutram_cpu2_rf.md) |
| `ip_lutram_cpu2_btb` | 64×59 | 2/2 | [说明](../../fpga/ip/ip_lutram_cpu2_btb.md) |
| `ip_lutram_cpu2_fast` | 1024×2 | 24/24 | [说明](../../fpga/ip/ip_lutram_cpu2_fast.md) |
| `ip_ram_cpu2_cache_data` | 2048×32 | 0/4 | [说明](../../fpga/ip/ip_ram_cpu2_cache_data.md) |
| `ip_ram_cpu2_cache_data64` | 2048×64，8字节mask | 4/2 | [说明](../../fpga/ip/ip_ram_cpu2_cache_data64.md) |
| `ip_ram_cpu2_cache_tag` | 512×19 | 2/4 | [说明](../../fpga/ip/ip_ram_cpu2_cache_tag.md) |
| `ip_ram_cpu2_cache_dtag` | 512×20 | 2/2 | [说明](../../fpga/ip/ip_ram_cpu2_cache_dtag.md) |
| `ip_ram_cpu2_cache_lru` | 512×1 | 2/3 | [说明](../../fpga/ip/ip_ram_cpu2_cache_lru.md) |
| `ip_ram_cpu2_tage` | 256×16 | 0/8 | [说明](../../fpga/ip/ip_ram_cpu2_tage.md) |
| `ip_ram_cpu2_tage_train` | 512×16 | 0/4 | [说明](../../fpga/ip/ip_ram_cpu2_tage_train.md) |
| `ip_ram_cpu2_base` | 2048×2 | 0/2 | [说明](../../fpga/ip/ip_ram_cpu2_base.md) |
| `ip_ram_cpu2_base_train` | 4096×2 | 0/1 | [说明](../../fpga/ip/ip_ram_cpu2_base_train.md) |
上述 12 种说明均存在，无缺失；README 的 fast×12 是单包装统计，整核使用两个包装共24，综合可删除未用副本；RF 数含 AGU；NONE 完成队列使用FF；整数乘法为标准算式推断，无需生成乘法 IP。

检查：两个新增顶层 `python3 tools/check/verilog_style.py fpga/rtl/edrv32_fpga_probe_cpu2_core{1,2}_top.v` 为0告警；分别执行 `verilator --lint-only -Wall -DSIM_MODE -F rtl/filelists/cpu2_probe_coreN.f --top-module edrv32_fpga_probe_cpu2_coreN_top`（N=1/2），均0告警；Tcl 用 stub add_design/add_constraint/compile 检查两脚本均38源文件、路径有效。
PDS 限制扫描覆盖全部22个 `rtl/cpu2/*.v` 和2个探针：20个 reg 数组各仅一处 always 所有权（含2个组合数组），无 generate 层次引用；generate 声明的 wire 数组均无元素再切片；扫描明细 `build/probe_cpu2_core/pds_scan.txt`。
原生前端逐文件命令：`yosys -Q -T -p "read_verilog -D FPGA_MODE -Irtl/include FILE"`，覆盖22个整数文件+13个 `rtl/cpu2/fpu/*.v`，32通过、3首次错误：alu:133 `g_pipe0.cancel_age_w`（141声明）、branch:586 同名（594声明）、issue:1616 `g_entry[0].age_w`（1624声明）；日志 `build/probe_cpu2_core/native_scan/`。
同类源码位置：alu:529→537、branch:984→992；issue:1616 同时前向使用 `occupied_w`（1626声明）；原生前端每文件首次错误即停止，这些声明顺序问题需由CPU所有者处理，本任务未改CPU RTL。
