# GPU DISP regression

`python3 tools/regress.py full --path verif/block/disp_gpu -j 1`

ST-04 retains the native L0 raster, TMDS, DMA, stop/reset, handoff and underflow
cases. ST-05 compares every received X2 pixel and exact AXI address/length with
nonzero scroll. ST-06 switches X2 between frames, injects read starvation, and
checks debt repayment and alignment. ST-07 checks the exact 39/40-beat urgent
boundary and line reservation. L1/alpha composition tests have been removed;
`verif/unit/disp_regs_gpu` checks that removed addresses ignore writes/read zero
and SWITCH1 remains zero.

`run.py full --parallel N` compiles each top once with `-j 1` and runs independent
cases concurrently. Smoke runs ST-05; full additionally runs the native L0 cases,
ST-06 and ST-07.
