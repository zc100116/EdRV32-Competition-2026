# R03

Two windows: 4096 load/add pairs (last value 8), then 4096 dependent mul/add pairs (last value 4097).

Run `python3 tools/cpu/b2_run.py r03` from the repository root after sourcing
`~/.local/opt/edrv32/env.sh`. See `verif/block/cpu_b2/README.md` for windows,
HPM counters, latency, logs and the C-I3 measurement scope.
