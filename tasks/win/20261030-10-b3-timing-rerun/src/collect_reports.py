"""Read-only report snapshots; never starts or interrupts PDS jobs."""
from pathlib import Path
from collections import Counter
import json, re, runpy, shutil, subprocess

REPO = Path(__file__).resolve().parents[4]
TASK = Path(__file__).resolve().parents[1]
OUT = TASK / 'artifacts'
ROOT = REPO.parent / 'EdRV32-FPGA'
H = runpy.run_path(str(REPO / 'tasks/win/20261028-03-cpu-sys-synth-r4/src/collect_reports.py'))
read, paths, index, hierarchy, section = (H[n] for n in ('read','paths','index_text','hierarchy','section'))
PROJECTS = {'B3V':'vision', 'B3VN':'vnpu', 'B3R':'render', 'B3F':'b2'}

def write(p, s):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text('\n'.join(l.rstrip() for l in s.splitlines())+'\n', encoding='utf-8')

def copy(root, out, stage, name):
    p = root/stage/name
    if p.exists():
        dst = out/'native_reports'/stage/name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(p, dst)

summary = []
for name, suffix in PROJECTS.items():
    root, out = ROOT/f'EdRV32-{name}', OUT/name
    top = f'edrv32_fpga_board_{suffix}_top'
    stage_data, warning_lines, excerpts = {}, [], []
    for stage in ('compile','synthesize','device_map','place_route','report_timing','generate_bitstream'):
        p = root/stage/'run.log'
        if not p.exists(): continue
        raw = read(p)
        # Route and subsequent reports are only accepted when this run has completed routing.
        if stage == 'place_route':
            routed = 'placed and routed successfully' in raw
            route_raw = raw
        if stage in ('report_timing','generate_bitstream') and not routed: continue
        warnings = [l for l in raw.splitlines() if re.match(r'^[WCE]:',l)]
        actions = [l for l in raw.splitlines() if l.startswith('Action ')]
        stage_data[stage] = {'actions':actions, 'counts':dict(Counter(l[:1] for l in warnings))}
        warning_lines += [f'=== {p} ===']+warnings+['']
        excerpts += [f'=== {p} ===']+[l for l in raw.splitlines() if
            re.match(r'^(Action |Current time:|Phase |Process |Start |Finished |Unrouted |Worst slack|Total negative|MT |W:|C:|E:)',l)
            or 'Time elapsed:' in l or re.search(r'takes .*sec',l)]+['']
    for stage, files in {
        'compile':[f'{top}.cmr','include_relation.txt'],
        'synthesize':[f'{top}.snr',f'{top}_controlsets.txt','apm_drm_lutram_utilization.log','add_sub_carrychain.log'],
        'device_map':[f'{top}.dmr',f'{top}_dmr.prt'],
        'constraint_check':['constraint_check.ccr'],
    }.items():
        for f in files: copy(root,out,stage,f)
    snr = read(root/'synthesize'/f'{top}.snr')
    dmr = read(root/'device_map'/f'{top}.dmr')
    table, entries = hierarchy(snr)
    write(out/'resource_hier_synthesis.txt',table)
    usage = section(dmr,'Device Utilization Summary:')
    write(out/'resource_summary.txt','Device-map capacity usage (not post-route).\n'+usage+'\n\nSynthesis hierarchy units: LUT, FF, distributed RAM, APM, DRM36K equivalent.\n'+str(entries[0]))
    write(out/'high_fanout.txt','\n\n'.join(section(dmr,t) for t in
          ('Other High Fanout Signal:','Clock Signal:','Reset Signal:','CE Signal:') if t in dmr))
    sp = paths(snr,'synthesis_estimate')
    write(out/'synthesis_paths.tsv',index(sp))
    write(out/'synthesis_path_detail.txt','\n\n'.join(p['block'] for p in sp))
    write(out/'synthesis_timing_summary.txt',snr[snr.index('Timing analysis mode'):].split('Startpoint',1)[0])
    route = re.findall(r'Unrouted general nets at iteration (\d+) \(MT total route time: ([\d.]+) sec\): (\d+)\(overused: (\d+)\)',route_raw)
    write(out/'route_progress.tsv','iteration\tMT_total_route_time_raw_sec\tunrouted_general_nets\toverused\n'+'\n'.join('\t'.join(r) for r in route))
    write(out/'route_progress.txt','Completed route: '+str(routed)+'\nMT total route time is copied verbatim; not summed as wall time.\n'+
          '\n'.join(l for l in route_raw.splitlines() if 'slack' in l.lower())+'\n\nLast 30 lines of the read snapshot:\n'+'\n'.join(route_raw.splitlines()[-30:]))
    write(out/'flow_summary.txt',f'Project: {root}\nRead-only snapshot; no jobs started/stopped.\n'+
          '\n\n'.join(f'{s}: {d["counts"]}\n'+'\n'.join(d['actions']) for s,d in stage_data.items()))
    write(out/'logs/warnings_detail.txt','\n'.join(warning_lines))
    write(out/'logs/execution_excerpt.txt','Selected stage/progress/action lines; full raw logs remain locally.\n'+'\n'.join(excerpts))
    write(out/'resource_hier.txt',('SYNTHESIS ONLY: route not complete.\n'+table) if not routed else hierarchy(read(root/'place_route'/f'{top}.prr'))[0])
    if routed:
        for stage, fs in {'place_route':[f'{top}.prr',f'{top}_prr.prt','clock_utilization.txt'], 'report_timing':[f'{top}.rtr']}.items():
            for f in fs: copy(root,out,stage,f)
        raw = read(root/'report_timing'/f'{top}.rtr')
        head = raw.split('\nSlow Corner',1)[0]
        tp = paths(raw,'routed_default_report')
        coverage = f'Existing default report contains {len(tp)} path records across all clocks/corners/classes. Per-clock 200 paths have NOT been exported. No extra STA process was launched while three PnR jobs consume memory. Supplement after routing jobs finish.\n'
        write(out/'timing_summary.txt',coverage+head)
        write(out/'timing_all_paths.tsv',index(tp))
        write(out/'timing_all_path_detail.txt',coverage+'\n\n'.join(p['block'] for p in tp))
        for direction, filename in [('max','setup_top20_detail.txt'),('min','hold_top20.txt')]:
            selected = [p for p in tp if p['type'].startswith(direction) and p['class']=='sequential timing path']
            picked = [p for corner in ('slow','fast') for p in sorted((q for q in selected if q['corner']==corner),key=lambda q:q['slack'])[:20]]
            write(out/filename,coverage+'\n\n'.join(p['block'] for p in picked))
        for clock in sorted(set(p['group'] for p in tp)):
            selected = [p for p in tp if p['group']==clock and p['type'].startswith('max')]
            safe_clock = re.sub(r'[^A-Za-z0-9_.-]', '_', clock)
            write(out/f'setup_top200_{safe_clock}.txt',coverage+'\n\n'.join(p['block'] for p in selected))
        write(out/'dangerous_positive_paths.txt',coverage+'\n\n'.join(p['block'] for p in tp if p['slack'] is not None and 0<=p['slack']<1))
    else:
        write(out/'timing_summary.txt','Route in progress. Final routed WNS/TNS/WHS/THS and recovery/removal not yet available. See synthesis estimates separately; do not treat these as routed STA.\n')
    worst = {}
    for p in sp:
        if p['type'].startswith('max') and p['class']=='sequential timing path' and (p['group'] not in worst or p['slack']<worst[p['group']]['slack']): worst[p['group']]=p
    summary.append({'name':name,'root':str(root),'routed':routed,'stages':stage_data,'usage':usage,'synth_totals':entries[0],
                    'last_route_iteration':route[-1] if route else None,'synth_worst':[{k:v for k,v in p.items() if k!='block'} for p in worst.values()]})
