"""Collect B3N reports and previously captured read-only GUI API evidence."""
from pathlib import Path
from collections import Counter,defaultdict
import csv,json,re,runpy,shutil

REPO=Path(__file__).resolve().parents[4]
TASK=Path(__file__).resolve().parents[1]
OUT=TASK/'artifacts'
ROOT=REPO.parent/'EdRV32-FPGA/EdRV32-B3N'
TOP='edrv32_fpga_board_npu_top'
BUILD=REPO/'build/win/20261030-13-b3n-npu'
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

# Preserve exact raw RX bytes, avoiding loss from UTF-8 replacement characters.
buf=json.loads(read(OUT/'uart/gui_buffer.json'))
rx=[e for e in buf['entries'] if e['dir']=='rx']
write(OUT/'uart/rx_hex.tsv','seq\ttimestamp_epoch_ms\thex\n'+'\n'.join(f'{e["seq"]}\t{e["ts"]}\t{e.get("hex","")}' for e in rx))
first_null=next((e for e in rx if e.get('hex','').startswith('00 00')),None)
zero_count=len(bytes.fromhex(first_null['hex'])) if first_null else 0
boot=[e for e in buf['entries'] if e['seq']<=21]
write(OUT/'uart/b3n_boot.log','\n'.join(f'{e["seq"]}\t{e["ts"]}\t{e["dir"]}\t{e["text"]}' for e in boot))
status=json.loads(read(OUT/'uart/gui_status.json'))
program=json.loads(read(OUT/'uart/gui_program_status.json'))
report=['# 20261030-13-b3n-npu 结果','',
    'B3N 已完成综合、映射、布局布线、STA 和 bitstream。上板在 115200 波特率下普通启动、DDR ready 和 BIOS 均正常；GUI 加载 ELF 时在切到 2 Mbaud 后乱码，尚未取得 ELF 加载完成或 NPU 测试结果。不得将本轮判为 NPU 功能 PASS，也没有取得 NPU 运算失败证据。','',
    '| 项 | 内容 |','|---|---|',
    '| 输入代码 | origin/zc100116/b3，b7519616（当前任务分支基点；未做源码/产物时间核验） |',
    '| 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3N，新建，按任务单工程运行 |',
    '| PDS | 2022.2-SP6.1，PG2L200H-6 FBB676 |',
    '| 导入 | 87 源文件，21 种 IP；include 和相对路径已检查 |',
    '| 完成情况 | 实现完成；步骤8 ELF加载阶段异常，测试未完成 |','',
    '## 阶段耗时与内存','',
    '以下保存 Real time、CPU time、Process CPU time 和 Peak memory pool 原文；不是由文件时间推算。','']
for stage,actions in stage_times:report += [f'### {stage}','',*['- '+l for l in actions],'']
report += ['## 布线与 APM 级联','',f'路由进度共 {len(rs)} 条，最后记录：{rs[-1] if rs else "未取得"}；字段依次为迭代、MT原始秒数、未布通数、overused。MT字段不累加成墙钟耗时。', '',
    f'APM/CPI/CPO/cascade 相关 W/C/E 行 {len(apm_warnings)} 条，原文见 apm_warnings.txt；完成布线与 bitstream 不代表上板 NPU 已通过。', '',
    'apm_placement.pcf 由原生 generate_constraint -db <现有pnr.adf> -device APM 导出，用于 Linux 检查8级链同列连续站点。未修改工程或运行综合/PnR。', '',
    '## 时序','',
    '布线后原生摘要保留全部同域和跨域 Setup/Hold/Recovery/Removal 数据。下表列同域 WNS/TNS/WHS/THS；Fmax=1000/(报告周期−WNS)，仅为该角估算，最终受 slow 角及其他约束共同限制。','',
    '| 时钟 | 角 | 周期ns | WNS | TNS | WHS | THS | setup违例端点 | Fmax MHz |','|---|---|---|---|---|---|---|---|---|']
