/* soc-hello: minimal SoC bring-up program.  Prints "EdRV32 SoC OK\n" through
 * UART0 TXDATA and exits by writing TOHOST (the SoC routes 0x8000_1000 to
 * DECERR; the TB watches the exit store at the core-side dmem channel). */
volatile unsigned int * const UART0_TXDATA = (volatile unsigned int *)0x40000000u;
volatile unsigned int * const UART0_CLKDIV = (volatile unsigned int *)0x40000010u;
volatile unsigned int * const UART0_CTRL   = (volatile unsigned int *)0x4000000Cu;
volatile unsigned int * const GPIO0_DIR    = (volatile unsigned int *)0x40001000u;
volatile unsigned int * const GPIO0_OUT    = (volatile unsigned int *)0x40001004u;
volatile unsigned int * const CLINT_MSIP   = (volatile unsigned int *)0x20000000u;
volatile unsigned int * const PLIC_PRIO1   = (volatile unsigned int *)0x30000004u;
volatile unsigned int * const CACHE_CTRL   = (volatile unsigned int *)0x40003000u;
volatile unsigned int * const CACHE_ADDR   = (volatile unsigned int *)0x40003004u;
volatile unsigned int * const CACHE_SIZE   = (volatile unsigned int *)0x40003008u;
volatile unsigned int * const CACHE_STATUS = (volatile unsigned int *)0x4000300Cu;
volatile unsigned int * const DDR_CANON0   = (volatile unsigned int *)0x80000020u;
volatile unsigned int * const DDR_ALIAS0   = (volatile unsigned int *)0xC0000020u;
volatile unsigned int * const DDR_CANON1   = (volatile unsigned int *)0x80000040u;
volatile unsigned int * const DDR_ALIAS1   = (volatile unsigned int *)0xC0000040u;

void putstr(const char *s)
{
    while (*s)
        *UART0_TXDATA = (unsigned int)(unsigned char)*s++;
}

int main(void)
{
    *UART0_CLKDIV = 2;          /* fast bit clock for simulation */
    *UART0_CTRL   = 1;          /* enable */

    /* Exercise one read/write path in every non-memory AXI response slot.
     * GPIO0_OUT is at addr[2]=1 and therefore also checks the upper 32-bit
     * lane of the 64-bit AXI-to-APB bridge. */
    *GPIO0_DIR = 0x0000A55Au;
    *GPIO0_OUT = 0x00005AA5u;
    if (*GPIO0_DIR != 0x0000A55Au) {
        putstr("GPIO DIR FAIL\n");
        return 1;
    }
    if (*GPIO0_OUT != 0x00005AA5u) {
        putstr("GPIO OUT FAIL\n");
        return 4;
    }

    *CLINT_MSIP = 1u;
    if ((*CLINT_MSIP & 1u) != 1u) {
        putstr("CLINT FAIL\n");
        return 2;
    }
    *CLINT_MSIP = 0u;

    *PLIC_PRIO1 = 3u;
    if (*PLIC_PRIO1 != 3u) {
        putstr("PLIC FAIL\n");
        return 3;
    }

    /* Both CPU-visible DDR windows must alias the same physical storage.
     * First verify uncached write -> cacheable refill.  Then verify the
     * write-back direction by cleaning the canonical cache line before the
     * uncached alias observes it. */
    *DDR_ALIAS0 = 0x13579BDFu;
    if (*DDR_CANON0 != 0x13579BDFu) {
        putstr("DDR A2C FAIL\n");
        return 5;
    }

    *DDR_CANON1 = 0x2468ACE0u;
    *CACHE_ADDR = (unsigned int)DDR_CANON1;
    *CACHE_SIZE = 4u;
    *CACHE_CTRL = 2u;            /* clean D-cache range */
    while ((*CACHE_STATUS & 1u) != 0u) {
        /* bounded by the simulation watchdog */
    }
    if (*DDR_ALIAS1 != 0x2468ACE0u) {
        putstr("DDR C2A FAIL\n");
        return 6;
    }

    putstr("DDR ALIAS OK\n");

    putstr("EdRV32 SoC OK\n");
    return 0;                    /* startup.S writes tohost=1 */
}
