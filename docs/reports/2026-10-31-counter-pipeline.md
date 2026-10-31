# 统计与 APB 命令打拍测量（2026-10-31）

改前 b3 `034885e6`；改后为本报告所在提交的 RTL。Yosys 0.70+219 / Verilator 5.020；SoC v0.21 §4.3/§7.1（基于 `1c38d04f`）。
同配置完整 mem_subsys/eth 顶层，FPGA_MODE、RAM/变量乘法黑盒、ABC LUT6；125 MHz 目标；PG2L200H-6 实际资源/WNS 未取得。
范围调整：PERF_MON/P6 保持 034885e6 基线，由 T-PMRM 删除；RND/NPU 不在本任务。

- 六块寄存器统一在 APB setup 锁存 paddr/pwrite/pwdata/pstrb，access 只用本地值；xbar cfg_write 译码归回寄存器块，MDIO 命令字从本地寄存值送出，访问周期不变。
- xbar：RD/WR_TXN、RD/WR_BEAT、WAIT_MAX/SUM、URG_CNT、DIR_SWITCH、DS_BUSY、WINDOW_CYC 事件一级寄存；SNAPSHOT/CLEAR 各八份同拍命令（七端口+全局，keep 保留，独立副本 8+8；单份 SNAPSHOT/CLEAR 最大负载 208/228），优先级和饱和不变。
- ETH：PERF0–10 原有事件级保留；DOORBELL/ABORT/MDIO_START 寄存，SOFT_RST 输出使用原有 clear_regs_r；MDIO 命令字与脉冲对齐。DONE_COUNT、CUR_DESC、WINn_BYTES 不变。
- DISP：扫描侧 PERF0/1/2/5/6 增加事件级；PERF3/4 已寄存；寄存器块 ENABLE/ABORT/SOFT_RST 已经过寄存，无新增级。
- VIN：PERF0–15 原有事件级及 DONE_COUNT 功能别名保留；ABORT/SOFT_RST/MSRC_START 在寄存器块寄存；配置写时刻不变。
- GEO：PERF0–5 原有事件级保留；DOORBELL/ABORT/SOFT_RST 寄存。PIX：PERF3 discard 补事件级，PERF1/2 原有级保留；soft_pending 输出去掉组合请求旁路，soft_reset 仅由已有 pending 和当前 busy 生成，空闲时实际清除晚 1 拍（协调者确认），保护同写拍接收的新帧。
- 协调者确认：PIX PERF0 继续读 DONE_COUNT 功能别名，Gamma 是数据寄存器写，保持原时序；xbar/SoC 事件接口无需改线。

|顶层|LUT6 改前→后|FF 改前→后|最长 LUT 级数 改前→后|
|---|---:|---:|---:|
|mem_subsys|27526→29275|13105→13180|28→26|
|eth|9705→9740|5104→5152|20→20|
独立寄存器块综合的原始 APB 输入 pin 负载（paddr[2] / pwdata[0]）：mem_xbar 8→1 / 33→1；eth 4→1 / 3→1；disp 7→1 / 4→1；vin 4→1 / 10→1；geo 7→1 / 2→1；pix 6→1 / 1→1。
扇出按输入 pin 数；排除顶层时钟/外部复位。每格为网络名（扇出），前十如下：

