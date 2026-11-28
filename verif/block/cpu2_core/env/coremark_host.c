/* File: coremark_host.c; Spec: cpu-v2-testplan CV15; Clock: clk_sys.
 * Console uses the B2 verification device; tohost reports main's return status.
 */
#include "edrv32.h"
extern volatile uint32_t cpu2_console;
volatile uint64_t tohost __attribute__((section(".tohost"), aligned(64))) = 0;
void edrv32_putchar(char value)
{
    cpu2_console = (unsigned char)value;
}
_Noreturn void edrv32_exit(int status)
{
    __asm__ volatile ("fence rw, rw" ::: "memory");
    tohost = ((uint64_t)(uint32_t)status << 1) | 1;
    for (;;) {
        __asm__ volatile ("wfi");
    }
}
