"""Parse exported placement constraints without interpreting encoded site names as coordinates."""
from pathlib import Path
from collections import Counter, defaultdict
import csv, json, re, shutil

TASK = Path(__file__).resolve().parents[1]
OUT = TASK/'artifacts'
PROJECT = Path('G:/codex_project/EdRV32-FPGA/EdRV32-B3V')
OUT.mkdir(parents=True,exist_ok=True)

def tsv(name, fields, rows):
    with (OUT/name).open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,delimiter='\t'); w.writeheader(); w.writerows(rows)

def parse(name):
    text=(PROJECT/name).read_text(encoding='utf-8-sig')
    records=[]; ports=[]
    for n,l in enumerate(text.splitlines(),1):
        if l.startswith('def_inst_site '):
            m=re.fullmatch(r'def_inst_site\s+\{(.*)\}\s+(\S+)(?:\s+(\S+))?\s+-no_check\s*',l)
            if not m: raise ValueError(f'{name}:{n}: unsupported syntax: {l}')
            inst,site,prim=m.groups(); prim=prim or ''
            s=re.fullmatch(r'(.+)_(\d+)_(\d+)',site)
            records.append(dict(instance=inst,module=inst.split('/')[0],resource_type=s[1] if s else site,
                site_name=site,encoded_name_x=s[2] if s else '',encoded_name_y=s[3] if s else '',primitive=prim,source_line=n))
        elif l.startswith('def_port '):
            m=re.fullmatch(r'def_port\s+\{(.*)\}\s+(.*)',l)
            ports.append(dict(port=m[1],attributes=m[2],source_line=n))
        elif l.strip() and not l.startswith('#'): raise ValueError(f'{name}:{n}: unknown command')
    return records,ports

names=['b3v-placement.pcf','b3v-apm.pcf','b3v-drm.pcf','b3v-placement.fdc']
for n in names: shutil.copyfile(PROJECT/n,OUT/n)
all_rows,ports=parse(names[0])
fields=list(all_rows[0])
tsv('placement_instances.tsv',fields,all_rows)
tsv('io_ports.tsv',['port','attributes','source_line'],ports)
hard=[r for r in all_rows if r['resource_type'] in ('APM','DRM')]
tsv('hardblock_instances.tsv',fields,hard)
groups=defaultdict(list)
for r in hard: groups[(r['resource_type'],int(r['encoded_name_x']))].append(r)
columns=[]
for (typ,x),rs in sorted(groups.items()):
    ys=sorted({int(r['encoded_name_y']) for r in rs})
    columns.append(dict(resource_type=typ,encoded_name_x=x,placed_instances=len(rs),
        occupied_site_names=len({r['site_name'] for r in rs}),encoded_name_y_min=ys[0],encoded_name_y_max=ys[-1],
        encoded_name_y_values=','.join(map(str,ys))))
tsv('occupied_columns.tsv',list(columns[0]),columns)
module=[]
by_module=defaultdict(list)
for r in all_rows: by_module[r['module']].append(r)
for name,rs in sorted(by_module.items()):
    for typ in sorted({r['resource_type'] for r in rs}):
        subset=[r for r in rs if r['resource_type']==typ]
        module.append(dict(module=name,resource_type=typ,placed_instances=len(subset),occupied_site_names=len({r['site_name'] for r in subset})))
tsv('module_resource_placement.tsv',list(module[0]),module)
base={(r['instance'],r['site_name'],r['primitive']) for r in hard}
checks={}
for filename,typ in [('b3v-apm.pcf','APM'),('b3v-drm.pcf','DRM')]:
    rs,_=parse(filename)
    subset={(r['instance'],r['site_name'],r['primitive']) for r in rs}
    expected={v for v in base if v[1].startswith(typ+'_')}
    assert subset==expected, f'{filename}: mismatch with full placement'
    checks[filename]={'instances':len(rs),'distinct_sites':len({r['site_name'] for r in rs}),'matches_full_export':True}
drm36=[r for r in hard if r['resource_type']=='DRM' and '/gopdrm_36k' in r['instance']]
drm18=[r for r in hard if r['resource_type']=='DRM' and '/gopdrm_18k' in r['instance']]
checks['drm']={'36k_instances':len(drm36),'18k_instances':len(drm18),'36k_equivalent_from_instance_names':len(drm36)+len(drm18)/2,
    'unclassified_instances':sum(r['resource_type']=='DRM' for r in hard)-len(drm36)-len(drm18)}
