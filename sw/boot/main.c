/* File: main.c
 * Spec: sys-subsys-spec 2.2, 2.6, 2.9; edrv32-soc-spec 7.5
 * Description: Print the ROM banner, select UART download or enter preloaded SRAM.
 * Clock domain: clk_sys.
 */
#include "boot.h"
#include "gpio.h"
#include "info.h"
#include "sysctrl.h"
#include "uart.h"

static const char logo[] =
    "\r\n"
    "  EEEEEEE   DDDD    RRRRR   V   V   3333   2222 \r\n"
    "  E         D   D   R   R   V   V      3      2 \r\n"
    "  EEEE      D   D   RRRRR    V V    3333   2222 \r\n"
    "  E         D   D   R  R     V V       3   2    \r\n"
    "  EEEEEEE   DDDD    R    R    V     3333   2222 \r\n"
    "\r\n  EdRV32 Boot ROM - UART 115200 8N1\r\n";

int main(void)
{
    uart_init();
    uart_set_baud(sysctrl_read(SYSCTRL_CLK_SYS_HZ), 115200u);
    gpio_set_output_enable(0u);
    uart_puts(logo);
    while ((sysctrl_read(SYSCTRL_STATUS) & SYSCTRL_STATUS_MEM_READY) == 0u) {
    }
    uint32_t mode = boot_download_requested(gpio_read(), sysctrl_read(SYSCTRL_SCRATCH0))
                    ? BOOT_MODE_UART : BOOT_MODE_SRAM;
    system_info(mode);
    if (mode == BOOT_MODE_UART) {
        uint32_t length = 0u;
        volatile uint8_t *destination = (volatile uint8_t *)EDRV32_SRAM_BASE;
        sysctrl_write(SYSCTRL_SCRATCH0, 0u);
        uart_puts("UART download ready\r\n");
        for (unsigned int byte = 0u; byte < 4u; ++byte) {
            length |= (uint32_t)uart_getc() << (8u * byte);
        }
        for (uint32_t byte = 0u; byte < length; ++byte) {
            destination[byte] = uart_getc();
        }
        uart_puts("UART download complete\r\n");
    }
    sysctrl_write(SYSCTRL_SCRATCH1, mode);
    uart_puts("Boot SRAM\r\n");
    uart_drain();
    boot_enter(EDRV32_SRAM_BASE);
}
