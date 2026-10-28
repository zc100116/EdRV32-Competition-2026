"""Prepare isolated PDS command-line projects for P1/P2/P3."""
from pathlib import Path
import sys
import tkinter


REPO = Path(__file__).resolve().parents[4]
TASK = REPO / "tasks/win/20261028-04-media-cpu-probes"
BUILD = REPO / "build/win/20261028-04-media-cpu-probes/cpu"
CPU = REPO.parent / "EdRV32-FPGA/EdRV32"
TOP = "edrv32_fpga_cpu_sys_top"


def quote(path):
    return "{" + str(path).replace("\\", "/") + "}"


def main():
    for version in sys.argv[1:] or ("p1", "p2", "p3"):
        t = tkinter.Tcl()
        t.eval("proc add_design {p} {lappend ::designs $p}")
        t.eval("proc add_constraint {p} {lappend ::constraints $p}")
        t.eval("proc compile {args} {set ::compile_args $args}")
        t.call("cd", CPU.as_posix())
        t.setvar("edrv32_probe", version.split("_")[0])
        t.call("source", (TASK / "src/import_cpu_probe.tcl").as_posix())
        sources = [str(p) for p in t.splitlist(t.getvar("designs"))]
        constraints = [str(p) for p in t.splitlist(t.getvar("constraints"))]
        if version != "p1":
            constraints[-1] = (TASK / "artifacts/cpu" / version / "fdc_used.fdc").as_posix()
        # Resolve using the actual FPGA project directory, then use absolute
        # resolved arguments in the separate build directories.
        for path in sources + constraints:
            Path(path).stat()
        for path in t.splitlist(t.getvar("edrv32_include_dirs")):
            Path(str(path)).stat()
        work = BUILD / version
        work.mkdir(parents=True, exist_ok=True)
        commands = ["set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676"]
        commands += ["add_design " + quote(p) for p in sorted((CPU / "ipcore").glob("*/*.idf"))]
        commands += ["add_design " + quote(p) for p in sources]
        commands += ["add_constraint " + quote(p) for p in constraints]
        commands += ["compile " + t.call("format", "%s", t.getvar("compile_args")) + " -force_to_run",
                     "synthesize -ads -force_to_run", "dev_map -force_to_run", "pnr -force_to_run",
                     "report_timing -max_path 200 -nworst 1 -input_pins TRUE -force_to_run"]
        (work / "run.tcl").write_text("\n".join(commands) + "\n", encoding="utf-8")
        print(version, "prepared:", len(sources), "sources;", len(constraints), "constraints", flush=True)


if __name__ == "__main__":
    main()
