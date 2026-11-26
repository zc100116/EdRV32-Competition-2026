/* main.c — gpu-soc 7–8; board VSync frame loop, CLINT measurement, no UART input.
 * Clock domain: clk_sys; DISP synchronizes frame delivery through plat.
 */
#include "test.h"
#include "clint.h"
uint64_t test_clock_us(void)
{
    return clint_time() / (EDRV32_CLK_SYS_HZ / 1000000);
}
int main(void)
{
    test_init();
    for (;;) {
        test_frame();
        plat_wait_vsync();
    }
}