write(OUT/'collection_summary.json',json.dumps(summary,ensure_ascii=False,indent=2))
print(json.dumps([{'project':s['name'],'routed':s['routed'],'last_iteration':s['last_route_iteration']} for s in summary],ensure_ascii=False))

host = json.loads((OUT/'host_resource_snapshot.json').read_text(encoding='utf-8-sig'))
commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
lines = ['# 20261030-10-b3-timing-rerun 阶段报告', '',
    '四个工程的编译、综合、device_map 均已完成。B3V 已完成布局布线、STA 和 bitstream；B3VN、B3R、B3F 仍在布线。本次按用户要求先回传已完成阶段及进行中快照，没有启动、停止或重跑任何 PDS 流程。', '',
    f'当前检出代码 commit：`{commit}`（记录检出位置，不另行核验构建来源）。工程均复用 `G:/codex_project/EdRV32-FPGA/EdRV32-<工程名>`，实际目录为 B3V、B3VN、B3R、B3F。', '',
    '## 阶段耗时与资源', '',
    '耗时是日志 Action 的 Real time；完整 CPU time、Process CPU time、峰值内存及 W/C/E 行数在各工程 flow_summary.txt。资源表取 device_map 原生 DMR，DRM 沿用报告的块数口径；综合层级表另有 DRM36K 等效量。', '',
    '| 工程 | compile | synthesize | device_map | PnR | LUT | FF | APM | DRM | 分布式 RAM | IO | GPLL/PPLL |',
    '|---|---|---|---|---|---|---|---|---|---|---|---|']
