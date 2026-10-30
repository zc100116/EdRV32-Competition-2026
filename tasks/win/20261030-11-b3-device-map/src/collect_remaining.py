"""Collect local manuals, clock-region sites and stopped route progress. No PDS execution."""
from pathlib import Path
from collections import Counter, defaultdict
import csv, re, shutil, fitz

TASK=Path(__file__).resolve().parents[1]
OUT=TASK/'artifacts'
INSTALL=Path('G:/Program/pango/PDS_2022.2-SP6.1')
ARCH=INSTALL/'arch/vendor/pango/logos2/pg2l200h'

def tsv(p,fields,rows):
    with p.open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,delimiter='\t');w.writeheader();w.writerows(rows)

rows=[]; filtered=['# Extracted verbatim region names and APM/DRM/IO/clock-related site lines.',
    '# Source: '+str(ARCH/'db/clk_region_info.txt'), '# No region-coordinate conversion inferred.']
counts=defaultdict(Counter); region=None
for line in (ARCH/'db/clk_region_info.txt').read_text().splitlines():
    m=re.fullmatch(r'Name: (CLOCK_REGION_\d+)',line)
    if m: region=m[1];filtered.extend(['',line]);continue
    m=re.fullmatch(r'\s+([A-Z][A-Z0-9_]*)_(\d+)_(\d+)\s*',line)
    if not m: continue
    typ,x,y=m.groups(); counts[region][typ]+=1
    if typ in ('APM','DRM','IOLHR','IOBD','IOBS','GPLL','PPLL','RCKB','IOCKB','HCKB','MRCKB','DDRPHY_CPD','TSERDES'):
        filtered.append(line)
        rows.append(dict(clock_region=region,resource_type=typ,site_name=line.strip(),encoded_name_x=x,encoded_name_y=y))
(OUT/'pg2l200h_sites_filtered.txt').write_text('\n'.join(filtered)+'\n',encoding='utf-8')
tsv(OUT/'pg2l200h_sites.tsv',list(rows[0]),rows)
hard=[r for r in rows if r['resource_type'] in ('APM','DRM')]
g=defaultdict(list)
for r in hard:g[(r['resource_type'],int(r['encoded_name_x']))].append(r)
cols=[]
for (typ,x),rs in sorted(g.items()):
    ys=sorted({int(r['encoded_name_y']) for r in rs})
    cols.append(dict(resource_type=typ,encoded_name_x=x,site_count=len(rs),encoded_name_y_min=min(ys),encoded_name_y_max=max(ys),encoded_name_y_values=','.join(map(str,ys))))
tsv(OUT/'pg2l200h_all_hardblock_columns.tsv',list(cols[0]),cols)
region_rows=[dict(clock_region=n,CLMA=c['CLMA'],CLMS=c['CLMS'],APM_sites=c['APM'],DRM_sites=c['DRM'],IOLHR_sites=c['IOLHR']) for n,c in counts.items()]
tsv(OUT/'pg2l200h_clock_regions.tsv',list(region_rows[0]),region_rows)
probes=[]; names={r['site_name'] for r in hard}
for typ in ('APM','DRM'):
    for x in (33,39,135,141,357,657):
        n=f'{typ}_{x}_582';probes.append(dict(site_name=n,present_in_install_clock_region_list=n in names))
tsv(OUT/'column_probes_from_install.tsv',list(probes[0]),probes)

manuals=OUT/'manuals';manuals.mkdir(exist_ok=True)
inventory=[]; errors=[]
for p in sorted(INSTALL.rglob('*')):
    if not p.is_file() or p.suffix.lower()!='.pdf':continue
    # Inventory filename and cover-title matches; do not dump unrelated manuals.
    try:
        with fitz.open(p) as d:
            cover=d[0].get_text(); title=d.metadata.get('title',''); pages=len(d)
        if not re.search(r'APM|DRM|Arithmetic|Memory|Multiply|Multiplier|乘法|存储|算术',p.name+' '+title+' '+cover,re.I):continue
        vers=re.search(r'V\d+\.\d+(?:_i\d+)?',cover)
        date=re.search(r'20\d\d[-/]\d\d[-/]\d\d',cover)
        inventory.append(dict(path=p.as_posix(),bytes=p.stat().st_size,pages=pages,title=(title+' | '+' '.join(cover.split()))[:700],
            version=vers[0] if vers else '未取得',date=date[0] if date else '未取得'))
    except Exception as e:errors.append(str(p)+': '+str(e))