for (kind,corner,clock),v in summ.items():
    if kind!='Setup':continue
    hold=summ.get(('Hold',corner,clock),('未取得',)*4)
    period=periods.get(clock)
    fmax=f'{1000/(period-float(v[0])):.3f}' if period and period>float(v[0]) else '未取得'
    report.append('| '+' | '.join([clock,corner,str(period),v[0],v[1],hold[0],hold[1],v[2],fmax])+' |')
report += ['',f'补充报告已从现有布线 DB 导出，索引包含 {len(eps)} 条路径；危险正裕度 setup（0–1 ns）{len(near)} 条已保留。各时钟 setup、最差20 setup/hold及全部索引见 artifacts；数量少于200时按实际报告保留，不填充。','',
    '每个存在 setup 违例的时钟域最差路径（按角各最多10条）：','']
for clock in sorted({p['group'] for p in seq if p['type'].startswith('max') and p['slack']<0}):
    for corner in ('slow','fast'):
        ps=sorted((p for p in seq if p['group']==clock and p['corner']==corner and p['type'].startswith('max') and p['slack']<0),key=lambda p:p['slack'])[:10]
        for p in ps:report.append(f'- {clock}/{corner}：{p["slack"]:+.3f} ns，{p["levels"]}级，`{p["start"]}` → `{p["end"]}`。')
report += ['', '## 资源','', '```text',usage,'```','',
    '层级完整展开见 resource_hier.txt（post-route）、resource_hier_synthesis.txt。APM按资源报告子单元计数，不混用物理站点数量。','',
    '## 串口异常与用户实测','',
    '已通过运行中 GUI 的只读 REST API 取得完整缓冲、原始RX hex、串口配置及加载状态；没有操作桌面，没有向板端发送数据，没有改波特率或重试。用户截图原图亦已保存。', '',
    '1. COM7 @115200 8N1 正常连接，21:28:24 普通启动，MEM_READY=1，出现 Monitor 菜单。',
    '2. 21:28:53 按 KEY1+复位后正常进入 BIOS。',
    '3. 21:29:12 点击加载，工具发送空行重新请求菜单；Input error 后 BIOS 重新打印菜单。这是现有空行探测行为，不能单凭该行判失败。',
    '4. 随后 Baud: / Baud result: 2000000 正常可读；21:29:12.748 开始乱码。',
    f'5. 用户报告此时复位后全是“·”；21:30:13.791 的接收记录实际是 {zero_count} 个字节，原始 hex 保存在 rx_hex.tsv，不能仅凭GUI显示判成发送了句点字符。',
    f'6. 只读状态快照：connected={status["connected"]}，端口={status["config"]["port"]}，主机波特率={status["config"]["baud"]}；加载器 active={program["active"]}，phase={program["phase"]}，sent={program["sent"]}/{program["total"]}，programmedBytes={program["programmedBytes"]}。',
    '7. 未出现 Load result: OK、Run 成功、任何 NPU A/B/C/D PASS/FAIL，未取得 PASS39/39、LED状态、ms/frame或fps。当前现象更早发生在波特率切换/菜单同步阶段，不能归因到 NPU MAC 运算。', '',
    '推断（尚未验证）：复位会令 BIOS 恢复115200，而主机快照仍为2000000，足以解释复位后无法正常解码；最初从115200切换到2000000为何失败，还需检查板端分频/时序与GUI切换及菜单握手。GUI工程选择仍为B3V，此项仅为工具状态记录，不能当成实际bitstream标识。', '',
    '## 日志与限制','',
    'uart/b3n_board_npu.log 是GUI当前全部缓冲的原文导出（包含NUL），gui_buffer.json / rx_hex.tsv保留原始字节证据；uart/b3n_boot.log是普通启动片段。其他json为只读状态快照，截图为用户提供原图。', '',
    '各阶段全部W/C/E原文、动作耗时和路由进度已保存；原始完整run.log保留在本地工程对应阶段目录。没有提交工程/IP目录、数据库、bitstream或完整执行日志。时序扩展导出仅用于报告，不触发实现流程。', '',
    'ROM/SRAM源IP配置的初始化dat与本卡dat此前已逐字节比较一致；当前启动打印的Build commit 9510c64是BIOS/监控镜像自报版本，不等同于本轮RTL提交。', '',
    '本轮回传实现结果和ELF加载异常，后续由Claude分析串口高波特率问题，再重测39项；未擅自修改GUI、RTL或重新烧录。']
