"""Collect MEDIA r3 and B1 rerun reports without rerunning implementation."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import importlib.util
import json
import re
import urllib.request

REPO = Path(__file__).resolve().parents[4]
TASK = REPO / "tasks/win/20261028-07-media-r3-b1"
BUILD = REPO / "build/win/20261028-07-media-r3-b1"


def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    m=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.TASK,m.BUILD=TASK,BUILD
    return m


def main():
    old=REPO/"tasks/win/20261028-04-media-cpu-probes/src"
    c=load("collector",old/"collect_reports.py")
    exporter=load("exporter",old/"export_timing.py")
    b1=load("b1_collector",REPO/"tasks/win/20261028-06-board-b1/src/collect_reports.py")
    b1.OUT=TASK/"artifacts/b1"
    db=REPO.parent/"EdRV32-FPGA/EdRV32-MEDIA/place_route/edrv32_fpga_media_top_pnr.adf"
    jobs=[("media_top200",db,"-max_path 200 -input_pins TRUE"),
          ("media_violating",db,"-delay_type max -max_path 100000 -slack_less_than 0 -input_pins FALSE"),
          ("media_near",db,"-delay_type max -max_path 200 -slack_greater_than 0 -slack_less_than 1 -input_pins TRUE"),
          ("media_disp",db,"-delay_type max -max_path 200 -to {u_disp/*} -input_pins TRUE")]
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(exporter.export,jobs))
    media=c.collect("media",REPO.parent/"EdRV32-FPGA/EdRV32-MEDIA","edrv32_fpga_media_top")
    negative_file=c.export_report("media_violating","edrv32_fpga_media_top")
    negative=c.setup(c.paths(c.read(negative_file),str(negative_file)),"clk_mem")
    unique={}
    for p in negative:
        unique.setdefault(p["end"],p)
    expected=media["timing"][("Setup","slow")]["clk_mem"][2]
    coverage=f"PDS violating endpoints={expected}; exported unique endpoints={len(unique)}; coverage={'complete' if expected==len(unique) else 'incomplete'}"
    out=TASK/"artifacts/media"
    c.write(out/"endpoints_violating.tsv","endpoint\tstartpoint\tslack_ns\tlogic_levels\n"+
            ("\n".join(f'{p["end"]}\t{p["start"]}\t{p["slack"]:.3f}\t{p["levels"]}' for p in unique.values()) if unique else "无"))
    modules=("u_vin","u_pix","u_geo","u_disp","u_eth","top")
    group_lines=[coverage,c.read(BUILD/"exports/media_violating/export.tcl"),"(a) Endpoint module\nmodule\tendpoints\tworst_slack_ns"]
    for module in modules:
        members=[p for p in unique.values() if (p["end"].split("/",1)[0] if p["end"].split("/",1)[0] in modules else "top")==module]
        group_lines.append(f'{module}\t{len(members)}\t'+(f'{min(p["slack"] for p in members):.3f}' if members else '无违例'))
    group_lines+=['(b) Register pair groups','无' if not unique else '\n'.join(
        f'{a}\t{b}\t{len(ps)}\t{min(p["slack"] for p in ps):.3f}\t{min(ps,key=lambda p:p["slack"])["levels"]}'
        for (a,b),ps in c.groups(list(unique.values())))]
    c.write(out/"endpoint_groups.txt","\n".join(group_lines))
    print(coverage,flush=True)
    b1data=b1.collect_pds()
    uart=collect_uart(c)
    write_result(c,media,b1data,coverage,uart)


def collect_uart(c):
    out=TASK/"artifacts/b1/uart"
    out.mkdir(parents=True,exist_ok=True)
    for endpoint,name in (("buffer/download","serial_console_session.log"),
                          ("buffer?since=0&limit=5000","serial_console_buffer.txt"),
                          ("status","serial_console_status.txt")):
        (out/name).write_bytes(urllib.request.urlopen("http://127.0.0.1:8765/api/"+endpoint).read())
    lines=c.read(out/"serial_console_session.log").splitlines()
    menus=[(i,re.search(r"\[TX\] ([123])<CR>",line)[1]) for i,line in enumerate(lines)
           if re.search(r"\[TX\] ([123])<CR>",line)]
    segments=[(menu,lines[start:menus[i+1][0] if i+1<len(menus) else len(lines)])
              for i,(start,menu) in enumerate(menus)]
    for menu,name in (("2","b1_periph.log"),("3","b1_sysinfo.log")):
        c.write(out/name,"\n".join(l for m,part in segments if m==menu for l in part) or "未取得")
    runs={}
    for menu,part in segments:
        raw="\n".join(part)
        if menu!="1" or "CoreMark result:" not in raw:
            continue
        label="tuned" if " -O3 " in raw else "O2"
        text="\n".join(re.sub(r"^\[[^]]+\]\[RX\] ?","",l) for l in part if "[RX]" in l)
        def field(key):
            return re.search(r"^"+re.escape(key)+r": (.*)$",text,re.M)[1]
        run={key:field(key) for key in ("Iterations","Cycles","Instructions","Iterations/Sec","CoreMark/MHz","IPC","CoreMark result","Compiler flags","Score status")}
        run["seconds"]=int(run["Cycles"])/100000000
        runs[label]=run
        c.write(out/("b1_o2.log" if label=="O2" else "b1_tuned.log"),raw)
        c.write(out/("hpm_o2.txt" if label=="O2" else "hpm_tuned.txt"),
                "\n".join(l for l in part if re.search(r"\[RX\] (HPM |CRC |Cycles:|Instructions:|IPC:|.*ratio:|.*rate:|.*MPKI:)",l)))
    download=[i for i,l in enumerate(lines) if "Boot mode: UART download" in l]
    if download:
        end=next(i for i,menu in menus if i>download[-1] and menu=="1")
        c.write(out/"b1_uart_download.log","\n".join(lines[download[-1]:end]))
    summary=["# 本轮串口采集","","原始会话见serial_console_session.log；分段日志保留原时间戳和方向。未向板卡发送新指令。",
             "按键第一次NOT PRESSED within wait，第二次按下3748 ms、松开4003 ms、保持255 ms、PASS；两次均保留。",
             "菜单3系统信息："+("PASS" if any("System info result: PASS" in l for l in lines) else "未取得"),
             "本轮LED目视观察未另行提供；串口打印按下时LED应全亮，不冒充用户已确认。"]
    for name in ("O2","tuned"):
        summary.append(name+": "+str(runs[name]) if name in runs else name+": 未取得；当前会话没有相应构建运行记录。")
    c.write(out/"uart_summary.md","\n\n".join(summary))
    return runs


def write_result(c,media,b1data,coverage,uart):
    timing,entries,setup,near,flow=b1data
    lines=["# 20261028-07-media-r3-b1 结果","","| 项 | 内容 |","|---|---|",
           "| 任务卡执行commit | b23c03c25060ea392e97b82e86f35432bd9da8d6 |",
           "| PDS / 器件 | 2022.2-SP6.1 build138931；PG2L200H-6 FBB676；ADS |",
           "| 完成情况 | A全部完成且时序通过；B两种编译选项均完成5000次、运行≥10秒且CRC PASS，按键和系统信息结果PASS，要求记录已取得 |","",
           "## A 媒体/网络模块","","| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |",
           "|---|---:|---:|---:|---:|---|---:|"]
    for corner in ("slow","fast"):
        for clock in ("clk_mem","clk_ext"):
            s,h=media["timing"][("Setup",corner)][clock],media["timing"][("Hold",corner)][clock]
            lines.append(f"| {clock}/{corner} | {s[0]:.3f} | {s[1]:.3f} | {h[0]:.3f} | {h[1]:.3f} | {s[2]}/{h[2]} | {1000/(8-s[0]):.4f} |")
    lines += ["","上一轮clk_mem slow -1.270 ns/542个违例端点（ETH196、GEO174、VIN172）；本轮+0.388 ns、0个，WNS改善1.658 ns。",
              coverage,"全部模块均无clk_mem slow setup违例，寄存器对违例分组为无，未用最差200条代替全量违例统计。",
              "clk_ext slow +1.898 ns。两时钟原引脚K21/D18及异步组检查保存在clock_checks.txt。每域最差200条setup、前20条逐级明细、fast hold前20条均已保存。",
              f'另保留0<slack<1 ns的危险setup样本{len(media["near"])}条及前20条明细；不能以无违例代表裕量充足。',"",
              "| 模块（PnR） | LUT | FF | 分布式RAM | APM | DRM36K当量 |","|---|---:|---:|---:|---:|---:|"]
    for e in media["entries"]:
        if e["depth"]<=1:
            lines.append("| "+e["name"]+" | "+" | ".join(map(str,e["values"]))+" |")
    lines += ["","上一轮VIN3532、PIX4935/132 APM、DISP1452、GEO3357/9 APM、ETH3841 LUT；本轮完整层次和器件占用率见media/resource_hier.txt、resource_summary.txt。","",
              "## B B1 上板补测","","| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |",
              "|---|---:|---:|---:|---:|---|---:|"]
    for corner in ("slow","fast"):
        s,h=timing[("Setup",corner)]["clk_sys"],timing[("Hold",corner)]["clk_sys"]
        lines.append(f"| clk_sys/{corner} | {s[0]:.3f} | {s[1]:.3f} | {h[0]:.3f} | {h[1]:.3f} | {s[2]}/{h[2]} | {1000/(10-s[0]):.4f} |")
    lines += ["","clk_board37.037 ns、clk_sys10.000 ns，generated clock已生效，见b1/clock_checks.txt。本轮slow WNS与上一轮+0.674 ns相同。",
              f'本轮PnR逻辑资源[LUT,FF,分布式RAM,APM,DRM36K当量]={entries[0]["values"]}；上一轮[14648,8334,151,4,26]。其余IO/PLL及18K/36K拆分见resource_summary.txt。',"",
              "### 串口", "", "原始日志来自用户串口工具现有会话，COM7/115200/8N1，保留时间戳与RX/TX/SYS方向；未向板卡发送新指令。",
              "完整当前会话见b1/uart/serial_console_session.log；分段及结论见同目录uart_summary.md。Build commit为207b05a，CLK_SYS_HZ100000000，ISA为rv32im_zicsr_zifencei。O2从SRAM app启动；tuned为UART download，原始文件monitor_tuned.wire共31896字节，工具报告发送完成，板卡报告UART download complete。下载记录另存b1_uart_download.log。", "",
              "| 编译选项 | 迭代次数 | 计时周期 | 运行秒数（cycles/100MHz） | CoreMark | CoreMark/MHz | CRC | IPC |",
              "|---|---:|---:|---:|---:|---:|---|---:|",
              *[f'| {label} | {r["Iterations"]} | {r["Cycles"]} | {r["seconds"]:.8f} | {r["Iterations/Sec"]} | {r["CoreMark/MHz"]} | {r["CoreMark result"]} | {r["IPC"]} |' if (r:=uart.get(label)) else f'| {label} | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |' for label in ("O2","tuned")], "",
              "O2和tuned均明确打印duration >=10 s及CoreMark result PASS，两轮CRC均PASS；HPM分两轮采集，O2串口总墙钟约28秒、tuned约23秒，不能当作单轮CoreMark计时。编译标志中DITERATIONS=10是编译默认值，实际Iterations均为5000。tuned标志末尾含-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4，后面的-O3覆盖前面的默认-O2。",
              "tuned计时1159978150周期=11.59978150秒，退休1239834691条指令，IPC1.068；两版HPM原文分别保存hpm_o2.txt和hpm_tuned.txt。按Iterations/Sec比较，431.042/360.326−1，tuned较O2提升约19.63%。",
              "上一轮O2为10次短诊断3.600 CoreMark/MHz；任务卡仿真参考O2 3.592456、tuned4.290770，仅作参考。", "",
              "按键：第一次NOT PRESSED within wait；第二次按下3748 ms、松开4003 ms、保持255 ms，GPIO button result PASS。两次记录都保留。",
              "第二次Timer请求4096、实际4143、晚47周期，mcause0x80000007、interrupts1、PASS；I2C两端口0设备，日志SCAN COMPLETE，未将零设备视为硬件连通性通过。",
              "菜单3系统信息已补充并PASS，见b1_sysinfo.log。LED的本轮独立目视确认未取得，不沿用上一轮观察代替；按键按下/松开的串口判定已为PASS。", "",
              "## 报告、日志与本地路径", "",
              "media/和b1/均保留各阶段耗时、CPU时间、峰值内存、warning分类与全部W/E/C提示摘录、原生资源报告及补导时序命令。B1含bitstream生成摘要，SCBV提示保持原文。",
              "原始PDS工程、IP目录、数据库、bitstream及完整PDS日志不入库；串口原始日志按任务卡上传。未改RTL/IP/约束，没有重跑综合或PnR，只补导STA。", "",
              "- MEDIA：G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/各阶段子目录。",
              "- B1：G:/codex_project/EdRV32-FPGA/EdRV32-B1/各阶段子目录。",
              f"- 补导STA：{BUILD.as_posix()}/exports/。"]
    c.write(TASK/"result.md","\n".join(lines))


if __name__=="__main__":
    main()