tsv(OUT/'manual_inventory.tsv',list(inventory[0]),inventory)
selected=[INSTALL/'ip/module_ip/ipm2l_flex_apm/ipm2l_flex_apm_eval/ipm2l_mult/UG041003_APM_IP.pdf',
          INSTALL/'ip/module_ip/ipm2l_flex_ram/ipm2l_flex_ram_eval/ipm2l_sdpram/UG041002_DRM_Based_RAM_IP.pdf']
for p in selected:shutil.copyfile(p,manuals/p.name)
notes=['# 本机手册与器件数据查找','',f'递归查过：{INSTALL}。doc、help、ipcore、IP Compiler 文档所在子目录一并覆盖；不存在的目录没有假定存在。未从网络下载。',
    '',f'相关 PDF 共 {len(inventory)} 个路径（含同一手册的多份副本），完整路径、大小、封面标题、版本与日期见 manual_inventory.tsv。',
    '', '已复制 Logos2 APM IP 用户指南 UG041003 V1.5 (2023-08-21)，覆盖 Multiplier、Multiply-Adder、Multiply-Accumulator、Accumulator；DRM Based RAM/FIFO IP 用户指南 UG041002 V1.10 (2023-08-23)，覆盖 DPRAM、SDPRAM、SPRAM、ROM、FIFO。',
    '', '未找到独立于上述 IP 用户指南的 Logos2 APM/DRM 硬块架构专册；不把 IP 指南冒称为完整硬块架构手册。', '',
    'PG2L200H db/clk_region_info.txt 是明文，包含 10 个时钟区域的站点清单。已提取 APM/DRM、IO 和时钟相关内容，未提交其他 CLMA/CLMS 站点明细（仅保留计数）。该清单不含 region 的整数边界换算信息，也不把 IO 站点数当成当前封装引脚数。', '',
    'arch_lp.eadf、arch_nt.eadf、arch_schm.eadf、fp_arch_lp.eadf、fp_arch_schm.eadf 为带 PANG 头的二进制文件，本轮未解析。没有执行架构生成脚本或修改安装目录。', '',*errors]
(OUT/'local_search_notes.md').write_text('\n'.join(notes)+'\n',encoding='utf-8')

stopped=[];tails=[]
for n in ('B3VN','B3R','B3F'):
    p=Path('G:/codex_project/EdRV32-FPGA')/f'EdRV32-{n}'/'place_route/run.log'
    raw=p.read_text(encoding='utf-8',errors='replace')
    ms=list(re.finditer(r'Unrouted general nets at iteration (\d+) \(MT total route time: ([\d.]+) sec\): (\d+)\(overused: (\d+)\)',raw))
    m=ms[-1] if ms else None
    stopped.append(dict(project=n,iteration=m[1] if m else '未取得',MT_total_route_time_raw_sec=m[2] if m else '未取得',
        unrouted_general_nets=m[3] if m else '未取得',overused=m[4] if m else '未取得',stop_time='未取得（日志末尾无明确停止时间，不用文件修改时间代填）',source=p.as_posix()))
    tails.extend([str(p),*raw.splitlines()[-20:],''])
tsv(OUT/'stopped_route_progress.tsv',list(stopped[0]),stopped)
(OUT/'stopped_route_log_tails.txt').write_text('\n'.join(tails)+'\n',encoding='utf-8')
print('Hardblock sites:',dict(Counter(r['resource_type'] for r in hard)))
print('Hardblock encoded columns:',dict(Counter(c['resource_type'] for c in cols)))
print('Clock regions:',region_rows)
print('Manual inventory paths:',len(inventory))
print('Stopped route:',stopped)

