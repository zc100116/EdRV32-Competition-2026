# R04

Taken branch stream: 256 iterations through 256 distinct eight-byte branch blocks. Direct-mapped BTB replacement prevents a stable hit; the skipped accumulator must remain zero.

Run `python3 tools/cpu/b2_run.py r04` from the repository root after sourcing
`~/.local/opt/edrv32/env.sh`. See `verif/block/cpu_b2/README.md` for windows,
HPM counters, latency, logs and the C-I3 measurement scope.
