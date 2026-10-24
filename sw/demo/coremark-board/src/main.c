/* Fixed board CoreMark baseline with a complete three-pass HPM sweep. */
#include "edrv32_uart.h"
#include "hpm_profile.h"

#define SOC_CLOCK_HZ 100000000u
#define UART_BAUD    115200u

int edrv32_coremark_run(void);

int main(void)
{
    unsigned int round;

    edrv32_uart_init(EDRV32_UART_DIVISOR(SOC_CLOCK_HZ, UART_BAUD));
    edrv32_uart_puts("\n[COREMARK] baseline v1, GCC 15.2.0, 4000 iterations\n");
    for (round = 0u; round < HPM_ROUND_COUNT; round++) {
        hpm_prepare(round);
        if (round == 0u)
            edrv32_uart_puts("[COREMARK] ROUND 1/3 events 1-40 BASELINE\n");
        else if (round == 1u)
            edrv32_uart_puts("[COREMARK] ROUND 2/3 events 41-80\n");
        else
            edrv32_uart_puts("[COREMARK] ROUND 3/3 events 81-98\n");
        (void)edrv32_coremark_run();
        edrv32_uart_puts("[COREMARK] ROUND_END\n");
    }
    edrv32_uart_puts("[COREMARK] ALL_ROUNDS_COMPLETE\n");
    (void)edrv32_uart_flush_timeout(SOC_CLOCK_HZ);

    for (;;) {
        __asm__ __volatile__("wfi");
    }
}