|序号|mem_subsys 改前|mem_subsys 改后|ETH 改前|ETH 改后|
|---:|---|---|---|---|
|1|`u_xbar.u_regs.clear_w[0]` (1592)|`timing_net_828[0]` (830)|`u_regs.clear_regs_r[0]` (567)|`clear_w[0]` (591)|
|2|`u_xbar.u_regs.snapshot_w[0]` (1552)|`timing_net_1981[0]` (587)|`$auto$alumacc.cc:578:replace_alu$491.CO[10]` (498)|`$auto$alumacc.cc:578:replace_alu$491.CO[10]` (498)|
|3|`timing_net_989[0]` (830)|`u_xbar.w_port_r[1]` (581)|`$auto$alumacc.cc:578:replace_alu$491.BB[6]` (463)|`$auto$alumacc.cc:578:replace_alu$491.BB[6]` (463)|
|4|`timing_net_1778[0]` (587)|`u_xbar.w_port_r[2]` (580)|`timing_net_757[5]` (463)|`timing_net_775[5]` (463)|
|5|`u_xbar.w_port_r[1]` (581)|`$abc$236637$auto$simplemap.cc:148:simplemap_reduce$22297[2][0]` (497)|`timing_net_749[7]` (456)|`timing_net_768[7]` (456)|
|6|`u_xbar.w_port_r[2]` (580)|`u_perf_mon.soft_reset_w[0]` (415)|`$abc$95648$auto$simplemap.cc:148:simplemap_reduce$18575[2][0]` (373)|`$abc$95697$auto$simplemap.cc:148:simplemap_reduce$17293[2][0]` (403)|
|7|`u_perf_mon.soft_reset_w[0]` (415)|`u_p6_arb.w_owner_r[0]` (292)|`$abc$95635$auto$simplemap.cc:148:simplemap_reduce$3342[2][0]` (350)|`$abc$95684$auto$simplemap.cc:148:simplemap_reduce$3446[2][0]` (350)|
|8|`u_p6_arb.w_owner_r[0]` (292)|`u_xbar.g_port[1].w_read_w[0]` (288)|`u_rx_packets.read_ptr_r[0]` (306)|`u_rx_packets.read_ptr_r[0]` (306)|
|9|`u_xbar.g_port[1].w_read_w[0]` (288)|`u_xbar.g_port[2].w_read_w[0]` (288)|`timing_net_456[0]` (291)|`timing_net_457[0]` (291)|
|10|`u_xbar.g_port[2].w_read_w[0]` (288)|`u_xbar.g_port[3].w_read_w[0]` (288)|`u_write_dma.write_hold_r[0]` (290)|`u_write_dma.write_hold_r[0]` (290)|
验证：风格/lint 0 告警；20 个依赖单元 smoke 全过（xbar Verilator/Icarus 均 PASS），xbar FULL=1 两种仿真器均 PASS（Icarus 180s 墙钟超时后直接同产物运行完成）；mem_subsys smoke 17/17，ETH 2/2，DISP/VIN/GEO/PIX smoke 全过；board_render/board_vision smoke 和 sc_bios_eth full 三场景均 PASS。
测试变更：`verif/block/geo/edrv32_geo_tb.sv` 的 GEO PERF0 参考起点 `doorbell_time=$time-4 ns` → `$time+4 ns`（顺延 1 个 8 ns 周期，上下界宽度不变）；unit eth_regs/geo_regs/disp_regs 的组合读与直接 access 改为 setup/access；xbar 注入 WINDOW_CYC 参考值 0xfffe→0xffff，保留一拍事件领先；pix_control 将既有 incomplete/reset 场景的首 SOF 对齐 SOFT_RST access 拍。
原始测量/网表：`build/counter-pipeline/{before,after}/{mem_subsys,eth}/{coarse,hardmul}.log`、`hardnet.json`、`paths.json`、`fanout.json`；回归仅保留自行汇总文字 `build/counter-pipeline/regression-summary.txt`。
回归复现：`for u in mem_xbar eth_regs eth_rx eth_tx disp_regs disp_scan vin_regs geo_regs pix_control disp_layers eth_crc eth_mdio eth_rx_write geo_address geo_bilinear geo_coords geo_math geo_source pix_filter pix_point; do flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/$u -j 1; done`；`flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/unit/mem_xbar/full -j 1`；补充 Icarus full：`flock /tmp/edrv32-sim.lock python3 -c "from pathlib import Path;from tools.regress import read_test,run_test;p=Path('verif/unit/mem_xbar/test.yaml').resolve();f=read_test(p);f.update(parameters='FULL=1',timeout='600');assert run_test(p,f,'iverilog','full',1)"`。
模块/SoC：`for m in mem_subsys eth disp vin geo pix; do flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/$m -j 1; done`；board_render/board_vision 同命令换为 `verif/soc/$m`；sc_bios_eth 用 `full --path verif/soc/sc_bios_eth`（现有档位，经协调者确认）。
风格/lint：`python3 tools/check/verilog_style.py rtl/mem rtl/eth rtl/media/{disp,vin,geo,pix}`；`for m in mem_subsys eth disp vin geo pix; do (cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_$m -f $m.f); done`。
复现（先 `. ~/.local/opt/edrv32/env.sh`；下列网表为通用 LUT6 参考，非 PDS 器件映射）：

