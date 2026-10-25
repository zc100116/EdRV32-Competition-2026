# CPU pipeline smoke program

`make -C sw PROGRAM=cpu_smoke` builds the shared BSP and this program using
`program.mk`: the optional per-program makefile overrides the default ISA with
`ARCH := rv32im_zicsr`, so the same image runs with core RVC_EN=0 and 1.
The program covers integer arithmetic, branches, byte/halfword/word memory,
multiply/divide/remainder, CSR read/write and FENCE/FENCE.I; BSP reports via tohost.
