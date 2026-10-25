# Infrastructure tools

Use `. ~/.local/opt/edrv32/env.sh` before simulation, lint or software builds.

`python3 tools/regress.py smoke|full|perf` discovers `verif/**/test.yaml`.
`full` also includes smoke tests. `make smoke`, `make full` and `make lint`
are the repository entry points. Each simulator run writes `compile.log` and
`run.log` under `build/regress/<tier>/<test>/<simulator>/`. A nonzero compile or
simulation exit, timeout, missing pass token, or `FAIL` token fails the test.
The command prints per-test results and a total; an empty tier returns nonzero.

Each test directory contains `test.yaml`, `files.f` and its testbench. YAML is
restricted to one unquoted `key: value` per line, with `#` comments; all fields
below are required, and empty values are permitted where shown. Values containing
multiple words are separated by spaces; no nested YAML structures are used.

| Field | Value |
|---|---|
| `top` | Testbench top module |
| `files` | File list relative to the test directory, normally `files.f` |
| `simulator` | `verilator`, `iverilog`, or both separated by a space |
| `defines` | Space-separated `NAME` or `NAME=value`, or empty |
| `parameters` | Space-separated top-level `NAME=value`, or empty |
| `software` | Program name built by `sw/Makefile`, or empty |
| `timeout` | Maximum seconds for each compilation and simulation |
| `pass` | Required standalone pass token, normally `PASS` |
| `tier` | Space-separated membership among `smoke full perf` |

File lists use paths relative to the containing file list, `-f nested.f`,
`+incdir+path` and `+define+NAME`. Software tests receive `+ROM_HEX=`,
`+SRAM_HEX=` and `+DDR_HEX=` paths from `build/sw/<program>/`.
Testbenches print `PASS` and finish on success, or print the actual/expected
values and time and call `$fatal(1)` on failure.

`python3 tools/check/verilog_style.py rtl/` checks mechanically recognizable
language, naming and formatting rules. Structural properties such as latch
inference and multiple drivers are checked by Verilator. The existing global
build-mode header is the explicit conditional-compilation exception in
CLAUDE.md 12.2. `tools/check/lint.sh <sources or -f files.f>` runs
`verilator --lint-only -Wall`; `make lint` checks each common primitive as a top.

`test.yaml` 可选 `runner` 字段指定在仓库根目录执行的命令；回归按退出码和 `pass` 字段判定，未指定时使用常规 HDL 编译流程。