for s in summary:
    def metric(stage):
        a = s['stages'].get(stage,{}).get('actions',[])
        return next((l.split('Real time elapsed is ',1)[1] for l in a if 'Real time elapsed is ' in l),'进行中')
    def resource(n):
        m = re.search(r'^\| '+re.escape(n)+r'\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)',s['usage'],re.M)
        return f'{m[1]} ({m[3]}%)'
    lines.append('| '+' | '.join([s['name'],*(metric(t) for t in ('compile','synthesize','device_map','place_route')),
        *(resource(n) for n in ('LUT','FF','APM','DRM','Distributed RAM','IO')),resource('GPLL')+'/'+resource('PPLL')])+' |')
lines += ['', '## 布线慢的证据', '',
    'B3R、B3F 存在显著的 RND 组合长路径，综合估算 clk_mem WNS 分别为 −18.535 ns（25 级）和 −18.700 ns（22 级），终点均为 u_draw/bank_sparse_r[0]。这是优先交给 RTL 侧分析的线索，不能直接当作布线后的结果。', '',
    '布线日志中 B3R/B3F 的 before-route Worst slack 原始值为 −16185/−17717，TNS 为 −59151227/−108811314；B3VN 为 +377、TNS 0，B3V 为 +926、TNS 0。该日志行未注明单位，这里保留原值，不转换成 ns。B3VN 布局后没有负裕度仍然布线很慢，说明耗时不能只归因于负 slack。', '',
    '| 工程 | 快照最后迭代 | 未布通 general nets | overused（原始计数） |',
    '|---|---|---|---|']
for s in summary:
    r=s['last_route_iteration']
    if r: lines.append(f'| {s["name"]} | {r[0]} | {r[2]} | {r[3]} |')
lines += ['', '三个进行中工程的未布通网络及 overused 随迭代总体下降，说明仍在收敛；大量 overused 是布线拥塞线索，不能保证最终成功。全部迭代见 route_progress.tsv。B3F 的 APM 77%、DRM 79% 增加了资源放置及布线压力；B3R 总 LUT 只有 33%，也不能排除局部拥塞。MT total route time 逐行保存，不累加成总墙钟时间。', '',
    f'系统快照时间：{host["capturedAt"]}。物理内存 {int(host["physicalMemoryKiB"])/1048576:.2f} GiB，可用 {int(host["freePhysicalMemoryKiB"])/1048576:.2f} GiB；系统提交量 {int(host["committedBytes"])/2**30:.2f} GiB / 提交上限 {int(host["commitLimitBytes"])/2**30:.2f} GiB。', '',
    '| PnR 进程 | 已运行分钟 | CPU 秒 | 工作集 GiB | 私有提交量 GiB |', '|---|---|---|---|---|']
for p in host['pnrProcesses']:
    lines.append(f'| {p["project"]} | {p["elapsedMinutes"]:.2f} | {p["cpuSeconds"]:.2f} | {p["workingSetBytes"]/2**30:.2f} | {p["privateCommitBytes"]/2**30:.2f} |')
