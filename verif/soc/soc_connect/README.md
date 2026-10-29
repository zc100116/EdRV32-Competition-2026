# SoC connection smoke (B2-1a, R-S2)

Run `. ~/.local/opt/edrv32/env.sh`, then:

```sh
python3 tools/regress.py smoke --path verif/soc/soc_connect -j 1
```

`run.py` builds both images using `sw/Makefile` and converts its byte images into
the 64-bit words expected by the ROM/SRAM wrappers. `reset_entry.S` and `boot.c`
start at the ROM reset vector and jump to the generated SRAM base. `main.c`
checks APB IDs and reserved-slot access faults, cached/uncached DDR aliases,
P2 directional snapshots, and GEO/RND DONE through PLIC to CPU MEIP. The GEO descriptor
has an empty output rectangle, as allowed by GEO 2.3; it completes normally under
GEO 5.1. The trap handler checks `mcause`, `mtval` and PLIC claim results.

R-S2 checks media slot 4's RND ID (`0x0004_0001`) and submits one opaque 8×8
ARGB8888 FILL (`rnd-spec` 2.5–2.6). The 64-byte command is at DDR physical
`0xc000`, and its destination is at `0xd000` with a 32-byte stride. Software
initializes the destination to zero through the uncached alias, then verifies
exactly one DONE interrupt claimed as PLIC source 11, `IRQ_STAT == DONE`,
`DONE_COUNT == 1`, and all 64 destination pixels equal `0xff123456`.

The test ends only after software writes SYSCTRL SIM_EXIT. UART bytes and
the result go to `build/soc_connect/run.log`; compiler, lint and build logs are
in the same directory. Regression-level output is under
`build/regress/smoke/soc/soc_connect/verilator/`.

The first run compiles the complete SoC. The runner prints the simulation elapsed
time after completion. The smoke concerns wiring and register connectivity;
module-level functional coverage remains with the existing engine tests.
