"""Collect B1 implementation reports and the existing Serial Console session."""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import importlib.util
import re
import shutil
import urllib.request

REPO = Path(__file__).resolve().parents[4]
TASK = REPO / "tasks/win/20261028-06-board-b1"
BUILD = REPO / "build/win/20261028-06-board-b1"
ROOT = REPO.parent / "EdRV32-FPGA/EdRV32-B1"
OUT = TASK / "artifacts"
TOP = "edrv32_fpga_board_b1_top"
PREVIOUS = REPO / "tasks/win/20261028-04-media-cpu-probes/src"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.BUILD = BUILD
    return module


c = load("previous_collector", PREVIOUS / "collect_reports.py")


def collect_uart():
    out = OUT / "uart"
    out.mkdir(parents=True, exist_ok=True)
    api = "http://127.0.0.1:8765/api/"
    for endpoint, name in (("buffer/download", "serial_console_session.log"),
                           ("status", "serial_console_status.txt"),
                           ("buffer?since=0&limit=5000", "serial_console_buffer.txt")):
        (out / name).write_bytes(urllib.request.urlopen(api + endpoint).read())
    session = c.read(out / "serial_console_session.log")
    lines = session.splitlines()
    periph_start = next(i for i,l in enumerate(lines) if "[TX] 2<CR>" in l)
    c.write(out / "b1_o2.log", "\n".join(lines[:periph_start]))
    menus = [(i,re.search(r"\[TX\] ([123])<CR>",l)[1]) for i,l in enumerate(lines)
             if re.search(r"\[TX\] ([123])<CR>",l)]
    segments = [(menu,lines[start:menus[i+1][0] if i+1<len(menus) else len(lines)])
                for i,(start,menu) in enumerate(menus)]
    c.write(out / "b1_periph.log", "\n".join(l for menu,part in segments if menu=="2" for l in part))
    c.write(out / "b1_sysinfo.log", "\n".join(l for menu,part in segments if menu=="3" for l in part))
    c.write(out / "hpm_summary.txt", "\n".join(l for l in lines[:periph_start] if
            re.search(r"\[RX\] (HPM |Cycles:|Instructions:|Iterations|CoreMark|CRC |IPC:|.*ratio:|.*rate:|.*MPKI:|Compiler |ISA:|Score status:)",l)))
    c.write(out / "collection_notes.txt", "Source: running Serial Console 2.0 REST API; same GUI serial session.\n"
            "COM7, 115200, 8N1; RX/TX/SYS timestamps retained. No commands sent to the board during collection.\n"
            "b1_o2.log and b1_periph.log are session segments; the complete export is serial_console_session.log.\n"
            "O2: 10 iterations, short diagnostic run, CRC PASS; no 5000-iteration official score captured.\n"
            "b1_tuned.log: 未取得；当前会话没有tuned下载/运行记录。菜单3系统信息已取得且PASS。\n"
            "GUI parameter panel has no captured rule parameters; HPM values are present in the RX log.\n"
            "User observation: LED正常，但是按键测试策略问题，不太好测试。\n"
            "LED sequence confirmed by user; button function not confirmed.\n")
    return session


