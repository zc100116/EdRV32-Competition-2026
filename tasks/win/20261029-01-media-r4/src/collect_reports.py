"""Collect MEDIA r4 stage reports and all near-positive endpoint paths."""
from pathlib import Path
import csv
import importlib.util

REPO=Path(__file__).resolve().parents[4]
TASK=REPO/"tasks/win/20261029-01-media-r4"
BUILD=REPO/"build/win/20261029-01-media-r4"
ROOT=REPO.parent/"EdRV32-FPGA/EdRV32-MEDIA"
TOP="edrv32_fpga_media_top"


def main():
    path=REPO/"tasks/win/20261028-04-media-cpu-probes/src/collect_reports.py"
    spec=importlib.util.spec_from_file_location("previous_collector",path)
    c=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(c)
    c.TASK,c.BUILD=TASK,BUILD
    data=c.collect("media",ROOT,TOP)
    out=TASK/"artifacts"
    for path in sorted((out/"media").rglob('*')):
        if path.is_file():
            destination=out/path.relative_to(out/"media")
            destination.parent.mkdir(parents=True,exist_ok=True)
            path.replace(destination)
    for path in sorted((out/"media").rglob('*'),reverse=True):
        if path.is_dir():
            path.rmdir()
    (out/"media").rmdir()
    negative_file=c.export_report("media_violating",TOP)
    negative=c.setup(c.paths(c.read(negative_file),str(negative_file)),"clk_mem")
    unique={}
    for p in negative:
        unique.setdefault(p["end"],p)
    expected=data["timing"][("Setup","slow")]["clk_mem"][2]
    c.write(out/"endpoints_violating.tsv","endpoint\tstartpoint\tslack_ns\tlogic_levels\n"+
            ("\n".join(f'{p["end"]}\t{p["start"]}\t{p["slack"]:.3f}\t{p["levels"]}' for p in unique.values()) if unique else "无"))
    coverage=f"PDS violating endpoints={expected}; exported unique endpoints={len(unique)}; coverage={'complete' if expected==len(unique) else 'incomplete'}."
    c.write(out/"setup_near_groups.txt","All exported slow setup paths with 0 < slack < 1 ns, one worst path per endpoint.\n"
            "Command uses max_path=100000, nworst=1; filenames retain legacy top200 name but do not truncate at 200.\n"
            f"Actual records={len(data['near'])}; cap=100000; no cap truncation.\n"
            "start_register\tend_register\tendpoints\tworst_slack_ns\tworst_path_levels\n"+
            "\n".join(f'{a}\t{b}\t{len(ps)}\t{min(p["slack"] for p in ps):.3f}\t{min(ps,key=lambda p:p["slack"])["levels"]}'
                      for (a,b),ps in c.groups(data['near'])))
    replication=c.read(out/"replication_check.txt")
    table=list(csv.DictReader((out/"replication_registers.tsv").open(encoding='utf-8'),delimiter='\t'))
    fans=list(csv.DictReader((out/"replication_fanout.tsv").open(encoding='utf-8'),delimiter='\t'))
    lines=["# 20261029-01-media-r4 结果","","| 项 | 内容 |","|---|---|",
           "| 任务卡执行commit | 90cf049ec44e877bfe983597bcf0192d4ba1b82e |",
           "| PDS / 器件 | 2022.2-SP6.1 build138931；PG2L200H-6 FBB676；ADS |",
           "| 完成情况 | 综合、PnR和STA完成，报告及复制寄存器核对完成；时序通过，但clk_mem未达到+1.0 ns目标 |","",
           "## 时序","","| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |",
           "|---|---:|---:|---:|---:|---|---:|"]
    for corner in ("slow","fast"):
        for clock in ("clk_mem","clk_ext"):
            s,h=data["timing"][("Setup",corner)][clock],data["timing"][("Hold",corner)][clock]
            lines.append(f"| {clock}/{corner} | {s[0]:.3f} | {s[1]:.3f} | {h[0]:.3f} | {h[1]:.3f} | {s[2]}/{h[2]} | {1000/(8-s[0]):.4f} |")
    lines += ["","clk_mem slow由上一轮+0.388 ns提升至+0.592 ns，改善0.204 ns；无违例，距+1.0 ns目标仍差0.408 ns。",
              "clk_ext slow为+1.872 ns，上一轮+1.898 ns。原引脚K21/D18与异步组检查保留在clock_checks.txt，未放宽专用时钟布线。",
              coverage,
              f"危险正裕度导出采用0<slack<1 ns、max_path100000、nworst1，实际{len(data['near'])}条，未在200条截断。这里的全量是每个端点最差一条，不是枚举同一端点所有组合拓扑路径。",
              "setup_near_positive_top200.txt沿用任务卡文件名，包含全部导出记录；setup_near_groups.txt给出寄存器对分组。",
              "上一轮任务卡模板写146条，而上一轮提交的slow sequential筛选结果为144条；本轮按上述明示定义报告实测数量，不将模板参考数当本轮测量。","",
              "危险路径分组：","","| 起点寄存器 → 终点寄存器 | 端点数 | 最差裕量(ns) | 最差路径级数 |","|---|---:|---:|---:|"]
    for (a,b),ps in c.groups(data['near']):
        worst=min(ps,key=lambda p:p['slack'])
        lines.append(f"| {a} → {b} | {len(ps)} | {worst['slack']:.3f} | {worst['levels']} |")
    lines += ["","最差setup路径（每域前3条；完整每域200条及前20条逐级明细见产物）：",""]
    for clock in ("clk_mem","clk_ext"):
        for p in c.setup(data['setup'],clock)[:3]:
            lines.append(f'- {clock}: {p["start"]} → {p["end"]}；{p["slack"]:.3f} ns，{p["levels"]}级。')
    lines += ["","## 复制寄存器","",
              "综合VM中103/103位advance寄存器均有PAP_PRESERVE=TRUE；60/60位kernel操作码寄存器也保留。路后功能网表中163位均对应独立物理FF。",
              "逐位Q网络及驱动类型见replication_fanout.tsv。扇出按路后功能网表中连接到Q网络的原语输入引脚数统计，方向来自本机厂商VOP库；不是Device Map阶段的逻辑扇出。物理打包可能重命名网络，因此同时保留RTL名、物理FF名和Q网络名。","",
              "| 寄存器 | RTL位数 | 综合/路后保留位数 | 每位Q扇出（bit:输入引脚数） |","|---|---:|---|---|"]
    for row in table:
        base=row['register'];fs=[]
        for f in fans:
            bit=f['register_bit']
            if bit==base or bit.startswith(base+'['):
                suffix=bit[len(base):] or 'scalar'
                fs.append(suffix+':'+f['Q_fanout_input_pins'])
        lines.append(f"| {base} | {row['rtl_bits']} | {row['synthesis_bits']}/{row['routed_logical_bits']} | {', '.join(fs)} |")
    top=replication.split('net\tfanout_input_pins\tdriver_type\tlogical_driver\tphysical_driver\toutput_pin\n',1)[1].split('\n\nOriginal attribute messages:',1)[0]
    lines += ["","u_pix扇出最大的10个网络（路后物理输入引脚口径）：","",
              "| 网络 | 扇出 | 驱动类型 | 逻辑驱动单元 |","|---|---:|---|---|"]
    for row in top.splitlines():
        net,count,kind,logical,physical,pin=row.split('\t')
        lines.append(f"| {net} | {count} | {kind} | {logical} |")
    lines += ["","syn_preserve原文提示：compile日志有12条Convert attribute name from syn_preserve to PAP_PRESERVE；综合日志本身没有同名提示。具体源文件/行号摘录在replication_check.txt。没有把没有提示等同于属性无效，实际保留数量由网表核对。",
              "Device Map原生高扇出表也保留：例如advance_kernel11_r[0]、advance_kernel21_r[0]映射阶段均为243；PnR后分别220、231。不同阶段和打包口径不能混用。","",
              "## 资源","","| 模块（PnR逻辑口径） | LUT | FF | 分布式RAM | APM | DRM36K当量 |","|---|---:|---:|---:|---:|---:|"]
    for e in data['entries']:
        if e['depth']<=1:
            lines.append('| '+e['name']+' | '+' | '.join(map(str,e['values']))+' |')
    lines += ["","上一轮：VIN3562、PIX4943/132 APM、DISP1468、GEO3184/9 APM、ETH3858 LUT；总18416 LUT、23199 FF。完整下一级层次、综合前后资源、DRM18K/36K拆分、器件容量和占用率见resource_hier.txt及resource_summary.txt。","",
              "## 日志与复现","","flow_summary.txt保留Compile/综合/Map/PnR/STA各阶段warning分类、Real/CPU/Process CPU耗时、峰值内存，logs保存全部W/E行及阶段摘录。常量传播Loop本身不能证明RTL组合环。",
              "复制核对另外从已完成PNR数据库导出功能网表，没有重跑综合/Map/PnR或修改RTL/IP/约束。没有生成bitstream。功能网表和原始数据库只保留本地，不入库。",
              "功能网表导出命令（在独立build工作目录的PDS命令行工程中）：","","```tcl",
              "set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676",
              "gen_netlist -input_db_file {G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/place_route/edrv32_fpga_media_top_pnr.adf} -func_sim_only -force_to_run","```","",
              "Python复现顺序：src/export_timing.py，导出上述功能网表到build/win/20261029-01-media-r4/flat_netlist，再执行src/check_replication.py和src/collect_reports.py。","",
              "## 完整报告在Windows本地的路径","",
              f"- PDS工程完整报告/日志：{ROOT.as_posix()}/各阶段子目录。",
              f"- 补导时序：{BUILD.as_posix()}/exports/。",
              f"- 路后功能网表：{BUILD.as_posix()}/flat_netlist/generate_netlist/{TOP}_sim.v。"]
    c.write(TASK/'result.md','\n'.join(lines))
    print('Near paths',len(data['near']),'resources',data['entries'][0]['values'],coverage,flush=True)


if __name__=='__main__':
    main()
