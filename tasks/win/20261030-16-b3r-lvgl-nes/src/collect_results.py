"""Parse captured S3 and NES evidence; never opens serial or loads a ROM."""
from pathlib import Path
import csv,json,re,shlex,subprocess

TASK=Path(__file__).resolve().parents[1]
OUT=TASK/'artifacts'

def write(p,text):
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text('\n'.join(l.rstrip() for l in text.splitlines())+'\n',encoding='utf-8')
def table(name,keys,rows):
    with (OUT/name).open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=keys,delimiter='\t');w.writeheader();w.writerows(rows)

b=json.loads((OUT/'uart/s3_gui_buffer.json').read_bytes())
rx=[e for e in b['entries'] if e['dir']=='rx']
lines=[e['text'] for e in rx]
splits=[dict(token.split('=',1) for token in shlex.split(line[len('LVGL split '):])) for line in lines if line.startswith('LVGL split ')]
assert len(splits)==17 and len({r['scene'] for r in splits})==17 and splits[-1]['scene']=='ALL'
keys=list(dict.fromkeys(k for row in splits for k in row))
table('lvgl_split.tsv',keys,splits)
table('s3_rx_hex.tsv',['seq','timestamp_epoch_ms','hex'],[dict(seq=e['seq'],timestamp_epoch_ms=e['ts'],hex=e.get('hex','')) for e in rx])
summary=[]
for i,line in enumerate(lines):
    if line.startswith('Benchmark Summary'):
        end=next((j for j in range(i+1,len(lines)) if lines[j].startswith('All scenes avg.')),None)
        if end is not None:summary=lines[i:end+1]
assert summary,'Benchmark Summary missing'
write(OUT/'benchmark_summary.txt','\n'.join(summary))
write(OUT/'rnd_type_statistics.txt','\n'.join(line for line in lines if line.startswith(('RND type=','RND batch='))))
raw=(OUT/'uart/nes-template.log').read_bytes()
nes=raw.decode('utf-8',errors='replace').splitlines()
rom=next((line for line in nes if line.startswith('NES ROM ')),'未取得')
assert rom=='NES ROM prg=16 chr=8 mapper=0'
fps=[]
for line in nes:
    m=re.fullmatch(r'NES fps=([\d.]+) shown=([\d.]+) cpu=(\d+)% ppu=(\d+)%',line)
    if m:fps.append(dict(window=len(fps)+1,fps=m[1],shown=m[2],cpu_percent=m[3],ppu_percent=m[4]))
assert len(fps)>=3
table('nes_template_fps.tsv',['window','fps','shown','cpu_percent','ppu_percent'],fps)
check=['# 测试清单','',
    '| 项目 | 结果 | 证据 |','|---|---|---|',
    '| 复用卡14 B3R bitstream | 本轮不重新综合或布线 | 用户按任务继续测试 |',
    '| 新版S3 benchmark自然结束 | 已完成 | Benchmark Summary及ALL行 |',
    '| LVGL split 16场景+ALL | 17/17 | lvgl_split.tsv |',
    '| RND type统计 | 已保存 | rnd_type_statistics.txt |',
    '| 外部演示ROM加载 | PASS | 三段Load result: PASS，ROM mapper=0 |',
    '| 演示画面、人物移动、板上按键 | 用户确认正常 | 用户回复“正常的” |',
    f'| NES帧率 | 已取得{len(fps)}行 | nes_template_fps.tsv |',
    '| 用户自备SMB ROM | 未执行 | 用户暂无ROM，要求结束测试并上传 |',
    '| 结束采集 | 已停止本次UART辅助进程，释放COM7 | 板端程序未复位或停止 |']
