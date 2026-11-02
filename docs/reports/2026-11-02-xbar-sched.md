# T-XBAR-SCHED 测量报告
基线：`f2028ed003ba54a0cdd5d4aa626bf4a43dd1b057`；RTL：`8abc899452faca951122155b357cfdeee9ab6261`。
做法：AR 握手保存 5 位 LEN+1；当前 free_cnt 的比较仍进入原有 eligible_r，不增拍。
读缓冲并行计算七口 `free_cnt + release - beats[p]`，授权后独热选择；与原先减后加在 8 位模运算中等价，描述符和 R 返回逻辑不变。
工具：本机 Yosys 0.70+219（5053d0e26），ABC LUT6；R RAM 黑盒、W RAM 按原流程推断；无器件/速度等级、无物理时钟约束，不能代替 PG2L200H PDS 时序。
| 路径/资源 | 改前 | 改后 |
|---|---:|---:|
| funded_r[0] → free_cnt_o 最长 LUT 级数 | 18 | 15 |
| 任意起点 → free_cnt_o 最长 LUT 级数 | 21 | 17 |
| free_cnt_o → eligible_r 最长 LUT 级数 | 6 | 6 |
| mem_subsys 参考 LUT / FF | 30087 / 38016 | 30149 / 38046 |
逐拍证据：`build/xbar-sched/miter.py` 双实例同激励，全部接口输出及授权/预留/free_cnt 比较，FULL=1 通过；数据寄存器不增加复位。
检查：Verilog 风格及子系统 lint 零告警；单元 smoke（Verilator 5.020 / Icarus 12.0）2 PASS；模块 smoke 14 PASS / 0 FAIL；full 42 PASS / 0 FAIL；board_render 1 PASS / 0 FAIL；board_vnpu 1 PASS / 0 FAIL。
BW-01 改前/后相同：65536 beats / 69650 cycles = 94.093%；11 项基线统计、拍数和仿真结束时刻逐项完全一致（compare.log）。
全部验收在本机以 flock、-j 1 串行执行；用户提供的仿真主机（环境不记录）传输失败，未用于验收，专用目录已清理。
原始数据：`build/xbar-sched/{before,after}/mem_subsys/`；基线日志 `build/xbar-sched/before-runs/`；最终验收日志 `build/regress/`，摘要 `build/xbar-sched/{unit-smoke,miter,block-smoke,block-full,board-render,board-vnpu,compare}.log`。
复现（两个版本各运行回归并保存 run.log，比较 PASS/BW-01/DRR/FLOW 行；不修改期望值）：
```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/mem
(cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_mem_subsys -f mem_subsys.f)
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/mem_xbar -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/mem_subsys -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/block/mem_subsys -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/soc/board_render -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/soc/board_vnpu -j 1
python3 tools/synth/fanout_soc.py build/xbar-sched/before --target mem_subsys --revision f2028ed0
python3 tools/synth/fanout_soc.py build/xbar-sched/after --target mem_subsys --revision 8abc8994
python3 - <<'PY'
import json; from pathlib import Path
from tools.synth.netlist_paths import analyze
for label in ('before', 'after'):
    d = json.loads(Path(f'build/xbar-sched/{label}/mem_subsys/hardnet.json').read_text())
    names = {n: 'ip_'+n for n,m in d['modules'].items() if int(m.get('attributes',{}).get('blackbox','0'),2)}
    d['modules'] = {names.get(n,n):m for n,m in d['modules'].items()}
    for m in d['modules'].values():
        for c in m.get('cells',{}).values(): c['type'] = names.get(c['type'],c['type'])
    for start,end in [(r'u_xbar.u_sched.funded_r\[0\]',r'u_xbar.u_rbuf.free_cnt_o'),(None,r'u_xbar.u_rbuf.free_cnt_o'),(r'u_xbar.u_rbuf.free_cnt_o',r'u_xbar.eligible_r')]: print(label,start,analyze(d,[start] if start else None,[end])['max_levels'])
PY
```
