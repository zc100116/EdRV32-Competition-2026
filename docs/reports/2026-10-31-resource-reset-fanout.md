# B3 复位负载与数据通路复位清单（T-RST1，2026-10-31）

实现 commit：`34293310`；基线 commit：`d06e32d646045f548f658177a9b1f9ef3f7e3c3c`；本任务只改 reset_ctrl、原语及其源列表和测试，未改下列业务 RTL。
工具：Yosys 0.70+219（5053d0e26），Verilator 5.020、Icarus 12.0；FPGA_MODE，SoC 默认参数，目标 PG2L200H-6（通用综合，无器件映射/时序约束）。
计数取粗粒度综合 `loads.json` 中 `$adff/$adffe` 的 Q 位（保留 RTL 状态编码，不做门级映射），按 ARST 网络及 Q 的源声明层次归属、合并共享位只计一次；RAM/APM 黑盒内部、同步复位 FF 不计入。VIN 内部 `rst_mem_n && !clear_r` 归入 rst_mem；POR 与 reset_ctrl 自身不计入业务区域。数值是 PDS 前的参考，不能等同于 B3N 扇出 7098/4799 或 B3VN 未布通数。
JSON 私有实例/网络名加 `audit_` 前缀以避开分进程综合的 Yosys 自动编号冲突；不改连线、端口或公开层级名。
原始数据：`build/reset_fanout/{baseline.ys,coarse.json,with_ip.json,finish.ys,counts.txt,q_registers.txt,reset_assigns.txt}`；全 SoC 异步 FF 为 22644（含控制器/POR；表 1 仅业务区域）；最终综合数字为 `build/reset_fanout/mapped-summary.txt` 中的自总结（粗粒度网表按下列命令重建）。以下命令可从基线重建（缺失硬 IP 只建立端口黑盒，不推断其内部 FF）：
```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build/reset_fanout/baseline; git archive d06e32d6 rtl tools/synth | tar -x -C build/reset_fanout/baseline
python3 - <<'PY'
from pathlib import Path
from tools.regress import expand_files
import json, subprocess
p=Path('build/reset_fanout'); b=(p/'baseline').resolve(); top='edrv32_soc_top'; files=[x for x in expand_files(b/'rtl/filelists/soc.f') if not x.startswith('+')]
s=f'read_verilog -D FPGA_MODE -I{b}/rtl/include '+ ' '.join(files)+f' {b}/tools/synth/ip_stubs.v\nhierarchy -top {top}\nproc\nflatten\nopt\nwreduce\nopt_clean\nwrite_json {p}/coarse.json\n'; (p/'baseline.ys').write_text(s)
subprocess.run(['yosys','-Q','-T','-l',str(p/'yosys.log'),'-s',str(p/'baseline.ys')],check=True)
j=json.loads((p/'coarse.json').read_text()); mods=j['modules']; cells=mods[top]['cells']; unknown={c['type'] for c in cells.values() if not c['type'].startswith('$') and c['type'] not in mods}
for t in unknown:
    c=next(c for c in cells.values() if c['type']==t); ports={}; i=2
    for n,v in c['connections'].items():
        w=max(1,len(v)); ports[n]={'direction':'output' if n in ('rd_data','p','P','COUT','CPO','CXBO','CXO') else 'input','bits':list(range(i,i+w))}; i+=w
    mods[t]={'attributes':{'blackbox':'1'},'ports':ports,'cells':{},'netnames':{}}
for c in cells.values():
    if c['type'] in unknown: c['parameters']={}
for m in mods.values():
    for k in ('cells','netnames'): m[k]={('audit_'+n if n.startswith('$') else n):v for n,v in m[k].items()}
(p/'with_ip.json').write_text(json.dumps(j)); (p/'finish.ys').write_text(f'read_json {p}/with_ip.json\nsynth -top {top} -run begin:coarse -nofsm -noshare\nwrite_json {p}/loads.json\nstat\n')
subprocess.run(['yosys','-Q','-T','-l',str(p/'finish.log'),'-s',str(p/'finish.ys')],check=True)
m=json.loads((p/'loads.json').read_text())['modules'][top]; print(sum(len(c['connections']['Q']) for c in m['cells'].values() if c['type'] in ('$adff','$adffe'))) # 22644
PY
```
表 1：列顺序为 rst_sys / rst_mem_core / rst_mem / rst_npu / rst_pix / cam0,cam1 / eth_rx,eth_tx；0 表示无该路负载。粗体表示初值区域超过 1000。
| 子系统顶层 | 各路总数（上述列顺序） | 规格 2.10 初值区域及负载（FF 位） |
|---|---|---|
| cpu_subsys | 6363 / 0 / 0 / 0 / 0 / 0,0 / 0,0 | core **2055**；I$ **1579**；D$+CACHE_CTRL **2729** |
| sys_subsys | 1131 / 16 / 0 / 0 / 0 / 0,0 / 0,0 | sys_xbar+ROM/SRAM 72；APB+外设 **1059**；mem_core 16 |
| mem_subsys | 47 / 5609 / 0 / 0 / 0 / 0,0 / 0,0 | xbar+性能监测/P6：mem_core **5537**、sys 0；网关：mem_core 72、sys 47 |
| npu | 0 / 0 / 93 / 1483 / 0 / 0,0 / 0,0 | 卷积 701；非卷积 103；描述符+DMA+寄存器/桥及顶层 679；mem 93 |
| vin | 0 / 0 / 1856 / 0 / 0 / 32,32 / 0,0 | mem **1856**（含派生复位）；cam 各 32 |
| pix | 0 / 0 / 366 / 0 / 0 / 0,0 / 0,0 | 每路一份 |
| geo | 0 / 0 / 485 / 0 / 0 / 0,0 / 0,0 | 每路一份 |
| rnd | 0 / 0 / 962 / 0 / 0 / 0,0 / 0,0 | 每路一份 |
| disp | 0 / 0 / 1619 / 0 / 775 / 0,0 / 0,0 | mem **1619**；pix 775 |
| eth | 0 / 0 / 1551 / 0 / 0 / 0,0 / 43,72 | mem **1551**；rx 43；tx 72 |
| 业务合计 | 7541 / 5625 / 6932 / 1483 / 775 / 32,32 / 43,72 | 22535；其余 109 位为 POR/控制器 |
建议拆分（仍各为一级副本）：CPU core 将 1024 位方向预测计数器分成两组 512，CSR 与其余控制分开；I$/D$ 的 512 位 valid/dirty/LRU 阵列分别分配副本，再合并小于 1000 的控制负载。
mem xbar 将各端口统计/快照按端口分组（单份≤1000），调度+队列单列；perf_mon 的 512 位直方图与配置/运行状态分开；DDR 网关维持现有划分。
SYS 的 APB+外设再拆为 GPIO+CLINT 与 APB/UART/I2C/PLIC；VIN 将寄存器区与通道/格式化/内存源分开；DISP 分为寄存器 908 与其余 mem 711；ETH 的寄存器区 1170 再拆配置与性能统计；VIN 的寄存器 973 与其余 mem 883。表中区域含开发初值未命名的顶层控制、寄存器和桥，避免漏计。
表 2：疑似可删复位项，按综合保留位宽合计降序；括号为保留位数，声明位宽完整列出，只有清单、未实施删除；合计 128 位。
| 子系统/合计 | 文件:复位赋值行；信号与声明位宽 | 复位；判断理由 |
|---|---|---|
| pix 66 | `rtl/media/pix/edrv32_pix.v:203` frame_cfg_r[31:0]（19）、`:204` frame_contrast_r[8:0]、`:205` frame_bias_r[9:0]、`:206` frame_thresh_r[7:0]；`rtl/media/pix/edrv32_pix_filter.v:270` width_r[9:0]×2 | rst_mem；帧配置由首次 SOF 捕获；首行 EOL 写入行宽后才进入尾行 flush，均为配置/尺寸影子 |
| disp 46 | `rtl/media/disp/edrv32_disp_reader.v:138` layer_ctrl_r[1:0]、`:140` l1_y_end_r[10:0]、`:141` l1_beats_r[7:0]、`:142` l0_beats_r[6:0]、`:143` l0_limit_r[9:0]（8）、`:144` l1_limit_r[9:0] | rst_mem；S_IDLE 接受 frame_start 时全部覆写，S_LOAD/S_INIT 后才参与请求，属于帧配置影子 |
| rnd 16 | `rtl/media/rnd/edrv32_rnd_affine.v:177` initial_mask_r[15:0] | rst_mem；start 装入偏移负载，S_X/S_Y 串行移位使用，非控制计数器 |
| 其余各 0 | cpu、sys、mem、npu、vin、eth、geo | 未确认其他符合删除条件的项；大量执行负载和 RAM 已无复位，valid/状态/计数器/指针保留 |
明确排除（软件可见）：全部 APB/CSR 寄存器及性能快照；CACHE_CTRL op_addr/op_size/err_addr；VIN 三通道 done_info/done_frame_id 由 APB 直接读取，不能按“完成负载”删除。
明确排除（无 valid 保护、影响功能）：CPU frontend `:386` f1_pc_r 是首次取指地址；CSR `:161` event_count_r 无条件参与事件累加；GEO regs `:147` pixel_r、VIN regs `:211` cfg_errors_r、ETH regs `:309` perf_length_r 在事件 valid 为 0 时仍用于累加；DISP scan `:211` params_r / frame_params_r 与四个 extent 寄存器在参数 valid 为 0 时仍被 frame_begin 复制、参与扫描，复位默认参数有功能意义。
验证：`flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke -j 1 --path verif/unit/soc_reset_ctrl`：两频率比×两模拟器，4 PASS；sys_subsys_reset 另有 2 PASS；SY-03/04/05 和新增 SY-07 均覆盖。系统块 SY-01–06 通过（`run.py 901` 构建组9后用 `+CASE_ID=902..906` 执行）；board_render smoke 1 PASS，lint 0 告警。
检查：`python3 tools/check/verilog_style.py rtl/` 175 文件 0 告警；reset_ctrl `verilator --lint-only -Wall` 0 告警；四板 mock import PASS（render/npu/vision/vnpu：104/107/113/146 源文件）。日志在 `build/reset_fanout/`、`build/sys/{901,reset-copy}/`、`build/regress/smoke/unit/soc_reset_ctrl/`；板级结果保留自总结 `board-summary.txt`。
