"""Export actual filtered CPU paths from the existing routed database."""
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import subprocess
import collect_reports as c


PDS = Path("G:/Program/pango/PDS_2022.2-SP6.1/bin/pds_shell.exe")
TOP = "edrv32_fpga_cpu_sys_top"
DB = c.REPO.parent / "EdRV32-FPGA/EdRV32/place_route" / f"{TOP}_pnr.adf"


def base(point):
    cell = point.split(" (")[0].rsplit("/", 1)[0]
    cell = re.sub(r"/(?:opit_|gop).*", "", cell)
    return re.sub(r"\[\d+\]", "", cell)


def pattern(cell):
    # Query the enclosing IP instance: packed primitive suffixes printed by STA
    # are not accepted as instance names by PDS's report filter.
    if "/u_ip/" in cell:
        return cell.split("/u_ip/")[0] + "/u_ip/*"
    return cell.removesuffix("/gateop_perm") + "*"


def requests():
    records = c.paths(c.read(c.BUILD / f"timing_cpu_200/report_timing/{TOP}.rtr"),
                      "global200")
    groups = defaultdict(list)
    for p in records:
        if p["class"] == "sequential timing path" and p["type"].startswith("max"):
            groups[(base(p["start"]), base(p["end"]))].append(p)
    selected = sorted(groups.items(), key=lambda x: min(p["slack"] for p in x[1]))[:30]
    jobs = []
    for i, ((start, end), ps) in enumerate(selected, 1):
        jobs.append(dict(id=f"T{i:02}", name=f"{start} -> {end}",
                         start=pattern(start), end=pattern(end), records=ps))
    for label, start, end in (
        ("G1", "u_cpu_subsys/u_dcache/addr_r*", "u_cpu_subsys/u_core/u_csr/counter_r*"),
        ("G2", "u_cpu_subsys/u_core/e_operand_a_r*", "u_cpu_subsys/u_core/u_frontend/u_predictor/ras_data_r*"),
        ("G3", "u_cpu_subsys/u_core/u_frontend/f2_pc_r*", "u_cpu_subsys/u_core/u_frontend/u_predictor/ras_data_r*"),
        ("G4", "u_cpu_subsys/u_core/e_operand_a_r*", "u_cpu_subsys/u_core/u_frontend/f1_pc_r*"),
        ("G5", "u_cpu_subsys/u_core/u_frontend/f2_pc_r*", "u_cpu_subsys/u_core/u_frontend/u_ib/entries_r*"),
        ("G6", None, "u_cpu_subsys/u_icache/u_data*/u_ip/*/CEB* u_cpu_subsys/u_icache/u_data*/u_ip/*/ADB*"),
    ):
        jobs.append(dict(id=label, name=f"{start or 'any'} -> {end}",
                         start=start, end=end, records=[]))
    return jobs


def command(job):
    filters = (f" -from {{{job['start']}}}" if job["start"] else "")
    return (f"report_timing -input_db_file {{{DB.as_posix()}}} -delay_type max "
            f"-max_path 1 -nworst 1 -input_pins TRUE{filters} "
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


def collect():
    lines = ["CPU r3 filtered setup path details (routed database).",
             "Global top200 is 200 paths PER CORNER; group counts below use those 400 rows.",
             "Grouping removes register bit indices and packed opit_/gop suffixes.",
             "17 observed groups (slow: 10, fast: 7), plus mandatory G1-G6.",
             "Observed groups below are sorted by the worst slack in their filtered exports.",
             "Each command exports one path per corner; full slow/fast details are retained.",
             "Group counts are top200 sample counts, not all design paths.", ""]
    lines += ["G6: PDS packed read-port address pins are ADB* (port B), read enable CEB*;",
              "the source-level read address is rd_addr/ADDRB, not the packed write-port ADA*.", ""]
    index = ["id\tgroup\ttop200_slow_count\ttop200_fast_count\tcorner\tslack_ns"
             "\tlevels\tstart\tend"]
    jobs = requests()
    def worst(job):
        ps = c.paths(c.read(c.BUILD / "groups" / job["id"] /
                            f"report_timing/{TOP}.rtr"), job["id"])
        return min(p["slack"] for p in ps if p["class"] == "sequential timing path")
    for job in sorted(jobs[:-6], key=worst) + jobs[-6:]:
        root = c.BUILD / "groups" / job["id"]
        exported = c.paths(c.read(root / f"report_timing/{TOP}.rtr"), job["id"])
        selected = [p for p in exported if p["type"].startswith("max")
                    and p["class"] == "sequential timing path"]
        slow_n = sum(p["corner"] == "slow" for p in job["records"])
        fast_n = sum(p["corner"] == "fast" for p in job["records"])
        count = (f"top200 paths: slow={slow_n}, fast={fast_n}" if job["records"]
                 else "Mandatory group; no top200 sample count assigned.")
        lines += ["=" * 100, f"{job['id']}: {job['name']}", count,
                  "Command: " + command(job),
                  f"Local export: {root.as_posix()}"]
        console = c.read(root / "console.log")
        lines += [l for l in console.splitlines() if
                  l.startswith(("I: The pattern", "W:", "E:", "C: Timing-4006:",
                                "C: STA-3016:", "Report timing is finished"))]
        if not selected:
            lines += ["无此类路径。见以上命令、对象匹配信息；没有将未匹配对象当作有效路径。"]
        for p in selected:
            lines += [f"Worst {p['corner']}: slack={p['slack']:.3f} ns; "
                      f"logic levels={p['levels']}", "", p["block"], ""]
            index.append("\t".join(str(v) for v in (job["id"], job["name"], slow_n,
                         fast_n, p["corner"], p["slack"], p["levels"], p["start"], p["end"])))
    c.write(c.TASK / "artifacts/cpu/setup_group_detail.txt", "\n".join(lines))
    c.write(c.TASK / "artifacts/cpu/setup_group_summary.txt", "\n".join(index))


if __name__ == "__main__":
    jobs = requests()
    with ThreadPoolExecutor(max_workers=3) as executor:
        list(executor.map(run, jobs))
    collect()
