/* File: core_portme.c
 * Spec: infra-plan I-07; cpu-spec 4 (cycle CSR)
 * Description: CoreMark seeds and cycle timing for the initial 150 MHz CPU target.
 *              Uses the BSP host console; no UART register offsets are assumed.
 * Clock domain: clk_sys.
 */
#include "coremark.h"

volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;
static CORE_TICKS start_ticks;
static CORE_TICKS stop_ticks;

static CORE_TICKS cycles(void)
{
    uint32_t high;
    uint32_t low;
    uint32_t after;
    /* RV32 needs a coherent high/low snapshot across low-half wrap. */
    do {
        __asm__ volatile ("rdcycleh %0" : "=r"(high));
        __asm__ volatile ("rdcycle %0" : "=r"(low));
        __asm__ volatile ("rdcycleh %0" : "=r"(after));
    } while (high != after);
    return ((uint64_t)high << 32) | low;
}

void start_time(void)
{
    start_ticks = cycles();
}

void stop_time(void)
{
    stop_ticks = cycles();
}

CORE_TICKS get_time(void)
{
    return stop_ticks - start_ticks;
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return (secs_ret)(ticks / 150000000u);
}

void portable_init(core_portable *port, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    port->portable_id = 1;
}

void portable_fini(core_portable *port)
{
    port->portable_id = 0;
}