write(OUT/'checklist.md','\n'.join(check))
commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
report=['# 20261030-16-b3r-lvgl-nes 结果','',
    'S3分场景性能和NES外部演示ROM测试已完成；用户确认演示画面、人物移动和板上按键正常。用户暂无SMB ROM，明确要求结束测试并上传，SMB项记为未执行。本卡不是全部三项验收完成。','',
    '| 项 | 内容 |','|---|---|',f'| 当前任务检出commit | {commit} |',
    '| bitstream | 复用卡14 B3R，G:/codex_project/EdRV32-FPGA/EdRV32-B3R；未重新实现 |',
    '| S3加载方式 | GUI，COM7，115200、8N1 |',
    '| NES加载方式 | 后台uart_tool.py，COM7，115200；--elf和--rom |',
    '| 完成情况 | 步骤2、3完成；步骤4因用户暂无SMB ROM未执行，按用户要求结束 |', '',
    '## LVGL benchmark','',
    '取得16个场景及ALL共17行LVGL split，字段共'+str(len(keys))+'列，数值均原样抄录到artifacts/lvgl_split.tsv；没有用计算值替换原文。原始GUI缓冲、全部串口导出及RX十六进制也已保留。','',
    'Benchmark Summary原文：','', '```text',*summary,'```','',
    '| 场景 | frames | render_ms | rnd_ms | sw_ms | other_ms | perf0_ms | perf4_rd_wait_cycles | perf5_wr_wait_cycles | copy_rnd_ms |',
    '|---|---|---|---|---|---|---|---|---|---|']
fields=['scene','frames','render_ms','rnd_ms','sw_ms','other_ms','perf0_ms','perf4_rd_wait_cycles','perf5_wr_wait_cycles','copy_rnd_ms']
for row in splits:report.append('| '+' | '.join(row.get(k,'未取得') for k in fields)+' |')
report += ['',
    'ALL的时间字段按程序统计口径记录，不能与Benchmark Summary里的平均fps直接互算替换。mem_xbar的RND/DISP端口统计、draw/copy拆分、PERF0–5完整字段见TSV。RND type=及batch/doorbell原文单独保存在rnd_type_statistics.txt。', '',
    '## NES外部演示ROM','',
    '执行顺序：用户断开GUI串口并按KEY1+复位；Codex在COM7以115200启动uart_tool.py，加载本卡nes.elf，随后把仓库自带nrom-template.nes装入ELF给出的ROM槽，再Run。未操作桌面、未切换高波特率、未重新下载bitstream。', '',
    '关键原文：','', '```text',*[line for line in nes if line.startswith(('Load bytes:','Load result:','Run:','Head:','NES powered','NES ROM'))],'```','',
    f'已取得{len(fps)}个fps统计窗口，全部原文在uart/nes-template.log，结构表在nes_template_fps.tsv。下表保留前4窗口；窗口1作为启动窗口，稳定性能比较可用后续窗口。', '',
    '| 窗口 | fps | shown | cpu% | ppu% |','|---|---|---|---|---|']
for row in fps[:4]:report.append('| '+' | '.join(str(row[k]) for k in ['window','fps','shown','cpu_percent','ppu_percent'])+' |')
report += ['',
    '用户试玩反馈：“正常的”（针对演示ROM画面、人物移动和板上按键）。已记录超过30秒，随后仅停止PC端日志采集并释放COM7；未向板端发送复位，板端NES继续运行。', '',
    '## 用户自备SMB ROM','',
    '未执行。用户回复“我现在没有，结束测试吧，整理报告上传”。没有查找、下载、复制或上传用户自备SMB ROM，也没有写入其文件路径。SMB的NES ROM行、帧率、画面/按键、主观速度均未取得。', '',
    '## 文件及范围','',
    '- uart/s3.log：GUI整个保留缓冲的原始导出，覆盖本次S3到benchmark结束；可能含同会话前后记录，不冒充逐字节串口抓包。',
    '- uart/s3_gui_buffer.json、uart/s3_gui_status.json、s3_rx_hex.tsv：原始条目、状态快照及RX字节证据。',
    '- lvgl_split.tsv：17行、全部字段；benchmark_summary.txt、rnd_type_statistics.txt：相应原文。',
    '- uart/nes-template.log：后台工具直接写出的原始串口字节；nes_template_fps.tsv：全部帧率窗口。',
    '- checklist.md：已完成项、用户观察及SMB未执行说明。', '',
    '没有提交ROM、bitstream或额外二进制。本卡只换软件，没有运行综合、布局布线或STA。未对源码版本或报告时间作额外核验。']
