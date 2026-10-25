# CoreMark compilation framework

Initialize the recorded dependency with `git submodule update --init
third_party/coremark`, then source the toolchain and run `make -C sw coremark`.
The upstream submodule remains unchanged. This port uses one context, static
work memory, volatile seeds, cycle CSR timing and the BSP HTIF console.

The compilation target is `rv32imc_zicsr/ilp32`, C11, `-Wall -Wextra -Werror`,
`-O0`, one iteration, with code/data in SRAM. GCC 15.2 diagnoses an upstream
`core_list_join.c` maybe-uninitialized value with `-O2 -Werror`; this framework
uses `-O0` so the unmodified dependency compiles with all requested warnings.
This target proves compilation and is not a CoreMark performance baseline.
`time_in_secs` uses the CPU specification's initial 150 MHz target; update the
port against the confirmed clock before taking or publishing measurements.
