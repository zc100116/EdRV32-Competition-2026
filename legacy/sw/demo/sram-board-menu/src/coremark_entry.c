/* Keep the unmodified upstream CoreMark source while exposing it as a menu
 * function instead of the firmware's main entry point. */
#define main edrv32_coremark_run
#include "core_main.c"
