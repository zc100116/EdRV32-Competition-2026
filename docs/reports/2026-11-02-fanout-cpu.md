# CPU/cache 高扇出拆分（2026-11-02）

基线 `bf56df5c`；改后 RTL `548861ff`（C2 `11b4b19e`、C1/C3 `457bfe0c`、C4–C7 `95afe80f`、C8/C9 `b8328b1b` + `548861ff`）。规格不变，无新增流水拍。
参考工具：Yosys 0.70+219、ABC LUT6、RVC_EN=0、FPGA_MODE、9 个 RAM/乘法 IP 黑盒；Verilator 5.020。非 PG2L200H-6 原生映射，不据此宣称频率改善。
测量副本把 `syn_preserve=1` 注释转换为 Yosys `keep`，`proc; flatten` 后对其驱动 FF 设置 keep；定版 RTL 仅保留厂商注释。RAM `rd_clk_en` 计作控制端点，不能按 clk 子串排除。
下表负载为映射后输入 pin/bit；级数为各组存储/输出边界的最长 LUT 路径，均为改前→改后；不同组的终点不同。

| 项 | RTL 位置与做法（路径均在 rtl/） | 参考负载；最长 LUT 级数 |
|---|---|---|
| C1 | cpu/edrv32_cpu_frontend.v：IB、请求、预测恢复分开 redirect 派生锥（组合副本在Yosys会合并）；record payload 在写所有权判断前生成 | redirect 98→81；F1 PC/数据 RAM 终点 28→27；IB→RAM CE 子路径 16→22 |
| C2 | cpu/edrv32_cpu_ib.v、edrv32_cpu_regfile.v：读指针按槽/32位片复制，写指针按表项复制；寄存器堆读地址按8位片单独取 IB | read_ptr 352→7，write_ptr 7→4，data[54] 129→42；IB 输出最大522→45；级数2→4 |
| C3 | cpu/edrv32_cpu_frontend.v:g_read：半字计数器按4个 stream 槽复制，同一 remaining D、同拍清零 | halfword_count 21→10；stream 终点9→10；N396_inv/N433 未唯一定位 |
| C4 | cpu/edrv32_cpu_core.v:g_predict_index：record[141] 是 REC_GHR_LSB+8，即训练索引[8]；训练索引按16个预测更新块复制 | 原位6→0；9位索引最大549→45；方向表终点18→16 |
| C5 | cpu/edrv32_cpu_core.v:g_e_enable：复制原 E-valid 状态，按操作数、record、训练和 M 负载生成同拍使能 | operand_load 566→195，advance 323→218；使能锥19→17 |
| C6 | cpu/edrv32_cpu_csr.v:g_counter：cycle、instret、8个HPM各自64位复位/写选择，保留写优先和事件延迟 | CSR复位868→228（控制）/64（计数器）；同步写公共控制657→各组write_low≤66（CSR峰137含trap）；计数器终点16→18 |
| C7 | cpu/edrv32_cpu_predictor.v:g_direction：方向表由2×256项拆为16×32项，局部饱和加减；8组并列复位 | CE最大512→64；索引副本≤45，复位512→128；方向表终点18→16 |
| C8 | cache/edrv32_icache.v:g_victim/g_valid_bank：8份查找/填充来源状态；按4个16项bank生成命中、填充与LRU控制；valid/LRU复位各分2组 | hit0 113→103，tag原网20→1，victim副本≤5；局部LRU选择≤137；复位512→256；终点28→27 |
| C9 | cache/edrv32_dcache.v:g_metadata：先合并bank选择再展开16位LRU清/置位；LRU复位分2组 | 两条512位LRU控制→16；模块非时钟/复位最大512→146；终点22→20；N786未唯一定位 |

PDS自动名不能由Yosys名直接等同，当前检出无卡31所述产物；未取得唯一门级回映：C1 _N361972/_N479275（N404_2），C3 N396_inv/N433，C6 N426及N265_9驱动网，C7 N8063/N8074/N203/N303，C8 N33/N36/N40/N43/N162/N172/N182，C9 N786/N1034/N1044；以上只报告已确认RTL/负载，不猜编号。
新增内部复位组端口：core/frontend/predictor 的 `rst_sys_direction_n_i[7:0]`（每组128）；core/CSR 的 `rst_sys_counter_n_i[9:0]`（64）；I$ 三类原端口扩为[1:0]（256）；D$ 新增 `rst_sys_dlru_n_i[1:0]`（256）。
协调者经 ask 扩展归属至 soc/edrv32_cpu_subsys.v；所有31份 reset_copy 都并列取原始 rst_n_i，仍在原来同一边沿释放；core/CSR控制/I$/D$控制/寄存器块分别194/228/73/116/94负载。
全局参考 LUT/FF：31678/11482→35978/12350；最长30→29。面积增加4300 LUT、868 FF，复制不是面积优化。
≥128普查及逐项数据：`build/fanout-cpu/reproduce-{before,after}/{loads.tsv,high_fanout.tsv,levels.tsv,*-paths.json}`；未消除的非复位峰值738→834（W有效/写回选择），另有F1 PC 540/485、halfword block选择444、预测查询索引256。
IB→I$ CE参考级数增加，未证明该路径时序改善；副本布线收益、工具保留情况与残留网络均须由 PDS 原生网表/布线复核。

