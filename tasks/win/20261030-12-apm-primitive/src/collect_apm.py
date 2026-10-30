"""Collect local GTP_APM_E2 evidence only; no PDS flow, no model modification."""
from pathlib import Path
import csv,re,shutil,subprocess,fitz

TASK=Path(__file__).resolve().parents[1]
OUT=TASK/'artifacts'
ROOT=Path('G:/Program/pango/PDS_2022.2-SP6.1')
OUT.mkdir(parents=True,exist_ok=True)

def table(name,fields,rows):
    with (OUT/name).open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,delimiter='\t');w.writeheader();w.writerows(rows)

# -a includes binary hits; --no-ignore/--hidden prevent silently skipping installed content.
proc=subprocess.run(['rg','-l','-a','--hidden','--no-ignore','GTP_APM_E2',str(ROOT)],capture_output=True)
if proc.returncode not in (0,1):raise RuntimeError(proc.stderr.decode(errors='replace'))
hit_paths={Path(l) for l in proc.stdout.decode('utf-8-sig').splitlines()}
for p in ROOT.rglob('*GTP_APM_E2*'):
    if p.is_file():hit_paths.add(p)
rows=[]; headers=[]; copied=[]
for p in sorted(hit_paths):
    b=p.read_bytes();text=b.decode('utf-8',errors='replace')
    encrypted=bool(re.search(r'pragma\s+protect\s+(?:begin|begin_protected|data_block)|protect\s+begin_protected|`protect',text,re.I))
    binary=b.startswith(b'MZ') or b'\0' in b[:8192]
    state='加密/保护内容' if encrypted else ('二进制' if binary else '明文')
    purpose='其他原语引用'
    if '/simulation/' in p.as_posix():purpose='仿真模型'
    elif p.name.endswith('.v.xml'):purpose='IP 生成器 RTL XML 模板'
    elif p.suffix.lower()=='.lib':purpose='时序/工艺库'
    elif p.suffix.lower()=='.gtp':purpose='原语注册/清单'
    elif binary:purpose='工具可执行文件的字符串命中'
    elif '/syn/' in p.as_posix():purpose='综合原语声明/库'
    rows.append(dict(path=p.as_posix(),bytes=len(b),readability=state,purpose=purpose))
    if encrypted:headers += [p.as_posix(),*text.splitlines()[:5],'']
    if state=='明文' and (purpose=='仿真模型' or (p.name.endswith('.v.xml') and 'ipm2l_flex_apm' in str(p))):
        sub='model' if purpose=='仿真模型' else 'ip_rtl'
        dst=OUT/sub/p.name;dst.parent.mkdir(exist_ok=True);shutil.copyfile(p,dst)
        copied.append(dict(file=dst.relative_to(OUT).as_posix(),source=p.as_posix(),description=purpose))
table('search.tsv',list(rows[0]),rows)
(OUT/'encrypted_headers.txt').write_text('\n'.join(headers) if headers else '本轮命中文件中未检测到明确的 protect 加密块标记。二进制不等同于加密。\n',encoding='utf-8')

docs=[];pdf_hits=[]
pat=re.compile(r'GTP|原语|Primitive|Library|UG0400|UG0410',re.I)
for p in sorted(ROOT.rglob('*')):
    if not p.is_file() or p.suffix.lower() not in ('.pdf','.html','.htm','.chm'):continue
    cover=''; title=''; apm_pages=[]
    if p.suffix.lower()=='.pdf':
        with fitz.open(p) as d:
            cover=d[0].get_text();title=d.metadata.get('title','')
            # Raw primitive-name mentions are inspected separately from IP guide names.
            for i,page in enumerate(d):
                if 'GTP_APM_E2' in page.get_text():apm_pages.append(i+1)
    elif p.suffix.lower() in ('.html','.htm'):
        text=p.read_text(encoding='utf-8',errors='replace');m=re.search(r'<title[^>]*>(.*?)</title>',text,re.I|re.S)
        title=m[1] if m else '';apm_pages=['HTML'] if 'GTP_APM_E2' in text else []
    if pat.search(p.name+' '+title+' '+cover) or apm_pages:
        docs.append(dict(path=p.as_posix(),bytes=p.stat().st_size,title=(' '.join((title+' '+cover).split()))[:700],
            GTP_APM_E2_pages=','.join(map(str,apm_pages)) or '未发现原语名',classification='原语名命中待分析' if apm_pages else '名称/封面候选（不代表原语说明）'))
        if apm_pages:
            dst=OUT/'manuals'/p.name;dst.parent.mkdir(exist_ok=True);shutil.copyfile(p,dst);pdf_hits.append(p)
            copied.append(dict(file=dst.relative_to(OUT).as_posix(),source=p.as_posix(),description='文档正文包含 GTP_APM_E2'))
