"""Write the task result from the collected PDS numbers."""
import csv
import re
import collect_reports as c


def rows(path):
    with path.open(encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def metric(text, pattern):
    return re.search(pattern, text)[1]


def main():
    result = ["# 20261028-04-media-cpu-probes 结果", "",
              "| 项 | 内容 |", "|---|---|",
              "| 任务卡 commit | f757c4f3b3b303811d2c69ccc8b855f3e6eb599b |",
              "| 结果分支 | win/20261028-04-media-cpu-probes |",
              "| 探针版本 | src/p1、src/p2、src/p3；源自15d21f8 / 2ec4170 / 3615a7e |",
              "| PDS / 器件 | 2022.2-SP6.1 build 138931；PG2L200H-6 FBB676；ADS综合 |",
              "| A工程 | G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/EdRV32-MEDIA.pds |",
              "| B工程 | build/win/20261028-04-media-cpu-probes/cpu/p1、p2、p3、p3_noregion |",
              "| 完成情况 | A布局布线完成；B的P1/P2完成，P3区域检查失败，去区域约束的P3_noregion完成。IP选项PNG未取得，其余提取结果见artifacts |",
              "", "按用户要求用三个独立后台工程并行运行CPU，复用原EdRV32工程的7个IP。没有修改RTL或IP生成文件。",
              "原始日志、工程和数据库保留在Windows本地；本分支只回传精简日志及报告。", "",
              "## A 媒体/网络模块", "", "### IP", "",
              "六个IP模块名和实际端口与包装一致。选项文本在`artifacts/media/ip/`；未操控桌面，选项PNG未取得。",
              "DRM数来自本次PnR层次报告，不是按位数估算。", "",
              "| IP | 模块名 | 端口与包装一致 | 每实例DRM | 实例数 | 总DRM36K当量 |",
              "|---|---|---|---|---:|---:|"]
    drm = {"vin_wfifo": (4,3), "disp_scan": (4,1), "pix_line": (2,4),
           "geo_src": (2,8), "eth_buf": (1,2), "eth_fifo": (0.5,2)}
    for name, (blocks, count) in drm.items():
        ip = "ip_ram_" + name
        primitive = "1 × DRM18K" if blocks == 0.5 else f"{blocks} × DRM36K"
        result.append(f"| {ip} | {ip} | 一致 | {primitive} | {count} | {blocks*count:g} |")
    result += ["", "六个生成IP合计43 DRM36K当量；整个MEDIA还有PIX内部推导RAM，合计8 DRM18K + 42 DRM36K = 46当量。",
               "GEO不同读写位宽配置已生成并通过综合/PnR；每实例实际使用2个DRM36K。未做IP功能仿真。", "",
               "### 时序", "", "两个时钟均约束8.000 ns（125 MHz）。", "",
               "| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |",
               "|---|---:|---:|---:|---:|---|---:|"]
    outputs = {}
    for version in ("media", "p1", "p2", "p3_noregion"):
        out = c.TASK / "artifacts" / ("media" if version == "media" else "cpu/" + version)
        _, timing = c.summaries(c.read(out / "timing_summary.txt"))
        _, entries = c.hierarchy(c.read(out / "resource_hier.txt"))
        outputs[version] = (out, timing, entries)
    out, timing, entries = outputs["media"]
    for corner in ("slow", "fast"):
        for clock in ("clk_mem", "clk_ext"):
            s = timing[("Setup", corner)][clock]
            h = timing[("Hold", corner)][clock]
            result.append(f"| {clock}/{corner} | {s[0]:.3f} | {s[1]:.3f} | {h[0]:.3f} | {h[1]:.3f} | {s[2]}/{h[2]} | {1000/(8-s[0]):.4f} |")
    result += ["", "PnR报告确认clk_mem_i=K21、clk_ext_i=D18，各使用一个全局时钟缓冲。",
               "时序报告列出异步组mem_ext_async；setup/hold汇总只有同域路径，没有跨两域路径。未放宽专用时钟布线。",
               "DISP的clk_ext域最差裕量为+2.064 ns；在125 MHz测试约束下满足setup。",
               "这支持该域74.25 MHz目标，但不代表其他域或完整SoC的板级时序已经通过。",
               "clk_mem最差路径位于PIX：行RAM到u_point2乘法器输入，14级，-7.667 ns。", "",
               "每域最差200条setup、前20条逐级明细、fast角最差20条hold、最多30组明细、DISP clk_ext前20条均已保存。",
               "分组样本来自每域top200，组内路径数表示导出样本数，并非设计所有路径数。",
               "额外保存0<slack<1 ns的200条clk_mem setup路径；clk_ext没有该区间路径，最差为+2.064 ns。", ""]
    setup_rows = rows(out / "setup_top200.txt")
    for clock in ("clk_mem", "clk_ext"):
        result += [f"最差路径前10条：{clock}", "", "| 起点 → 终点 | 裕量(ns) | 级数 |", "|---|---:|---:|"]
        for p in [p for p in setup_rows if p["clock"] == clock][:10]:
            result.append(f'| {p["startpoint"]} → {p["endpoint"]} | {p["slack_ns"]} | {p["logic_levels"]} |')
        result.append("")
    synth = c.read(out / "resource_summary.txt")
    result += ["### 资源", "", "LUT采用逻辑层次口径；DRM总量采用36K当量。详细器件容量、占用率及18K/36K拆分见resource_summary.txt。", "",
               "| 阶段 | LUT | FF | DRM18K/36K | APM | 分布式RAM | IO | PLL |", "|---|---:|---:|---|---:|---:|---:|---:|",
               "| 综合 | 19105 | 16480 | 8 / 42 | 105 | 113 | 7 | 0（PnR核实） |",
               "| PnR逻辑层次 | 19009 | 16480 | 8 / 42（SNR拆分；PRR46当量） | 105 | 113 | 7 | 0 |", "",
               "| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |", "|---|---:|---:|---:|---:|---:|"]
    direct = [e for e in entries if e["depth"] == 1]
    for e in direct:
        result.append("| " + e["name"] + " | " + " | ".join(map(str,e["values"])) + " |")
    result += ["| 顶层自身差额（含激励/观测逻辑） | 1385 | 2909 | 0 | 0 | 0 |", "",
               "顶层自身资源按总计减去直接子模块计算；单个stim/obs寄存器的独立资源数未取得，不按声明位宽冒充实测资源。",
               "完整下一级子模块资源见resource_hier.txt。",
               "Linux Yosys参考（LUT6/FF，RAM黑盒）：VIN8422/5651、DISP3179/1856、PIX32535/5234、GEO9043/3116、ETH8279/4553。",
               "本次PDS将PIX算术映射到96个APM，GEO使用9个APM，因此不能只按LUT数与Yosys黑盒估算作等价比较。",
               "SoC规格预算：VIN+PIX+DISP10K、GEO8K、ETH5K；本次三者逻辑LUT合计10523，GEO3238、ETH3863。", "",
               "### 导入脚本修正", "",
               "按此前用户要求，保留../../EdRV32-Competition-2026的相对根路径计算；include参数改为rtl/include与当前FPGA工程目录组成的Tcl列表，并用compile -force_to_run应用新配置。",
               "已从MEDIA和CPU工程目录展开源码/include/约束路径；没有修改RTL中的include或复制头文件。MEDIA现已完成完整流程。", "",
               "## B CPU时序探针", "", "### 约束确认", "",
               "- 外部FDC的syn_preserve/syn_keep在本机PDS报ConstraintEditor-0046：属性无效。",
               "- UCE手册68页规定集成版层次分隔符为`.`，`i:`表示instance；空格分隔试验出现解析警告。",
               "- 最小工程及实际Compile日志都显示：六个valid在读取FDC前合并为两份，仅probe_f1_redirect_valid_r和probe_f1_d_redirect_valid_r保留。",
               "- 最终只对两份存在的FF设置PAP_DONT_TOUCH；手册93页规定它作用于Device Map，不能恢复Compile已合并的FF。本次不宣称六份复制成功。",
               "- P3区域改为先define_global_attribute {PAP_REGION} {core_probe(423,806,600,791)}，再以define_attribute把u_cpu_subsys.u_core关联到core_probe。",
               "- PDS报ConstraintEditor-0027（非法floorplan坐标）及UserConstraintEditor-0058，在综合约束检查阶段停止。clock_utilization.txt的block坐标范围为x=0..238、y=0..249；候选坐标误用了另一种网格尺度，未验证覆盖4个APM。",
               "- 按B6去掉区域约束，保存P3失败日志及原约束，再运行P3_noregion；比较表使用该实测结果。",
               "- 探针FDC仅本地适配，最终全文以artifacts内fdc_used.fdc回传；src/p2、src/p3候选FDC不随结果提交修改。", "",
               "### 时序", "", "| 版本/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |",
               "|---|---:|---:|---:|---:|---|---:|",
               "| 第四轮RVC=1/slow（任务卡参考） | -1.789 | -4967.383 | — | — | 7611/— | 118.3 |"]
    for version in ("p1", "p2", "p3_noregion"):
        out, timing, entries = outputs[version]
        for corner in ("slow", "fast"):
            s, h = timing[("Setup", corner)]["clk_sys"], timing[("Hold", corner)]["clk_sys"]
            result.append(f"| {version}/{corner} | {s[0]:.3f} | {s[1]:.3f} | {h[0]:.3f} | {h[1]:.3f} | {s[2]}/{h[2]} | {1000/(6.667-s[0]):.4f} |")
    result += ["", "P1→P2的WNS改善0.316 ns，P2→P3_noregion再改善0.228 ns。三版均未满足6.667 ns约束。",
               "全量违例端点导出采用max_path100000、nworst1、slack<0；去重后8196/1361/432个，与PDS汇总逐版一致。",
               "每版另外保存最差200条setup、前20条逐级明细、fast角最差20条hold，以及0<slack<1 ns的200条危险正裕度setup及前20条明细。",
               "三版危险正裕度样本最小均为+0.001 ns。P2/P3为功能不正确的时序探针，不能用于上板。", ""]
    for version in ("p1", "p2", "p3_noregion"):
        out, timing, entries = outputs[version]
        first = rows(out / "setup_top200.txt")[0]
        result += [f"{version}最差路径：{first['startpoint']} → {first['endpoint']}，{first['slack_ns']} ns，{first['logic_levels']}级。", "",
                   "前10组（去除寄存器位下标及打包后缀，保留generate实例下标；IP内部归并到u_ip）：", "",
                   "| 起点寄存器 → 终点寄存器 | 端点数 | 最差裕量(ns) | 最差路径级数 |", "|---|---:|---:|---:|"]
        group_text = c.read(out / "endpoint_groups.txt").split("start_register\tend_register",1)[1]
        for line in group_text.splitlines()[1:11]:
            a,b,n,s,l = line.split("\t")
            result.append(f"| {a} → {b} | {n} | {s} | {l} |")
        result.append("")
    result += ["### 资源", "", "| 版本 | LUT | FF | DRM36K当量 | APM | 分布式RAM | u_core LUT/FF |", "|---|---:|---:|---:|---:|---:|---|"]
    for version in ("p1", "p2", "p3_noregion"):
        out, timing, entries = outputs[version]
        lut,ff,ram,apm,drm_count = entries[0]["values"]
        core = next(e for e in entries if e["name"] == "u_core")["values"]
        result.append(f"| {version} | {lut} | {ff} | {drm_count} | {apm} | {ram} | {core[0]}/{core[1]} |")
    result += ["", "CPU均为4 DRM18K + 24 DRM36K，IO9、PLL0。u_core和下一级模块的LUT/FF全文见各版resource_hier.txt。", "",
               "## 日志、耗时和产物范围", "", "| 工程 | Compile | 综合 | Device Map | PnR | 最终阶段Error数 |", "|---|---|---|---|---|---:|"]
    for version in ("p1", "p2", "p3_noregion", "media"):
        flow = c.read(outputs[version][0]/"flow_summary.txt")
        times = [metric(flow,rf"Action {stage}: Real time elapsed is ([^\n]+)")
                 for stage in ("compile", "synthesize", "dev_map", "pnr")]
        errors = sum(int(x) for x in re.findall(r"Errors=(\d+)", flow))
        result.append(f"| {version} | " + " | ".join(times) + f" | {errors} |")
    result += ["", "flow_summary.txt保留各阶段warning分类/条数、Real/CPU/Process CPU时间、峰值内存；logs保留全部W/E行及阶段摘要。",
               "主要warning包括常量传播Loop、位宽截断/扩展、常量寄存器移除、未约束IO。ConstantProbeLoop本身不能据此判为RTL组合环。具体原文及位置均在warnings_detail.txt。",
               "MEDIA内存域在fast角仍有-1.862 ns/314个setup违例；CPU和MEDIA的hold汇总均无违例，但最小裕量约0.100 ns，已保留hold明细。",
               "时序汇总也保留recovery/removal和pulse-width检查，不能只看setup。",
               "P1初始批处理在PDS执行队列前复制尚未产生的报告，出现Flow-0163；实际Compile/PnR/STA均成功，脚本已移除这些提前复制命令，详细导出另起只读STA任务完成。",
               "P3原区域失败日志与前次FDC试验已精简保留；未用成功重跑覆盖失败事实。", "",
               "### Windows本地完整报告", "",
               "- MEDIA：G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/{compile,synthesize,device_map,place_route,report_timing}/。",
               "- CPU：G:/codex_project/EdRV32-Competition-2026/build/win/20261028-04-media-cpu-probes/cpu/{p1,p2,p3,p3_noregion}/。",
               "- 补导时序：G:/codex_project/EdRV32-Competition-2026/build/win/20261028-04-media-cpu-probes/exports/。", "",
               "### 复现命令", "", "```powershell",
               "C:/Python314/python.exe tasks/win/20261028-04-media-cpu-probes/src/export_timing.py",
               "C:/Python314/python.exe tasks/win/20261028-04-media-cpu-probes/src/collect_reports.py",
               "C:/Python314/python.exe tasks/win/20261028-04-media-cpu-probes/src/write_result.py", "```", "",
               "本次只整理报告及此前授权的导入脚本修复，不改RTL，不跑Verilator或功能仿真。"]
    c.write(c.TASK / "result.md", "\n".join(result))


if __name__ == "__main__":
    main()
