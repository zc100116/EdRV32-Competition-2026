/* Keep the upstream CoreMark source unchanged and call it from the board
 * profiler after UART and HPM setup. */
#define main edrv32_coremark_run
#include "core_main.c"