checks['apm_resource_report_comparison']={'device_map_report_APM':161,'exported_APM_constraints':checks['b3v-apm.pcf']['instances'],
    'difference':161-checks['b3v-apm.pcf']['instances'],'explanation':'Unresolved. Placement constraints and device-map utilization differ; no missing constraints invented.'}
(OUT/'pcf_parse_summary.json').write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
lines=['# B3V 布局导出解析（任务 11 阶段产物）','',
    '已解析用户导出的四个文件并保留原文。未修改 FPGA 工程、RTL 或任何约束，未运行 PDS 流程。', '',
    f'完整 PCF 解析出 {len(all_rows)} 条实例位置约束、{len(ports)} 条端口约束。APM/DRM 专用导出与完整导出逐项一致。', '',
    '| 文件 | 实例约束数 | 不重复站点名数 |', '|---|---|---|']
for n,c in checks.items():
    if n.endswith('.pcf'): lines.append(f'| {n} | {c["instances"]} | {c["distinct_sites"]} |')
lines += ['',f'DRM 按实例名称分类：36K {len(drm36)} 个，18K {len(drm18)} 个，36K 等效量 {len(drm36)+len(drm18)/2:g}。这与独立站点数、实例数是不同口径，详见 JSON。', '',
    f'**APM 口径差异待核实：device_map 报告为 161，而专用 PCF 与完整 PCF 均只含 {checks["b3v-apm.pcf"]["instances"]} 条 APM 约束，差 {161-checks["b3v-apm.pcf"]["instances"]} 条。两份导出彼此一致，不能声称已满足任务卡的 161 实例判据；当前无法确定差异原因。**', '',
    '## 已占用位置的列分组', '',
    '**下表只按站点名称中的第一个数字分组。数字不是经验证的 PCE siteX/siteY，也不是区域约束坐标。仅列出已占用站点范围，不代表器件整列上下边界或全部可用资源。**', '',
    '| 类型 | 名称编码 X | 实例数 | 已占用站点数 | 名称编码 Y 最小–最大 |', '|---|---|---|---|---|']
for c in columns: lines.append(f'| {c["resource_type"]} | {c["encoded_name_x"]} | {c["placed_instances"]} | {c["occupied_site_names"]} | {c["encoded_name_y_min"]}–{c["encoded_name_y_max"]} |')
lines += ['', '## 坐标边界与下一步', '',
    '用户截图中的 APM_65_120 对应 siteX=18、siteY=22，界面像素 x=1968、y=8344。这直接说明名称编码 65/120 不能当成 site 坐标或区域坐标。当前解析不推导任何换算公式。', '',
    '已自动完成：全部实例到站点/primitive 的位置表、IO 端口属性、APM/DRM 专表、已占用列分组、顶层模块资源分布和导出一致性检查。', '',
    '仍未取得：全器件空闲站点、真实区域坐标对应、每条硬块列的完整上下边界、10 个区域资源统计、IO bank 到物理坐标对应。PCF 不包含这些信息，不能由当前表格代填。PCE 公开 help 没有坐标查询命令。', '',
    '下一步人工只需先提供一个临时 region 的 Statistics 截图确认统计方式；逐列截图暂缓。本机架构数据与手册查找尚未完成。停止进度与停止时间尚未采集，本卡不是最终完成报告。', '',
    '## 文件说明', '',
    '- placement_instances.tsv：全部实例约束，保留原文件行号。',
    '- hardblock_instances.tsv：APM/DRM 实例、站点和子单元。',
    '- occupied_columns.tsv：名称编码分组、已占用范围和全部出现的编码 Y。',
    '- module_resource_placement.tsv：顶层模块 × 器件类型的实例/站点计数，不等同 LUT/FF 利用率。',
    '- io_ports.tsv：端口和导出属性原文；未推断 bank。',
    '- pcf_parse_summary.json：完整/专用导出一致性及 DRM 口径。', '',
    '原始文件位置：G:/codex_project/EdRV32-FPGA/EdRV32-B3V。四个原文共约 10 MiB，是任务卡要求的必要布局证据。']
(TASK/'result.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(json.dumps({'placement_instances':len(all_rows),'ports':len(ports),'checks':checks,'column_groups':dict(Counter(c['resource_type'] for c in columns))},ensure_ascii=False,indent=2))
