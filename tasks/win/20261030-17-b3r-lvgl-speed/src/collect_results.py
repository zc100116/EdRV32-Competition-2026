"""Parse captured GUI UART records for card17; no serial or FPGA mutations."""
from pathlib import Path
import csv,io,json,shlex,subprocess

TASK=Path(__file__).resolve().parents[1]
OUT=TASK/'artifacts'

def write(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text('\n'.join(l.rstrip() for l in text.splitlines())+'\n',encoding='utf-8')
def table(name,fields,rows):
    with (OUT/name).open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,delimiter='\t');w.writeheader();w.writerows(rows)

buf=json.loads((OUT/'uart/gui_buffer.json').read_bytes())
entries=buf['entries'];rx=[e for e in entries if e['dir']=='rx'];lines=[e['text'] for e in rx]
splits=[dict(t.split('=',1) for t in shlex.split(l[len('LVGL split '):])) for l in lines if l.startswith('LVGL split ')]
assert len(splits)==17 and len({r['scene'] for r in splits})==17
keys=list(splits[0]);assert len(keys)==52 and all(set(r)==set(keys) for r in splits)
assert sum(r['scene']=='ALL' for r in splits)==1
table('lvgl_split.tsv',keys,splits)
table('uart/rx_hex.tsv',['seq','timestamp_epoch_ms','hex'],[dict(seq=e['seq'],timestamp_epoch_ms=e['ts'],hex=e.get('hex','')) for e in rx])
summary=[]
for i,line in enumerate(lines):
    if line.startswith('Benchmark Summary'):
        end=next((j for j in range(i+1,len(lines)) if lines[j].startswith('All scenes avg.')),None)
        if end is not None:summary=lines[i:end+1]
assert summary,'Benchmark Summary incomplete'
write(OUT/'benchmark_summary.txt','\n'.join(summary))
rn=[l for l in lines if l.startswith('RN-17')]
rn_result=[l for l in rn if l.startswith('RN-17 full_')]
assert rn_result,'RN-17 result absent'
cache_full=[l for l in lines if 'S3 glyph cache full' in l]
write(OUT/'rn17.txt','\n'.join(rn))
write(OUT/'rnd_statistics.txt','\n'.join(l for l in lines if l.startswith(('RND type=','RND batch='))))
write(OUT/'glyph_cache_status.txt','\n'.join(cache_full) if cache_full else 'Captured UART contains no S3 glyph cache full line.')
# Compare stored measurements, without changing any raw split values.
baseline_commit='788064d5'
baseline=subprocess.check_output(['git','show',baseline_commit+':tasks/win/20261030-16-b3r-lvgl-nes/artifacts/lvgl_split.tsv'],text=True,encoding='utf-8')
before={r['scene']:r for r in csv.DictReader(io.StringIO(baseline),delimiter='\t')}
comp=[]
for row in splits:
    old=before.get(row['scene'],{})
    comp.append(dict(scene=row['scene'],card16_frames=old.get('frames','未取得'),card17_frames=row['frames'],
        card16_render_ms=old.get('render_ms','未取得'),card17_render_ms=row['render_ms'],
        card16_rnd_ms=old.get('rnd_ms','未取得'),card17_rnd_ms=row['rnd_ms'],
        card16_sw_ms=old.get('sw_ms','未取得'),card17_sw_ms=row['sw_ms'],
        card16_other_ms=old.get('other_ms','未取得'),card17_other_ms=row['other_ms']))
table('comparison_card16.tsv',list(comp[0]),comp)
current=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
status=json.loads((OUT/'uart/gui_status.json').read_bytes())
program=json.loads((OUT/'uart/gui_program_status.json').read_bytes())
allrow=next(r for r in splits if r['scene']=='ALL');old=before['ALL']
report=['# 20261030-17-b3r-lvgl-speed 结果','',
    '新版S3 benchmark自然结束，已取得16个场景及ALL共17行split、每行52个字段，RN-17 PASS。串口未出现S3 glyph cache full。平均FPS为18，上轮卡16为15；本轮仅换软件，未运行综合、布局布线或STA。','',
    '| 项 | 内容 |','|---|---|',f'| 当前任务检出commit | {current} |',
    '| 任务基点 | f6489840，软件构建来源按任务卡为6bcce541 |',
    '| bitstream | 沿用卡14 B3R，G:/codex_project/EdRV32-FPGA/EdRV32-B3R |',
    f'| 加载方式 | GUI，{status["config"]["port"]}，{status["config"]["baud"]}，8N1 |',
    f'| 加载程序（GUI状态） | {program["path"]} |',
    f'| 加载结果 | programmedBytes={program["programmedBytes"]}，{program["result"]}，error={program["error"]} |',
    '| 完成情况 | benchmark和RN-17均完成，数据完整 |','',
    '## Benchmark Summary 原文','', '```text',*summary,'```','',
    '## split摘要','',
    '完整17行52列见artifacts/lvgl_split.tsv，所有字段名及数字按原文保留。实际IPC字段名为cpu_ipc，本报告也使用此原始名称，不改为ipc。', '',
    '| 场景 | render_ms | rnd_ms | sw_ms | other_ms | perf0_ms | clean_ms | wait_ms | finish_ms | cache_ops | glyph_cpu_ms | cpu_ipc | icache_mpki | dcache_mpki |',
    '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|']
