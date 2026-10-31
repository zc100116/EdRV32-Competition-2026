# D$ 32 KiB 与维护遍历（T-CM1）
- 基线 `6bab90a0`；改后为本报告所属提交；环境：用户提供的仿真主机（环境不记录）。
- I$/D$ 各 512组×2路×32B；每路 tag 512×18、data 2048×64；有效/脏/LRU 均为寄存器。
- 组段为16组；脏位图跳过干净段及段内干净组；范围双路并查、预取与检查重叠，写回时保留预取。
- 旧三态遍历全部等待设备通道空闲，STATUS轮询确实暂停遍历；新遍历独立推进。
- AXI：在途设备事务先完成，D_BUS 与写回同时申请时设备优先；写回占有至B，之后可让出给设备。
- I$局部失效标志当拍屏蔽有效位，下拍清物理位；metadata按32段×16位快照，命中延迟/吞吐不变。
- 新增写缓冲排空→脏位快照旁路；定向反例改前丢失写回，改后通过；未改CPU接口或流水线。

| 无写回范围行数 | 改前周期 | 改后周期 | 上限 |
|---|---:|---:|---:|
| 1 | 768 | 4 | 9 |
| 16 | 768 | 19 | 24 |
| 128 | 768 | 131 | 136 |
| 512 | 768 | 515 | 520 |
| 2048 | 768 | 515 | 520 |

| 整体clean | 改前周期（8KiB） | 改后周期（32KiB） |
|---|---:|---:|
| 无脏行 | 768 | 32 |
| 单脏行：首/末组 | 778 / 778 | 46 / 46 |
| 全脏 | 3328（256行） | 12832（1024行） |
- 周期为D$接受命令→BUSY清零；无反压、AXI立即响应。实测每行AW→B（含首尾）10拍，授予另1拍，每脏组tag读/检查/恢复另3拍；整体clean=32+11×脏行数+3×脏组数，位置不影响额外停顿。
- 512行无脏范围并发轮询STATUS仍515拍；随机反压及可缓存请求等待由MT-12覆盖。CoreMark：O2、RV32IM_Zicsr、10 iterations、read latency=2，2,774,323→2,774,323拍，CRC PASS。

| Yosys LUT6参考（RAM/APM黑盒，RVC_EN=0） | 改前 LUT / FF / 最长级数 | 改后 LUT / FF / 最长级数 |
|---|---|---|
| I$ | 5197 / 2159 / 8 | 4748 / 1820 / 9 |
| D$ | 6323 / 1144 / 12 | 16594 / 3597 / 13 |
| CPU+cache | 30919 / 11567 / 31 | 41139 / 13681 / 30 |
- 未修改b3单核为19905 LUT、8106 FF、31级；cache相关最长31→30级，均不超过单核基线。综合顶层ic_inv负载1029→99；以上非PDS物理资源/Fmax，器件参考PG2L200H-6，无物理时序约束。
- C-F1六类同过滤器级数（改前→改后）：1 无→无；2 无→无；3 12→13；4 10→11；5 7→9；6 无→9；“无”为该起终点间无可达路径。
- 以下为同口径cache相关前10条：cache FF/DRM输出→全网端点，与全网→cache FF合并；省略u_target，D=dcache，P=core.frontend.predictor，数组下标保留。

| # | 改前起点→终点 | 级数 | 改后起点→终点 | 级数 |
|---|---|---:|---|---:|
| 1 | D.addr_r[20]→P.ras_count_r[0] | 31 | D.addr_r[24]→P.ras_data_r[96] | 30 |
| 2 | D.addr_r[20]→P.ras_count_r[1] | 31 | D.addr_r[24]→P.ras_data_r[64] | 30 |
| 3 | D.addr_r[20]→P.ras_count_r[2] | 31 | D.addr_r[24]→P.ras_data_r[32] | 30 |
| 4 | D.addr_r[20]→P.ras_data_r[96] | 31 | D.addr_r[24]→P.ras_count_r[0] | 30 |
| 5 | D.addr_r[20]→P.ras_data_r[64] | 31 | D.addr_r[24]→P.ras_count_r[1] | 30 |
| 6 | D.addr_r[20]→P.ras_data_r[32] | 31 | D.addr_r[24]→P.ras_count_r[2] | 30 |
| 7 | D.addr_r[20]→P.ras_data_r[97] | 31 | D.addr_r[24]→P.ras_data_r[97] | 30 |
| 8 | D.addr_r[20]→P.ras_data_r[98] | 31 | D.addr_r[24]→P.ras_data_r[98] | 30 |
| 9 | D.addr_r[20]→P.ras_data_r[99] | 31 | D.addr_r[24]→P.ras_data_r[99] | 30 |
| 10 | D.addr_r[20]→P.ras_data_r[100] | 31 | D.addr_r[24]→P.ras_data_r[100] | 30 |

- 最终验收：37个RTL/层次top lint零告警、32文件风格零告警；单元5、模块25及MT-07/08/12、CPU smoke74（含riscv-tests19）+arch-test155、板级3项：全部PASS。
- 复现先 `. ~/.local/opt/edrv32/env.sh`；本机全部Verilator/Yosys/regress加 `flock /tmp/edrv32-sim.lock`，编译 `-j 1`。风格：`python3 tools/check/verilog_style.py rtl/cache rtl/tech`。
- 回归：逐 `verif/unit/cache_*`、`verif/block/cache`、`verif/block/cpu`、`verif/soc/board_{render,npu,vnpu}` 执行 `python3 tools/regress.py smoke --path <目录> -j 1`；逐 `verif/block/cpu/arch-*` 和 `verif/block/cache/mt_{07,08,12}` 以 `full --path` 执行。
- Lint：用 `tools.regress.expand_files` 展开cache/soc filelist及board测试filelist（保留公共timescale，去掉tb和boot_window），执行 `verilator --lint-only --timing -Wall -DSIM_MODE --top-module <top> <sources>`；tech逐模块检查。
- CoreMark：`python3 tools/cpu/b2_run.py r05 --rvc 0 --read-latency 2`；维护：按 `verif/unit/cache_dcache/files.f` 编译tb，运行 `sim +MAINT_PERF +CACHE_LINES=1024`（改前256）。
- 综合：`read_verilog -D FPGA_MODE -Irtl/include <cache/PMA/RAM包装> tools/synth/ip_stubs.v; hierarchy -check -top <cache>; synth -top <cache> -flatten -noabc; abc -lut 6 -dress; opt_clean; write_json <netlist>; stat`；`tools/synth/netlist_paths.py`分析。CPU用 `python3 tools/synth/yosys_synth.py edrv32_cpu_subsys --rvc-en 0`，单核改用 `edrv32_cpu_core`；六类过滤器同C-F1报告。
- 自行归纳的日志/复现脚本：`build/cache-maint/{delivery-verify,delivery-system,delivery-measure,threshold-final-synth}.log`及同目录脚本；未回传仿真主机原始文件；上板前按更新的IP说明重新生成D$两个IP，物理时序待PDS确认。
