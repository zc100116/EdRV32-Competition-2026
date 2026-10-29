"""Collect existing B3V reports after Route-0038; does not run PDS."""
from pathlib import Path
from collections import Counter,defaultdict
import re,runpy,shutil,subprocess

REPO=Path(__file__).resolve().parents[4]
TASK=REPO/'tasks/win/20261029-05-b3-vision'
ROOT=REPO.parent/'EdRV32-FPGA/EdRV32-B3V'
OUT=TASK/'artifacts'
TOP='edrv32_fpga_board_vision_top'
C=runpy.run_path(str(REPO/'tasks/win/20261028-03-cpu-sys-synth-r4/src/collect_reports.py'))
read,write,section,hierarchy,paths,index_text=(C[k] for k in ['read','write','section','hierarchy','paths','index_text'])


def main():
    reports=[('compile',TOP+'.cmr'),('compile','include_relation.txt'),
             ('synthesize',TOP+'.snr'),('synthesize',TOP+'_controlsets.txt'),
             ('synthesize','apm_drm_lutram_utilization.log'),('synthesize','add_sub_carrychain.log'),
             ('device_map',TOP+'.dmr'),('device_map',TOP+'_dmr.prt'),('device_map',TOP+'.pcf'),
             ('constraint_check','constraint_check.ccr'),('place_route',TOP+'.prr'),
             ('place_route',TOP+'_prr.prt'),('place_route','clock_utilization.txt')]
    for stage,name in reports:
        dst=OUT/'native_reports'/stage/name;dst.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/stage/name,dst)
    for name in ['fail_route_nets.txt','mt_route_fail_net_loads.txt','mt_route_message.0.log']:
        dst=OUT/'route_failure'/name;dst.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/'place_route'/name,dst)
    flow=['Counts are W:/C:/E: log lines, not unique defects. Full raw logs stay in the FPGA project.','']
    warnings=[];stage_rows=[]
    for stage in ['compile','synthesize','device_map','place_route']:
        raw=read(ROOT/stage/'run.log');lines=raw.splitlines()
        alerts=[l for l in lines if l.startswith(('W:','C:','E:'))]
        count=Counter(l[:1] for l in alerts);categories=Counter((re.match(r'[WCE]:\s*([A-Za-z]+-\d+):',l)[1] if re.match(r'[WCE]:\s*([A-Za-z]+-\d+):',l) else C['warning_category'](l)) for l in alerts)
        actions=[l for l in lines if l.startswith('Action ')]
        flow += [f'STAGE {stage}: W={count["W"]}; C={count["C"]}; E={count["E"]}']+actions
        flow += [f'{k}\t{v}' for k,v in categories.most_common()]+['']
        warnings += [f'STAGE {stage}: {ROOT/stage/"run.log"}']+alerts+['']
        selected=[]
        for i,l in enumerate(lines,1):
            if l.startswith(('W:','C:','E:','Action ','Current time:','Process ','Phase ','Start ','Placement ','Routing ','Total ','Unrouted nets','Unrouted general nets','Worst slack','Saving design')) or 'Time elapsed:' in l or 'takes ' in l or 'slack' in l.lower():
                selected.append(f'{i}: {l}')
        write(OUT/'logs'/(stage+'_excerpt.txt'),'Source: '+str(ROOT/stage/'run.log')+'\n'+'\n'.join(selected))
        def metric(label):
            matches=[l.split(label,1)[1].strip() for l in actions if re.match(r'^Action \w+: '+re.escape(label),l)]
            return matches[-1] if matches else '未取得'
        stage_rows.append((stage,metric('Real time elapsed is'),metric('CPU time elapsed is'),metric('Process CPU time elapsed is'),metric('Peak memory pool usage is'),count))
    write(OUT/'flow_summary.txt','\n'.join(flow)+'\nreport_timing/gen_bit_stream: not run after routing failure.')
    write(OUT/'logs/warnings_detail.txt','\n'.join(warnings))
    project_lines=read(ROOT/'pds.log').splitlines()
    project_actions=[f'{i}: {l}' for i,l in enumerate(project_lines,1) if l.startswith(('W:','C:','E:','Action ','Current time:','Process ')) or re.match(r'Executing : (source |compile |synthesize |dev_map|pnr|report_timing|add_design .*\.idf)',l)]
    write(OUT/'logs/project_actions_excerpt.txt','Historical GUI actions; final stage status comes from stage run.log.\n'+'\n'.join(project_actions))
    pnr=read(ROOT/'place_route/run.log');pnrlines=pnr.splitlines()
    write(OUT/'route_failure/routing_progress.txt','\n'.join(f'{i}: {l}' for i,l in enumerate(pnrlines,1) if 'Unrouted' in l or 'Route-' in l or l.startswith(('Total net:','Total routing','Action pnr:'))))
    snr=read(ROOT/'synthesize'/(TOP+'.snr'));dmr=read(ROOT/'device_map'/(TOP+'.dmr'));prr=read(ROOT/'place_route'/(TOP+'.prr'))
    table,entries=hierarchy(snr)
    write(OUT/'resource_hier.txt','Source: SYNTHESIS SNR; failed PRR has no module hierarchy table.\nColumns: LUT, FF, distributed RAM, APM, DRM36K equivalent.\n'+table)
    write(OUT/'resource_summary.txt','SYNTHESIS PRIMITIVE COUNTS:\n'+snr[snr.index('Cell Usage:'):snr.index('Overview of Control Sets:')]+ '\nDEVICE MAP (successful mapping stage):\n'+section(dmr,'Device Utilization Summary:')+'\nFAILED PNR PHYSICAL UTILIZATION (not a successful routed result):\n'+section(prr,'Device Utilization Summary :')+'\nSynthesis logical hierarchy top [LUT,FF,distributed RAM,APM,DRM36K equivalent]:\n'+str(entries[0]['values'])+'\nPhysical CLMA/CLMS usage and logical SNR totals have different packing conventions.')
    write(OUT/'high_fanout.txt','DEVICE MAP, before PnR:\n'+'\n\n'.join(section(dmr,title) for title in ['Other High Fanout Signal:','Clock Signal:','Reset Signal:','CE Signal:']))
    a=snr.index('Timing analysis mode');b=snr.index('Startpoint',a)
    head=snr[a:b]
    write(OUT/'timing_synthesis_estimate.txt','SYNTHESIS ESTIMATE ONLY, single corner; not routed STA.\n'+head)
    records=paths(snr,'native_reports/synthesize/'+TOP+'.snr')
    sequential=[p for p in records if p['class']=='sequential timing path']
    write(OUT/'timing_synthesis_paths.tsv',index_text(records))
    write(OUT/'timing_synthesis_path_details.txt','SYNTHESIS ESTIMATE ONLY. All existing path blocks, including positive-margin paths.\n\n'+'\n\n'.join(p['block'] for p in records))
    groups=defaultdict(list)
    for p in sequential:groups[p['group']].append(p)
    synth_rows=[]
    for clock,ps in groups.items():
        setup=sorted([p for p in ps if p['type'].startswith('max')],key=lambda p:p['slack'])
        hold=sorted([p for p in ps if p['type'].startswith('min')],key=lambda p:p['slack'])
        synth_rows.append((clock,setup[0]['slack'] if setup else '未取得',hold[0]['slack'] if hold else '未取得',len(setup),len(hold)))
    missing='未取得：PnR因Route-0038/Route-0008失败，没有完成布线的pnr.adf和路后report_timing。已有综合单角预估和全部172条路径另存，不作为路后WNS/TNS/WHS/THS，也不宣称满足每时钟200条/逐级20条要求。\n'
    write(OUT/'timing_summary.txt',missing+'\nPlacement log raw diagnostics (units not stated on these lines; not per-clock STA):\n'+'\n'.join(l for l in pnrlines if 'slack' in l.lower()))
    for name in ['setup_top200.txt','setup_top20_detail.txt','hold_top20.txt']:
        write(OUT/name,missing)
    fdc=read(REPO/'fpga/constraints/edrv32_fpga_board_vision_top.fdc')
    clockrows=[l for l in fdc.splitlines() if l.startswith(('create_clock','create_generated_clock'))]
    ccr=read(ROOT/'constraint_check/constraint_check.ccr')
    write(OUT/'clock_checks.txt','Declared clocks from repository FDC (no local FDC edits):\n'+'\n'.join(clockrows)+'\n\nSNR Clock Summary and clock groups:\n'+head.split(' Performance Summary:',1)[0]+'\n\nPNR Global Clock Info:\n'+section(prr,'Global Clock Info:')+'\n\nConstraint checker:\n'+ccr)
    loads=read(ROOT/'place_route/mt_route_fail_net_loads.txt')
    source=read(REPO/'fpga/rtl/edrv32_fpga_tmds.v').splitlines()
    write(OUT/'route_failure/tmds_source_excerpt.txt','Source: fpga/rtl/edrv32_fpga_tmds.v (repository RTL, unchanged)\n'+'\n'.join(f'{i}: {l}' for i,l in enumerate(source,1) if 25<=i<=122))
    pinlines=read(ROOT/'place_route'/(TOP+'_prr.prt')).splitlines()
    write(OUT/'route_failure/tmds_pin_locations.txt','Source: PRR port placement table. This does not itself map every IOLHR to an RTL instance.\n'+'\n'.join(l for l in pinlines if 'tmds_' in l))
    write(OUT/'route_failure/README.md','''# B3V routing failure evidence

Confirmed: Route-2014 cannot route GND to OSHIFTIN0/1 of IOLHR_16_678/702/726/750 (8 loads). Total nets 80380, routed 80379. Route-0038 and Route-0008 terminate PnR.

fail_route_nets.txt is a 5.9 MB vendor diagnostic report, not a raw execution log. It retains all 18332 GND loads and the route tree so Claude can inspect local constant routing. The identically named companion diagnostic fail_st_const_route_nets.txt_all_nets.txt is not additionally copied. Database files remain local.

mt_route_fail_net_loads.txt gives the exact 8 failed loads. routing_progress.txt records convergence to 1 remaining net. Native PRR and port placement are under ../native_reports/place_route/.

Candidate source: 4 TMDS slave serializers each tie OSHIFTIN0/1 to 0, in DDR10TO1 mode with OCASCADE_EN=TRUE. Their relation to the failed physical cells remains a hypothesis until physical-to-logical mapping is established. DDR PHY also uses OSHIFTIN ports. No RTL/IP/constraint fix has been made or tested.
''')
    commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True,cwd=REPO).strip()
    result=['# 20261029-05-b3-vision 结果','','B3V已完成编译、综合、器件映射；布局布线在routing阶段失败，停止于任务步骤5。未生成bitstream，未上板。','',
            '| 项 | 内容 |','|---|---|',f'| 代码commit（zc100116/b3） | {commit} |','| PDS / 器件 | 2022.2-SP6.1 build138931；PG2L200H-6/FBB676 |',f'| 工程路径 | {ROOT.as_posix()} |','| 导入源文件数 | 112 |','| 运行方式 | 用户在GUI执行，与其他工程并行准备/运行；未另核对并发进程时间 |','',
            '## 布线失败','','- 总网络80380，布通80379；剩余1条GND常量网络。','- 失败负载：IOLHR_16_678、702、726、750的OSHIFTIN0和OSHIFTIN1，共8处。','- Route-2014列出不可达端点；Route-0038与Route-0008终止流程。','- PnR耗时23分7秒；其中routing为853.38秒，峰值内存6581 MB。','- 未见资源容量超限；物理资源APM 153/740、DRM 109/415、IO 137/400。','',
            '初步排查方向：TMDS四个从串化单元将级联输入接0，与8个失败端点的形态对应；物理位置与TMDS IO区域相近。但尚未建立物理单元到RTL实例的逐个映射，DDR PHY也使用这些端口，不能认定最终根因，更不能直接把接0判定为错误。请协调者检查级联原语配置、映射和常量布线。','',
            '证据：`artifacts/route_failure/`；完整失败网络报告5.9 MB，包含18332个负载和路由树，保留用于定位专用IO端口不可达原因。未提交DB/ADF。','',
            '## 各阶段耗时和日志','','| 阶段 | Real | CPU | Process CPU | 峰值内存 | W / C / E行数 |','|---|---|---|---|---|---|']
    for stage,real,cpu,pcpu,mem,counts in stage_rows:result.append(f'| {stage} | {real} | {cpu} | {pcpu} | {mem} | {counts["W"]} / {counts["C"]} / {counts["E"]} |')
    result += ['','完整warning/critical/error行、分类计数、阶段耗时见flow_summary.txt和logs/。保留常量传播Loop提示，但它本身不证明RTL组合环。GUI历史导入日志与最终阶段日志分开保存。','',
               '## 约束','','综合SNR列出16个时钟；clk_sys=10ns、clk_mem=8ns、clk_pix=13.468ns、clk_serial=2.6936ns、clk_cam0/1=10ns、clk_eth=8ns，以及DDR内部时钟。无clk_npu。详见clock_checks.txt和原生SNR。',
               '约束检查：857条约束，0 error、61 critical warning、0 warning；共享引脚和IO属性提示保留在原生CCR中。没有修改FDC。综合识别时钟不等于完成路后约束/时序验收。','',
               '## 时序','','路后slow/fast角WNS/TNS/WHS/THS、路后Fmax、每时钟setup最差200条和最差20条setup/hold：未取得，因为布线失败，未运行report_timing。','',
               '以下仅为综合单角预估。全部已报告172条路径（包括正裕量路径、跨组路径、无约束路径）的一行列表和逐级明细已保存，未只截取违例。不能作为路后签收。','',
               '| 时钟组 | 已报告setup最差裕量ns | 已报告hold最差裕量ns | setup / hold路径数 |','|---|---:|---:|---|']
    for clock,wns,whs,ns,nh in synth_rows:result.append(f'| {clock} | {wns} | {whs} | {ns} / {nh} |')
    result += ['','综合预估中特别需要审查：','', '| 时钟 | 起点 → 终点 | 裕量ns | 逻辑级数 |','|---|---|---:|---:|']
    for clock in ['clk_pix','clk_mem','clk_sys','clk_serial']:
        q=min([q for q in sequential if q['group']==clock and q['type'].startswith('max')],key=lambda q:q['slack'])
        result.append(f'| {clock} | {q["start"]} → {q["end"]} | {q["slack"]:.3f} | {q["levels"]} |')
    result += ['','综合中的clk_mem/PHY负hold估计也保留，需完成实现后的STA再判断。布局日志原始slack值-8253等未标单位，单独保留原文，不直接当作ns或每时钟WNS。','',
               '## 资源','','下表为综合SNR逻辑层次口径；失败PnR的物理CLMA/CLMS、APM、DRM、IO、GPLL/PPLL容量与用量另见resource_summary.txt。PRR无模块层次表，所以未把综合层次冒充路后层次。','',
               '| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |','|---|---:|---:|---:|---:|---:|']
    for e in entries:
        if e['depth']<=1:result.append('| '+e['name']+' | '+' | '.join(map(str,e['values']))+' |')
    result += ['','资源层次完整462行见resource_hier.txt。DRM18K/36K原语拆分、全工程原语计数在SNR Cell Usage，PLL物理用量包含DDR内部PLL，不能直接按外部PLL IP种类计数。','',
               '## IP与导入脚本','','19类IP实际模块、端口、位宽、配置与初始化检查保留在artifacts/B3V/ip/ip_check.md。ROM/SRAM使用B3R/F任务的G盘HEX初始化文件。',
               '本次提交包含此前用户授权的vision导入脚本路径修正：仓库由FPGA工程工作目录的../../EdRV32-Competition-2026计算，include_path传仓库rtl/include，定义FPGA_MODE。未修改RTL、IP或约束。','',
               '## 上板','','未执行：布局布线失败，没有bitstream；boot/sysinfo/BIOS/HDMI和2000000波特率测试未取得。','',
               '## 本地完整报告与复现','','- '+ROOT.as_posix()+'/{compile,synthesize,device_map,place_route}/run.log','- 各阶段CMR/SNR/DMR/PRR、constraint_check/constraint_check.ccr。','- place_route/fail_route_nets.txt、mt_route_fail_net_loads.txt；失败数据库留在本地。','',
               '整理命令：`C:/Python314/python.exe tasks/win/20261029-05-b3-vision/src/collect_reports.py`。只读取现有文件，没有核对时间戳、重跑实现、导出数据库、修改RTL/IP/约束，也没有操控桌面。']
    write(TASK/'result.md','\n'.join(result))
    print('Collected B3V:',entries[0]['values'],'timing paths',len(records),'hierarchy rows',len(entries))
    for row in stage_rows:print(row)


if __name__=='__main__':main()