```sh
python3 - <<'PY'
from pathlib import Path;import subprocess,json,collections;from tools.synth.yosys_synth import read_filelist;from tools.rnd.timing_measure import retain_multipliers;from tools.synth.netlist_paths import analyze;base=Path('build/counter-pipeline/reproduce');base.mkdir(parents=True,exist_ok=True)
stubs=base/'stubs.v';stubs.write_text('(* blackbox *) module ip_ram_mem_xbar_r(input wr_clk,wr_en,wr_rst,rd_clk,rd_clk_en,rd_rst,input [8:0] wr_addr,rd_addr,input [258:0] wr_data,output [258:0] rd_data); endmodule\n(* blackbox *) module ip_lutram_mem_xbar_w(input wr_clk,wr_en,rd_clk,rst,input [3:0] wr_addr,rd_addr,input [143:0] wr_data,output [143:0] rd_data); endmodule\n(* blackbox *) module ip_ram_eth_buf(input wr_clk,wr_en,wr_rst,rd_clk,rd_clk_en,rd_rst,input [9:0] wr_addr,rd_addr,input [31:0] wr_data,output [31:0] rd_data); endmodule\n(* blackbox *) module ip_ram_eth_fifo(input wr_clk,wr_en,wr_rst,rd_clk,rd_clk_en,rd_rst,input [8:0] wr_addr,rd_addr,input [9:0] wr_data,output [9:0] rd_data); endmodule\n')
for rev in ['034885e6','HEAD']:
 root=base/rev;root.mkdir(exist_ok=True);subprocess.run(['tar','xf','-','-C',str(root)],input=subprocess.check_output(['git','archive',rev,'rtl']),check=True)
 for fl,top in [('mem_subsys','edrv32_mem_subsys'),('eth','edrv32_eth')]+[(f,'edrv32_'+m+'_regs') for m,f in [('mem_xbar','mem_subsys'),('eth','eth'),('disp','disp'),('vin','vin'),('geo','geo'),('pix','pix')]]:
  out=root/top;out.mkdir(exist_ok=True);files=[];incs=set();read_filelist(Path('rtl/filelists')/(fl+'.f'),files,incs)
  read='read_verilog -D FPGA_MODE '+' '.join('-I'+str(root/i) for i in sorted(incs))+' '+' '.join(str(root/f) for f in files)+' '+str(stubs)
  (out/'coarse.ys').write_text(read+f'\nhierarchy -check -top {top}\nproc\nflatten\nopt\nwreduce\nopt_clean\nwrite_json {out}/coarse.json\n')
  for stage in ['coarse','hardmul']:
   with (out/(stage+'.log')).open('w') as log: subprocess.run(['flock','/tmp/edrv32-sim.lock','yosys','-Q','-T','-s',str(out/(stage+'.ys'))],stdout=log,check=True)
   if stage=='coarse':retain_multipliers(out,top)
  d=json.loads((out/'hardnet.json').read_text());r=analyze(d);m=d['modules'][top];c=collections.Counter(b for v in m['cells'].values() for p,bs in v['connections'].items() if v['port_directions'][p]=='input' for b in bs if isinstance(b,int));skip={b for p,v in m['ports'].items() if p.startswith(('clk','rst')) for b in v['bits']};names=collections.defaultdict(list)
  for n,v in m['netnames'].items():
   for i,b in enumerate(v['bits']):names[b].append((v['hide_name'],len(n),f'{n}[{i}]'))
  print(rev,top,r['totals'],r['max_levels'],{p:[c[b] for b in m['ports'][p]['bits']] for p in ['apb_paddr_i','apb_pwdata_i'] if p in m['ports']},[(min(names[b])[2],v) for b,v in c.most_common() if b not in skip][:10])
PY
```
