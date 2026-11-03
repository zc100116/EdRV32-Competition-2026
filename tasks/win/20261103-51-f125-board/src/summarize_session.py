"""Summarize the captured card51 session; does not operate the board."""
from pathlib import Path
import re, csv, statistics, collections

repo=Path(__file__).resolve().parents[4]
art=Path(__file__).resolve().parents[1]/'artifacts'
text=(art/'uart/final_session_snapshot.log').read_text(encoding='utf-8')
lines=text.splitlines()
raw=re.sub(r'^\[\d+\] \[\w+\] ','',text,flags=re.M)
def save(name,content):
 p=art/name;p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text(content.rstrip()+'\n',encoding='utf-8')
def selected(name,keys):save(name,'\n'.join(l for l in lines if any(k in l for k in keys)))

selected('uart/coremark.log',['CoreMark','CRC ','Iterations','HPM','Cycle','cycles','Instructions','instructions','Round','round','IPC','Score status'])
selected('uart/npu_selftest.log',['NPU A-','NPU B-','NPU C-','NPU D-','NPU board:'])
selected('uart/eth_diagnostic.log',['PHY','PERF','link=','PEER=','TX sequence','STATUS=','IRQ_STAT=','ERR_CODE=','ETH load ready','Load bytes:','Load result:','Run:'])
selected('benchmark.txt',['LVGL split','LVGL benchmark','RND type=','RND batch='])
selected('uart/showcase_events.log',['Showcase:','showcase ','Showcase CPU','NES fps=','LAYERS','Uniform transparency'])

for marker,name in [('Demo: demo_vision','demo_vision.log'),('Demo: demo_vnpu','demo_vnpu.log')]:
 start=next((i for i,l in enumerate(lines) if marker in l),None)
 if start is not None:
  end=next((i for i in range(start+1,len(lines)) if 'Demo:' in lines[i]),len(lines))
  save('uart/'+name,'\n'.join(lines[start:end]))

actual=re.findall(r'RND (\w+) crc=\s*(0x[0-9a-f]{8})',raw)
expected=re.findall(r'RND (\w+) crc=(0x[0-9a-f]{8})',(repo/'tasks/win/20261103-46-b3r-rnd1slim/src/rnd_board_expected.log').read_text(encoding='utf-8'))
save('rnd_crc_check.txt','\n'.join(f'{n}: actual={v} expected={ev} '+('PASS' if (n,v)==(en,ev) else 'FAIL') for (n,v),(en,ev) in zip(actual,expected))+f'\nactual={len(actual)} expected={len(expected)} matches={sum(a==b for a,b in zip(actual,expected))}')
nes=[tuple(map(float,m)) for m in re.findall(r'NES fps=([\d.]+) display=([\d.]+) CPU=([\d.]+)%',raw)]
summary=[f'CoreMark result PASS messages: {raw.count("CoreMark result: PASS")}',f'CoreMark CRC PASS messages: {raw.count("CRC result: PASS")} (two internal HPM rounds are one menu run)',f'NPU board PASS39/39 messages: {raw.count("NPU board: PASS 39/39")}',f'NPU D PASS lines: {len(re.findall(r"NPU D-\d+ PASS",raw))}',f'RND matches: {sum(a==b for a,b in zip(actual,expected))}/{len(expected)}',f'NES samples: {len(nes)}']
if nes:
 for i,name in enumerate(['emulation_fps','display_fps','cpu_percent']):
  vals=[x[i] for x in nes];summary.append(f'NES {name}: mean={statistics.mean(vals):.3f} min={min(vals):.3f} max={max(vals):.3f}')
summary.extend(l for l in raw.splitlines() if any(k in l for k in ['NPU C-YOLO','CoreMark/MHz','Iterations/Sec','LVGL benchmark average']))
save('test_counts.txt','\n'.join(summary))
with (art/'cpu_nes.csv').open('w',newline='',encoding='utf-8-sig') as f:
 w=csv.writer(f);w.writerow(['host_timestamp_ms','record','idle_percent','comm_percent','app_percent','gui_percent','gui_fps','nes_fps','nes_display_fps','nes_cpu_percent'])
 for l in lines:
  ts=re.match(r'\[(\d+)\]',l)
  m=re.search(r'Showcase CPU idle=(\d+)% comm=(\d+)% app=(\d+)% gui=(\d+)% GUI fps=(\d+)',l)
  n=re.search(r'NES fps=([\d.]+) display=([\d.]+) CPU=(\d+)%',l)
  if m:w.writerow([ts[1],'showcase',*m.groups(),'','',''])
  if n:w.writerow([ts[1],'nes','','','','','',*n.groups()])
with (art/'edtm_final.csv').open(encoding='utf-8-sig',newline='') as f:
 rows=list(csv.DictReader(f))
save('telemetry_coverage.txt',f'Rows={len(rows)}\nTypes={dict(collections.Counter(x["type"] for x in rows))}\nScenes={dict(collections.Counter(x["scene"] for x in rows))}\nMixed live-session export; no host timestamp column, do not assign all rows to a single program.\n')
print('\n'.join(summary))
