# B2 connection smoke

Run `. ~/.local/opt/edrv32/env.sh`, then:

```sh
python3 tools/regress.py smoke --path verif/soc/soc_connect -j 1
```

`run.py` builds both images using `sw/Makefile` and converts its byte images into
the 64-bit words expected by the ROM/SRAM wrappers. `reset_entry.S` and `boot.c`
start at the ROM reset vector and jump to the generated SRAM base. `main.c`
checks APB IDs and reserved-slot access faults, cached/uncached DDR aliases,
P2 directional snapshots, and GEO DONE through PLIC to CPU MEIP. The descriptor
has an empty output rectangle, as allowed by GEO 2.3; it completes normally under
GEO 5.1. The trap handler checks `mcause`, `mtval` and PLIC claim results.

The test ends only after software writes SYSCTRL SIM_EXIT. UART bytes and
the result go to `build/soc_connect/run.log`; compiler, lint and build logs are
in the same directory. Regression-level output is under
`build/regress/smoke/soc/soc_connect/verilator/`.

The first run compiles the complete SoC. With the compiled simulator available,
the checked run took 13 seconds including software rebuild and lint; simulation
took 4.460 seconds. The smoke concerns wiring and register connectivity;
module-level functional coverage remains with the existing engine tests.