newbuf=OUT/'uart/gui_buffer_115200.json'
if newbuf.exists():
    attempt=json.loads(read(newbuf))
    entries=attempt['entries']
    secondstatus=json.loads(read(OUT/'uart/gui_program_status_115200.json'))
    write(OUT/'uart/rx_hex_115200.tsv','seq\ttimestamp_epoch_ms\thex\n'+'\n'.join(f'{e["seq"]}\t{e["ts"]}\t{e.get("hex","")}' for e in entries if e['dir']=='rx'))
    results=[e['text'] for e in entries if e['text'].startswith('NPU ')]
    report[2]='B3N 已完成综合、映射、布局布线、STA 和 bitstream。第一次 GUI 切换到2 Mbaud后乱码；第二次保持115200，ELF加载和运行成功，三个寄存器项通过，首个卷积用例失败，最终 NPU board: FAIL 1/39。实现时序通过，上板功能未通过。'
    report=[l.replace('实现完成；步骤8 ELF加载阶段异常，测试未完成','实现完成；步骤8已运行NPU测试，首个卷积用例失败') for l in report]
    report=[l.replace('## 串口异常与用户实测','## 第一次尝试：2 Mbaud 切换异常（历史记录）') for l in report]
    report=[l.replace('本轮回传实现结果和ELF加载异常，后续由Claude分析串口高波特率问题，再重测39项；未擅自修改GUI、RTL或重新烧录。','本轮同时回传2 Mbaud握手异常和115200下真实NPU数据比对失败，两者分别分析。没有擅自修改GUI、RTL或重新烧录。') for l in report]
    insert=report.index('## 日志与限制')
    detail=['## 第二次尝试：115200 加载成功，NPU功能失败','',
        '用户在GUI选择不切换波特率后重试。COM7、115200、8N1；Load bytes: 5177412 at 0x80000000；Load result: PASS；Run: 0x80000000。加载器 active=false、phase=done、error=null，确认已经完成加载并运行，不能再把本次故障归为ELF没有加载成功。','',
        '板端逐项原文：','', '```text',*results,'```','',
        '三个A项通过（ID、空描述符完成、复位寄存器），首个B项 B-OP-01-c16_32 失败：desc=0；首错地址0x1102000d；期望0x02，实际0x01；mismatches=160；PERF0=522；MAC=32；失败前passed=3。程序按设计首错停止，未运行后续小用例、整网和连续20帧，ms/frame、fps及LED状态未取得。最终 FAIL 1/39 按板端原文保留，不擅自解释为39项全部跑完。','',
        '该错误发生在真实NPU输出数据比对阶段，和第一次2 Mbaud解码/菜单同步异常是独立现象。保留完整数据差异作为Linux侧排查APM级联/符号/量化/存储等问题的输入，目前不凭首错值认定根因。','',
        '第二次完整缓冲：uart/b3n_board_npu_115200.log；原始条目与HEX：gui_buffer_115200.json、rx_hex_115200.tsv；配置和加载状态快照：gui_status_115200.json、gui_program_status_115200.json。','']
    report[insert:insert]=detail
report += ['', '## APM相关警告分类补充','',
    'apm_warnings.txt 的3087行是按 APM/CPI/CPO/cascade 关键字筛选的日志行，不是3087个级联放置错误。其中Public-4008为3045行，Sdm-2003为42行。完整原文已保存；其中Sdm-2003包括CPU ip_mul_s33x33的cpo未驱动告警。实现流程没有因级联连接/放置错误中止。', '',
    '扩展导出记录：使用现有DB补充STA 8456条路径，并成功导出APM布局；首次APM导出因未传映射DB失败，补入compile/synthesize/devmap DB后原生命令成功。仅导出报告，无实现重跑。大文件setup_top200_clk_mem.txt约7.9MiB，保留多路径逐级原文用于分析。']
write(TASK/'result.md','\n'.join(report))
print('Collected',len(eps),'timing paths;',len(near),'dangerous positive setup paths.')
