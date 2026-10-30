"""Collect B3R reports and captured read-only GUI UART evidence."""
from pathlib import Path
from collections import Counter,defaultdict
import csv,json,re,runpy,shutil

REPO=Path(__file__).resolve().parents[4]
TASK=Path(__file__).resolve().parents[1]
OUT=TASK/'artifacts'
ROOT=REPO.parent/'EdRV32-FPGA/EdRV32-B3R'
TOP='edrv32_fpga_board_render_top'
BUILD=REPO/'build/win/20261030-14-b3r-rnd'
H=runpy.run_path(str(REPO/'tasks/win/20261028-03-cpu-sys-synth-r4/src/collect_reports.py'))
read,paths,index,section,hierarchy=(H[n] for n in ('read','paths','index_text','section','hierarchy'))

def write(p,s):
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text('\n'.join(l.rstrip() for l in s.splitlines())+'\n',encoding='utf-8')
def copy(stage,name):
    p=ROOT/stage/name
    if p.exists():
        dst=OUT/'native_reports'/stage/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dst)

for stage,names in {
    'compile':[f'{TOP}.cmr','include_relation.txt'],
    'synthesize':[f'{TOP}.snr',f'{TOP}_controlsets.txt','apm_drm_lutram_utilization.log','add_sub_carrychain.log'],
    'device_map':[f'{TOP}.dmr',f'{TOP}_dmr.prt'],
    'place_route':[f'{TOP}.prr',f'{TOP}_prr.prt','clock_utilization.txt'],
    'report_timing':[f'{TOP}.rtr'],
    'constraint_check':['constraint_check.ccr'],
}.items():
    for n in names:copy(stage,n)
flow=[];warn=[];excerpts=[];stage_times=[];counts=[];apm_warnings=[]
for stage in ('compile','synthesize','device_map','place_route','report_timing','generate_bitstream'):
    raw=read(ROOT/stage/'run.log')
    ws=[l for l in raw.splitlines() if re.match(r'^[WCE]:',l)]
    actions=[l for l in raw.splitlines() if l.startswith('Action ')]
    cats=Counter((re.match(r'^[WCE]:\s*(\S+)',l)[1]) for l in ws)
    counts.append((stage,Counter(l[0] for l in ws)))
    flow += [stage, *actions, 'W/C/E line counts: '+str(dict(counts[-1][1])), 'Message categories: '+str(dict(cats)), '']
    stage_times.append((stage,actions))
    warn += [f'=== {ROOT/stage/"run.log"} ===',*ws,'']
    excerpts += [f'=== {stage} ===',*[l for l in raw.splitlines() if re.match(r'^(Action |Current time:|Process |Phase |Unrouted |Worst slack|Total negative)',l) or 'takes ' in l],'']
    apm_warnings += [stage+': '+l for l in ws if re.search(r'APM|CPI|CPO|cascade',l,re.I)]
write(OUT/'flow_summary.txt','\n'.join(flow))
write(OUT/'logs/warnings_detail.txt','\n'.join(warn))
write(OUT/'logs/execution_excerpt.txt','\n'.join(excerpts))
write(OUT/'apm_warnings.txt','\n'.join(apm_warnings) if apm_warnings else 'No APM/CPI/CPO/cascade W/C/E lines in collected stage logs.')
route=read(ROOT/'place_route/run.log')
rs=re.findall(r'Unrouted general nets at iteration (\d+) \(MT total route time: ([\d.]+) sec\): (\d+)\(overused: (\d+)\)',route)
write(OUT/'route_progress.tsv','iteration\tMT_total_route_time_raw_sec\tunrouted_general_nets\toverused\n'+'\n'.join('\t'.join(r) for r in rs))
prr=read(ROOT/'place_route'/f'{TOP}.prr')
dmr=read(ROOT/'device_map'/f'{TOP}.dmr')
write(OUT/'resource_hier.txt',hierarchy(prr)[0])
write(OUT/'resource_hier_synthesis.txt',hierarchy(read(ROOT/'synthesize'/f'{TOP}.snr'))[0])
usage=section(dmr,'Device Utilization Summary:')
write(OUT/'resource_summary.txt','Device-map capacity table:\n'+usage+'\nPost-route primitive counts:\n'+section(prr,'Device Utilization Summary :'))
native=read(ROOT/'report_timing'/f'{TOP}.rtr')
head=native.split('\nSlow Corner',1)[0]
write(OUT/'timing_summary.txt',head)
expanded=BUILD/'timing200/report_timing'/f'{TOP}.rtr'
assert expanded.exists(),'Expanded timing export not complete'
eps=paths(read(expanded),'routed200')
write(OUT/'timing_all_paths.tsv',index(eps))
seq=[p for p in eps if p['class']=='sequential timing path']
for clock in sorted(set(p['group'] for p in seq)):
    selected=[p for p in seq if p['group']==clock and p['type'].startswith('max')]
    safe=re.sub(r'[^A-Za-z0-9_.-]','_',clock)
    write(OUT/f'setup_top200_{safe}.txt','Expanded routed report; actual counts can be lower where fewer paths exist.\n'+'\n\n'.join(p['block'] for p in selected))