smb_path=OUT/'uart/nes-smb.log'
if smb_path.exists():
    smb_lines=smb_path.read_bytes().decode('utf-8',errors='replace').splitlines()
    marker=next((i for i,l in enumerate(smb_lines) if l=='NES ROM prg=32 chr=8 mapper=0'),None)
    assert marker is not None,'SMB ROM identification missing'
    windows=[]
    for line in smb_lines[marker+1:]:
        m=re.fullmatch(r'NES fps=([\d.]+) shown=([\d.]+) cpu=(\d+)% ppu=(\d+)%',line)
        if m:windows.append(dict(window=len(windows)+1,fps=m[1],shown=m[2],cpu_percent=m[3],ppu_percent=m[4]))
    table('nes_smb_fps.tsv',['window','fps','shown','cpu_percent','ppu_percent'],windows)
    text='\n'.join(report)
    text=text.replace('S3分场景性能和NES外部演示ROM测试已完成；用户确认演示画面、人物移动和板上按键正常。用户暂无SMB ROM，明确要求结束测试并上传，SMB项记为未执行。本卡不是全部三项验收完成。',
        'S3分场景性能及NES演示ROM测试已完成。之后用户提供自备SMB ROM，已加载并识别mapper 0，但用户观察HDMI“画面全是灰色”，显示测试失败，不能判本卡全部通过。演示ROM此前画面和按键正常。')
    text=text.replace('步骤2、3完成；步骤4因用户暂无SMB ROM未执行，按用户要求结束','步骤2、3完成；步骤4加载成功但HDMI全灰，记录失败后结束采集')
    start=text.index('## 用户自备SMB ROM')
    end=text.index('## 文件及范围',start)
    extra=['## 用户自备SMB ROM（补测）','',
        '用户此前暂无ROM而暂停该项，之后提供本地文件并指定了一个mapper 0版本重试。原文件已是iNES格式，仅在仓库外解压，未修改头或转换mapper。文档中按任务卡仅称“用户自备SMB ROM”，不记录文件路径，不提交ROM。', '',
        '串口加载及运行关键原文：','', '```text',*[l for l in smb_lines if l.startswith(('Load bytes:','Load result:','Run:','Head:','Read in trainer','ROM loaded:','NES ROM'))],'```','',
        '用户反馈：“画面全是灰色”。因此本项为加载成功、HDMI显示失败；左右移动、跳跃、Start和游戏速度未获得有效验证，不因串口有FPS/shown计数而判显示正常。', '',
        f'标识ROM之后取得{len(windows)}个帧率窗口，全部保留到nes_smb_fps.tsv；日志开头有旧演示程序残留FPS，分析本次游戏只使用NES ROM prg=32 chr=8 mapper=0之后的窗口。','',
        '| 窗口 | fps | shown | cpu% | ppu% |','|---|---|---|---|---|']
    for row in windows[:4]:extra.append('| '+' | '.join(str(row[k]) for k in ['window','fps','shown','cpu_percent','ppu_percent'])+' |')
    extra += ['',
        '可确认事实：ELF和ROM各段Load result均PASS，ROM识别为PRG32KiB、CHR8KiB、mapper0，日志包含Read in trainer at $7000，程序持续报告FPS。当前不能确定灰屏来自该改版ROM/Trainer兼容性、模拟核心还是图像输出链路；没有擅自改ROM、模拟器或RTL，不把猜测写成根因。', '',
        '测试后只停止本次PC串口辅助进程，释放COM7；板端未被复位。用户提供的ROM和扫描清单不入artifacts，原始串口日志uart/nes-smb.log已保留。','']
    text=text[:start]+'\n'.join(extra)+text[end:]
    report=text.splitlines()
    check=[l.replace('| 用户自备SMB ROM | 未执行 | 用户暂无ROM，要求结束测试并上传 |',
        '| 用户自备SMB ROM | 已加载，显示失败 | 用户反馈画面全灰；nes-smb.log |') for l in check]
    write(OUT/'checklist.md','\n'.join(check))
write(TASK/'result.md','\n'.join(report))
print('S3 split:',len(splits),'fields:',len(keys),'NES windows:',len(fps),'SMB: not run per user')
