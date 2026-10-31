"""Summarize stopped NES captures. No serial, ROM conversion, or FPGA actions."""
from pathlib import Path
from statistics import mean,median
import csv,json,re,subprocess

TASK=Path(__file__).resolve().parents[1]
OUT=TASK/'artifacts'

def write(p,t):
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text('\n'.join(l.rstrip() for l in t.splitlines())+'\n',encoding='utf-8')

raw=(OUT/'uart/nes-smb-hack.log').read_bytes()
lines=raw.decode('utf-8',errors='replace').splitlines()
marker=lines.index('NES ROM prg=32 chr=8 mapper=0')
assert 'Read in trainer at $7000' in lines
rows=[]
for line in lines[marker+1:]:
    m=re.fullmatch(r'NES fps=([\d.]+) shown=([\d.]+) cpu=(\d+)% ppu=(\d+)%',line)
    if m:rows.append(dict(window=len(rows)+1,fps=m[1],shown=m[2],cpu_percent=m[3],ppu_percent=m[4]))
assert len(rows)>=3
with (OUT/'nes_smb_hack_fps.tsv').open('w',encoding='utf-8',newline='') as f:
    w=csv.DictWriter(f,fieldnames=['window','fps','shown','cpu_percent','ppu_percent'],delimiter='\t');w.writeheader();w.writerows(rows)
stats={}
for k in ('fps','shown','cpu_percent','ppu_percent'):
    v=[float(r[k]) for r in rows[1:]]
    stats[k]=dict(min=min(v),max=max(v),window_arithmetic_mean=round(mean(v),3),median=median(v))
(OUT/'fps_summary.json').write_text(json.dumps(dict(window_count=len(rows),excluded_windows=[1],statistics=stats,
    scope='Final stopped capture. Arithmetic mean of reported windows; not duration-weighted aggregate.'),indent=2)+'\n',encoding='utf-8')
# Replace earlier snapshot with the final stopped-capture numbers.
snapshot=OUT/'fps_snapshot.json'
if snapshot.exists():snapshot.write_text((OUT/'fps_summary.json').read_text(),encoding='utf-8')
write(OUT/'checklist.md','''# 上板检查

| 项目 | 结果 | 证据 |
|---|---|---|
| 复用B3R bitstream | 本轮未重新综合或布线 | 使用卡14工程 |
| 带trainer ROM加载 | PASS | Load result及trainer/mapper原文 |
| 标题与游戏画面恢复 | 用户确认可正常游玩 | 用户回复 |
| 操作 | 用户确认可正常游玩，未逐键单列结果 | 用户回复 |
| 主观速度 | 用户感觉帧率低，要求监控并留作优化依据 | 用户回复 |
| 帧率采集 | 已保存全部窗口；按用户要求停止，COM7已释放 | 原始日志及TSV |
| 不带trainer原版对照 | 未执行，待测 | 未取得日志 |
| 照片 | 未提供 | 不补造 |
''')
commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
report=['# 20261031-18-nes-trainer 结果','',
    '带trainer超级版已能正常游玩，之前的全灰现象不再出现。用户认为帧率偏低，要求监控串口并整理数据上传；采集已按用户要求停止。不带trainer原版对照尚未执行，本卡回传已完成部分，不判整卡全部完成。','',
    '| 项 | 内容 |','|---|---|',f'| 当前检出commit | {commit} |',
    '| 任务输入程序 | tasks/win/20261031-18-nes-trainer/src/nes.elf，构建来源按任务卡为b3dfeec3 |',
    '| bitstream | 卡14 B3R；本轮不改RTL、IP或工程，不重新综合布线 |',
    '| 加载方式 | Codex后台uart_tool.py，COM7、115200、8N1；用户预先断开GUI并进入BIOS |',
    '| 现场操作 | KEY4 Start、KEY1/2左右、KEY3跳；用户确认可以正常游玩 |',
    '| 完成情况 | 超级版测试及帧率采集完成；原版对照未执行 |', '',
    '## 两个ROM的状态','',
    '| ROM | NES ROM行 | trainer行 | 画面 | 按键 | FPS第2–4窗口 | 用户反馈 |',
    '|---|---|---|---|---|---|---|',
    '| 超级马里奥1超级版 | NES ROM prg=32 chr=8 mapper=0 | Read in trainer at $7000 | 恢复，可以正常游玩 | 正常游玩，未逐键单列反馈 | '+' / '.join(r['fps'] for r in rows[1:4])+' | 感觉帧率有点低，希望记录后优化 |',
    '| 超级马里奥1原版 | 未取得 | 未取得 | 待测 | 待测 | 未取得 | 未执行 |', '',
    '## 串口关键原文','', '```text',*[l for l in lines if l.startswith(('Load bytes:','Load result:','Run:','Head:','Read in trainer','ROM loaded:','NES powered','NES ROM'))],'```', '',
    '## 低帧率现象及最终统计','',
    '用户原话：“可以正常游玩了，但是你能否监控一下串口数据，记录一下帧率，我感觉帧率有点低，后续看有没有优化手段”。之后用户明确要求停止采集并整理上传。', '',
    f'最终完整采集共{len(rows)}个帧率窗口。以下聚合统计排除第1个启动窗口；最小/最大取已打印数值，均值为窗口算术平均，不冒充按实际时间加权的整体帧率。全部窗口原值见nes_smb_hack_fps.tsv。', '',
    '| 字段 | 最小 | 最大 | 窗口算术平均 | 中位数 |','|---|---|---|---|---|']
for k,s in stats.items():report.append('| '+' | '.join(map(str,[k,s['min'],s['max'],s['window_arithmetic_mean'],s['median']]))+' |')
report += ['',
    'fps是模拟核心推进的帧数；shown是观察到DISP SWITCH的实际显示新帧数，不是HDMI扫描刷新率。CPU/PPU百分比按NES内部模拟核心耗时统计，不是整颗RV32 CPU利用率；不包含全部帧复制、显示接收端、输入与串口统计开销，不能强行与100%做剩余时间分配。', '',
    '用户感到低帧率与shown偏低相符。后续建议分别测量：模拟6502/PPU热路径；RND忙导致的显示跳过；提交新FRAME及等待SWITCH/缓冲释放的耗时；帧复制和cache维护。当前数据不足以判定唯一瓶颈，本轮未擅自优化或改配置。', '',
    '旧灰屏版本曾打印约84 FPS，但程序没有正常运行游戏，不能将其作为此次正常游戏的有效性能基线。后续32KiB I-cache评估可使用本轮正常游戏数据作参考，但应保持ROM、软件和试玩场景一致。', '',
    '## 日志与边界','',
    'artifacts/uart/nes-smb-hack.log为后台工具逐字节写出的完整串口记录；nes_smb_hack_fps.tsv保留每个窗口；fps_summary.json为最终统计；checklist.md和user_feedback.json保存用户反馈及待测项。此前阶段快照已更新为停止后的最终统计，避免继续引用旧窗口数。', '',
    '只停止了本次PC串口捕获进程，释放COM7；没有向板端发送复位，游戏仍可运行。ROM从已有本地副本读取，本次不在任务18新增提交ROM。没有运行原版对照，不将缺失项补成通过。', '',
    '没有核验源码/报告时间，没有运行仿真、综合、PnR或STA。用户要求后续研究优化，本轮只负责留下可复核的数据。']
write(TASK/'result.md','\n'.join(report))
print(json.dumps(dict(windows=len(rows),stats=stats),ensure_ascii=False))