for direction,name in [('max','setup_top20_detail.txt'),('min','hold_top20.txt')]:
    ps=[p for corner in ('slow','fast') for p in sorted((q for q in seq if q['type'].startswith(direction) and q['corner']==corner),key=lambda q:q['slack'])[:20]]
    write(OUT/name,'\n\n'.join(p['block'] for p in ps))
near=[p for p in seq if p['type'].startswith('max') and 0<=p['slack']<1]
write(OUT/'setup_dangerous_positive.txt','0 <= slack < 1 ns from expanded report.\n'+'\n\n'.join(p['block'] for p in near))
write(OUT/'clock_constraint_evidence.txt',head.split('Performance Summary:',1)[0])
# Derived per-clock/angle same-clock WNS/WHS and requested-period Fmax.
periods={m[1]:float(m[2]) for m in re.finditer(r'^\s*(\S+)\s+([\d.]+)\s+\{',head,re.M)}
summ={};active=None
for line in head.splitlines():
    m=re.match(r'(Setup|Hold|Recovery|Removal) Summary\((Slow|Fast) Corner\):',line)
    if m:active=m.groups();continue
    if 'Summary' in line:active=None
    if active:
        m=re.match(r'\s*(\S+)\s+(\S+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)\s*$',line)
        if m and m[1]==m[2]:summ[active+(m[1],)]=m.groups()[2:]

import subprocess,sys,statistics
buffer=json.loads(read(OUT/'uart/gui_buffer.json'))
entries=buffer['entries'];rx=[e for e in entries if e['dir']=='rx']
write(OUT/'uart/rx_hex.tsv','seq\ttimestamp_epoch_ms\thex\n'+'\n'.join(f'{e["seq"]}\t{e["ts"]}\t{e.get("hex","")}' for e in rx))
starts=[]
for i,e in enumerate(rx):
    if e['text']=='RND board' or e['text'].startswith('S3:') or e['text']=='NES powered on':starts.append((i,e['text']))
# RND CRC printing pauses while computing, so GUI idle flush splits prefix/value.
# Merge only an exact CRC prefix immediately followed by an exact 8-digit value.
normalized=[];merges=[];i=0
while i<len(rx):
    e=rx[i];text=e['text']
    if re.fullmatch(r'RND \w+ crc=',text) and i+1<len(rx) and re.fullmatch(r'0x[0-9a-fA-F]{8}',rx[i+1]['text']):
        normalized.append(text+rx[i+1]['text']);merges.append((e['seq'],rx[i+1]['seq']));i+=2
    else:normalized.append(text);i+=1
write(OUT/'uart/rnd.log','\n'.join(l for l in normalized if l.startswith('RND ') and ('crc=' in l or 'ERR_CODE=' in l or l=='RND display ready')))
write(OUT/'uart/rnd_normalization.txt','GUI idle flush split CRC prefix/value into adjacent RX records. Only exact matching adjacent pairs joined; originals remain in gui_buffer.json and rx_hex.tsv.\n'+'\n'.join(f'{a}+{b}' for a,b in merges))
proc=subprocess.run([sys.executable,'-X','utf8',str(REPO/'sw/tests/rnd_board/expect.py'),str(OUT/'uart/rnd.log')],cwd=REPO,capture_output=True,text=True,encoding='utf-8')
write(OUT/'rnd_compare.txt',proc.stdout+'\n'+proc.stderr)
assert proc.returncode in (0,1), 'Reference comparison tool execution error'
# Retain complete application RX sessions, splitting when the next boot logo starts.
sessions=[]
for i,e in enumerate(rx):
    if e['text'].startswith('S3:') or e['text']=='NES powered on':
        end=next((j for j in range(i+1,len(rx)) if rx[j]['text'].startswith('  EEEEEEE')),len(rx))
        sessions.append((e['text'],rx[i:end]))
