# Asynchronous RAM FIFO unit verification

Run `make smoke REGRESS_ARGS='-j 1 --path verif/unit/edrv32_async_fifo_ram'`
and the equivalent `make full` command after sourcing
`~/.local/opt/edrv32/env.sh`.

The test runs five independent FIFO/RAM instances in one simulation process,
with random clock phases and write/read frequency ratios 0.3, 0.5, 1, 2 and 3.
Depths 2, 16 and 512 exercise pointer width boundaries and the scan FIFO depth.
Each accepted output is checked against its input item number. Empty/full,
stalled-head stability, full-write blocking, RAM collision avoidance,
continuous output throughput, randomized valid/ready and reset with prefetched
data are checked. RAM payload/output registers are not initialized or reset.

See `../edrv32_sync_fifo_ram/README.md` for the complete V-P2 integration,
verification commands, synthesis references and shared filelist additions.
