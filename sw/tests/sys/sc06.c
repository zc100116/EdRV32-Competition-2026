/* File: sc06.c
 * Spec: sys-subsys-testplan 3.6 SC-06; edrv32-soc-spec 7.4
 * Description: Check both DDR aliases after the required cache maintenance.
 * Clock domain: clk_sys.
 */
#include "cache.h"
#include "sc.h"

#define SC_DDR_OFFSET 0x1000u
#define SC_DDR_WORDS 16u

int main(void)
{
    volatile uint32_t *cached = (volatile uint32_t *)(EDRV32_DDR_BASE + SC_DDR_OFFSET);
    volatile uint32_t *uncached =
        (volatile uint32_t *)(EDRV32_DDR_UNCACHED_BASE + SC_DDR_OFFSET);
    for (unsigned int index = 0u; index < SC_DDR_WORDS; ++index) {
        cached[index] = 0x12340000u + index;
    }
    cache_clean((uintptr_t)cached, SC_DDR_WORDS * sizeof(uint32_t));
    for (unsigned int index = 0u; index < SC_DDR_WORDS; ++index) {
        if (uncached[index] != 0x12340000u + index) {
            sc_finish(0x60u + index);
        }
        uncached[index] = 0xabcd0000u + index;
    }
    cache_invalidate((uintptr_t)cached, SC_DDR_WORDS * sizeof(uint32_t));
    for (unsigned int index = 0u; index < SC_DDR_WORDS; ++index) {
        if (cached[index] != 0xabcd0000u + index) {
            sc_finish(0x70u + index);
        }
    }
    sc_finish(0u);
}