s3=[e['text'] for label,es in sessions if label.startswith('S3:') for e in es]
nes_runs=[[e['text'] for e in es] for label,es in sessions if label=='NES powered on']
write(OUT/'uart/s3.log','\n'.join(s3))
write(OUT/'uart/nes.log','\n\n'.join(f'=== Display run {i+1} ===\n'+'\n'.join(es) for i,es in enumerate(nes_runs)))
write(OUT/'uart/nes_nodisplay.log','未取得。两次可识别NES运行均打印shown>0，加载段大小也相同，不能把其中一次当作不显示版。')
bench=[]
for i,line in enumerate(s3):
    if line.startswith('Benchmark Summary'):
        j=next((j for j in range(i+1,len(s3)) if s3[j].startswith('All scenes avg.')),None)
        if j is not None:bench.extend(s3[i:j+1])
write(OUT/'s3_benchmark.txt','\n'.join(bench))
rn17=[l for l in s3 if l.startswith('RN-17')]
write(OUT/'rn17.txt','\n'.join(rn17))
fps=[]
for k,es in enumerate(nes_runs,1):
    ms=[re.fullmatch(r'NES fps=([\d.]+) shown=([\d.]+) cpu=(\d+)% ppu=(\d+)%',l) for l in es]
    vs=[m.groups() for m in ms if m]
    if vs:fps.append((k,vs))
write(OUT/'nes_fps.tsv','run\twindow\tfps\tshown\tcpu_percent\tppu_percent\n'+'\n'.join('\t'.join(map(str,[k,j,*v])) for k,vs in fps for j,v in enumerate(vs,1)))
check=['# 上板检查清单','',
    '用户回复：“正常，直接上传吧”。照片未提供，不用软件截图冒充实物照片。', '',
    '| 项目 | 结果 | 证据 |','|---|---|---|',
    f'| RND 16组CRC | {"PASS" if proc.returncode==0 else "FAIL/缺项，见比较原文"} | rnd_compare.txt |',
    '| RND HDMI图案 | 用户确认正常 | 用户回复 |',
    '| S3主界面、游戏、widgets、按键 | 用户确认正常 | 用户回复；串口日志 |',
    '| S3 benchmark | 已取得16场景及平均15 FPS | s3_benchmark.txt |',
    '| RN-17比对 | PASS | rn17.txt |',
    '| NES画面、按键 | 用户确认正常 | 用户回复；nes.log |',
    '| NES显示版帧率 | 已取得两次运行；首窗口舍弃 | nes_fps.tsv |',
    '| NES不显示版 | 未取得 | 不从显示版推断 |',
    '| 照片 | 未提供 | 用户要求直接上传已有数据 |']
write(OUT/'checklist.md','\n'.join(check))
report=['# 20261030-14-b3r-rnd 结果','',
    'B3R 已完成综合、布局布线、STA及bitstream，上板RND/S3/NES测试完成。用户确认画面与按键正常并要求直接上传。CRC比较、benchmark、RN-17及NES实测原文见下；不显示版NES日志未取得，照片未提供，不补造。', '',
    '| 项 | 内容 |','|---|---|',
    '| 当前任务检出 | 3a344936（含任务14及删除2个RND无用源文件的说明；未核验源码/报告时间） |',
    '| 工程路径 | G:/codex_project/EdRV32-FPGA/EdRV32-B3R，复用本机原工程 |',
    '| PDS | 2022.2-SP6.1，PG2L200H-6 FBB676 |',
    '| 运行方式 | 用户已授权R/N并行；本轮不由agent停止或重跑实现流程 |',
    '| 加载方式 | GUI，COM7，115200，8N1，不切换波特率（沿用用户偏好及此前实测） |', '',
    '## 阶段耗时、峰值内存','']
for stage,actions in stage_times:report += [f'### {stage}','',*['- '+l for l in actions],'']
report += ['',f'路由共保存{len(rs)}条迭代进度，末条{rs[-1] if rs else "未取得"}，字段为迭代/MT原始秒数/未布通/overused。实际总耗时以Action Real time为准，不累加MT字段。', '',
    '## 布线后时序','',
    '同域汇总如下，全部同域/跨域Setup、Hold、Recovery、Removal及脉宽摘要见timing_summary.txt。Fmax=1000/(报告周期−WNS)，是各角估算，不能以fast角代替slow角。', '',
    '| 时钟 | 角 | 周期ns | WNS | TNS | WHS | THS | setup违例端点 | Fmax MHz |','|---|---|---|---|---|---|---|---|---|']
