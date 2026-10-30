"""Collect completed B3V rerun reports; feedback is recorded separately."""
from pathlib import Path
from collections import Counter,defaultdict
import re,runpy,shutil,subprocess
REPO=Path(__file__).resolve().parents[4]
TASK=REPO/'tasks/win/20261029-07-b3-rerun';OUT=TASK/'artifacts/B3V'
ROOT=REPO.parent/'EdRV32-FPGA/EdRV32-B3V';TOP='edrv32_fpga_board_vision_top'
BUILD=REPO/'build/win/20261029-07-b3-rerun/B3V/export'
C=runpy.run_path(str(REPO/'tasks/win/20261028-03-cpu-sys-synth-r4/src/collect_reports.py'))
read,section,hierarchy,paths,index_text=(C[k] for k in ['read','section','hierarchy','paths','index_text'])
def write(p,s):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text('\n'.join(l.rstrip() for l in s.splitlines()).rstrip()+'\n',encoding='utf-8')
def main():
 reports=[('compile',TOP+'.cmr'),('compile','include_relation.txt'),('synthesize',TOP+'.snr'),('synthesize','apm_drm_lutram_utilization.log'),('synthesize','add_sub_carrychain.log'),('device_map',TOP+'.dmr'),('place_route',TOP+'.prr'),('place_route','clock_utilization.txt'),('constraint_check','constraint_check.ccr'),('report_timing',TOP+'.rtr')]
 for stage,name in reports:
  dst=OUT/'native_reports'/stage/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/stage/name,dst)
 flow=[];warn=[];stages=[]
 for stage in ['compile','synthesize','device_map','place_route','report_timing','generate_bitstream']:
  raw=read(ROOT/stage/'run.log');ls=raw.splitlines();alerts=[l for l in ls if l.startswith(('W:','C:','E:'))];counts=Counter(l[:1] for l in alerts)
  acts=[l for l in ls if l.startswith('Action ')]
  def metric(k):
   ms=[l.split(k,1)[1].strip() for l in acts if re.match(r'^Action \w+: '+re.escape(k),l)];return ms[-1] if ms else '未取得'
  stages.append((stage,metric('Real time elapsed is'),metric('CPU time elapsed is'),metric('Process CPU time elapsed is'),metric('Peak memory pool usage is'),counts))
  cats=Counter(re.match(r'[WCE]:\s*([A-Za-z]+-\d+):',l)[1] if re.match(r'[WCE]:\s*([A-Za-z]+-\d+):',l) else C['warning_category'](l) for l in alerts)
  flow += [f'{stage}: W={counts["W"]}, C={counts["C"]}, E={counts["E"]}']+acts+[f'{k}\t{v}' for k,v in cats.most_common()]+['']
  warn += ['STAGE '+stage]+alerts+['']
  excerpt=[f'{i}: {l}' for i,l in enumerate(ls,1) if l.startswith(('W:','C:','E:','Action ','Current time:','Process ','Phase ','Start ','Total ','Unrouted','Worst slack')) or 'Time elapsed:' in l or 'slack' in l.lower()]
  write(OUT/'logs'/(stage+'_excerpt.txt'),'Source: '+str(ROOT/stage/'run.log')+'\n'+'\n'.join(excerpt))
 write(OUT/'flow_summary.txt','\n'.join(flow));write(OUT/'logs/warnings_detail.txt','\n'.join(warn))
 original=read(ROOT/'report_timing'/(TOP+'.rtr'));expanded=read(BUILD/'report_timing'/(TOP+'.rtr'));head=original.split('\nSlow Corner',1)[0]
 tables={}
 marks=list(re.finditer(r'(Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((Slow|Fast) Corner\):',head))
 for i,m in enumerate(marks):
  body=head[m.end():marks[i+1].start() if i+1<len(marks) else len(head)]
  rows=re.findall(r'^\s*(\w+)\s+(\w+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)\s*$',body,re.M)
  tables[(m[1],m[2].lower())]={(a,b):(float(c),float(d),int(e),int(f)) for a,b,c,d,e,f in rows}
 periods={a:float(b) for a,b in re.findall(r'^\s*(\w+)\s+([\d.]+)\s+\{',head,re.M)}
 timing=['Full routed summary, both corners; recovery/removal included.','',head,'','Fmax estimates from same-clock setup only:']
 for corner in ['slow','fast']:
  for (a,b),v in tables[('Setup',corner)].items():
   if a==b:timing.append(f'{corner}/{b}: 1000/({periods[b]}-{v[0]})={1000/(periods[b]-v[0]):.4f} MHz')
 write(OUT/'timing_summary.txt','\n'.join(timing))
 ps=paths(expanded,'expanded routed report');seq=[p for p in ps if p['class']=='sequential timing path'];asyncs=[p for p in ps if p['class']=='async timing path']
 write(OUT/'timing_all_paths.tsv',index_text(ps))
 setups=[]
 for clock in sorted({p['group'] for p in seq}):
  chosen=[]
  for corner in ['slow','fast']:
   chosen+=sorted([p for p in seq if p['group']==clock and p['corner']==corner and p['type'].startswith('max')],key=lambda p:p['slack'])[:200]
  write(OUT/('setup_top200_'+clock+'.txt'),index_text(chosen));setups+=chosen
 details=[]
 for corner in ['slow','fast']:
  details+=sorted([p for p in seq if p['corner']==corner and p['type'].startswith('max')],key=lambda p:p['slack'])[:20]
 write(OUT/'setup_top20_detail.txt','\n\n'.join(p['block'] for p in details))
 holds=[]
 for corner in ['slow','fast']:holds+=sorted([p for p in seq if p['corner']==corner and p['type'].startswith('min')],key=lambda p:p['slack'])[:20]
 write(OUT/'hold_top20.txt','\n\n'.join(p['block'] for p in holds))
 recoveries=[p for p in asyncs if p['type'].startswith('max')]
 write(OUT/'recovery_paths.tsv',index_text(recoveries))
 recdetail=[]
 for corner in ['slow','fast']:recdetail+=sorted([p for p in recoveries if p['corner']==corner],key=lambda p:p['slack'])[:20]
 write(OUT/'recovery_top20_detail.txt','\n\n'.join(p['block'] for p in recdetail))
 write(OUT/'removal_top20_detail.txt','\n\n'.join(p['block'] for corner in ['slow','fast'] for p in sorted([q for q in asyncs if q['corner']==corner and q['type'].startswith('min')],key=lambda q:q['slack'])[:20]))
 write(OUT/'setup_near_positive_paths.tsv','Slow setup, 0 < slack < 1 ns, selected from expanded report.\n'+index_text([p for p in seq if p['corner']=='slow' and p['type'].startswith('max') and 0<p['slack']<1]))
 prr=read(ROOT/'place_route'/(TOP+'.prr'));snr=read(ROOT/'synthesize'/(TOP+'.snr'));ht,entries=hierarchy(prr)
 write(OUT/'resource_hier.txt','Post-route PRR logical hierarchy:\n'+ht)
 write(OUT/'resource_summary.txt','Post-route physical resources:\n'+section(prr,'Device Utilization Summary :')+'\nPost-route logical top [LUT,FF,distributed RAM,APM,DRM36K equivalent]:\n'+str(entries[0]['values'])+'\nSynthesis primitive counts (DRM18K/36K split):\n'+snr[snr.index('Cell Usage:'):snr.index('Overview of Control Sets:')])
 write(OUT/'clock_checks.txt',head.split('Setup Summary',1)[0]+'\n'+section(prr,'Global Clock Info:'))
 write(OUT/'logs/timing_export_excerpt.txt',read(BUILD/'export.tcl')+'\n'+'\n'.join(l for l in read(BUILD/'console.log').splitlines() if l.startswith(('E:','C:','W:','Action ','Process '))))
 commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True,cwd=REPO).strip()
 lines=['# 20261029-07-b3-rerun 结果（先回传B3V）','','B3V已完成编译、综合、映射、布局布线、STA和bitstream，用户已运行demo_vision。实际功能基本可用，但仍有setup违例和切换黑屏问题。B3R/B3F本次结果未收集。','',
 '| 项 | 内容 |','|---|---|',f'| 代码commit | {commit} |','| PDS/器件 | 2022.2-SP6.1 build138931；PG2L200H-6/FBB676 |',f'| 实际工程 | {ROOT.as_posix()} |','| 源文件数 | 112 |','| 复用说明 | 按用户决定复用旧B3V，没有新建B3V-r2；其他工程保留 |','',
 '## 布线后时序','','| 时钟对/角 | WNS ns | TNS ns | WHS ns | THS ns | setup/hold违例端点 | Fmax MHz（同域估算） |','|---|---:|---:|---:|---:|---|---:|']
 for corner in ['slow','fast']:
   for (a,b),v in tables[('Setup',corner)].items():
     h=tables[('Hold',corner)][(a,b)];fm=f'{1000/(periods[b]-v[0]):.3f}' if a==b else '—'
     lines.append(f'| {a}→{b}/{corner} | {v[0]:.3f} | {v[1]:.3f} | {h[0]:.3f} | {h[1]:.3f} | {v[2]}/{h[2]} | {fm} |')
 lines+=['','slow clk_mem WNS=-0.554 ns，TNS=-11.348 ns，32个违例端点；125MHz目标按同域setup裕量估算约116.9MHz。clk_sys裕量+0.182ns、clk_eth+0.798ns，也应关注。','hold/recovery/removal两角均无违例；完整汇总（含minimum pulse width）保留在timing_summary.txt。用户反馈违例暂未影响本次实测，不作为时序豁免或全部条件下稳定的结论。','',
 'slow clk_mem最差10条setup：','', '| 起点→终点 | 裕量ns | 逻辑级数 |','|---|---:|---:|']
 worst=sorted([q for q in seq if q['group']=='clk_mem' and q['corner']=='slow' and q['type'].startswith('max')],key=lambda q:q['slack'])
 for q in worst[:10]:lines.append(f'| {q["start"]} → {q["end"]} | {q["slack"]:.3f} | {q["levels"]} |')
 lines+=['','## 路径覆盖','',f'从现有pnr.adf补导report_timing -max_path 200 -nworst 1 -input_pins TRUE，共{len(ps)}条路径。未重跑综合、映射或布线。',
 '每个捕获时钟分slow/fast保存最差200条setup（不足则全部），各角最差20条setup/hold和recovery/removal逐级明细另存。timing_all_paths.tsv保留全部路径；setup_near_positive_paths.tsv保留slow角0到1ns正裕量，既有默认RTR也完整保留。','',
 '## 资源','','来自路后PRR逻辑层次；物理CLMA/CLMS、IO、PLL、DRM容量与综合原语拆分另见resource_summary.txt。','', '| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |','|---|---:|---:|---:|---:|---:|']
 for e in entries:
   if e['depth']<=1:lines.append('| '+e['name']+' | '+' | '.join(map(str,e['values']))+' |')
 lines+=['','## 各阶段日志','','| 阶段 | Real | CPU | Process CPU | 峰值内存 | W/C/E行数 |','|---|---|---|---|---|---|']
 for stage,real,cpu,pcpu,mem,counts in stages:lines.append(f'| {stage} | {real} | {cpu} | {pcpu} | {mem} | {counts["W"]}/{counts["C"]}/{counts["E"]} |')
 lines+=['','日志分类及全部W/C/E行在flow_summary.txt和logs/；原生CMR/SNR/DMR/PRR/RTR/CCR在native_reports/。未提交完整原始执行日志或DB/bitstream。','',
 '## 约束和导入','','clk_sys=10ns、clk_mem=8ns、clk_pix=13.468ns、clk_serial=2.6936ns、cam0/1、clk_eth及DDR内部时钟识别情况见clock_checks.txt，DDR异步组原文见原生RTR。未修改RTL/IP或FDC。',
 '本次提交包含先前用户授权的vision导入路径修正：FPGA工程目录../../EdRV32-Competition-2026定位仓库，include为rtl/include。','',
 '## 上板及改进反馈','','用户反馈基本可用；功能切换短暂黑屏，希望平滑切换；先进入BIOS再点烧录仍要再次KEY1+复位；网口及DDR未能验证；希望把场景/YOLO/视频/DDR/烧录等整合成项目专用SoC中控台。',
 '网口/DDR：任务卡、README和当前源码声明已有相关功能；实际反馈记为交付/工具联调缺口，不写通过，也不直接断言功能未编入。',
 '详细复现、代码线索和验收要求：tasks/win/20261029-09-b3-software/artifacts/B3V/user_feedback.md。未取得本次UART、照片、视频或CSV。','',
 '## 本地数据与复现','',f'- 完整工程报告/日志：{ROOT.as_posix()}/各阶段目录。',f'- 补导：{BUILD.as_posix()}/report_timing/{TOP}.rtr。',
 '- 整理：C:/Python314/python.exe tasks/win/20261029-07-b3-rerun/src/collect_b3v_reports.py。','- 只收集现有结果、补导时序并只读代码，没有重跑实现、改软件/工具或操控桌面。没有核对报告时间戳或计算文件哈希。']
 write(TASK/'result.md','\n'.join(lines));print('Collected B3V',len(ps),'paths; resource',entries[0]['values'])
if __name__=='__main__':main()
