"""Snapshot completed VN stages and current routing progress without changing the flow."""
from pathlib import Path
from collections import Counter
import runpy, re, shutil
R = Path(__file__).resolve().parents[4]
O = R / "tasks/win/20261031-21-b3-rerun-eth/artifacts/b3vn"
P = R.parent / "EdRV32-FPGA/EdRV32-B3VN"
TOP = "edrv32_fpga_board_vnpu_top"
u = runpy.run_path(str(R / "tasks/win/20261028-03-cpu-sys-synth-r4/src/collect_reports.py"))
def write(name, text):
    p = O / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text.rstrip() + "\n", encoding="utf-8")
flow = []
for stage in ["compile", "synthesize", "device_map", "place_route"]:
    lines = (P / stage / "run.log").read_text(errors="replace").splitlines()
    warnings = [l for l in lines if l.startswith("W:")]
    errors = [l for l in lines if l.startswith("E:")]
    flow += [stage, "IN PROGRESS snapshot" if stage == "place_route" else "Completed", f"Warnings={len(warnings)} Errors={len(errors)}", str(Counter(u["warning_category"](l) for l in warnings))]
    flow += [l for l in lines if l.startswith("Action ")]+[""]
    prefixes = ("W:", "E:", "Action ", "Current time:", "Finished ", "Worst slack", "Unrouted ", "Total ", "Routing ", "Placement ", "Route ", "Pre route ", "Timing-driven ")
    write(f"logs/{stage}_excerpt.txt", "\n".join(l for l in lines if l.startswith(prefixes)))
    if stage == "place_route":
        write("routing_progress.txt", "Source: live place_route/run.log snapshot; not a final report.\n" + "\n".join(l for l in lines if l.startswith(("Worst slack", "Placement ", "Total placement", "Routing ", "Route thread", "Total nets", "Total loads", "Total route", "Pre route", "Unrouted "))))
        write("routing_tail.txt", "Snapshot only; routing was not stopped.\n"+"\n".join(lines[-100:]))
write("flow_summary.txt", "\n".join(flow))
for stage, suffix in [("compile", ".cmr"), ("synthesize", ".snr"), ("device_map", ".dmr")]:
    dest = O / "native_reports" / stage / (TOP + suffix)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(P / stage / (TOP + suffix), dest)
snr = (P / "synthesize" / (TOP + ".snr")).read_text(errors="replace")
dmr = (P / "device_map" / (TOP + ".dmr")).read_text(errors="replace")
hierarchy, entries = u["hierarchy"](snr)
write("resource_hier.txt", "SYNTHESIS hierarchy; not final PnR usage.\n" + hierarchy)
write("resource_summary.txt", "DEVICE MAP, before placement/routing:\n" + u["section"](dmr, "Device Utilization Summary:") + "\n\nSYNTHESIS:\n" + snr[snr.index("Cell Usage:"):snr.index("Overview of Control Sets:")])
write("high_fanout.txt", "\n\n".join(u["section"](dmr,t) for t in ["Other High Fanout Signal:", "Clock Signal:", "Reset Signal:", "CE Signal:"]))
paths = u["paths"](snr, "synthesize/" + TOP + ".snr")
write("timing_synthesis_paths.txt", "PRE-PLACEMENT estimates only; not signoff timing.\n" + u["index_text"](paths))
write("timing_synthesis_detail.txt", "PRE-PLACEMENT estimates only. Full original path details also retained in native SNR.\n"+u["details"](sorted([p for p in paths if p["slack"] is not None], key=lambda p:p["slack"]),20))
write("timing_status.txt", "Final PnR timing, top200 routed paths, bitstream and board results: not obtained in this partial snapshot. Do not use reports remaining from an earlier run.\nThe placement/router log's integer slack values retain vendor raw units; no ns conversion inferred.")
print("VN synthesis hierarchy total:", entries[0])
print("VN synthesis path count:", len(paths))
