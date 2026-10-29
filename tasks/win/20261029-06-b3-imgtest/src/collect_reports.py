"""Collect completed B3I reports and the user's board observations."""
from pathlib import Path
from collections import Counter,defaultdict
import re,runpy,shutil,subprocess
REPO=Path(__file__).resolve().parents[4]
TASK=REPO/'tasks/win/20261029-06-b3-imgtest';OUT=TASK/'artifacts'
ROOT=REPO.parent/'EdRV32-FPGA/EdRV32-B3I';TOP='edrv32_fpga_board_imgtest_top'
BUILD=REPO/'build/win/20261029-06-b3-imgtest/export'
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
 checklist='''# B3I 上板观察

来源：用户本轮反馈“上板验证功能都是正常的，就是key1像素处理的功能切换感觉切换的时候有很小的卡顿”。

| 项目 | 结果 | 说明 |
|---|---|---|
| 上板整体功能 | 用户反馈正常 | 没有独立采集视频或串口 |
| KEY1 PIX五档 | 功能正常，有轻微切换卡顿 | 卡顿持续时间未测量；未认定根因 |
| KEY2 GEO四档 | 总体正常反馈 | 未逐档单独描述 |
| KEY3摄像头切换 | 总体正常反馈 | 未单独描述切换过程 |
| LED0/1/2/3 | 未单独提供观察 | 不根据总体正常反馈编造LED时序 |
| LED4 | 未单独提供观察 | 未独立确认 |
| 每档照片 | 未取得 | 本轮未提供照片 |

图像错位、撕裂、颜色异常、闪烁未单独报告。没有调试或修改实现。
'''
 write(OUT/'checklist.md',checklist)
 rows=[]
 for corner in ['slow','fast']:
  for pair,v in tables[('Setup',corner)].items():
   h=tables[('Hold',corner)][pair];a,b=pair;fm=f'{1000/(periods[b]-v[0]):.3f}' if a==b else '—'
   rows.append(f'| {a}→{b} / {corner} | {v[0]:.3f} | {v[1]:.3f} | {h[0]:.3f} | {h[1]:.3f} | {v[2]}/{h[2]} | {fm} |')
 commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True,cwd=REPO).strip()
 result=['# 20261029-06-b3-imgtest 结果','','综合、映射、布局布线、时序分析、bitstream已完成；用户反馈上板功能正常，KEY1像素处理切换时轻微卡顿。setup/hold通过，recovery有违例，不能称作所有时序检查通过。','',
 '| 项 | 内容 |','|---|---|',f'| 代码commit（zc100116/b3） | {commit} |','| PDS/器件 | 2022.2-SP6.1 build138931；PG2L200H-6/FBB676 |',f'| 工程 | {ROOT.as_posix()} |','| 导入源文件数 | 67 |','',
 '## 布线后时序','','| 时钟对/角 | WNS ns | TNS ns | WHS ns | THS ns | setup/hold违例端点 | Fmax MHz（同域推算） |','|---|---:|---:|---:|---:|---|---:|']+rows
 result+=['','主时钟最紧的是clk_mem：slow setup +0.244 ns，hold最小约+0.100 ns。正裕量路径也已保留供后续集成评估，不仅保存违例。','',
 '## Recovery / removal','','Recovery违例集中在DDR PHY复位相关路径。以下是报告原文汇总，未自行添加false_path或修改IP/RTL/约束。','',
 '| 时钟对/角 | recovery WNS ns | recovery TNS ns | 违例端点 |','|---|---:|---:|---:|']
 for corner in ['slow','fast']:
  for (a,b),v in tables[('Recovery',corner)].items():
   if v[2]:result.append(f'| {a}→{b} / {corner} | {v[0]:.3f} | {v[1]:.3f} | {v[2]} |')
 result+=['','最差recovery路径（expanded report）：','', '| 角 | 起点→终点 | 裕量ns |','|---|---|---:|']
 for q in sorted(recoveries,key=lambda p:p['slack'])[:10]:result.append(f'| {q["corner"]} | {q["start"]} → {q["end"]} | {q["slack"]:.3f} |')
 result+=['','Recovery各角最差20条逐级明细见recovery_top20_detail.txt；removal同样保留。setup/hold为0违例并不消除recovery问题，上板正常也未用于豁免违例。','',
 '## 路径覆盖','','从既有pnr.adf补导report_timing -max_path 200 -nworst 1 -input_pins TRUE，不重跑综合、映射或布线。各捕获时钟按slow/fast分别选最差200条setup；不足200时保留全部。setup和hold最差20条明细分别按角保留。补导全部路径索引、接近零的正setup裕量路径、recovery/removal另存。',f'补导记录数：{len(ps)}；原生默认报告也完整保留。','',
 '## 资源','','下表来自路后PRR逻辑层次，物理容量、IO、GPLL/PPLL以及DRM原语拆分见resource_summary.txt。','', '| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |','|---|---:|---:|---:|---:|---:|']
 for e in entries:
  if e['depth']<=1:result.append('| '+e['name']+' | '+' | '.join(map(str,e['values']))+' |')
 result+=['','## 各阶段','','| 阶段 | Real | CPU | Process CPU | 峰值内存 | W/C/E行数 |','|---|---|---|---|---|---|']
 for stage,real,cpu,pcpu,mem,counts in stages:result.append(f'| {stage} | {real} | {cpu} | {pcpu} | {mem} | {counts["W"]}/{counts["C"]}/{counts["E"]} |')
 result+=['','W/C/E为行数而非独立缺陷数，完整分类及所有warning/error在flow_summary.txt和logs/。原生CMR/SNR/DMR/PRR/RTR/CCR保存于native_reports。','',
 '## 上板','','用户确认：上板功能均正常；KEY1切换像素处理时有很小的卡顿，未测量时长，不推断根因。逐项记录见checklist.md。LED状态及各档照片未单独取得，不补写为已验证。','',
 '## 导入与约束','','保留本机此前授权的导入脚本路径修正：工程目录../../EdRV32-Competition-2026定位仓库，include_path传rtl/include，FPGA_MODE。GUI初次导入曾报Flow-0245和头文件错误，最终工程已完成全流程；不把之前的路径展开检查当作实际编译通过证据。未修改RTL/IP或FDC。时钟约束识别情况见clock_checks.txt。','',
 '## 本地原始数据与复现','',f'- 完整工程日志、原生报告：{ROOT.as_posix()}/各阶段目录。',f'- 补导报告：{BUILD.as_posix()}/report_timing/{TOP}.rtr。','- 整理命令：C:/Python314/python.exe tasks/win/20261029-06-b3-imgtest/src/collect_reports.py。','- 只收集已有实现结果并补导时序；没有重跑综合/布局布线，没有核对时间戳或做文件哈希，也没有提交数据库、bitstream、完整原始执行日志。']
 write(TASK/'result.md','\n'.join(result));print('Collected',len(ps),'paths; resources',entries[0]['values'])
if __name__=='__main__':main()
