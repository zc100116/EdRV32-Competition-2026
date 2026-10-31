"""Collect completed Compile/Synthesis/Device Map reports for card 22 R/N/V."""
from pathlib import Path
from collections import Counter
import re, runpy, shutil
R = Path(__file__).resolve().parents[4]
T = R / "tasks/win/20261031-22-b3-rnv"
U = runpy.run_path(str(R / "tasks/win/20261028-03-cpu-sys-synth-r4/src/collect_reports.py"))
STAGES = [("compile", ".cmr"), ("synthesize", ".snr"), ("device_map", ".dmr")]
PROJECTS = [("b3r", "render", 103), ("b3n", "npu", 106), ("b3v", "vision", 112)]
def write(p, text):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text.rstrip() + "\n", encoding="utf-8")
flows, resources, paths_summary, notes = [], [], [], []
for name, variant, count in PROJECTS:
    P = R.parent / "EdRV32-FPGA" / ("EdRV32-" + name.upper())
    O = T / "artifacts" / name
    top = "edrv32_fpga_board_" + variant + "_top"
    flow = []
    for stage, ext in STAGES:
        lines = (P / stage / "run.log").read_text(errors="replace").splitlines()
        warning = [l for l in lines if l.startswith("W:")]
        error = [l for l in lines if l.startswith("E:")]
        actions = [l for l in lines if l.startswith("Action ")]
        flow += [stage, f"W: lines={len(warning)} E: lines={len(error)}", str(Counter(U["warning_category"](l) for l in warning))] + actions + [""]
        write(O / "logs" / (stage + "_excerpt.txt"), "\n".join(l for l in lines if l.startswith(("W:", "E:", "Action ", "Current time:", "Finished ", "Design '", "Saving design", "Total device mapping"))))
        dest = O / "native_reports" / stage / (top + ext)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(P / stage / (top + ext), dest)
        def value(pattern):
            return re.search(pattern, "\n".join(actions))[1]
        flows.append((name, stage, value(r"Real time elapsed is (.*)"), value(r"\nAction [^:]+: CPU time elapsed is (.*)"), value(r"Process CPU time elapsed is (.*)"), value(r"Peak memory pool usage is (.*)"), len(warning), len(error)))
    write(O / "flow_summary.txt", "\n".join(flow))
    snr = (P / "synthesize" / (top + ".snr")).read_text(errors="replace")
    dmr = (P / "device_map" / (top + ".dmr")).read_text(errors="replace")
    hierarchy, entries = U["hierarchy"](snr)
    write(O / "resource_hier.txt", "Synthesis hierarchy (before placement and routing).\n" + hierarchy)
    table = U["section"](dmr, "Device Utilization Summary:")
    write(O / "resource_summary.txt", "Device Map resources:\n" + table + "\n\nSynthesis primitive usage:\n" + snr[snr.index("Cell Usage:"):snr.index("Overview of Control Sets:")])
    usage = {m[1].strip(): m[2].strip() for m in re.finditer(r"^\|\s*([^|]+)\|\s*([0-9.]+)\s*\|", table, re.M)}
    resources.append((name, *[usage[k] for k in ["LUT", "FF", "Distributed RAM", "APM", "DRM", "IO", "GPLL", "PPLL"]]))
    write(O / "high_fanout.txt", "Device Map, pre-PnR:\n\n" + "\n\n".join(U["section"](dmr, title) for title in ["Other High Fanout Signal:", "Clock Signal:", "Reset Signal:", "CE Signal:"]))
    region = [l for l in dmr.splitlines() if "PAP_REGION" in l]
    write(O / "regions_pre_pnr.txt", "Device Map attribute records; these do not establish final physical placement.\n" + "\n".join(region))
    records = U["paths"](snr, "native_reports/synthesize/" + top + ".snr")
    write(O / "timing_pre_pnr_paths.tsv", "PRE-PnR synthesis estimates; not routed timing.\n" + U["index_text"](records))
    write(O / "timing_pre_pnr_counts.txt", "\n".join(f"{k}: {v}" for k,v in Counter((x["corner"],x["group"],x["type"],x["class"]) for x in records).items()))
    for kind, label in [("max", "setup"), ("min", "hold")]:
        selected = sorted([x for x in records if x["type"].startswith(kind) and x["class"] == "sequential timing path"], key=lambda x:x["slack"])
        write(O / ("timing_pre_pnr_" + label + "_detail.txt"), "PRE-PnR estimates, worst available 20 per corner.\n" + U["details"](selected, 20))
        worst = min((x["slack"] for x in selected), default=None)
        negative = sum(x["slack"] < 0 for x in selected)
        paths_summary.append((name,label,len(selected),worst,negative))
    near = sorted([x for x in records if x["slack"] is not None and x["slack"] < 1],key=lambda x:x["slack"])
    write(O / "timing_pre_pnr_near.tsv", "PRE-PnR available paths with slack < 1 ns, including negative slack.\n" + U["index_text"](near))
    for f in O.rglob("*"):
        if f.is_file() and f.stat().st_size > 2_000_000:
            notes.append(f"{f.relative_to(T)} ({f.stat().st_size} bytes)：保留原厂警告或层次数据供分析，未复制完整原始运行日志。")
    print(name, "stages=3", "path records",len(records),"synthesis hierarchy",entries[0]["values"],flush=True)
