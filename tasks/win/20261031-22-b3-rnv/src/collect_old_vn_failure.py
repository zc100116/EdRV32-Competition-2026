"""Collect the old card21 VN failure, preserving large raw router dumps locally."""
from pathlib import Path
from collections import Counter
import re, runpy, shutil
R = Path(__file__).resolve().parents[4]
O = R / "tasks/win/20261031-22-b3-rnv/artifacts/b3vn_card21_failure"
P = R.parent / "EdRV32-FPGA/EdRV32-B3VN"
TOP = "edrv32_fpga_board_vnpu_top"
u = runpy.run_path(str(R / "tasks/win/20261028-03-cpu-sys-synth-r4/src/collect_reports.py"))
def write(name, text):
    p = O / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text.rstrip() + "\n", encoding="utf-8")
flow = []
for stage, ext in [("compile", ".cmr"), ("synthesize", ".snr"), ("device_map", ".dmr"), ("place_route", ".prr")]:
    lines = (P / stage / "run.log").read_text(errors="replace").splitlines()
    warning = [l for l in lines if l.startswith("W:")]
    error = [l for l in lines if l.startswith("E:")]
    flow += [stage, f"Warnings={len(warning)} Errors={len(error)}", str(Counter(u["warning_category"](l) for l in warning))]+[l for l in lines if l.startswith("Action ")]+[""]
    prefixes = ("W:", "E:", "Action ", "Current time:", "Finished ", "Worst slack", "Unrouted ", "Total ", "Routing ", "Placement ", "Route thread", "Pre route", "Timing-driven")
    write(f"logs/{stage}_excerpt.txt", "\n".join(l for l in lines if l.startswith(prefixes)))
    dst = O / "native_reports" / stage / (TOP + ext)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(P / stage / (TOP + ext), dst)
    if stage == "place_route":
        write("routing_progress.txt", "FAILED ROUTE, old card21 VN; not the new card22 V.\n"+"\n".join(l for l in lines if l.startswith(prefixes)))
write("flow_summary.txt", "\n".join(flow))
snr = (P / "synthesize" / (TOP + ".snr")).read_text(errors="replace")
dmr = (P / "device_map" / (TOP + ".dmr")).read_text(errors="replace")
prr = (P / "place_route" / (TOP + ".prr")).read_text(errors="replace")
hierarchy, entries = u["hierarchy"](snr)
write("resource_hier.txt", "SYNTHESIS hierarchy, not successfully routed usage.\n"+hierarchy)
write("resource_summary.txt", "FAILED PnR resource snapshot:\n"+u["section"](prr,"Device Utilization Summary :")+"\nDevice Map:\n"+u["section"](dmr,"Device Utilization Summary:")+"\nSynthesis:\n"+snr[snr.index("Cell Usage:"):snr.index("Overview of Control Sets:")])
write("high_fanout.txt", "\n\n".join(u["section"](dmr,t) for t in ["Other High Fanout Signal:","Clock Signal:","Reset Signal:","CE Signal:"]))
paths = u["paths"](snr, "native_reports/synthesize/"+TOP+".snr")
write("timing_synthesis_paths.tsv", "PRE-PLACEMENT estimates; no routed timing available for this failed run.\n"+u["index_text"](paths))
source = P / "place_route/fail_route_nets.txt"
records, current, samples = [], None, []
with source.open(errors="replace") as f:
    for line in f:
        if line.startswith("design net:"):
            if current is not None:
                records.append(current)
            current = {"name":line.split(":",1)[1].strip(), "driver":"", "loads":0,"unrouted":0}
        if current is None:
            continue
        if line.startswith("driver:") and not current["driver"]:
            current["driver"] = line.split(":",1)[1].strip()
        if line.startswith("loads:"):
            current["loads"] = int(line.split(":",1)[1])
        if line.startswith("un-routed loads:"):
            current["unrouted"] = int(line.split(":",1)[1])
        if len(records)<3 and len(samples)<900:
            samples.append(line.rstrip())
    if current is not None:
        records.append(current)
ranked = sorted(records,key=lambda x:(x["unrouted"],x["loads"]),reverse=True)
write("failed_nets_top200.tsv", "net\tdriver (vendor TX/TY coordinates)\tloads\tunrouted_loads\n"+"\n".join(f'{x["name"]}\t{x["driver"]}\t{x["loads"]}\t{x["unrouted"]}' for x in ranked[:200]))
write("failed_nets_samples.txt", "First 3 network blocks, capped at 900 lines; full dump retained locally.\n"+"\n".join(samples))
write("failed_nets_summary.txt", f"Local raw source: {source}\nRaw file bytes: {source.stat().st_size}\nNetwork blocks: {len(records)}\nSum of listed loads: {sum(x['loads'] for x in records)}\nSum of listed un-routed loads: {sum(x['unrouted'] for x in records)}\nMax un-routed loads in one listed net: {max(x['unrouted'] for x in records)}\nCounts describe dump contents; do not equate them with router iteration counts without vendor documentation.\nPhysical routing net names and sites cannot identify owning RTL modules directly.\n")
write("status.txt", "Old card21 VN routing FAILED: Route-0039 congestion / iteration time exceeds 2000 sec; Route-0008 cannot route.\nPnR wall time 3h26m11s; CPU 17m41s; process CPU 19m27s; peak memory pool 6618 MB.\nNo successful routed DB or final timing/bitstream from this attempt. Do not use older report_timing/generate_bitstream leftovers.\nLarge fail_route_nets.txt and *_fail_pnr.adf / partial_route.adf remain in the local project.\n")
print("old VN failure nets",len(records),"listed unrouted loads",sum(x['unrouted'] for x in records))
