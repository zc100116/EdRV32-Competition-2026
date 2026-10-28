"""Export routed MEDIA r2 timing, then collect compact task results."""
from concurrent.futures import ThreadPoolExecutor
from collections import defaultdict
from pathlib import Path
import importlib.util
import re
import subprocess

REPO = Path(__file__).resolve().parents[4]
TASK = REPO / "tasks/win/20261028-05-media-r2"
BUILD = REPO / "build/win/20261028-05-media-r2"
PREVIOUS = REPO / "tasks/win/20261028-04-media-cpu-probes/src"
ROOT = REPO.parent / "EdRV32-FPGA/EdRV32-MEDIA"
TOP = "edrv32_fpga_media_top"
MODULES = ("u_vin", "u_pix", "u_geo", "u_disp", "u_eth", "top")


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.TASK, module.BUILD = TASK, BUILD
    return module


def main():
    export = load("previous_export", PREVIOUS / "export_timing.py")
    c = load("previous_collector", PREVIOUS / "collect_reports.py")
    db = ROOT / "place_route" / (TOP + "_pnr.adf")
    jobs = [("media_top200", db, "-max_path 200 -input_pins TRUE"),
            ("media_violating", db, "-delay_type max -max_path 100000 -slack_less_than 0 -input_pins FALSE"),
            ("media_near", db, "-delay_type max -max_path 200 -slack_greater_than 0 -slack_less_than 1 -input_pins TRUE"),
            ("media_disp", db, "-delay_type max -max_path 200 -to {u_disp/*} -input_pins TRUE")]
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(export.export, jobs))
    data = c.collect("media", ROOT, TOP)
    out = TASK / "artifacts"
    # The previous collector uses an A/B layout; this task has MEDIA only.
    for path in sorted((out / "media").rglob("*")):
        if path.is_file():
            destination = out / path.relative_to(out / "media")
            destination.parent.mkdir(parents=True, exist_ok=True)
            path.replace(destination)
    for path in sorted((out / "media").rglob("*"), reverse=True):
        if path.is_dir():
            path.rmdir()
    (out / "media").rmdir()
    negative_file = c.export_report("media_violating", TOP)
    negative = c.setup(c.paths(c.read(negative_file), str(negative_file)), "clk_mem")
    endpoints = {}
    for p in negative:
        endpoints.setdefault(p["end"], p)
    negative = sorted(endpoints.values(), key=lambda p: p["slack"])
    expected = data["timing"][("Setup", "slow")]["clk_mem"][2]
    coverage = (f"PDS clk_mem slow setup failing endpoints={expected}; "
                f"exported unique endpoints={len(negative)}; "
                f"coverage={'complete' if len(negative)==expected else 'incomplete'}.")
    c.write(out / "endpoints_violating.tsv", "endpoint\tstartpoint\tslack_ns\tlogic_levels\n" +
            ("\n".join(f'{p["end"]}\t{p["start"]}\t{p["slack"]:.3f}\t{p["levels"]}'
                       for p in negative) if negative else "无"))
    module_paths = defaultdict(list)
    for p in negative:
        module = p["end"].split("/",1)[0]
        module_paths[module if module in MODULES else "top"].append(p)
    module_rows = []
    for module in MODULES:
        members = module_paths[module]
        worst = f'{min(p["slack"] for p in members):.3f}' if members else "无违例"
        module_rows.append(f"{module}\t{len(members)}\t{worst}")
    group_rows = []
    for (start,end), members in c.groups(negative):
        worst = min(members, key=lambda p:p["slack"])
        group_rows.append(f'{start}\t{end}\t{len(members)}\t{worst["slack"]:.3f}\t{worst["levels"]}')
    command = c.read(BUILD / "exports/media_violating/export.tcl")
    c.write(out / "endpoint_groups.txt", coverage + "\n\nCommand:\n" + command +
            "\n(a) Endpoint top module\nmodule\tendpoints\tworst_slack_ns\n" +
            "\n".join(module_rows) + "\n\n(b) Register pair groups\n"
            "Packed suffixes and register bit indices removed; generate instance indices retained. "
            "IP internals grouped by u_ip.\n"
            "start_register\tend_register\tendpoints\tworst_slack_ns\tworst_path_levels\n" +
            "\n".join(group_rows))
    print(coverage, flush=True)
    print("\n".join(module_rows), flush=True)
    write_result(c, data, out, module_rows, group_rows, coverage)


