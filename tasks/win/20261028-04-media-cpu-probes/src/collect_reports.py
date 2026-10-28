"""Collect compact reports for the completed CPU probes and MEDIA run."""
from collections import Counter, defaultdict
from pathlib import Path
import re
import runpy
import shutil

REPO = Path(__file__).resolve().parents[4]
TASK = REPO / "tasks/win/20261028-04-media-cpu-probes"
BUILD = REPO / "build/win/20261028-04-media-cpu-probes"
UTIL = runpy.run_path(str(REPO / "tasks/win/20261028-03-cpu-sys-synth-r4/src/collect_reports.py"))
read, write = UTIL["read"], UTIL["write"]
paths, index_text = UTIL["paths"], UTIL["index_text"]
section, hierarchy = UTIL["section"], UTIL["hierarchy"]
STAGES = ("compile", "synthesize", "device_map", "place_route", "report_timing")


def export_report(name, top):
    return BUILD / "exports" / name / "report_timing" / (top + ".rtr")


def reg_name(name):
    cell = name.split(" (")[0].rsplit("/", 1)[0]
    cell = re.sub(r"/(?:opit_|gop|gateop).*", "", cell)
    if "/u_ip/" in cell:
        return cell.split("/u_ip/")[0] + "/u_ip"
    prefix, sep, leaf = cell.rpartition("/")
    gen, dot, reg = leaf.rpartition(".")
    return prefix + sep + (gen + dot if dot else "") + re.sub(r"\[\d+\]", "", reg)


def groups(records):
    grouped = defaultdict(list)
    for p in records:
        grouped[(reg_name(p["start"]), reg_name(p["end"]))].append(p)
    return sorted(grouped.items(), key=lambda pair: min(p["slack"] for p in pair[1]))


def setup(records, clock=None):
    return sorted([p for p in records if p["type"].startswith("max")
                   and p["corner"] == "slow" and p["class"] == "sequential timing path"
                   and (clock is None or p["group"] == clock)], key=lambda p: p["slack"])


def summaries(text):
    head = text.split("\nSlow Corner", 1)[0]
    tables = {}
    marks = list(re.finditer(r"(Setup|Hold|Recovery|Removal|Minimum Pulse Width) "
                            r"Summary\((Slow|Fast) Corner\):", head))
    for i, m in enumerate(marks):
        body = head[m.end():marks[i+1].start() if i+1 < len(marks) else len(head)]
        rows = re.findall(r"^\s*(clk_\w+)\s+(clk_\w+)\s+(-?[\d.]+)\s+"
                          r"(-?[\d.]+)\s+(\d+)\s+(\d+)\s*$", body, re.M)
        tables[(m[1], m[2].lower())] = {r[0]: [float(r[2]), float(r[3]), int(r[4]), int(r[5])]
                                       for r in rows}
    return head, tables


def log_excerpt(raw):
    return "\n".join(l for l in raw.splitlines() if
                     l.startswith(("W:", "E:", "Action ", "Current time:", "Process ",
                                   "Phase ", "Worst slack", "Unrouted general nets", "Finished "))
                     or (l.startswith("Executing :") and ("Time elapsed:" in l or "successfully" in l))
                     or "Removed inst probe_" in l)


