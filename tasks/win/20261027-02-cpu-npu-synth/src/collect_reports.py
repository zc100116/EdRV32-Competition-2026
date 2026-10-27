"""Collect the completed Windows PDS reports and the separate timing exports.

Run with Python 3 from the checkout. Raw implementation databases and full logs
stay in the FPGA projects; all W:/E: lines and stage timings are retained here.
"""
from collections import Counter
from pathlib import Path
import re
import shutil


REPO = Path(__file__).resolve().parents[4]
TASK = REPO / "tasks/win/20261027-02-cpu-npu-synth"
BUILD = REPO / "build/win/20261027-02-cpu-npu-synth"
STAGES = ("compile", "synthesize", "device_map", "place_route", "report_timing")
PROJECTS = {
    "cpu": ("EdRV32", "edrv32_fpga_cpu_sys_top"),
    "npu": ("EdRV32-NPU-DP", "edrv32_fpga_npu_dp_top"),
}


def read(path):
    return path.read_text(encoding="utf-8", errors="replace")


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def section(text, title):
    tail = text.split(title, 1)[1]
    # A table has a top border, header separator, and bottom border.
    borders = list(re.finditer(r"^\+[-]+\+\s*$", tail, re.M))
    return title + tail[:borders[2].end()]


def paths(text, source):
    result = []
    for block in re.split(r"(?=^Startpoint\s*:)", text, flags=re.M)[1:]:
        def field(key):
            return re.search(r"^" + key + r"\s*:\s*(.*)", block, re.M)[1].strip()
        path_type = field("Path Type")
        cls = field("Path Class")
        slack = (None if cls == "combinational timing path" else
                 float(re.search(r"^\s*Slack \([^)]*\)\s+(-?[\d.]+)", block, re.M)[1]))
        result.append({
            "start": field("Startpoint"), "end": field("Endpoint"),
            "group": field("Path Group"), "type": path_type,
            "corner": re.search(r"\((slow|fast) corner\)", path_type)[1],
            "class": cls, "slack": slack,
            "levels": int(re.search(r"Logic Levels:\s*(\d+)", block)[1]),
            "block": block.rstrip(), "source": source,
        })
    return result


def index_text(records):
    lines = ["source\tcorner\tclock\ttype\tclass\tslack_ns\tlogic_levels\tstartpoint\tendpoint"]
    for p in records:
        lines.append("\t".join(str(v) for v in (
            p["source"], p["corner"], p["group"], p["type"], p["class"],
            "N/A (unconstrained)" if p["slack"] is None else f'{p["slack"]:.3f}',
            p["levels"], p["start"], p["end"])))
    return "\n".join(lines)


def select(records, direction, corner, cls="sequential timing path"):
    return [p for p in records if p["type"].startswith(direction)
            and p["corner"] == corner and p["class"] == cls]


def details(records, count=20):
    return "\n\n".join(p["block"] for c in ("slow", "fast")
                        for p in [x for x in records if x["corner"] == c][:count])


def hierarchy(text):
    table = section(text, "Device Utilization Summary Of Each Module:")
    entries, stack = [], []
    for line in table.splitlines():
        cols = [c.rstrip() for c in line.split("|")[1:]]
        if not cols or not cols[1:6] or not cols[1].strip().isdigit():
            continue
        label = cols[0]
        m = re.match(r"(\s*)\+\s*(\S+)", label)
        if m:
            depth = (len(m[1]) + 1) // 2
            name = m[2]
            stack = stack[:depth] + [name]
        else:
            depth, stack = 0, [label.strip()]
        entries.append({"depth": depth, "path": "/".join(stack),
                        "name": stack[-1], "values": [
                            float(c.strip()) if "." in c else int(c.strip())
                            for c in cols[1:6]]})
    return table, entries


def timing_summary(text):
    head = text.split("\nSlow Corner", 1)[0]
    values = {}
    for m in re.finditer(r"(Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((Slow|Fast) Corner\):", head):
        tail = head[m.end():]
        line = re.search(r"^\s*clk_\w+.*$", tail, re.M)[0]
        numbers = re.findall(r"-?\d+\.\d+|\b\d+\b", line)
        values[(m[1], m[2].lower())] = numbers
    return head, values


