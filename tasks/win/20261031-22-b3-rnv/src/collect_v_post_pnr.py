"""Collect completed V implementation reports; do not run implementation."""
from pathlib import Path
from collections import Counter
import runpy, re, shutil, subprocess
R = Path(__file__).resolve().parents[4]
T = R / "tasks/win/20261031-22-b3-rnv"
O = T / "artifacts/b3v"
P = R.parent / "EdRV32-FPGA/EdRV32-B3V"
TOP = "edrv32_fpga_board_vision_top"
u = runpy.run_path(str(R / "tasks/win/20261028-03-cpu-sys-synth-r4/src/collect_reports.py"))
read, section = u["read"], u["section"]
def write(name, text):
    p = O / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text.rstrip() + "\n", encoding="utf-8")
flow = []
for stage in ["compile", "synthesize", "device_map", "place_route", "report_timing", "generate_bitstream"]:
    raw = read(P / stage / "run.log")
    lines = raw.splitlines()
    warnings = [l for l in lines if l.startswith("W:")]
    errors = [l for l in lines if l.startswith("E:")]
    flow += [stage, f"Warnings={len(warnings)} Errors={len(errors)}"]
    flow += [l for l in lines if l.startswith("Action ")]
    flow += [str(Counter(u["warning_category"](l) for l in warnings)), ""]
    write(f"logs/{stage}_excerpt.txt", "\n".join(l for l in lines if l.startswith(("W:", "E:", "Action ", "Current time:", "Finished ", "Worst slack", "Unrouted ", "Design '"))))
write("flow_summary.txt", "\n".join(flow))
for stage, suffix in [("compile", ".cmr"), ("synthesize", ".snr"), ("device_map", ".dmr"), ("place_route", ".prr")]:
    target = O / "native_reports" / stage / (TOP + suffix)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(P / stage / (TOP + suffix), target)
prr = read(P / "place_route" / (TOP + ".prr"))
snr = read(P / "synthesize" / (TOP + ".snr"))
hier, entries = u["hierarchy"](prr)
write("resource_hier.txt", hier)
write("resource_summary.txt", section(prr, "Device Utilization Summary :") + "\n\n" + snr[snr.index("Cell Usage:"):snr.index("Overview of Control Sets:")] + "\nHierarchy units [LUT, FF, distributed RAM, APM, DRM36K-equivalent]:\n" + "\n".join(str(e) for e in entries if e["depth"] <= 2))
rtr = read(P / "report_timing" / (TOP + ".rtr"))
write("timing_summary.txt", rtr.split("\nSlow Corner", 1)[0])
export = R / "build/win/20261031-22-b3-rnv/exports/b3v_top200/report_timing" / (TOP + ".rtr")
records = u["paths"](read(export), str(export))
for direction, filename in [("max", "timing_setup_top200.txt"), ("min", "timing_hold_top200.txt")]:
    paths = [p for p in records if p["type"].startswith(direction) and p["class"] == "sequential timing path"]
    paths.sort(key=lambda p: (p["corner"], p["group"], p["slack"]))
    write(filename, u["index_text"](paths))
    worst = sorted(paths, key=lambda p: p["slack"])
    write("timing_setup_top20_detail.txt" if direction == "max" else "timing_hold_top20.txt", u["details"](worst, 20))
    write("timing_near_setup.txt" if direction == "max" else "timing_near_hold.txt", u["index_text"]([p for p in worst if p["slack"] < 1]))
write("timing_other_checks.txt", u["index_text"]([p for p in records if p["class"] != "sequential timing path"]))
write("timing_path_counts.txt", "Report command: report_timing -delay_type min_max -max_path 200 -input_pins TRUE -nworst 1\n" + "\n".join(str(k)+" = "+str(v) for k,v in Counter((p["corner"],p["group"],p["type"],p["class"]) for p in records).items()))