def collect(version, root, top):
    media = version == "media"
    out = TASK / "artifacts" / ("media" if media else "cpu/" + version)
    notes, warning_lines, flow = [], [], []
    for stage in STAGES:
        raw = read(root / stage / "run.log")
        errors = [l for l in raw.splitlines() if l.startswith("E:")]
        warnings = [l for l in raw.splitlines() if l.startswith("W:")]
        counts = Counter(UTIL["warning_category"](l) for l in warnings)
        flow += [f"STAGE {stage}: Errors={len(errors)} Warnings={len(warnings)}"]
        flow += [f"{k}\t{v}" for k, v in counts.most_common()]
        flow += [l for l in raw.splitlines() if l.startswith(("Action ", "Current time:"))] + [""]
        warning_lines += [f"STAGE {stage}"] + warnings + errors + [""]
        write(out / "logs" / (stage + "_excerpt.txt"), log_excerpt(raw))
    write(out / "flow_summary.txt", "\n".join(flow))
    write(out / "logs/warnings_detail.txt", "\n".join(warning_lines))
    for stage, file in (("compile", top + ".cmr"), ("compile", "include_relation.txt"),
                        ("synthesize", top + ".snr"),
                        ("synthesize", "apm_drm_lutram_utilization.log"),
                        ("synthesize", "add_sub_carrychain.log"),
                        ("device_map", top + ".dmr"), ("place_route", top + ".prr"),
                        ("place_route", "clock_utilization.txt"),
                        ("constraint_check", "constraint_check.ccr")):
        source = root / stage / file
        # Some runs do not produce every optional PDS diagnostic report.
        if source.exists():
            destination = out / "native_reports" / stage / file
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        else:
            notes.append(f"未取得: {source}")
    prr = read(root / "place_route" / (top + ".prr"))
    dmr = read(root / "device_map" / (top + ".dmr"))
    snr = read(root / "synthesize" / (top + ".snr"))
    hier, entries = hierarchy(prr)
    write(out / "resource_hier.txt", "Source: final PnR PRR. Columns retain vendor units.\n" + hier)
    synth = snr[snr.index("Cell Usage:"):snr.index("Overview of Control Sets:")]
    write(out / "resource_summary.txt", "SYNTHESIS:\n" + synth +
          "\nPNR physical resource use and device capacity:\n" +
          section(prr, "Device Utilization Summary :") +
          "\nPNR logical hierarchy totals [LUT,FF,distributed RAM,APM,DRM36K-equivalent]:\n" +
          str(entries[0]["values"]) + "\n\n" +
          "\n".join(f'{e["path"]}\t{e["values"]}' for e in entries if
                    e["depth"] <= (2 if media else 4)) +
          "\nPhysical CLMA/CLMS LUT usage includes packing effects; do not label its sum as logical LUTs.\n"
          "DRM18K/DRM36K primitive split is in SNR Cell Usage; PRR DRM is 36K equivalent.\n")
    fanout = [section(dmr, title) for title in
              ("Other High Fanout Signal:", "Clock Signal:", "Reset Signal:", "CE Signal:")]
    write(out / "high_fanout.txt", "Source: Device Map, before PnR. Full native table retained.\n\n" +
          "\n\n".join(fanout) + "\n\n" + section(prr, "Global Clock Info:"))

    base = (export_report(version + "_top200", top) if version in ("p1", "media") else
            root / "report_timing" / (top + ".rtr"))
    general_text = read(base)
    head, timing = summaries(general_text)
    records = paths(general_text, str(base))
    period = 8.0 if media else 6.667
    fmax = [f"{corner}/{clock}: Fmax=1000/({period}-{v[0]})="
            f"{1000/(period-v[0]):.4f} MHz" for corner in ("slow", "fast")
            for clock, v in timing[("Setup", corner)].items()]
    write(out / "timing_summary.txt", "\n".join(fmax) + "\n\n" + head)
    clocks = ("clk_mem", "clk_ext") if media else ("clk_sys",)
    setups = [p for clock in clocks for p in setup(records, clock)[:200]]
    write(out / "setup_top200.txt", index_text(setups))
    write(out / "setup_top20_detail.txt", "\n\n".join(p["block"] for clock in clocks
          for p in setup(records, clock)[:20]))
    holds = [p for clock in clocks for p in sorted([p for p in records if
             p["type"].startswith("min") and p["class"] == "sequential timing path"
             and p["corner"] == "fast" and p["group"] == clock], key=lambda p: p["slack"])[:20]]
    write(out / "hold_top20.txt", "Fast corner (smallest hold margin); see summary for slow corner.\n\n" +
          "\n\n".join(p["block"] for p in holds))
    near_file = export_report(version + "_near", top)
    near = setup(paths(read(near_file), str(near_file)))
    write(out / "setup_near_positive_top200.txt", "Slow setup: 0 < slack < 1 ns.\n" + index_text(near))
    write(out / "setup_near_positive_top20_detail.txt", "\n\n".join(p["block"] for clock in clocks
          for p in [p for p in near if p["group"] == clock][:20]) or "未报告符合筛选条件的路径。")
    group_rows = []
    if media:
        group_detail = []
        for clock in clocks:
            for (start, end), members in groups(setup(records, clock))[:30]:
                worst = min(members, key=lambda p: p["slack"])
                group_detail += [f"Clock={clock}; group={start} -> {end}; "
                                 f"exported paths in group={len(members)}; worst={worst['slack']:.3f} ns; "
                                 f"source command={general_text.split('| Tcl Command  :',1)[1].splitlines()[0]}",
                                 worst["block"]]
        disp_file = export_report("media_disp", top)
        disp = setup(paths(read(disp_file), str(disp_file)), "clk_ext")[:20]
        write(out / "disp_clk_ext_top20.txt", index_text(disp) + "\n\n" +
              "\n\n".join(p["block"] for p in disp))
        write(out / "setup_group_detail.txt", "Groups from exported top200 per clock; counts refer to exported paths.\n\n" +
              "\n\n".join(group_detail) + "\n\nDISP clk_ext worst20: see disp_clk_ext_top20.txt")
        write(out / "clock_checks.txt", section(prr, "IO Port Info:") + "\n\n" +
              section(prr, "Global Clock Info:") + "\n\n" + head +
              "\nAsynchronous clock groups are declared in the report; setup/hold summaries contain only same-clock rows.\n"
              "No PAP_CLOCK_DEDICATED_ROUTE FALSE override was added.\n")
    else:
        negative_file = (root / "report_timing" / (top + ".rtr") if version == "p1" else
                         export_report(version + "_violating", top))
        negative = setup(paths(read(negative_file), str(negative_file)))
        endpoints = {}
        for p in negative:
            endpoints.setdefault(p["end"], p)
        negative = sorted(endpoints.values(), key=lambda p: p["slack"])
        expected = timing[("Setup", "slow")]["clk_sys"][2]
        coverage = (f"Reported violating endpoints: {expected}; exported unique endpoints: {len(negative)}; "
                    f"coverage={'complete' if len(negative) == expected else 'incomplete'}.\n"
                    "Command: report_timing -delay_type max -max_path 100000 -nworst 1 "
                    "-slack_less_than 0 -input_pins FALSE -force_to_run\n")
        write(out / "endpoints_violating.tsv", "endpoint\tstartpoint\tslack_ns\tlogic_levels\n" +
              "\n".join(f'{p["end"]}\t{p["start"]}\t{p["slack"]:.3f}\t{p["levels"]}' for p in negative))
        group_rows = ["start_register\tend_register\tendpoints\tworst_slack_ns\tworst_logic_levels"]
        for (start, end), members in groups(negative):
            worst = min(members, key=lambda p: p["slack"])
            group_rows.append(f'{start}\t{end}\t{len(members)}\t{worst["slack"]:.3f}\t{worst["levels"]}')
        write(out / "endpoint_groups.txt", coverage + "\n" + "\n".join(group_rows))
        notes.append(coverage)
        if version != "p1":
            shutil.copyfile(out / "probe_used.fdc", out / "fdc_used.fdc")
    notes += [f"Full local project: {root}", f"General paths: {base}",
              f"Near-positive paths: {near_file}",
              "Additional report commands: build/win/20261028-04-media-cpu-probes/exports/*/export.tcl",
              "No RTL, IP or routed databases were changed for report extraction.",
              "Clock/IO unconstrained warnings retained; board timing of unconstrained IO is not certified.",
              "ConstantProbeLoop warnings are constant-propagation diagnostics, not by themselves proof of an RTL combinational loop."]
    write(out / "collection_notes.txt", "\n".join(notes))
    export_lines = []
    for job in sorted((BUILD / "exports").glob(version + "_*")):
        export_lines += [str(job), read(job / "export.tcl"),
                         log_excerpt(read(job / "console.log"))]
    write(out / "logs/timing_export_excerpt.txt", "\n".join(export_lines))
    return {"timing": timing, "entries": entries, "setup": setups, "near": near,
            "groups": group_rows, "root": root, "flow": flow, "synth": synth}


if __name__ == "__main__":
    data = {}
    for version in ("p1", "p2", "p3_noregion", "media"):
        root = (REPO.parent / "EdRV32-FPGA/EdRV32-MEDIA" if version == "media" else
                BUILD / "cpu" / version)
        top = "edrv32_fpga_media_top" if version == "media" else "edrv32_fpga_cpu_sys_top"
        data[version] = collect(version, root, top)
        print(version, data[version]["entries"][0]["values"],
              data[version]["timing"][("Setup", "slow")], flush=True)
    # Preserve failed attempts as compact diagnostics, not full raw logs.
    for version in ("p2", "p3"):
        out = TASK / "artifacts/cpu" / version
        for name in ("constraint_attempt_failed.log", "region_failed.log"):
            path = out / name
            if path.exists():
                write(path, log_excerpt(read(path)))