with (OUT/'hardblock_instances.tsv').open(encoding='utf-8-sig') as f: occupied=list(csv.DictReader(f,delimiter='\t'))
assert {r['site_name'] for r in occupied} <= names, 'Occupied hardblock site missing from installation list'
with (OUT/'pce_devices.tsv').open(encoding='utf-8-sig') as f: samples=list(csv.DictReader(f,delimiter='\t'))
report=['# 20261030-11-b3-device-map 结果','',
    '已完成 Windows 侧布局解析、6 个坐标样点、区域统计、全器件 APM/DRM 站点清单提取、手册查找和停止进度整理。没有运行综合/PnR/bitstream，也没有修改 RTL 或保存 PCE 临时区域约束。', '',
    '| 项 | 内容 |','|---|---|',
    '| 任务卡来源 | origin/zc100116/b3，070cddd7（含第 9 节补充） |',
    '| 当前分支 | win/20261030-11-b3-device-map |',
    '| B3V 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3V，复用卡 10 布线结果 |',
    '| PDS | 2022.2-SP6.1；PG2L200H-6 FBB676 |',
    '| 三个工程停止时间 | 未取得；日志无明确停止时刻，不以文件时间推算 |', '',
    '## 布局导出与解析','', '| 文件 | 行数 | 字节数 | 说明 |','|---|---|---|---|']
for name in ('b3v-placement.pcf','b3v-apm.pcf','b3v-drm.pcf','b3v-placement.fdc'):
    p=OUT/name
    report.append(f'| {name} | {len(p.read_text().splitlines())} | {p.stat().st_size} | 原始导出，未修改 |')
report+=['',
    '完整 PCF：62,023 条 def_inst_site、137 条 def_port。APM 专用导出与完整导出相同，155 条约束，91 个独立站点；资源报告为 161，差 6，按补充任务卡保留“未查明”，不继续追查。DRM：115 条约束、109 个独立站点，其中 103 个 36K + 12 个 18K = 109 个 36K 等效，与资源报告一致。', '',
    '自动整理表：placement_instances.tsv、hardblock_instances.tsv、occupied_columns.tsv、module_resource_placement.tsv、io_ports.tsv。名称中的编码数字不等于 PCE siteX/siteY，也不直接当成区域约束坐标。', '',
    '## 坐标样点','', '| 类型 | 位置 | name | siteX/siteY | Properties x/y 原值 | 截图 |','|---|---|---|---|---|---|']
for s in samples:
    report.append('| '+' | '.join([s['类型'],s['位置(ll/ur)'],s['name'],s['site_x']+'/'+s['site_y'],s['fp_x']+'/'+s['fp_y'],s['截图文件']])+' |')