text = """# 任务 22：R/N/V 布局布线前阶段报告

本版仅整理三个工程的 Compile、Synthesize、Device Map。各阶段日志来自现有工程目录；不启动、不停止或重跑任何流程，不采集布局布线、最终 routed timing、bitstream 或上板结果。

- 分支：win/20261031-22-b3-rnv；整理时已同步软件更新 8edfca2d。
- 工具：PDS 2022.2-SP6.1；器件 PG2L200H-6 FBB676。
- 工程目录：G:/codex_project/EdRV32-FPGA/EdRV32-B3R、EdRV32-B3N、EdRV32-B3V。
- 源码目标数：R=103、N=106、V=112；配置时的添加/移除清单在各 artifacts 子目录 sources.txt。
- 用户安排三个工程并行实现、配置逐个完成，覆盖任务卡的串行安排。

## 阶段耗时和告警

W/E 为日志行数，同一类告警可能重复出现，不代表独立根因数。峰值是工具报告的 memory pool，不等同于操作系统总工作集。

| 工程 | 阶段 | 实际耗时 | CPU 时间 | Process CPU 时间 | 峰值内存池 | W: | E: |
|---|---|---|---|---|---|---|---|
"""
text += "\n".join("| " + " | ".join(map(str,row)) + " |" for row in flows)
text += """

## Device Map 资源

全部为布局布线前的 Device Map 原文数值。DRM 采用厂商 36K 等效口径；原始 DRM18K/DRM36K 数量在 SNR Cell Usage。综合层次资源单独保存，不与 Device Map 数字混用。

| 工程 | LUT | FF | 分布式 RAM | APM | DRM | IO | GPLL | PPLL |
|---|---|---|---|---|---|---|---|---|
"""
text += "\n".join("| " + " | ".join(map(str,row)) + " |" for row in resources)
text += """

## 布线前时序估计

以下仅统计 SNR 中现有的 sequential timing path，已保存的路径数量受原生报告选项限制。负裕量条数是已报告路径数，不是全设计失败端点总数。setup 为 max，hold 为 min，合并 SNR 中可用的 corners 统计最差值；具体角、时钟和起终点见逐路径列表。

| 工程 | 类型 | 已报告路径数 | 最差裕量 ns | 其中负裕量路径数 |
|---|---|---|---|---|
"""
text += "\n".join("| " + " | ".join(map(str,row)) + " |" for row in paths_summary)
text += """

最终 WNS/TNS/WHS/THS、区域内实际站点、卡21违例路径的最终改善情况，需等待布局布线完成后分析，当前不作通过结论。

## 产物和说明

每个 artifacts/b3r、b3n、b3v 下：

- native_reports/：原生 CMR、SNR、DMR。
- logs/*_excerpt.txt：全部 W:/E: 行及阶段耗时/内存等关键信息。完整原始 run.log 留在各工程的 compile/、synthesize/、device_map/。
- flow_summary.txt：各阶段告警代码计数及时间/内存原文。
- resource_summary.txt、resource_hier.txt：Device Map 汇总、综合 primitive usage、完整综合层次表，包含 CPU/cache、u_mem/u_xbar，以及各工程实际包含的 RND/NPU/图像处理/ETH 模块。
- high_fanout.txt：Device Map 的高扇出、时钟、复位、CE 表。
- regions_pre_pnr.txt：DMR 的 PAP_REGION 属性记录；表示映射阶段记录了约束，不代表最终寄存器已经落入指定区域。
- timing_pre_pnr_paths.tsv：SNR 中全部可取得的路径；timing_pre_pnr_counts.txt：按角/组/类型的数量。
- timing_pre_pnr_setup_detail.txt、timing_pre_pnr_hold_detail.txt：最差可用路径明细；timing_pre_pnr_near.tsv：裕量 <1 ns 的现有路径，包含负裕量。

大量警告已按代码归类并保留原文，包括 ConstantProbeLoop、未驱动信号、综合资源优化及约束覆盖类信息。不通过修改 RTL 消警，不将布线前估计当作实际板级故障结论。

网口和软件上板测试尚未在本卡验收。卡22使用新的 BIOS 与应用协议，上板使用卡22 src 镜像。调试工具已更新，重新启动后才生效。

## 复现整理

C:/Python314/python.exe tasks/win/20261031-22-b3-rnv/src/collect_pre_pnr.py

此脚本只读取现有工程报告并写任务产物，不调用 PDS。
"""
if notes:
    text += "\n## 较大产物\n\n" + "\n".join("- " + x for x in notes)
write(T / "result.md", text)
