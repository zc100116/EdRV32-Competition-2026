# CoreMark compilation framework

Initialize the recorded dependency with `git submodule update --init
third_party/coremark`, then source the toolchain and run `make -C sw coremark`.
The upstream submodule remains unchanged. This port uses one context, static
work memory, volatile seeds, cycle CSR timing and the BSP HTIF console.

The compilation target is `rv32imc_zicsr/ilp32`, C11, `-Wall -Wextra -Werror`,
`-O2`, one iteration, with code/data in SRAM. The coordinator authorized compiling the unmodified third-party C files with
`-Wall -Wextra` and no `-Werror`; our BSP and port retain `-Werror`.
GCC 15.2 reports the upstream `core_list_join.c` maybe-uninitialized warning
at `-O2`; it remains visible and the dependency remains unchanged.
This target proves compilation and is not a CoreMark performance baseline.
`time_in_secs` uses the CPU specification's initial 150 MHz target; update the
port against the confirmed clock before taking or publishing measurements.
