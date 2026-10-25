/* File: host.c
 * Spec: cpu-testplan 2.2, 3.8; CLAUDE.md 9.2.
 * Description: B2 console uses an uncached test device instead of cached HTIF.
 *              The testbench observes committed tohost stores for exit.
 * Clock domain: clk_sys.
 */
#include "edrv32.h"

extern volatile uint32_t b2_console;
volatile uint64_t tohost __attribute__((section(".tohost"), aligned(64))) = 0;

void edrv32_putchar(char value)
{
    b2_console = (unsigned char)value;
}

_Noreturn void edrv32_exit(int status)
{
    __asm__ volatile ("fence rw, rw" ::: "memory");
    tohost = ((uint64_t)(uint32_t)status << 1) | 1;
    for (;;) {
        __asm__ volatile ("wfi");
    }
}

int __real_main(void);
int __wrap_main(void)
{
    /* The other eight events are observed in parallel by the B2 testbench. */
    __asm__ volatile (
        "csrwi 0x323, 1\ncsrwi 0x324, 2\ncsrwi 0x325, 3\ncsrwi 0x326, 4\n"
        "csrwi 0x327, 5\ncsrwi 0x328, 6\ncsrwi 0x329, 7\ncsrwi 0x32a, 8"
        ::: "memory");
    return __real_main();
}