def collect_pds():
    exporter = load("previous_export", PREVIOUS / "export_timing.py")
    db = ROOT / "place_route" / (TOP + "_pnr.adf")
    jobs = [("b1_top200", db, "-max_path 200 -input_pins TRUE"),
            ("b1_near", db, "-delay_type max -max_path 200 -slack_greater_than 0 -slack_less_than 1 -input_pins TRUE")]
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(exporter.export, jobs))
    flow, warnings = [], []
    stages = ("compile", "synthesize", "device_map", "place_route", "report_timing", "generate_bitstream")
    for stage in stages:
        raw = c.read(ROOT / stage / "run.log")
        ws = [l for l in raw.splitlines() if l.startswith("W:")]
        es = [l for l in raw.splitlines() if l.startswith("E:")]
        counts = Counter(c.UTIL["warning_category"](l) for l in ws)
        flow += [f"STAGE {stage}: Errors={len(es)} Warnings={len(ws)}"]
        flow += [f"{k}\t{v}" for k,v in counts.most_common()]
        flow += [l for l in raw.splitlines() if l.startswith(("Action ","Current time:","C:"))] + [""]
        warnings += ["STAGE " + stage] + [l for l in raw.splitlines() if l.startswith(("E:","W:","C:"))] + [""]
        c.write(OUT / "logs" / (stage + "_excerpt.txt"), c.log_excerpt(raw) + "\n" +
                "\n".join(l for l in raw.splitlines() if l.startswith("C:")))
    c.write(OUT / "flow_summary.txt", "\n".join(flow))
    c.write(OUT / "logs/warnings_detail.txt", "\n".join(warnings))
    for stage, name in (("compile",TOP+".cmr"),("compile","include_relation.txt"),
                        ("synthesize",TOP+".snr"),("synthesize","apm_drm_lutram_utilization.log"),
                        ("synthesize","add_sub_carrychain.log"),("device_map",TOP+".dmr"),
                        ("place_route",TOP+".prr"),("place_route","clock_utilization.txt"),
                        ("constraint_check","constraint_check.ccr")):
        target = OUT / "native_reports" / stage / name
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT / stage / name, target)
    original = c.read(ROOT / "report_timing" / (TOP+".rtr"))
    head, timing = c.summaries(original)
    c.write(OUT / "timing_summary.txt", "Fmax from rounded WNS: 1000/(10.000-WNS) MHz.\n" +
            "\n".join(f'{corner}: {1000/(10-timing[("Setup",corner)]["clk_sys"][0]):.4f} MHz'
                      for corner in ("slow","fast")) + "\n\n" + head)
    full = BUILD / "exports/b1_top200/report_timing" / (TOP+".rtr")
    records = c.paths(c.read(full),str(full))
    setup = c.setup(records,"clk_sys")[:200]
    hold = sorted([p for p in records if p["corner"]=="fast" and p["type"].startswith("min")
                   and p["class"]=="sequential timing path"],key=lambda p:p["slack"])[:20]
    near_file = BUILD / "exports/b1_near/report_timing" / (TOP+".rtr")
    near = c.setup(c.paths(c.read(near_file),str(near_file)),"clk_sys")
    c.write(OUT / "setup_top200.txt",c.index_text(setup))
    c.write(OUT / "setup_top20_detail.txt","\n\n".join(p["block"] for p in setup[:20]))
    c.write(OUT / "hold_top20.txt","Fast corner\n\n"+"\n\n".join(p["block"] for p in hold))
    c.write(OUT / "setup_near_positive_top200.txt",c.index_text(near))
    c.write(OUT / "setup_near_positive_top20_detail.txt","\n\n".join(p["block"] for p in near[:20]))
    prr = c.read(ROOT / "place_route" / (TOP+".prr"))
    snr = c.read(ROOT / "synthesize" / (TOP+".snr"))
    dmr = c.read(ROOT / "device_map" / (TOP+".dmr"))
    table, entries = c.hierarchy(prr)
    c.write(OUT / "resource_hier.txt",table)
    c.write(OUT / "resource_summary.txt", "SYNTHESIS:\n"+
            snr[snr.index("Cell Usage:"):snr.index("Overview of Control Sets:")] +
            "\nPNR PHYSICAL:\n"+c.section(prr,"Device Utilization Summary :")+
            "\nPNR LOGICAL: [LUT,FF,distributed RAM,APM,DRM36K-equivalent]\n"+str(entries[0]["values"]))
    c.write(OUT / "high_fanout.txt","\n\n".join(c.section(dmr,title) for title in
            ("Other High Fanout Signal:","Clock Signal:","Reset Signal:","CE Signal:")))
    synth_log = c.read(ROOT / "synthesize/run.log")
    clock_lines = [l for l in synth_log.splitlines() if "get_pins u_pll_sys/clkout0" in l or "create_generated_clock" in l]
    c.write(OUT / "clock_checks.txt",c.section(prr,"IO Port Info:")+"\n\n"+
            c.section(prr,"Global Clock Info:")+"\n\n"+head+"\n\n"+"\n".join(clock_lines))
    c.write(OUT / "logs/timing_export_excerpt.txt","\n\n".join(
            c.read(BUILD/"exports"/name/"export.tcl")+c.log_excerpt(c.read(BUILD/"exports"/name/"console.log"))
            for name in ("b1_top200","b1_near")))
    return timing,entries,setup,near,flow


def main():
    session = collect_uart()
    data = collect_pds()
    write_result(session,*data)