report += ['',
    '6 个样点均清晰可读。pce_devices.tsv 的 fp_x/fp_y 表头沿用任务卡，数值仅为 Properties x/y 原样抄录（手册称像素坐标），没有断言它们是区域约束坐标，也没有拟合未经验证的换算关系。原图位于 artifacts/pce/。', '',
    '## 区域 cr_x1y2','',
    '任务创建命令：region -create cr_x1y2 -value (124,238,100,149)。截图 pce/pce-region-cr_x1y2.png 已显示区域名称和 Statistics；创建坐标来自操作命令，截图未直接显示坐标。', '',
    '| 资源 | PCE 原值 | 指南 X1,Y2 | 比较 |','|---|---|---|---|',
    '| CLMA、CLMS | 合计 4600 | 3500 + 1100 = 4600 | 一致；PCE 未拆分 |',
    '| DRM | 50 | 50 | 一致 |',
    '| APM | 50 | 100 | 差 2 倍，统计口径不同 |', '',
    '其他原值：BKCL (1)、DDRPHY_IOCLK_DIV (1)、GCLK_INBUF_SYN (4)、GPLL (1)、IOCKB (4)、MRCKB (2)、PPLL (1)、RCKB (4)、TSERDES (8)。', '',
    '安装目录的 CLOCK_REGION_6 资源清单同样含 CLMA 3500、CLMS 1100、APM 50 个站点、DRM 50 个站点。全器件 APM 清单是 370 个站点，而资源报告容量 740；布局 PCF 同一 APM 站点又可出现 XAPM_CORE_U/D 两类子单元。这些证据支持“PCE/站点清单按整站点、资源报告按上下运算子单元计数”的解释，但未把名称编码据此换算成 region 坐标。', '',
    '## 全器件硬块与时钟区域清单','',
    '在安装目录 arch/vendor/pango/logos2/pg2l200h/db/clk_region_info.txt 找到明文站点列表，包含空闲与已用位置。提取后共 370 个 APM 站点（9 个名称编码 X 分组）、415 个 DRM 站点（10 个编码 X 分组）。已验证 B3V PCF 中所有 APM/DRM 站点均在安装清单中。', '',
    '**任务卡 B 的 12 条人工列探测不再需要执行。** 原始列表过滤版、完整站点 TSV、全部硬块列、区域统计和指定探测结果均已保存：pg2l200h_sites_filtered.txt、pg2l200h_sites.tsv、pg2l200h_all_hardblock_columns.tsv、pg2l200h_clock_regions.tsv、column_probes_from_install.tsv。', '',
    '清单附带 IOLHR 和时钟相关器件名称及所属区域，不提供 FBB676 全部 bank 坐标对应；IOLHR 500 是器件站点数，不是当前封装的 IO 可用量。未提交 CLMA/CLMS 站点全文，只保存每区计数。', '',
    '| 时钟区域原名 | CLMA | CLMS | APM 站点 | DRM 站点 |','|---|---|---|---|---|']
for r in region_rows:report.append('| '+' | '.join(str(r[k]) for k in ('clock_region','CLMA','CLMS','APM_sites','DRM_sites'))+' |')
report += ['', '## 三个停止工程最后路由进度','',
    '| 工程 | 最后迭代 | 未布通 general nets | overused | 停止时刻 |','|---|---|---|---|---|']
for r in stopped:report.append(f'| {r["project"]} | {r["iteration"]} | {r["unrouted_general_nets"]} | {r["overused"]} | 未取得 |')
report += ['',
    '原始末尾日志与原始 MT total route time 字段保存在 stopped_route_log_tails.txt / stopped_route_progress.tsv。进程检查未发现正在运行的 -action place_route pds_shell；不从此推算具体停止时刻。', '',
    '## APM/DRM 手册','',
    '| 文件 | 版本/日期 | 内容 |','|---|---|---|',
    '| manuals/UG041003_APM_IP.pdf | V1.5 / 2023-08-21 | Logos2 APM IP：乘法、乘加、乘累加、累加器 |',
    '| manuals/UG041002_DRM_Based_RAM_IP.pdf | V1.10 / 2023-08-23 | Logos2 DPRAM、SDPRAM、SPRAM、ROM、FIFO |','',
    f'本机 PDS 安装目录递归查找，得到 {len(inventory)} 个相关 PDF 路径（含重复副本）；全部文件的路径、大小、标题、版本、日期保存在 manual_inventory.tsv。只复制上述两份合并 IP 指南，覆盖任务卡要求的 APM 乘法/乘加和 DRM IP。未找到独立的 Logos2 APM/DRM 硬块架构专册，明确记录“未找到”，不以 IP 指南冒充。查找目录及二进制架构数据边界见 local_search_notes.md。没有从网络下载。', '',
    '## 限制与完成情况','',
    '已取得全部六个样点和区域 Statistics，完整安装站点清单替代手工列探测。Windows 侧可取得的任务产物均已整理；停止时间未取得、APM 155/161 未查明、独立硬块架构专册未找到，均按任务卡如实留缺。区域坐标换算与后续全局规划交给 Linux 端分析，不在本轮改 RTL 或加入区域约束。', '',
    '原始布局导出本地目录：G:/codex_project/EdRV32-FPGA/EdRV32-B3V。手册和架构数据原始路径见各自 TSV。PDS 工程/数据库、二进制架构数据库和 bitstream 未上传。完整 PCF 约 5.2 MiB，是任务卡要求的必要产物。']
(TASK/'result.md').write_text('\n'.join(report)+'\n',encoding='utf-8')
