# CPU v2 探针设计记录

本记录汇总 CPU v2 探针阶段（cpu-v2-plan P01–P09）的探针结构、测量端点和 IP；PDS 实测结果另见测量报告。

## FMA 探针

背景/约束：P09 按 fpu-spec v0.1 2.2/5.2/5.3/7.1 实现 FP32 四变体，8 拍、II=1、150 MHz 约束。
决策：独立 CPU APM 包装；完整 48 位积、77 位对齐加减、并行双向幅值/LZA；无 ADD/MUL 旁路。
E0 为调用者输入寄存器；下表 E1–E8 是其后八个采样沿，E8 本地结果可转发。

| 拍 | 工作及主要起点 → 终点寄存器 | XC7 代理最大级数 |
|---|---|---:|
| E1 | `a_r/b_r/c_r` → `e1_*_mantissa_r/e1_*_lz_r/e1_*_exp_r`；分类/特殊值/尾零计数 | 10 |
| E2 | `e1_*` → head 内部 X/Y（直接采样规格化输出）；指数差 → `e2_delta_r/e2_base_exp_r` | 9 |
| E3 | head X/Y → MULT；tail 错拍输入 → X/Y；`e2_*` → `e3_shift_r/e3_limit_r` | 6 |
| E4 | head MULT → P/CPO；tail X/Y → MULT；`e3_c_r` → `e4_c_r/e4_sticky_r`，对齐低3层 | 4 |
| E5 | head CPO/tail MULT → tail P/CPO；`e4_c_r` → `e5_c_r`，对齐高4层并合 sticky | 4 |
| E6 | tail P + `e5_c_r` → `e6_forward_r/e6_reverse_r`；并行 LZA → `e6_*_count*_r` | 10 |
| E7 | `e6_*_hit/count*_r` → `e7_magnitude_r`；LZA末级、规格化粗移4层、并行指数候选 | 12 |
| E8 | `e7_magnitude_r/e7_right_r` → `result_o/flags_o`；细移3层、1位校正、舍入/打包 | 17 |

APM 恰为2颗：`a×b[15:0]` head → CPI/CPO 专线右移16 → `a_delayed×b_delayed[23:16]` tail。
链为 E2–E5 四拍；head P 低16位再延1拍，与 tail P 低32位拼成完整48位积；X/Y/MULT/P/CPO全开。
上述 E2–E5 级数只计外围逻辑；APM 内部及专线在 Yosys 中是寄存黑盒，须由 PDS 实测。
测量版本：`e1fd27d5c`（RTL/测试；本节由协调者追加提交）；命令：
`python3 verif/unit/cpu2_fpu_fma32/levels.py`（Yosys 0.70+219，XC7 LUT6/MUXF各1，连续carry链按2级）。
原始数据：`build/cpu2_fpu_fma32/levels/{synth.log,xc7.json,stages.json}`；复现脚本随提交保存。
最差段实际端点：E1 `e1_c_mantissa_r[0]`→`e1_special_result_r[31]`（综合合并后的寄存器别名）；
E2 `e1_b_exp_r[0]`→`e2_base_exp_r[0]`；E3 `e2_base_exp_r[1]`→`e3_limit_r[0]`；
E4 `e3_shift_r[2]`→`e4_sticky_r`；E5 `e4_right_r`→`e5_c_r[0]`；
E6 `e5_far_r`/tail P→`e6_*_count1_r`；E7 `e6_forward_hit0_r`→`e7_magnitude_r[0]`；
E8 `e7_right_r`→探针 `result_w[31]`（FMA结果寄存器）。
优化将 C 对齐移到 E4/E5、sticky改尾零比较、下溢约束预埋入LZA标记，E7首轮16级降至最终12级；
E8预计算指数候选由19降至17级。仍明显超过估算，协调者 ask 已同意保留8拍并按超预算探针交PDS判断。
功能验证：仿真主机 Verilator 5.051，`run.py smoke` 131,120、`run.py full` 1,121,120向量全PASS；
最终 `tools/regress.py full --path verif/unit/cpu2_fpu_fma32 -j 1` 为2 PASS/0 FAIL（full 130秒、缓存构建smoke 7秒）。
8拍/II=1逐位比较结果与flags；smoke首次含编译约30秒、full仿真约10秒。
`tools/check/verilog_style.py` 与 Verilator `--lint-only -Wall` 零告警；参考模型仅标准库 Fraction。
影响/状态：探针与正式数据通路源码已实现；150 MHz未通过物理验证，不冻结F03、不加拍、不用multicycle。

## 整数探针

背景/约束：P01/P03/P05/P07 按 cpu-v2-spec v0.1 5.2/5.4/5.5/7、C2-I4 实现满配结构；150 MHz 尚待 PDS。
决策：四个独立探针；不做整核提交、LSU/miss 控制；输入由顶层 `*_r` 捕获，输出再由顶层同名观察寄存器捕获。
IB_DEPTH=8，按协调者确认使用12物理项（固定头），显式 enqueue/remove；不做整核信用/在途控制。
RF 的 x1..31 LVT、双写年轻优先、显式 WB 转发；F2 在物理字后查 LVT，5bit候选随IB保存/同沿修正。
WB 两区由顶层 `fetch_wb_*_r/fetch_wb_*_copy_r` 同沿复制且保留；一区六项+两输入，另一区六项。
TAGE 历史为(4,12,32,96)，折叠已注册；D预读当前行，EX/MEM按年龄训练，单待写项镜像预测/训练副本。
TAGE 行编码 `{valid,tag10,counter3,useful2}`；provider=0表示基表，1..4表示由短到长的标签表。
同沿查询旁路阵列写与新待写项；F1注册index/tag匹配，F2只合并匹配/方向，避免先选整行再比较标签。
AGU 的两个32×32 RF读副本是独立路径副本；D$只读数据/tag与选路，输出先本地捕获，下一拍才供消费者。