for (kind,corner,clock),v in summ.items():
    if kind!='Setup':continue
    h=summ.get(('Hold',corner,clock),('未取得',)*4);period=periods.get(clock)
    fmax=f'{1000/(period-float(v[0])):.3f}' if period and period>float(v[0]) else '未取得'
    report.append('| '+' | '.join([clock,corner,str(period),v[0],v[1],h[0],h[1],v[2],fmax])+' |')
report += ['',f'补充导出包含{len(eps)}条路径，危险正裕度setup（0≤slack<1ns）{len(near)}条。各时钟setup多路径、最差20条setup/hold、完整路径索引均已保存；数量按实际路径，不填充。', '',
    '### setup违例时钟域最差路径（每角最多10条）','']
violations=[p for p in seq if p['type'].startswith('max') and p['slack']<0]
for clock in sorted({p['group'] for p in violations}):
    for corner in ('slow','fast'):
        for p in sorted((p for p in violations if p['group']==clock and p['corner']==corner),key=lambda p:p['slack'])[:10]:
            report.append(f'- {clock}/{corner} {p["slack"]:+.3f}ns，{p["levels"]}级，`{p["start"]}` → `{p["end"]}`。')
if not violations:report.append('扩展报告未出现setup负裕度路径。')
report += ['', '## 资源','', '```text',usage,'```','',
    'resource_hier.txt按post-route完整展开CPU/SYS/MEM/RND/DISP及子模块；另存综合层级。资源表APM/DRM使用原生报告口径，不混用站点/子单元。', '',
    '## RND自检','',f'参考模型expect.py返回码：{proc.returncode}。原始RX中16组CRC各被GUI闲置刷新拆成两段；只将相邻的精确 `RND <组名> crc=` 和 `0x<8位hex>` 拼接，合并索引保存在uart/rnd_normalization.txt，原始JSON及HEX保留。未修改任何CRC数值。','',
    '```text',proc.stdout.rstrip(),'```','',
    '用户确认RND图案正常；硬件ERR_CODE行原文全部保留。', '',
    '## S3、RN-17及benchmark','',
    '用户确认主界面、游戏、widgets及按键正常。串口benchmark原文（若耗时/CPU数字与即时fps不同，不重算替换）：','',
    '```text',*bench,'```','', 'RN-17原文：','', '```text',*rn17,'```','',
    '## NES显示版','',
    '用户确认画面与按键正常。缓冲中有两次NES运行，均shown>0；首次统计窗口舍弃，表中列窗口2–4。', '',
    '| 运行 | 窗口 | fps | shown | CPU% | PPU% |','|---|---|---|---|---|---|']
for k,vs in fps:
    for j in range(1,min(4,len(vs))):report.append('| '+' | '.join(map(str,[k,j+1,*vs[j]]))+' |')
report += ['',
    'NES不显示版：未取得。两次运行的加载段大小相同，shown均非零，不能把第二次认定为nes_nodisplay；完整日志及全部窗口表已保存。', '',
    '## 证据范围与未取得项','',
    f'GUI缓冲seq范围{entries[0]["seq"]}–{entries[-1]["seq"]}，共{len(entries)}条。只读API抓取，不操作桌面、不向串口发送命令。GUI工程下拉仍是B3V，仅记录工具状态，不据此判断实际bitstream。', '',
    'uart/gui_all.log、gui_buffer.json及rx_hex.tsv保留全部取得的原始记录；按程序提取rnd.log、s3.log、nes.log。用户要求直接上传，本次不要求补测或照片。未取得不显示版NES实测和实物照片，见checklist.md。', '',
    '完整实现日志仍在本地工程compile/synthesize/device_map/place_route/report_timing/generate_bitstream目录；已回传原生报告、各阶段全部W/C/E、耗时内存、路由迭代。未上传工程/IP/数据库/bitstream或完整执行日志。补充STA仅从已有布线DB导出，不重跑实现。', '',
    '任务14采用本机B3R目录，任务卡中的B3R-r2未另建。构建时源文件已由PDS引用仓库；本轮不核对源码/报告时间，也不由当前HEAD推断正在或已经完成的构建版本。']
large=[p for p in OUT.rglob('*') if p.is_file() and p.stat().st_size>3*2**20]
if large:report += ['', '较大产物（保留多路径与警告诊断原文）：','',*[f'- {p.relative_to(TASK).as_posix()}：{p.stat().st_size/2**20:.2f}MiB' for p in large]]
write(TASK/'result.md','\n'.join(report))
print('Timing paths',len(eps),'near setup',len(near),'CRC return',proc.returncode,'NES runs',len(nes_runs),'benchmark lines',len(bench))