def write_result(c, data, out, module_rows, group_rows, coverage):
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
    lines = ["# 20261028-05-media-r2 结果", "", "| 项 | 内容 |", "|---|---|",
             f"| 任务卡执行commit | {commit} |",
             "| PDS / 器件 | 2022.2-SP6.1 build138931；PG2L200H-6 FBB676；ADS |",
             f"| 工程路径 | {ROOT.as_posix()}/EdRV32-MEDIA.pds |",
             "| 完成情况 | 布局布线完成，要求产物已收集；125 MHz内存域仍有setup违例 |", "",
             "## 时序", "", "| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |",
             "|---|---:|---:|---:|---:|---|---:|"]
    timing = data["timing"]
    for corner in ("slow","fast"):
        for clock in ("clk_mem","clk_ext"):
            s,h = timing[("Setup",corner)][clock],timing[("Hold",corner)][clock]
            lines.append(f"| {clock}/{corner} | {s[0]:.3f} | {s[1]:.3f} | {h[0]:.3f} | {h[1]:.3f} | {s[2]}/{h[2]} | {1000/(8-s[0]):.4f} |")
    lines += ["", "Fmax按1000/(8.000−WNS)计算。上一轮clk_mem slow为-7.667 ns、63.8284 MHz、6356个违例端点；本轮WNS改善6.397 ns，剩余542个端点。",
              "clk_ext从+2.064 ns变为+1.475 ns，仍满足本次8.000 ns setup约束。",
              "PnR报告IO表确认clk_mem_i=K21、clk_ext_i=D18，各经一个全局时钟缓冲；异步组mem_ext_async生效，setup/hold汇总仅同域路径。",
              "未增加PAP_CLOCK_DEDICATED_ROUTE FALSE。", "", "clk_mem违例端点按模块：", "",
              "| 终点模块 | 端点数 | 最差裕量(ns) |", "|---|---:|---:|"]
    lines += ["| " + " | ".join(row.split("\t")) + " |" for row in module_rows]
    lines += ["", coverage, "",
              "本次全量端点表显示：PIX、DISP和顶层自身无clk_mem slow setup违例；剩余违例在ETH、GEO、VIN。",
              "全部违例按每端点最差一条去重；端点是PDS原生时序端点，可能为打包单元输入/CE/APM/DRM引脚。模块统计按终点归属，跨模块起点保留在TSV。",
              "", "寄存器对分组前15组（全表见endpoint_groups.txt）：", "",
              "| 起点寄存器 → 终点寄存器 | 端点数 | 最差裕量(ns) | 最差路径级数 |", "|---|---:|---:|---:|"]
    for row in group_rows[:15]:
        a,b,n,s,l = row.split("\t")
        lines.append(f"| {a} → {b} | {n} | {s} | {l} |")
    lines += ["", "### 违例及危险路径", ""]
    for clock in ("clk_mem","clk_ext"):
        for p in c.setup(data["setup"],clock)[:3]:
            lines.append(f'- {clock}: {p["start"]} → {p["end"]}；{p["slack"]:.3f} ns，{p["levels"]}级。')
    lines += ["", "每域最差200条slow setup及前20条逐级明细、每域fast角最差20条hold均已保存。",
              "另外导出0<slack<1 ns的危险正裕度setup（每域上限200条）及前20条逐级明细；具体数量和最小裕量：", ""]
    for clock in ("clk_mem","clk_ext"):
        near = [p for p in data["near"] if p["group"] == clock]
        margin = f'{min(p["slack"] for p in near):.3f} ns' if near else "该范围无路径"
        lines.append(f"- {clock}: {len(near)}条，{margin}。")
    lines += ["", "## 资源", "", "PnR逻辑层次口径；DRM按36K当量。物理CLMA/CLMS LUT占用不冒充逻辑LUT总数。", "",
              "| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |", "|---|---:|---:|---:|---:|---:|"]
    for entry in data["entries"]:
        if entry["depth"] <= 1:
            lines.append("| " + entry["name"] + " | " + " | ".join(map(str,entry["values"])) + " |")
    lines += ["", "各模块下一级和完整层次见resource_hier.txt；SNR原语数、综合后/路后资源、器件容量和利用率见resource_summary.txt。",
              "上一轮：u_vin3482、u_pix5593 LUT/96 APM、u_disp1448、u_geo3238、u_eth3863 LUT；整个工程19009 LUT/16480 FF/105 APM。",
              "PIX本轮4935 LUT/7107 FF/132 APM，上一轮5593 LUT/1166 FF/96 APM；流水化后FF增加5941、APM增加36。",
              "本轮综合Cell Usage为8 DRM18K + 42 DRM36K，46 DRM36K当量；IO7、PLL0（PnR）。", "",
              "## 日志与阶段耗时", "", "```text", c.read(out / "flow_summary.txt"), "```", "",
              "各阶段W/E原文及耗时/峰值内存摘录位于logs/。Loop was found during constant probe是常量传播诊断，单独此条不能证明RTL组合环。",
              "未约束IO警告保持原文；测量顶层的时序结论不等于完整板级IO时序已通过。",
              "仅补导STA并整理报告，没有重跑Compile/综合/PnR，没有修改RTL、IP、导入脚本或约束，不生成bitstream。", "",
              "## 完整报告在Windows本地的路径", "",
              f"- 完整日志和报告：{ROOT.as_posix()}/{{compile,synthesize,device_map,place_route,report_timing}}/。",
              f"- 补导时序及命令：{BUILD.as_posix()}/exports/。", "",
              "## 复现整理命令", "", "```powershell",
              "C:/Python314/python.exe tasks/win/20261028-05-media-r2/src/collect_reports.py", "```", "",
              "脚本复用上一轮已提交的报告提取函数；不上传PDS工程、IP目录、中间数据库、bitstream或完整原始日志。"]
    c.write(TASK / "result.md", "\n".join(lines))


if __name__ == "__main__":
    main()