| 规格7关键段 | 起点 → 终点寄存器（省略顶层层次） | Yosys LUT6级数 |
|---|---|---:|
| RF 4R2W补充读路径 | `rf_id_rs_r/rf_id_owner_r/rf_wb_*_r` → `rf_id_data_r` | 5 |
| RF owner预解码后ID→AGU | `id_agu_id_candidates_r/id_rs1_r/wb_*_r` → `u_id_agu.ex_addr_r` | 16 |
| 双bank F2→LVT/WB优先 | `u_fetch.g_bank[*].g_way[*].u_data/u_tag`读输出 → `u_fetch.ib_candidates_r[*]` | 15 |
| TAGE F2/双bank方向 | `u_tage.g_table[*].g_bank[*].u_predict`读输出 → `tage_f2_prediction_r/alternate_r/provider_r` | 14 |
| 待写训练命中前置 | `u_tage.pending_*_r` → `u_tage.f2_shadow_index_r/tag_r/direction_r` | 22 |
| DRM load→操作数捕获 | `u_id_agu.g_way[*].u_data/u_tag`读输出 → `u_id_agu.operand_data_r/hit_r` | 4 |

级数是通用ABC LUT6参考：同步RAM/FF输出切断，异步LUTRAM算1级；不含Pango进位链、宏延迟、布线或布局。
实际最深待写段经过MEM更新→EX同址转发→写选择→F1命中；级数明显高于模型，不能据模型宣称150 MHz成立。
保持当前拍边界交PDS测量；是否另立训练/IB结构优化任务由协调者依据结果决定，不自行加拍或multicycle。

| IP 创建说明（`fpga/ip/ip_*_cpu2_*.md`） | 几何 | 顶层实例数 |
|---|---|---:|
| `ip_lutram_cpu2_rf` | 32×32，异步 | 10 |
| `ip_lutram_cpu2_btb` | 64×59，异步；`{1,PC[31:9],type3,target32}`，有效另有FF复位 | 2 |
| `ip_lutram_cpu2_fast` | 1024×2，异步；4096项四bank，三个读副本 | 12 |
| `ip_ram_cpu2_cache_data` | 2048×32，一拍读 | 8 |
| `ip_ram_cpu2_cache_tag` | 512×19，一拍读；`{valid,addr[31:14]}` | 6 |
| `ip_ram_cpu2_tage / tage_train` | 256×16 / 512×16，一拍读 | 8 / 4 |
| `ip_ram_cpu2_base / base_train` | 2048×2 / 4096×2，一拍读 | 2 / 1 |

估算：数据RAM 8×2=16 DRM36K；tag 6×0.5=3；TAGE预测/训练(8+4+2+1)×0.5=7.5；总26.5 DRM36K。
LUTRAM按32bit/LUT估算：(10×32×32+2×64×59+12×1024×2)/32=1324 LUT，含独立AGU与快速gshare副本。
上述为按RAM18K最小宏取整的估算，碎片/实际映射以PDS为准；RAM数据不复位，TAGE初始0、base/fast初始弱不跳。
复现版本：本整数探针交付提交；逻辑级数命令 `python3 verif/unit/cpu2_tage/levels.py`（Yosys 0.70+219）。
原始数据：`build/cpu2_int/levels/{synth.log,mapped.json,levels.txt}`，脚本随提交保存。
仿真主机 Verilator 5.051：四个smoke分别10/12/19/10秒（RF/fetch/TAGE/AGU），全部PASS；fetch最终区域复制版另测PASS。
命令：`for m in rf fetch tage id_agu; do python3 tools/regress.py smoke --path verif/unit/cpu2_$m -j 2; done`。
独立参考只通过公开接口比对；覆盖WB/WAW/x0/等待owner切换、任意字起点/跨行/路选/BTB最老taken、训练碰撞/旁路/折叠。
风格：`python3 tools/check/verilog_style.py rtl/cpu2/edrv32_cpu2_*.v rtl/tech/edrv32_ram_cpu2_*.v fpga/rtl/edrv32_fpga_probe_cpu2_int_top.v`，零告警。
lint：`(cd rtl/filelists && ../../tools/check/lint.sh -DSIM_MODE --top-module edrv32_fpga_probe_cpu2_int_top -f cpu2_probe_int.f)`，零告警。
影响/状态：RTL/测试/IP说明/导入文件已就绪；PDS由协调者另发Windows任务卡，频率和真实DRM/LUTRAM尚未实测。

PDS 2022.2-SP6.1 在 rtl-infer/DFF-inference 崩溃：generate 展开的多个 always 写同一模块级 reg 数组。
整数探针改为每次迭代独占局部 reg，由同作用域 assign 接到模块级扁平 wire，读取使用常量位段。
RF LVT 同样拆为局部位寄存器；不跨 generate 层次引用、不切片局部数组，保持原有行为与拍边界。
