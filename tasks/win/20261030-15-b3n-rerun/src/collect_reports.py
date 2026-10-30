"""Collect B3N reports and previously captured read-only GUI API evidence."""
from pathlib import Path
from collections import Counter,defaultdict
import csv,json,re,runpy,shutil

REPO=Path(__file__).resolve().parents[4]
TASK=Path(__file__).resolve().parents[1]
OUT=TASK/'artifacts'
ROOT=REPO.parent/'EdRV32-FPGA/EdRV32-B3N'
TOP='edrv32_fpga_board_npu_top'
BUILD=REPO/'build/win/20261030-15-b3n-rerun'
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
expanded=BUILD/'export/report_timing'/f'{TOP}.rtr'
assert expanded.exists(),'Expanded timing export not complete'
eps=paths(read(expanded),'routed200')
head=read(expanded).split('\nSlow Corner',1)[0]
write(OUT/'timing_summary.txt','Primary summary: supplementary STA directly from existing routed DB. Original GUI RTR retained under native_reports.\n'+head)
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

import subprocess
uart=OUT/'uart'
b=json.loads(read(uart/'gui_buffer.json'));entries=b['entries'];rx=[e for e in entries if e['dir']=='rx']
write(uart/'rx_hex.tsv','seq\ttimestamp_epoch_ms\thex\n'+'\n'.join(f'{e["seq"]}\t{e["ts"]}\t{e.get("hex","")}' for e in rx))
npu=[e['text'] for e in rx if e['text'].startswith('NPU ')]
write(OUT/'board_npu_results.txt','\n'.join(npu))
fail=[l for l in npu if re.search(r'FAIL|channel|mismatch',l,re.I)]
write(OUT/'failed_channels.txt','\n'.join(fail) if fail else '本次日志全部39项PASS，没有失败用例或出错通道行。实际加载为卡13旧ELF；不要声称验证了卡15新增诊断输出。')
status=json.loads(read(uart/'gui_status.json'));program=json.loads(read(uart/'gui_program_status.json'))
commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
pass_lines=[l for l in npu if re.match(r'NPU [ABCD][ -].* PASS',l)]
final=next((l for l in reversed(npu) if l.startswith('NPU board:')),'未取得')
c=next((l for l in npu if l.startswith('NPU C-YOLO')),'未取得')
d=[l for l in npu if re.match(r'NPU D-\d+',l)]
apm_file=OUT/'apm_placement.pcf'
assert apm_file.exists(),'APM export not finished'
apm_rows=[l for l in read(apm_file).splitlines() if l.startswith('def_inst_site')]
assert len(pass_lines)==39 and final=='NPU board: PASS 39/39'
report=['# 20261030-15-b3n-rerun 结果','',
    '**B3N实现完成，上板原测试ELF运行PASS 39/39。** 此前失败的第一个卷积用例现已通过，整网41.665 ms/frame、24.000 fps，连续20帧CRC均为0738f96e。实际使用GUI、115200和卡13旧ELF，未使用卡15新增诊断ELF；该差异如实记录，不把本轮称为新版诊断程序验收。','',
    '| 项 | 内容 |','|---|---|',f'| 当前任务检出commit | {commit} |',
    '| 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3N，复用 |',
    '| PDS | 2022.2-SP6.1，PG2L200H-6 FBB676 |',
    '| 源文件 | 任务卡要求88个，新增edrv32_mac_npu_int8_head.v；include关系和CMR原文已保存 |',
    '| 运行方式 | 用户授权与B3R并行；agent未停止或重跑实现 |',
    f'| 串口 | {status["config"]["port"]}，{status["config"]["baud"]}，8N1，GUI |',
    f'| 实际ELF路径（GUI状态） | {program["path"]} |',
    f'| 已加载字节 | {program["programmedBytes"]}；{program["result"]} |',
    f'| 结果 | {final} |',
    '| 整网 | 41.665 ms/frame；24.000 fps |',
    '| LED | 未取得 |','',
    '## 实现耗时与峰值内存','']
for stage,actions in stage_times:report += [f'### {stage}','',*['- '+l for l in actions],'']
report += ['',f'路由共记录{len(rs)}条进度，最后一条{rs[-1] if rs else "未取得"}，字段依次为迭代、MT原始秒数、未布通网络、overused。总耗时取Action Real time，不累加MT字段。', '',
    '## 布线后时序','',
    '每个同域的slow/fast汇总如下；跨域以及Recovery/Removal/脉宽约束见timing_summary.txt原文。Fmax=1000/(报告周期−WNS)，仅作为该角估算。', '',
    '| 时钟 | 角 | 周期ns | WNS | TNS | WHS | THS | setup违例端点 | Fmax MHz |','|---|---|---|---|---|---|---|---|---|']
