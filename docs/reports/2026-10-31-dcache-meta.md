# D$ tag RAM 元数据测量（2026-10-31）
基线 b3 `217ff5415c4913c5ca2b903d6c4b499345d864b1`；改后为本报告同提交；cache-spec v0.9 / testplan v0.4。
Yosys 0.70+219、Verilator 5.020；`edrv32_cpu_subsys`，RVC_EN=0，FPGA_MODE，RAM/APM 黑盒，ABC LUT6；PG2L200H-6 为目标器件，未取得原生资源/WNS。
|参考资源|改前|改后|变化|
|---|---:|---:|---:|
|LUT6|41493|28987|-12506|
|FF|13765|11472|-2293|
扇出按同一 hardnet.json 的输入 pin 计数，排除顶层 clk_i/rst_n_i；前 10：
|改前网络（扇出）|改后网络（扇出）|
|---|---|
|`timing_net_2126[0]` (2059)|`timing_net_220[0]` (1024)|
|`$abc$259057$timing_net_2767_new[0]` (1024)|`$abc$216917$timing_net_1567[8]_new[0]` (1023)|
|`$abc$259057$timing_net_2765_new[0]` (1024)|`timing_net_954[0]` (657)|
|`timing_net_217[0]` (1024)|`u_core.e_operand_load_w[0]` (566)|
|`$abc$259052$timing_net_1537[8]_new[0]` (1023)|`ic_req_addr_w[3]` (547)|
|`timing_net_1125[0]` (656)|`$abc$216917$timing_net_1567[7]_new[0]` (543)|
|`u_dcache.buffer_valid_r[0]` (601)|`timing_net_1567[1]` (525)|
|`timing_net_4024[0]` (585)|`u_core.d_data_w[52]` (521)|
|`u_core.e_operand_load_w[0]` (566)|`u_icache.u_tag1.wr_en_i[0]` (513)|
|`ic_req_addr_w[3]` (547)|`timing_net_2768[0]` (513)|
端口：store buffer 排空时写 {1,1,buffer tag}；RAM 旧数据碰撞用两位寄存旁路补脏，维持连续命中吞吐。维护开始前排空 buffer；fill/B/MCHECK 属于互斥状态，各路可并行清位，写回清脏用 wb_addr 保存的 tag，不破坏预取输出。
替换清有效位合并到最后一拍 fill 写（出错写 valid=0）；阻塞 miss 期间无其他阵列使用者，因此不增加周期，也消除 miss 判定与 buffer drain 的双写冲突。初始化独占两路写口，512 拍后 ready；LRU 仍为寄存器。
32 个组段标志由 buffer drain 置位；范围维护保守保留；整体 clean 扫完整个 16 组后清位。协调者已允许脏组段内逐组扫描的必要周期变化。
|B2 测量窗口（改前→改后）|RVC=0 周期 / IPC|RVC=1 周期 / IPC|
|---|---|---|
|R-01|8559→8559 / 1.974296|8560→8560 / 1.974065|
|R-02|16465→16465 / 1.026298|16462→16459 / 1.026485→1.026672|
|R-03 窗口0；1|12576→12576 / 0.692271；16681→16681 / 0.521971|12577→12577 / 0.692295；16678→16678 / 0.522065|
|R-04|263876→263876 / 0.250303|263875→263875 / 0.250304|
|R-05 CoreMark|2774323→2774323 / 1.038816|2787561→2787561 / 1.033883|
CoreMark 10 iterations，O2，read latency=2，CRC 均 PASS；Total ticks：RVC0 2774323→2774323，RVC1 2787555→2787555。
窗口 HPM 逐项一致，例外 R02/RVC1 的事件1/2/3/5/12/16为503→504、15892→15890、68→65、15866→15865、58→56、10→9。旧 RTL 仅加512拍 ready 延迟的控制实验完全复现新窗口及全部16项 HPM，确认来自初始化启动相位；严格性能验收尚未完成，例外口径待协调者答复问题 msg_59e3da7b3549。
整程 HPM 含启动：stall 多459/461/475拍（初始化与取指重叠）；其余差异和各窗口逐项比较见 `build/dcache-meta/perf-comparison.txt`。
|整体 clean（无反压，接收→BUSY清零）|改前周期|改后周期|
|---|---:|---:|
|无脏行|32|32|
|单脏行，组0 / 511|47 / 47|92 / 92|
|32个组段各一脏行|512|1952|
|1024行全脏|13856|13856|
每个实际含 D 个脏组的脏组段比旧版多 3×(16−D) 拍；只有保守标志而无脏组时多48拍。维护计数在终止下降沿更新后取样，修正原 TB 的 delta 竞争；前后同法。
DC-01～DC-07 无反压响应周期前后逐项一致：8/1；8+28×1；8/1/1；8；8/8/8；8/8/19；8/1/8/19（流式命中均1拍）。MT-10 的 N=1/2/16/128/511/512/513/2048 均为4/5/19/131/514/515/515/515拍，前后相同；DC-16 覆盖随机 metadata、中途复位、512拍拒收和1024行冷缺失；DC-17/MT-13 新增；未删减其他项。
回归：unit/cache_dcache 1/1、unit/cache_ram 1/1；block/cpu smoke 74/74、sys_cpu smoke 3/3；cpu_b2 perf RVC0/1 各5/5；cache smoke 28/28、full 41/41（DC-15 50 seeds）、board_render/board_npu smoke 各1/1。
风格检查及 CPU 子系统 `--lint-only -Wall -DSIM_MODE`：0 告警。日志/摘要：`build/dcache-meta/`；映射网表：`{before,after}-synth/{coarse,hardnet}.json`；本机 B2 原始日志 `build/cpu_b2/r*/rvc*/run.log`。
复现先 `. ~/.local/opt/edrv32/env.sh`；本机仿真加 `flock /tmp/edrv32-sim.lock`、构建 `-j 1`。原始基线用 git archive 217ff541，第三方 CoreMark 使用仓库固定的子模块版本。
```sh
python3 tools/check/verilog_style.py rtl/cache/edrv32_dcache.v rtl/tech/edrv32_ram_dcache_tag.v; (cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_cpu_subsys -f cpu_subsys.f)
for p in verif/unit/{cache_dcache,cache_ram} verif/block/{cache,cpu,sys_cpu} verif/soc/{board_render,board_npu}; do flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path "$p" -j 1; done
flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/block/cache -j 1
for v in 0 1; do for t in r01 r02 r03 r04 r05; do flock /tmp/edrv32-sim.lock python3 tools/cpu/b2_run.py "$t" --rvc "$v" --read-latency 2; done; done
python3 - <<'PY'
from pathlib import Path; import subprocess; from tools.synth.yosys_synth import read_filelist; from tools.rnd.timing_measure import retain_multipliers
out=Path('build/dcache-meta/reproduce'); out.mkdir(parents=True,exist_ok=True); files=[]; incs=set(); read_filelist(Path('rtl/filelists/cpu_subsys.f'),files,incs); s=Path('tools/synth/ip_stubs.v').read_text(); a=s.index('module ip_ram_dcache_tag'); b=s.index('endmodule',a); width='[19:0]' if '[19:0]' in Path('rtl/tech/edrv32_ram_dcache_tag.v').read_text() else '[17:0]'; (out/'stubs.v').write_text(s[:a]+s[a:b].replace('[17:0]',width)+s[b:])
(out/'coarse.ys').write_text('read_verilog -D FPGA_MODE '+' '.join('-I'+v for v in sorted(incs))+' '+' '.join(files)+f' {out}/stubs.v\nchparam -set RVC_EN 0 edrv32_cpu_subsys\nhierarchy -top edrv32_cpu_subsys\nproc\nflatten\nopt\nwreduce\nopt_clean\nwrite_json {out}/coarse.json\n')
for stage in ['coarse','hardmul']:
    subprocess.run(['flock','/tmp/edrv32-sim.lock','yosys','-Q','-T','-l',str(out/(stage+'.log')),'-s',str(out/(stage+'.ys'))],check=True)
    if stage=='coarse': retain_multipliers(out,'edrv32_cpu_subsys')
PY
```
综合脚本依 `tools/rnd/timing_measure.py` 方法：read_filelist(cpu_subsys.f)；read_verilog -D FPGA_MODE；chparam RVC_EN=0；hierarchy/proc/flatten/opt/wreduce/opt_clean → coarse.json；retain_multipliers；synth -flatten -noabc；abc -lut 6 -dress；opt_clean → hardnet.json；stat。原始测量脚本在 build/dcache-meta/measure.py；上面的自包含命令可在前后源码快照各执行一次。
唯一存根差异：临时 stubs.v 中 ip_ram_dcache_tag 输入/输出改20位（基线18位）；其余取 tools/synth/ip_stubs.v。该归属外的正式存根仍为18位，已通知协调者同步。
