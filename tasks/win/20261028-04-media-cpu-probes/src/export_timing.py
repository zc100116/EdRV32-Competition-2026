"""Export additional timing reports from the existing routed databases."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parents[4]
BUILD = REPO / "build/win/20261028-04-media-cpu-probes"
PDS = Path("G:/Program/pango/PDS_2022.2-SP6.1/bin/pds_shell.exe")
CPU_TOP = "edrv32_fpga_cpu_sys_top"
MEDIA_TOP = "edrv32_fpga_media_top"
MEDIA = REPO.parent / "EdRV32-FPGA/EdRV32-MEDIA"


def export(job):
    name, db, options = job
    work = BUILD / "exports" / name
    work.mkdir(parents=True, exist_ok=True)
    command = (f"report_timing -input_db_file {{{db.as_posix()}}} "
               f"{options} -nworst 1 -force_to_run")
    script = work / "export.tcl"
    script.write_text("set_arch -family Logos2 -device PG2L200H -speedgrade -6 "
                      "-package FBB676\n" + command + "\n", encoding="utf-8")
    with (work / "console.log").open("w", encoding="utf-8") as log:
        result = subprocess.run([str(PDS), "-file", str(script), "-work_dir", str(work),
                                 "-project_name", name], cwd=work, stdout=log,
                                stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    print(name, "exit", result.returncode, flush=True)
    result.check_returncode()


if __name__ == "__main__":
    jobs = []
    for version in ("p1", "p2", "p3_noregion"):
        db = BUILD / "cpu" / version / "place_route" / f"{CPU_TOP}_pnr.adf"
        if version == "p1":
            jobs.append((version + "_top200", db, "-max_path 200 -input_pins TRUE"))
        else:
            jobs.append((version + "_violating", db,
                         "-delay_type max -max_path 100000 -slack_less_than 0 -input_pins FALSE"))
        jobs.append((version + "_near", db,
                     "-delay_type max -max_path 200 -slack_greater_than 0 "
                     "-slack_less_than 1 -input_pins TRUE"))
    db = MEDIA / "place_route" / f"{MEDIA_TOP}_pnr.adf"
    jobs += [("media_top200", db, "-max_path 200 -input_pins TRUE"),
             ("media_near", db, "-delay_type max -max_path 200 -slack_greater_than 0 "
              "-slack_less_than 1 -input_pins TRUE"),
             ("media_disp", db, "-delay_type max -max_path 200 -to {u_disp/*} -input_pins TRUE")]
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(export, jobs))