fields=['scene','render_ms','rnd_ms','sw_ms','other_ms','perf0_ms','clean_ms','wait_ms','finish_ms','cache_ops','glyph_cpu_ms','cpu_ipc','icache_mpki','dcache_mpki']
for row in splits:report.append('| '+' | '.join(row[k] for k in fields)+' |')
report += ['', '## 与卡16数据对照','',
    f'来源为任务16提交{baseline_commit}的已上传原始TSV，并非重新测量。逐场景原值并排保存在comparison_card16.tsv。两个benchmark统计帧数不同，比较时应结合各场景字段，不能把ALL帧数或累计xbar计数直接当成相同工作量。', '',
    '| ALL字段 | 卡16 | 卡17 |','|---|---|---|']
for k in ('frames','render_ms','rnd_ms','sw_ms','other_ms','perf0_ms','copy_rnd_ms'):report.append(f'| {k} | {old[k]} | {allrow[k]} |')
report += ['',
    'Benchmark Summary的All scenes avg.整数FPS为15→18，按该汇总计算提升20%；ALL render_ms为67.110→57.464。这是两轮上板观测值对照，不把程序不同口径的时间和平均FPS强行互算。', '',
    '## CPU与RND观察','',
    f'ALL：cpu_ipc={allrow["cpu_ipc"]}、icache_mpki={allrow["icache_mpki"]}、dcache_mpki={allrow["dcache_mpki"]}；clean_ms={allrow["clean_ms"]}、wait_ms={allrow["wait_ms"]}、finish_ms={allrow["finish_ms"]}、glyph_cpu_ms={allrow["glyph_cpu_ms"]}。', '',
    f'原始CPU计数：cycles={allrow["cpu_cycles"]}、instructions={allrow["cpu_instructions"]}、frontend_empty_cycles={allrow["cpu_frontend_empty_cycles"]}、icache_misses={allrow["cpu_icache_misses"]}、dcache_misses={allrow["cpu_dcache_misses"]}。load-use/divide/device-wait/branch等完整字段及mem_xbar端口统计见TSV。', '',
    '上述计数供Linux端分析CPU瓶颈；本轮没有改cache容量或进行控制变量实验，不能据一次测量断言扩大cache一定改善性能。cache_ops字段保留程序打印值，不能用它直接替代每次门铃的cache维护调用数。', '',
    '## RN-17 原文','', '```text',*rn,'```','',
    'RN-17结果为PASS；完整差异统计按板端原文保存，未在主机重新计算或替换。', '',
    '## 产物与范围','',
    f'取得GUI缓冲seq范围{entries[0]["seq"]}–{entries[-1]["seq"]}，共{len(entries)}条。uart/s3.log为完整GUI文本导出，gui_buffer.json与rx_hex.tsv保留条目和字节证据，状态快照也已保存。采集时GUI已断开，读取缓冲不重新连接、不发送串口数据。', '',
    'benchmark_summary.txt、lvgl_split.tsv、rn17.txt、rnd_statistics.txt、glyph_cache_status.txt及comparison_card16.tsv均已保存。S3 glyph cache full出现次数：'+str(len(cache_full))+'。', '',
    'GUI工程下拉显示B3V仅为工具状态，不据此判定bitstream。未核验源码版本或报告时间，未修改RTL、软件或工程配置，未重跑任何FPGA流程。本轮没有新增照片或用户主观显示结论，报告只依据实际串口结果。']
write(TASK/'result.md','\n'.join(report))
print('split',len(splits),'columns',len(keys),'RN17',rn_result[-1],'glyph cache full',len(cache_full))
