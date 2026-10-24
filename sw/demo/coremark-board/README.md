# PG2L200H CoreMark profiler

This is the fixed `coremark-hpm-v1` board baseline. It boots from ROM and
runs the same 4000-iteration CoreMark workload three times from the 32 KiB
cached SRAM. UART0 at 115200 baud reports the CoreMark validation, timing,
and every platform HPM event ID 1..98 when rebuilt from current sources.
There is no test menu. The checked-in `build/` and `baseline/v1/` images
remain the original 1..83 firmware until the Linux build below is run.

The first run after reset is the **baseline score**. Its 40 physical HPM
counters observe events 1..40. Run 2 observes events 41..80; run 3 observes
events 81..98, with the other 22 selectors disabled. Each run prints its own
cycles and retired instructions so differences between runs remain visible.
Only compare HPM values from runs with comparable cycles and instret.
The exact GCC 15.2.0 baseline ELF, map, disassembly, and memory images are
preserved in `baseline/v1/`. Future CPU RTL comparisons should use those
images unchanged; if the software changes, give it a new baseline version.

Build on the Linux VM with xPack RISC-V GCC 15.2.0:

```sh
cd ~/File/EdRV32-Competition-2026
make sw-build CASE=demo/coremark-board \
  RISCV_PREFIX="$HOME/.local/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-"
```

`build/bootrom.hex` and `build/sram.hex` are 64-bit memory images. Copy them
to `fpga/pango_200h/edrv32_soc_coremark/bootrom.dat` and `sram.dat`, regenerate
the Boot ROM and SRAM IP, then run the FPGA implementation flow.

For each run, HPM selectors and 64-bit counters are configured and cleared
before CoreMark starts. Two inlined CSR writes enable HPM, then the initial
`minstret` snapshot occurs before the initial `mcycle` read. The final
`mcycle` read closes the CoreMark timing window; the final `minstret` read,
HPM disable, CRC validation, UART output, and 80 CSR reads all occur
afterwards. Disassembly confirms that `start_time` and `stop_time` are leaf
functions with no HPM-induced stack save/restore in the timed window.
Counter-control and counter-read overhead therefore does not enter the
CoreMark score. The timer boundary still includes the normal
`start_time` return, `stop_time` call, and two `mcycle` reads.

HPM values are printed as 64-bit hexadecimal. Event 40 counts empty-retire
cycles in run 1. Events 41..56 partition those cycles in run 2, but a direct
equality check spans separate runs and is subject to their measured cycle
differences and the few boundary cycles outside the `mcycle` window. Events
outside 41..56 may overlap one another, so their values must not be summed
as independent cycle costs. Event names and exact definitions are in
`rtl/include/edrv32_hpm.vh` and `rtl/cpu/core/edrv32_core.v`.

The upstream CoreMark source reports `Correct operation validated` when
its CRC checks pass. `ROUND_END` means a run finished; it is not a substitute
for the CoreMark validation line.