table('document_search.tsv',['path','bytes','title','GTP_APM_E2_pages','classification'],docs)
table('copied_files.tsv',['file','source','description'],copied)
model=OUT/'model/GTP_APM_E2.v'
mt=model.read_text()
evidence=[]
for i,line in enumerate(mt.splitlines(),1):
    if any(s in line for s in ('USE_SIMD','USE_POSTADD','CPO','CPI','modezi','pzi','cin_inter')):
        evidence.append(f'{i}: {line}')
(OUT/'model_behavior_index.txt').write_text('Source: model/GTP_APM_E2.v; line-number index, not a hardware feasibility proof.\n'+'\n'.join(evidence)+'\n',encoding='utf-8')
commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
report=['# 20261030-12-apm-primitive 结果','',
    '| 项 | 内容 |','|---|---|',f'| 代码 commit | {commit} |',f'| PDS 安装目录 | {ROOT.as_posix()} |',
    '| 执行范围 | 本地只读查找、复制模型/模板、解析 PDF；未运行 PDS 或仿真、未改 RTL |','',
    '## 取得的模型和模板','',
    '已取得明文仿真模型 model/GTP_APM_E2.v，完整保留原文。另取得 Multiply-Adder、Multiply-Accumulator、Multiplier、Accumulator 的 4 个明文 .v.xml 模板，位于 ip_rtl/。这些是生成器输入，保留 XML 外壳及占位符，不冒充可直接编译的生成 RTL。','',
    '| 文件 | 来源 | 说明 |','|---|---|---|']
for c in copied:report.append(f'| {c["file"]} | {c["source"]} | {c["description"]} |')
report += ['', '## 搜索完整性与文件性质','',
    f'递归搜索整个安装目录，使用 rg -l -a --hidden --no-ignore 匹配 GTP_APM_E2，并补查同名文件。共 {len(rows)} 个文件命中，完整路径、字节大小、明文/保护/二进制及用途见 artifacts/search.tsv。二进制工具、Liberty 时序库、其他系列原语引用均列入，但没有复制无关的大文件。', '',
    '检测明文 protect 标记并单独记录到 encrypted_headers.txt；二进制不会被擅自判断为加密。本机目标仿真模型及 4 份模板可读，无需解密。原始版权头保留，不修改模型。','',
    '## 原语说明文档','',
    f'递归查过 {ROOT.as_posix()} 的全部 PDF/HTML/HTM/CHM 文件名，并扫描 PDF 封面/元数据标题及正文中的 GTP_APM_E2，HTML 标题/正文。名称/标题候选列表见 document_search.tsv；CHM 只检查文件名，未解包内部正文。','',
    ('正文包含原语名的文档已复制，具体页码见 document_search.tsv；文档是否完整说明 SIMD 行为仍需逐页判断。' if pdf_hits else
     '未找到专门的 Logos2 GTP 原语说明文档，PDF/HTML 正文也未找到 GTP_APM_E2。UG041003 是上轮已取得的 IP 指南，不冒称为原语说明，本轮没有重复复制。manuals/ 无文件即表示未找到。'),'',
    '## 模型中与本任务直接相关的线索','',
    '明文模型包含 USE_SIMD、USE_POSTADD、MODEZ、CPI/CPO 的完整组合逻辑及寄存器行为。model_behavior_index.txt 提供原始行号索引，Linux 可直接以完整模型分析并构造定向测试。', '',
    '- 模型第 364 行：USE_SIMD 时乘法结果打包为 {mult_out_h,mult_out_l}。',
    '- 第 404–408 行：MODEZ 对应的选择分支可从 CPI 及其移位形式取后加器输入。',
    '- 第 425 行：USE_SIMD 会改变高半部进位来源 cin_inter（需连同周边加法逻辑分析）。',
    '- 第 446–447 行：P/CPO 的结果选择受 USE_POSTADD 控制，CPO 还受 CPO_REG 控制。', '',
    '这些是仿真源码线索，不等于已验证 SIMD 双乘可跨 lane 求和，也不能单凭模型证明硬件级联的合法放置与时序。SIMD 双路加法的 lane 语义、溢出/符号与流水对齐仍需 Linux 端结合模板及定向仿真判断。', '',
    '## 完成情况','',
    '已满足“至少取得明文模型或模板”的判据；模型和模板均已取得。专门原语手册的查找结果如实记录。用户无需操作，不生成 IP、不运行 PDS 流程。']
report += ['', '## 文档命中核对', '',
    'fpga_reference.pdf 是 Synplify Pro for Pango Reference Manual（August 2022）。PDF 第 318 页仅列出 GTP_APM_E2 支持的综合映射功能，包括乘法、乘加减、累加以及级联推断；没有说明 USE_SIMD=1 下的 MODEZ/USE_POSTADD/CPI/CPO 行为。因此专门原语说明仍记为“未找到”，这份手册仅作为综合能力的补充证据，不能替代仿真模型分析。']
(TASK/'result.md').write_text('\n'.join(report)+'\n',encoding='utf-8')
print(f'hits={len(rows)}, copied={len(copied)}, doc_candidates={len(docs)}, primitive_body_docs={len(pdf_hits)}')
