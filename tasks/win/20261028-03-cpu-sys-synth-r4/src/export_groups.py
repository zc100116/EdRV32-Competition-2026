"""Export CPU r4 observed path groups and mandatory G1-G8 from routed DB."""
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import subprocess
import collect_reports as c


TOP = "edrv32_fpga_cpu_sys_top"
ROOT = c.REPO.parent / "EdRV32-FPGA/EdRV32"
OUT = c.TASK / "artifacts"
DB = ROOT / "place_route" / f"{TOP}_pnr.adf"
PDS = Path("G:/Program/pango/PDS_2022.2-SP6.1/bin/pds_shell.exe")


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
    ps = c.paths(c.read(ROOT / "report_timing" / f"{TOP}.rtr"), "native200")
    groups = defaultdict(list)
    for p in ps:
        if p["class"] == "sequential timing path" and p["type"].startswith("max"):
            groups[(base(p["start"]), base(p["end"]))].append(p)
    jobs = []
    for i, ((start, end), records) in enumerate(sorted(groups.items(),
            key=lambda x: min(p["slack"] for p in x[1]))[:30], 1):
        jobs.append(dict(id=f"T{i:02}", name=f"{start} -> {end}", start=pattern(start),
                         end=pattern(end), records=records))
    operand = "u_cpu_subsys/u_core/e_operand_a_r*"
    front = "u_cpu_subsys/u_core/u_frontend/"
    for label, start, end in (
        ("G1", operand, front + "u_predictor/ras_data_r*"),
        ("G2", operand, front + "f1_cross_target_r*"),
        ("G3", operand, front + "f1_pc_r*"),
        ("G4", "u_cpu_subsys/u_dcache/u_tag*/u_ip/*",
         front + "u_predictor/ras_data_r* " + front + "f1_pc_r*"),
        ("G5", operand, "u_cpu_subsys/u_icache/addr_r*"),
        ("G6", operand, "u_cpu_subsys/u_dcache/dirty0_r* u_cpu_subsys/u_dcache/dirty1_r*"),
        ("G7", operand, " ".join(f"u_cpu_subsys/u_dcache/u_{ram}*/u_ip/*/{pin}*"
                                  for ram in ("data", "tag") for pin in ("CEB", "ADB"))),
        ("G8", None, "u_cpu_subsys/u_core/m_result_r*"),
    ):
        jobs.append(dict(id=label, name=f"{start or 'any'} -> {end}", start=start,
                         end=end, records=[]))
    return jobs


def command(job):
    start = f" -from {{{job['start']}}}" if job["start"] else ""
    return (f"report_timing -input_db_file {{{DB.as_posix()}}} -delay_type max "
            f"-max_path 1 -nworst 1 -input_pins TRUE{start} "
            f"-to {{{job['end']}}} -force_to_run")


def run(job):
    work = c.BUILD / "groups" / job["id"]
    work.mkdir(parents=True, exist_ok=True)
    script = work / "export.tcl"
    c.write(script, "set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676\n"
            + command(job))
    with (work / "console.log").open("w", encoding="utf-8") as log:
        subprocess.run([str(PDS), "-file", str(script), "-work_dir", str(work),
                        "-project_name", "cpu_group"], stdout=log, stderr=subprocess.STDOUT,
                       check=True)
    print(job["id"], "exported", flush=True)


def group_paths(job):
    return [p for p in c.paths(c.read(c.BUILD / "groups" / job["id"] /
                                     f"report_timing/{TOP}.rtr"), job["id"])
            if p["class"] == "sequential timing path" and p["type"].startswith("max")]


def collect():
    jobs = requests()
    observed = jobs[:-8]
    observed.sort(key=lambda j: min(p["slack"] for p in group_paths(j)))
    lines = ["CPU r4 routed setup groups; 200 paths per corner (400 sampled rows).",
             "Register bit indices and packed suffixes removed; generate indices retained.",
             "IP internals are grouped by logical u_ip instance; full patterns/commands below.",
             "Observed groups sorted by filtered worst slack, followed by mandatory G1-G8.",
             "Counts refer to top200 samples, not all paths in the design.",
             "G7 reads port B: CEB*/ADB*. ADA* write-address pins are excluded.", ""]
    index = ["id\tsample_count\tslow_count\tfast_count\tcorner\tslack_ns\tlevels\tstart\tend"]
    for job in observed + jobs[-8:]:
        ps = group_paths(job)
        counts = [sum(p["corner"] == corner for p in job["records"])
                  for corner in ("slow", "fast")]
        lines += ["=" * 100, f"{job['id']}: {job['name']}",
                  f"top200 sampled paths={sum(counts)}; slow={counts[0]}, fast={counts[1]}",
                  "Command: " + command(job)]
        console = c.read(c.BUILD / "groups" / job["id"] / "console.log")
        lines += [l for l in console.splitlines() if l.startswith((
            "I: The pattern", "W:", "E:", "C: Timing-4006:", "C: STA-3016:"))]
        if not ps:
            lines += ["无此类路径。对象匹配信息见上；未将忽略过滤后的全局路径作为此组路径。"]
        for p in ps:
            lines += [f"Worst {p['corner']}: slack={p['slack']:.3f} ns; "
                      f"logic levels={p['levels']}", "", p["block"], ""]
            index.append("\t".join(str(v) for v in (job["id"], sum(counts), *counts,
                         p["corner"], p["slack"], p["levels"], p["start"], p["end"])))
    c.write(OUT / "setup_group_detail.txt", "\n".join(lines))
    c.write(OUT / "setup_group_summary.txt", "\n".join(index))


if __name__ == "__main__":
    with ThreadPoolExecutor(max_workers=4) as executor:
        list(executor.map(run, requests()))
    collect()