lines += ['',
    f'当前单点 PagesInput/sec={host["pagesInputPerSecond"]}，PageReads/sec={host["pageReadsPerSecond"]}。此前排查中曾观测到全系统 8916/2274 的非零采样值，当前快照为零，表明不能把换页视为持续状态。私有提交量不是页面文件驻留量。并行运行及提交量说明内存压力，但现有采样不能量化换页对各工程耗时的贡献。待本轮结束，后续可按任务卡串行运行较大的工程进行比较；本次未改变运行方式。', '',
    '## 综合估算最差路径', '', '以下全部是综合估算，单位 ns；同时保留正裕度风险。详细路径、完整时钟域和层级资源见各工程 artifacts。', '',
    '| 工程 | 时钟 | WNS | 逻辑级数 | 起点 → 终点 |', '|---|---|---|---|---|']
for s in summary:
    for p in s['synth_worst']:
        if p['group'] in ('clk_mem','clk_sys','clk_eth','clk_npu'):
            lines.append(f'| {s["name"]} | {p["group"]} | {p["slack"]:+.3f} | {p["levels"]} | `{p["start"]}` → `{p["end"]}` |')
lines += ['', '## B3V 布线后 STA', '',
    '原生报告结论 All Constraints Met。slow 角 clk_mem +0.305 ns、clk_sys +0.762 ns、clk_eth +0.189 ns；正裕度仍偏紧，特别是 eth 和 mem。相比卡 07：mem −0.554 → +0.305、sys +0.182 → +0.762、eth +0.798 → +0.189 ns。当前通过不代表以后集成更多模块后仍有足够裕度。', '',
    '| 分析 | 角 | launch → capture | WNS/WHS ns | TNS/THS ns | 违例端点 | 总端点 |', '|---|---|---|---|---|---|---|']
raw = read(OUT/'B3V/timing_summary.txt')
active=None
for l in raw.splitlines():
    m=re.match(r'(Setup|Hold|Recovery|Removal) Summary\((Slow|Fast) Corner\):',l)
    if m: active=m.groups()
    elif 'Summary' in l and not m: active=None
    elif active:
        m=re.match(r'\s*(\S+)\s+(\S+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)\s*$',l)
        if m: lines.append('| '+' | '.join([*active,m[1]+' → '+m[2],*m.groups()[2:]])+' |')
lines += ['',
    '当前原生默认 report_timing 含 232 条路径记录（跨时钟、角和路径类型），已全部保存索引及明细，并额外汇总 0–1 ns 的正裕度路径。每个角的 setup/hold 最差路径也已整理。setup_top200_<时钟>.txt 文件头明确标注覆盖不足：本次未另行导出每时钟 200 条，以避免在三个 PnR 进程运行时启动额外 STA。后续最终报告需补足该项。B3VN/B3R/B3F 的布线后时序尚未取得，不以综合结果代填。', '',
    '## 警告与产物范围', '',
    '各工程保存 CMR/SNR/DMR、include 关系、综合控制集、APM/DRM/LUTRAM、carry-chain、约束检查报告、层级资源及高扇出表。B3V 另有 PRR/RTR 和时钟资源报告。logs/warnings_detail.txt 保存各阶段全部 W/C/E 原文，flow_summary.txt 统计行数；C 行按原始严重级别保留，不擅自当成致命错误。原生报告内的 loop、截位、未驱动、扇出等警告均可由 Claude 直接复核。', '',
    '未上传完整 run.log、数据库、工程/IP 目录或 bitstream。执行摘要保留阶段耗时和路由收敛行。完整本地日志位于上述各工程的 <stage>/run.log；PDS 报告在对应 compile/synthesize/device_map/place_route/report_timing 子目录。上板启动信息和 BIOS 验收本次未取得。', '',
    '这是按用户要求提交的阶段回传；其余三个工程结束后仍需追加最终 PnR/STA/bitstream 结果。', '', '大文件清单（超过 3 MiB；保留原生报告或完整警告供诊断）：', '']
for p in sorted(OUT.rglob('*')):
    if p.is_file() and p.stat().st_size>3*2**20: lines.append(f'- `{p.relative_to(TASK).as_posix()}`：{p.stat().st_size/2**20:.2f} MiB')
write(TASK/'result.md','\n'.join(lines))