性能（同一程序/档位，周期改前→改后；r03两窗口均列出）：
| 档位 | 周期 |
|---|---|
| cpu_b2 r01/r02 | 8560→8560 / 16459→16459 |
| cpu_b2 r03窗口0/1 | 12577→12577 / 16678→16678 |
| cpu_b2 r04/r05 CoreMark | 263875→263875 / 2787555→2787555 |
| cache pf_01 | 总617→617；冷访问21→21；I读/D读/D写流16/16/16→16/16/16 |
| cache pf_02 | 总525→525；request_to_response/axi_round_trip/bound=8/2/11→8/2/11 |
验证：cache单元5项、cache smoke 28项、B2 smoke 3项、B2 perf 5项、cache perf 2项、board_render均PASS；CPU单元16目录/19项（含本机2项Icarus）、CPU模块74项、sys_cpu 3项均PASS。B2的264条事件/HPM计数记录逐项相等。改前 B2 文件列表缺 reset_copy，已改用 cpu_subsys.f；CoreMark/LVGL 子模块按锁定版本初始化，未改子模块版本。
本机风格17文件/0告警，CPU RVC=1、CPU子系统RVC=0、I$/D$ `-Wall` lint 0告警；本机使用 flock/-j1，CPU CSR/regfile的Icarus两项在本机PASS，其余回归在用户提供的仿真主机（环境不记录）执行。
复现（基线/改后分别检出上述提交，性能软件从空 build 构建；原始本机证据与主机结果的自主汇总在 build/fanout-cpu/）：
```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/cpu rtl/cache rtl/soc/edrv32_cpu_subsys.v
(cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_cpu_subsys -f cpu_subsys.f)
for d in verif/unit/cpu_* verif/unit/cache_* verif/block/{cpu,cpu_b2,cache,sys_cpu} verif/soc/board_render; do flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path "$d" -j 1; done
for d in cpu_b2 cache; do flock /tmp/edrv32-sim.lock python3 tools/regress.py perf --path "verif/block/$d" -j 1; done
python3 -m tools.synth.fanout_cpu build/fanout-cpu/reproduce-before bf56df5c
python3 -m tools.synth.fanout_cpu build/fanout-cpu/reproduce-after 548861ff
python3 -m unittest discover -s tools/synth -p test_netlist_paths.py
```
协调者经 ask 扩展归属至 tools/synth/ 的测量入口、端点分析及对应测试；工具测试14项PASS。参考综合流程为按 cpu_subsys.f 展开文件、加 ip_stubs.v、转换 preserve、chparam RVC_EN=0、proc/flatten/保留驱动FF、synth -noabc、abc -lut 6 -dress、opt_clean、write_json；load按全部输入pin计，LUT级数按 netlist_paths.py 的 FF/IP 边界计。

提频待决策建议（已 ask，仅列建议，本 Task 不实现）：
IB read_ptr（副本）→译码/非法判断→D重定向→I$ data RAM rd_clk_en：参考 LUT 16→22；F1 PC/CE整体终点参考28→27，均不能替代PDS时序。
方案一：D级JAL重定向与取指请求之间加一级，预计未命中BTB的JAL代价2→3拍；CoreMark增量约为未被其他停顿覆盖的D重定向次数，未测量，不能给固定百分比。
方案二：预译码时寄存合法性/目标，把判断移到IB之前；若加入新取指级，则冷启动/恢复至少多一拍，JAL早重定向能否维持2拍需重新设计；若重用现有边沿，则可能维持周期但把路径压力前移。
CoreMark窗口已测误预测事件总数79637（含E/D），固定现有预测轨迹，仅作方案一每次全暴露多一拍的宽松估算上界：约+2.86%周期、得分约-2.78%；D事件数与停顿重叠未分离，两方案的实际影响均待单独评估并由用户决定。