for (kind,corner,clock),v in summ.items():
    if kind!='Setup':continue
    hold=summ.get(('Hold',corner,clock),('未取得',)*4);period=periods.get(clock)
    fmax=f'{1000/(period-float(v[0])):.3f}' if period and period>float(v[0]) else '未取得'
    report.append('| '+' | '.join([clock,corner,str(period),v[0],v[1],hold[0],hold[1],v[2],fmax])+' |')
report += ['',f'扩展STA从现有pnr数据库导出，{len(eps)}条路径，危险正裕度setup（0≤slack<1ns）{len(near)}条。保留每时钟setup多路径、最差20 setup/hold、全部索引，数量按实际报告，不补造。', '',
    'setup负裕度最差路径（每域/角最多10条）：','']
neg=[p for p in seq if p['type'].startswith('max') and p['slack']<0]
for clock in sorted({p['group'] for p in neg}):
    for corner in ('slow','fast'):
        for p in sorted((q for q in neg if q['group']==clock and q['corner']==corner),key=lambda q:q['slack'])[:10]:report.append(f'- {clock}/{corner} {p["slack"]:+.3f}ns，{p["levels"]}级，`{p["start"]}` → `{p["end"]}`。')
if not neg:report.append('未发现setup负裕度路径。')
report += ['', '## 资源与APM布局','', '```text',usage,'```','',
    '完整post-route/synthesis层级分别为resource_hier.txt、resource_hier_synthesis.txt。APM计数沿用原生资源口径。APM/CPI/CPO/cascade关键字相关警告原文保存在apm_warnings.txt，不能把所有命中行当作级联放置错误。', '',
    f'原生generate_constraint -db <pnr>并指定已有compile/synthesize/devmap数据库导出apm_placement.pcf，包含{len(apm_rows)}条位置约束。级联组可能仅导出根位置，不把约束条数当作实际APM利用量，也不据此声称已逐级检查8级连续性。', '',
    '## 上板加载与结果','',
    'GUI配置115200；Load result: PASS；Run: 0x80000000。与卡13相比，此次同一个旧ELF的首个OP-01已由FAIL变为PASS，全部39项通过。这个事实支持修复对硬件结果有改善，但不是单独证明原故障根因；没有额外做A/B硬件实验。', '',
    '卡15建议CLI+2 Mbaud及新的诊断ELF；本轮沿用用户GUI偏好和已验证的115200。GUI路径明确指向tasks/win/20261030-13-b3n-npu/src/board_npu.elf，不用文件时间/哈希推测。没有再次验证2 Mbaud，不能报告其已修复。', '',
    '### 各用例结果（全部原文）','', '```text',*npu,'```','',
    '### 失败用例及出错通道','',
    '本次全部39项PASS，没有失败项。由于实际加载旧ELF，不能把无通道行解释为新版诊断输出已经被验证。', '',
    '## 日志、上板状态及未取得项','',
    f'GUI缓冲seq {entries[0]["seq"]}–{entries[-1]["seq"]}，共{len(entries)}条。完整日志uart/b3n_rerun.log，原始JSON/HEX与只读状态快照均保留；没有操作桌面或向板端发送数据。GUI工程下拉显示B3V只是工具状态，不据此判断实际工程。', '',
    'LED状态未取得；未重测2 Mbaud；卡15诊断ELF未运行。按用户要求直接整理回传，没有为上述缺项重跑上板。已有原ELF PASS39/39、整网fps及20帧CRC证据完整。', '',
    '各阶段CMR/SNR/DMR/PRR/RTR、约束检查、全部W/C/E、耗时/内存、路由收敛、危险正裕度路径均已归档。完整执行run.log保留在工程对应阶段目录，不提交工程/IP目录、数据库、bitstream或完整执行日志。', '',
    '本次只从已完成数据库补充导出STA及APM布局，没有重新综合或布局布线；没有核验报告时间或源码版本。']
large=[p for p in OUT.rglob('*') if p.is_file() and p.stat().st_size>3*2**20]
if large:report+=['','较大原文产物（诊断所需）：','',*[f'- {p.relative_to(TASK).as_posix()}：{p.stat().st_size/2**20:.2f}MiB' for p in large]]
write(TASK/'result.md','\n'.join(report))
print(final,c,'paths',len(eps),'near',len(near))