def warning_category(line):
    m = re.match(r"[WE]:\s*([A-Za-z]+-\d+):", line)
    if m:
        return m[1]
    if "Loop was found during constant probe" in line:
        return "ConstantProbeLoop"
    if "fanout" in line.lower():
        return "Uncoded fanout warning"
    return "Uncoded warning"


def collect(kind, project, top):
    root = REPO.parent / "EdRV32-FPGA" / project
    out = TASK / "artifacts" / kind
    native = out / "native_reports"
    reports = [("compile", f"{top}.cmr"), ("compile", "include_relation.txt"),
               ("synthesize", f"{top}.snr"),
               ("synthesize", f"{top}_controlsets.txt"),
               ("synthesize", "apm_drm_lutram_utilization.log"),
               ("synthesize", "add_sub_carrychain.log"),
               ("device_map", f"{top}.dmr"), ("device_map", f"{top}_dmr.prt"),
               ("place_route", f"{top}.prr"), ("place_route", f"{top}_prr.prt"),
               ("place_route", "clock_utilization.txt"),
               ("report_timing", f"{top}.rtr"),
               ("constraint_check", "constraint_check.ccr")]
    for stage, name in reports:
        dst = native / stage / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / stage / name, dst)

    summary, warnings, excerpts, stages = [], [], [], []
    summary += [f"Project: {root}", "Counts are W:/E: lines, not unique defects.",
                "Full raw stage logs remain at <project>/<stage>/run.log.", ""]
    for stage in STAGES:
        raw = read(root / stage / "run.log")
        warn = [l for l in raw.splitlines() if l.startswith("W:")]
        err = [l for l in raw.splitlines() if l.startswith("E:")]
        count = Counter(warning_category(l) for l in warn)
        timing = [l for l in raw.splitlines() if l.startswith(("Action ", "Current time:"))]
        summary += [f"STAGE {stage}: Errors={len(err)} Warnings={len(warn)}"]
        summary += [f"{key}\t{value}" for key, value in count.most_common()]
        summary += timing + [""]
        warnings += [f"STAGE {stage}; source={root / stage / 'run.log'}"] + warn + err + [""]
        excerpts += [f"STAGE {stage}"] + [l for l in raw.splitlines() if
                    l.startswith(("#", "Generated by", "Start ", "Current time:", "Action ",
                                  "Process ", "Report timing is finished", "Program Error"))
                    or (l.startswith("Executing :") and "Time elapsed:" in l)] + [""]
        stages.append({"stage": stage, "warnings": len(warn), "errors": len(err),
                       "timing": timing, "counts": count})
    write(out / "flow_summary.txt", "\n".join(summary))
    write(out / "logs/warnings_detail.txt", "\n".join(warnings))
    write(out / "logs/execution_excerpt.txt", "\n".join(excerpts))
    action_lines = [l for l in read(root / "pds.log").splitlines() if
                    re.match(r"^(Executing : (?:source |compile |synthesize |dev_map|pnr|report_timing)|[ECW]:|Current time:|Action |Process )", l)]
    write(out / "logs/project_actions_excerpt.txt",
          "Historical GUI actions, including earlier failed imports; not final-stage error counts.\n"
          + "\n".join(action_lines))

    original = read(root / "report_timing" / f"{top}.rtr")
    timing_head, timing_values = timing_summary(original)
    write(out / "timing_summary.txt", timing_head)
    expanded_path = BUILD / f"timing_{kind}_200/report_timing/{top}.rtr"
    expanded = paths(read(expanded_path), "global200")
    setup = [p for p in expanded if p["class"] == "sequential timing path"
             and p["type"].startswith("max")]
    hold = [p for p in expanded if p["class"] == "sequential timing path"
            and p["type"].startswith("min")]
    write(out / "setup_top200.txt", index_text(setup))
    write(out / "hold_top200.txt", index_text(hold))
    write(out / "setup_top20_detail.txt", details(setup))
    write(out / "hold_top20.txt", details(hold))
    asyncs = [p for p in expanded if p["class"] == "async timing path"]
    write(out / "recovery_removal_top20.txt", "\n\n".join(
        p["block"] for corner in ("slow", "fast") for direction in ("max", "min")
        for p in select(asyncs, direction, corner, "async timing path")[:20]))
    all_paths = expanded[:]
    unconstrained = [p for p in expanded if p["class"] == "combinational timing path"]
    write(out / "unconstrained_io_paths.txt",
          "These paths have arrival times but no reported slack or pass/fail verdict.\n\n"
          + "\n\n".join(p["block"] for p in unconstrained))
    near = []
    if kind == "cpu":
        near_path = BUILD / f"timing_cpu_near/report_timing/{top}.rtr"
        near = paths(read(near_path), "positive_setup_lt1ns")
        write(out / "setup_near_positive_top200.txt", index_text(near))
        write(out / "setup_near_positive_top20_detail.txt", details(near))
        all_paths += near
    write(out / "all_paths.tsv", index_text(all_paths))
    export_notes = [f"Expanded report: {expanded_path}",
                    "Command: report_timing -input_db_file <original pnr.adf> "
                    "-max_path 200 -nworst 1 -input_pins TRUE -force_to_run",
                    "Reports are exported in separate scratch projects; routed databases are unchanged.",
                    "Full expanded reports remain local; indexed paths and required detail blocks are saved here."]
    for suffix in (f"timing_{kind}_200",) + (("timing_cpu_near",) if kind == "cpu" else ()):
        console = read(BUILD / suffix / "console.log")
        export_notes += [suffix] + [l for l in console.splitlines() if
                         l.startswith(("Action ", "E:", "W:", "Process ", "Executing : report_timing"))]
    write(out / "logs/timing_export_excerpt.txt", "\n".join(export_notes))

    prr = read(root / "place_route" / f"{top}.prr")
    dmr = read(root / "device_map" / f"{top}.dmr")
    snr = read(root / "synthesize" / f"{top}.snr")
    hierarchy_table, entries = hierarchy(prr)
    write(out / "resource_hier.txt", "Source: final place_route PRR\n" + hierarchy_table)
    physical = section(prr, "Device Utilization Summary :")
    synth = snr[snr.index("Cell Usage:"):snr.index("Overview of Control Sets:")]
    resource = ["Final logical hierarchy total (LUT, FF, Distributed RAM, APM, DRM36K-equivalent):",
                str(entries[0]["values"]), "", physical, "", "SYNTHESIS STAGE (different stage):", synth,
                "Do not sum physical CLMA/CLMS LUT rows and label the result as the logical LUT count."]
    if kind == "npu":
        resource += ["DRM18K: 0; DRM36K: 148 (synthesis Cell Usage).",
                     "The task comparison baseline is 148 DRM, excluding unused scratch.",
                     "stim/obs register-bank breakdown is not separately reported by PRR; source widths:",
                     "stim_r 1025; obs_r 358; l1_r 60; l2_r 10; l3_r 2; obs_bit_r 1.",
                     "These are RTL widths, not post-optimization resource counts."]
    else:
        resource += ["Synthesis DRM primitives: 4 DRM18K + 24 DRM36K = 26 DRM36K-equivalent."]
    write(out / "resource_summary.txt", "\n".join(resource))
    fanout = ["Source: final device_map DMR; counts are pre-PnR mapping fanout.",
              section(dmr, "Other High Fanout Signal:")]
    fanout += [section(dmr, title) for title in ("Clock Signal:", "Reset Signal:", "CE Signal:")]
    fanout += ["Final PnR clock distribution:", section(prr, "Global Clock Info:")]
    write(out / "high_fanout.txt", "\n\n".join(fanout))
    return {"root": root, "top": top, "entries": entries, "stages": stages,
            "setup": setup, "hold": hold, "near": near,
            "timing": timing_values, "all_paths": all_paths}


if __name__ == "__main__":
    for kind, (project, top) in PROJECTS.items():
        data = collect(kind, project, top)
        print(kind, "paths", len(data["all_paths"]), "final resources", data["entries"][0]["values"])
