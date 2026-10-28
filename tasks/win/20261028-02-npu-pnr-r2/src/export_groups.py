"""Export per-clock setup groups using actual PDS from/to queries."""
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import subprocess
import report_utils as u
from collect_reports import TOP, ROOT, OUT, CLOCKS


PDS = Path("G:/Program/pango/PDS_2022.2-SP6.1/bin/pds_shell.exe")
DB = ROOT / "place_route" / f"{TOP}_pnr.adf"


def base(point):
    cell = point.split(" (")[0].rsplit("/", 1)[0]
    cell = re.sub(r"/(?:opit_|gop|gateop).*", "", cell)
    if "/u_ip/" in cell:
        return cell.split("/u_ip/")[0] + "/u_ip"
    prefix, sep, leaf = cell.rpartition("/")
    gen, dot, reg = leaf.rpartition(".")
    leaf = (gen + dot if dot else "") + re.sub(r"\[\d+\]", "", reg)
    return prefix + sep + leaf


def pattern(cell):
    return cell + ("/*" if cell.endswith("/u_ip") else "*")


def requests():
    ps = u.paths(u.read(u.BUILD / f"timing_200/report_timing/{TOP}.rtr"), "global200")
    jobs = []
    for clock in CLOCKS:
        groups = defaultdict(list)
        for p in ps:
            if p["group"] == clock and p["type"].startswith("max") \
                    and p["class"] == "sequential timing path":
                groups[(base(p["start"]), base(p["end"]))].append(p)
        selected = sorted(groups.items(), key=lambda x: min(p["slack"] for p in x[1]))[:30]
        for i, ((start, end), records) in enumerate(selected, 1):
            jobs.append(dict(id=f"{clock}_{i:02}", clock=clock, start=start, end=end,
                             records=records, total_groups=len(groups)))
    return jobs


def command(job):
    return (f"report_timing -input_db_file {{{DB.as_posix()}}} -delay_type max "
            f"-max_path 1 -nworst 1 -input_pins TRUE "
            f"-from {{{pattern(job['start'])}}} -to {{{pattern(job['end'])}}} -force_to_run")


def run(job):
    work = u.BUILD / "groups" / job["id"]
    work.mkdir(parents=True, exist_ok=True)
    script = work / "export.tcl"
    u.write(script, "set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676\n"
            + command(job))
    with (work / "console.log").open("w", encoding="utf-8") as log:
        subprocess.run([str(PDS), "-file", str(script), "-work_dir", str(work),
                        "-project_name", "npu_group"], stdout=log, stderr=subprocess.STDOUT,
                       check=True)
    print(job["id"], "exported", flush=True)


def collect():
    observed = defaultdict(list)
    for p in u.paths(u.read(u.BUILD / f"timing_200/report_timing/{TOP}.rtr"), "global200"):
        if p["class"] == "sequential timing path" and p["type"].startswith("max"):
            observed[(p["group"], base(p["start"]), base(p["end"]))].append(p)
    all_index = ["clock\tgroup_sample_count\tslow_count\tfast_count"
                 "\tsample_worst_slack_ns\tstart_body\tend_body"]
    for (clock, start, end), ps in sorted(observed.items(),
            key=lambda x: (x[0][0], min(p["slack"] for p in x[1]))):
        counts = [sum(p["corner"] == corner for p in ps) for corner in ("slow", "fast")]
        all_index.append("\t".join(map(str, [clock, len(ps), *counts,
                                           min(p["slack"] for p in ps), start, end])))
    u.write(OUT / "setup_group_index.txt", "\n".join(all_index))
    lines = ["Full NPU routed setup group details.",
             "200 setup paths PER CLOCK PER CORNER; group counts refer to this sample.",
             "Register bit indices and packed opit/gop/gateop suffixes removed; "
             "generate instance indices retained. Generated IP primitives grouped by u_ip instance.",
             "At most 30 groups selected per clock, ordered by sampled worst slack.",
             "Each group has an actual PDS -from/-to query; details retain both corners.", ""]
    index = ["id\tclock\tgroup_sample_count\tslow_count\tfast_count\tcorner"
             "\tslack_ns\tlevels\tstartpoint\tendpoint"]
    for job in requests():
        root = u.BUILD / "groups" / job["id"]
        ps = u.paths(u.read(root / f"report_timing/{TOP}.rtr"), job["id"])
        seq = [p for p in ps if p["class"] == "sequential timing path"]
        counts = [sum(p["corner"] == corner for p in job["records"])
                  for corner in ("slow", "fast")]
        console = u.read(root / "console.log")
        lines += ["=" * 100, f"{job['id']}: {job['start']} -> {job['end']}",
                  f"clock={job['clock']}; sampled paths={sum(counts)}; slow={counts[0]}, "
                  f"fast={counts[1]}; observed groups in clock={job['total_groups']}",
                  "Command: " + command(job)]
        lines += [l for l in console.splitlines() if l.startswith((
            "I: The pattern", "W:", "E:", "C: Timing-4006:", "C: STA-3016:"))]
        for p in seq:
            lines += [f"Worst {p['corner']}: slack={p['slack']:.3f} ns; "
                      f"logic levels={p['levels']}", "", p["block"], ""]
            index.append("\t".join(str(v) for v in (job["id"], job["clock"], sum(counts),
                         *counts, p["corner"], p["slack"], p["levels"], p["start"], p["end"])))
    u.write(OUT / "setup_group_detail.txt", "\n".join(lines))
    u.write(OUT / "setup_group_summary.txt", "\n".join(index))


if __name__ == "__main__":
    with ThreadPoolExecutor(max_workers=4) as executor:
        list(executor.map(run, requests()))
    collect()
