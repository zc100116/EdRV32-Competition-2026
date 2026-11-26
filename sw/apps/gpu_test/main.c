/* main.c — gpu-soc 7–8; board VSync frame loop, CLINT measurement, no UART input.
 * Clock domain: clk_sys; DISP synchronizes frame delivery through plat.
 */
#include "test.h"
#include "clint.h"
#include "virtual_input.h"
uint64_t test_clock_us(void)
{
    return clint_time() / (EDRV32_CLK_SYS_HZ / 1000000);
}
uint32_t test_input_keys(void)
{
    uint32_t keys = plat_keys();
    uint16_t network = virtual_input_get().keys;
    if (network & VI_ENTER) keys |= PLAT_A;
    if (network & VI_ESC) keys |= PLAT_START;
    if (network & VI_NEXT) keys |= PLAT_RIGHT;
    if (network & VI_PREV) keys |= PLAT_LEFT;
    return keys;
}
int main(void)
{
    test_init();
    for (;;) {
        test_frame();
        plat_wait_vsync();
    }
}