def write_result(session,timing,entries,setup,near,flow):
    lines = ["# 20261028-06-board-b1 结果", "", "| 项 | 内容 |", "|---|---|",
             "| 任务卡执行commit | 346c171c4b003b53f4df2b241ea145cefe91c8c3；软件构建75dff18 |",
             "| PDS / 器件 | 2022.2-SP6.1 build138931；PG2L200H-6 FBB676；ADS |",
             f"| 工程 | {ROOT.as_posix()}/EdRV32-B1.pds |",
             "| 完成情况 | 综合/PnR/STA/bitstream完成并已有上板输出；O2短诊断、系统信息和外设日志已取得，5000次O2和tuned未取得，未满足完整B1验收 |", "",
             "用户选择新建B1工程，再用PDS Tcl复制和导入原7个IP，另生成PLL；原EdRV32工程未改。", "",
             "## IP", "", "| IP | 模块/端口 | 配置 |", "|---|---|---|",
             "| ip_pll_sys | clkin1、clkout0、lock，与顶层一致 | 输入27 MHz；I=1、M=2、F=18.75、O0=10.125，CLKOUTF反馈；推算VCO1012.5 MHz、输出100.000 MHz；无输出buffer，后端已插全局缓冲 |",
             "| ip_rom_boot | 与包装一致 | 2048×64，INIT_EN=true，HEX，本卡src/ip_rom_boot.dat |",
             "| ip_ram_sram | 与包装一致 | 单口8192×64，8字节写使能，INIT_EN=true，HEX，本卡src/ip_ram_sram.dat |", "",
             "实际IP端口和初始化配置见ip/ip_check.txt。初始化已展开为生成RTL的INIT向量，未修改生成文件。PLL选项截图未取得，频率来自生成参数及PDS时序，不是仪器实测。", "",
             "## 约束", "",
             "clk_board=37.037 ns，clk_sys=10.000 ns。原create_generated_clock命令正常执行，get_pins u_pll_sys/clkout0未报找不到对象，最终解析为u_pll_sys/u_gpll/gpll_inst/CLKOUT0。",
             "clk_sys报告6949个clock loads、303个non-clock loads；详细路径涵盖CPU及系统子系统。没有本地修改FDC，无需提交fdc_used.fdc。",
             "实际Compile已通过。首次GUI导入在include设置应用前启动层次解析，曾报缺头文件及Flow-0245；后续Compile正确读取两个include目录，无Error。历史错误摘录单独保留，未为此修改RTL或脚本。", "",
             "## 时序", "", "| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |", "|---|---:|---:|---:|---:|---|---:|"]
    for corner in ("slow","fast"):
        s,h=timing[("Setup",corner)]["clk_sys"],timing[("Hold",corner)]["clk_sys"]
        lines.append(f"| clk_sys/{corner} | {s[0]:.3f} | {s[1]:.3f} | {h[0]:.3f} | {h[1]:.3f} | {s[2]}/{h[2]} | {1000/(10-s[0]):.4f} |")
    lines += ["", "clk_board没有寄存器到寄存器的setup/hold汇总行，相关WNS/TNS/WHS/THS为未取得/不适用，不填0。",
              "PDS最终判定All Constraints Met；clk_sys setup最小裕量+0.674 ns，fast hold最小+0.101 ns。推算Fmax取舍入后的WNS，和原报告107.2280 MHz有微小舍入差。",
              f"另导出0<slack<1 ns的危险setup路径{len(near)}条，连同最差200条setup、20条setup逐级明细和fast hold最差20条保存。", "",
              "最差路径前10条：", "", "| 起点 → 终点 | 裕量(ns) | 级数 |", "|---|---:|---:|"]
    lines += [f'| {p["start"]} → {p["end"]} | {p["slack"]:.3f} | {p["levels"]} |' for p in setup[:10]]
    lines += ["", "## 资源", "", "| 阶段 | LUT | FF | DRM18K/36K | APM | 分布式RAM | IO | PLL |",
              "|---|---:|---:|---|---:|---:|---:|---:|",
              "| 综合 | 14737 | 8334 | 4 / 24 | 4 | 151 | 9 | 1 |",
              "| PnR逻辑层次 | 14648 | 8334 | 4 / 24（SNR拆分；PRR26当量） | 4 | 151 | 9 | 1 |", "",
              "PnR逻辑层次口径；DRM为36K当量，完整容量/占用率及综合口径见resource_summary.txt。", "",
              "| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |", "|---|---:|---:|---:|---:|---:|"]
    for e in entries:
        if e["depth"]<=2:
            lines.append("| "+e["path"]+" | "+" | ".join(map(str,e["values"]))+" |")
    lines += ["", "完整下级层次见resource_hier.txt。DRM18K/36K拆分、IO、PLL均保留SNR/PRR原文，不把不同阶段物理LUT相加当作逻辑LUT。", "",
              "## 上板与串口", "", "使用用户提供的EdRV32 Serial Console 2.0，COM7、115200、8N1、UTF-8，DTR/RTS关闭。通过工具REST API读取既有会话，没有另开串口或向板卡发送测试指令。",
              "完整原始RX/TX/SYS时间戳日志见uart/serial_console_session.log；O2及外设段分别保存b1_o2.log和b1_periph.log，原始会话条目含hex字段另存serial_console_buffer.txt。", "",
              "启动确认：logo、CHIP_ID 0xed320001、CLK_SYS_HZ 100000000、ROM16384/SRAM65536、I$/D$各8192、MEM_READY=1、SRAM app启动、Build commit 75dff18、GCC15.2.0。ISA打印rv32im_zicsr_zifencei，不含C扩展。", "",
              "### CoreMark", "", "| 编译选项 | 迭代 | 计时周期 | Iterations/Sec | CoreMark/MHz | CRC | IPC |", "|---|---:|---:|---:|---:|---|---:|",
              "| O2（短诊断） | 10 | 2777214 | 360.073 | 3.600 | seed/list/matrix/state及总结果PASS | 1.037 |",
              "| tuned | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |", "",
              "串口明确打印：Score status: short diagnostic run (<10 s); not a publishable CoreMark score。上表为诊断输出，不能当作正式CoreMark成绩。",
              "本次没有5000次O2计时，也没有tuned下载/运行记录；不将菜单1的一次短运行写成两种构建均已通过。",
              "仿真参考（任务卡）：O2 3.592456、tuned4.290770 CoreMark/MHz，仅供参考，不代替板测。", "",
              "HPM两轮：第一轮events1..8，2777214 cycles/2882008 instructions；第二轮events9..16，2776175 cycles/2882008 instructions。16项计数和比率原文见uart/hpm_summary.txt。GUI参数面板未捕获规则参数，但串口RX已包含HPM。", "",
              "### 系统信息和外设", "",
              "- 菜单3系统信息已取得，System info result: PASS；详见uart/b1_sysinfo.log。",
              "- 用户观察：LED正常；按键测试策略问题，不太好测试。LED顺序记录为通过观察，按键功能未确认。两次外设测试均显示GPIO button pressed: 0。",
              "- Timer两次：均请求4096周期，实际4168/4142，晚72/46周期；mcause=0x80000007，interrupts=1，均PASS。",
              "- I2C：100000 Hz、地址0x08..0x77，两端口均0设备；日志为SCAN COMPLETE，未把零设备写成探测成功。", "",
              "## 日志和bitstream", "", "```text", "\n".join(flow), "```", "",
              "bitstream已成功生成；Bitstream-2001提示SCBV未设置，原文保留在generate_bitstream摘录中。没有为此修改配置。",
              "各阶段warning、C级提示、耗时、峰值内存及高扇出表均已保存。常量传播Loop日志不能单凭该提示判定为RTL组合环。", "",
              "## 串口工具一并上传", "",
              "工具目录tools/serial-console-2：GUI入口main.py、同会话CLI、REST API、串口引擎、规则配置、说明、启动bat及已有截图一并提交。运行依赖PySide6和pyserial；本机PySide6 6.11.2、pyserial3.5。工具已实际启动并通过API读取本次会话，未运行压测或进行源码改造。",
              "工具的文件发送是原始字节发送；本次没有验证它是否适配B1 bootloader下载协议。tuned UART下载仍按任务卡tools/board/uart_tool.py执行。", "",
              "## 完整报告在Windows本地的路径", "",
              f"- PDS完整报告/原始日志：{ROOT.as_posix()}/各阶段子目录。",
              f"- 补导STA及命令：{BUILD.as_posix()}/exports/。",
              "- 工具：G:/codex_project/EdRV32-Competition-2026/tools/serial-console-2/。", "",
              "本次上传现有结果；采集期间用户又完成菜单3及第二次外设测试，已纳入。未补做5000次O2、tuned或按键测试，需要这些实测结果才能宣称任务卡全部通过。"]
    c.write(TASK/"result.md","\n".join(lines))


if __name__=="__main__":
    main()
