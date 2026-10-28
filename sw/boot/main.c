/* File: main.c
 * Spec: sys-subsys-spec 2.2, 2.6, 2.9; edrv32-soc-spec 7.5
 * Description: Print startup information, sample KEY1 and offer the SRAM programming BIOS.
 * Clock domain: clk_sys.
 */
#include "boot.h"
#include "cache.h"
#include "clint.h"
#include "gpio.h"
#include "info.h"
#include "sysctrl.h"
#include "uart.h"
#include "uart_input.h"

static const char logo[] =
    "\r\n"
    "  EEEEEEE   DDDD    RRRRR   V   V   3333   2222 \r\n"
    "  E         D   D   R   R   V   V      3      2 \r\n"
    "  EEEE      D   D   RRRRR    V V    3333   2222 \r\n"
    "  E         D   D   R  R     V V       3   2    \r\n"
    "  EEEEEEE   DDDD    R    R    V     3333   2222 \r\n"
    "\r\n  EdRV32 Boot ROM - UART 115200 8N1\r\n";

static void program_sram(struct uart_input *input)
{
    uint32_t length = 0u;
    volatile uint8_t *destination = (volatile uint8_t *)EDRV32_SRAM_BASE;
    uart_puts("UART download ready\r\n");
    uart_drain();
    uart_input_binary_begin(input);
    for (unsigned int byte = 0u; byte < 4u; ++byte) {
        length |= (uint32_t)uart_getc() << (8u * byte);
    }
    if (length == 0u || length > EDRV32_SRAM_SIZE - BOOT_STACK_BYTES) {
        uart_puts("Program SRAM result: FAIL length\r\n");
        return;
    }
    for (uint32_t byte = 0u; byte < length; ++byte) {
        destination[byte] = uart_getc();
    }
    cache_clean_all();
    info_number("Program SRAM bytes", length);
    uart_puts("Program SRAM result: PASS, press reset to run\r\n");
}

static _Noreturn void bios(void)
{
    struct uart_input input = {0u};
    uart_puts("BIOS: EdRV32\r\n");
    for (;;) {
        uart_puts("BIOS menu: 1=Program SRAM\r\n");
        if (uart_read_selection(&input) == '1') {
            program_sram(&input);
        } else {
            uart_puts("Input error: type 1 then Enter\r\n");
        }
    }
}

int main(void)
{
    uart_init();
    uart_set_baud(sysctrl_read(SYSCTRL_CLK_SYS_HZ), 115200u);
    gpio_set_output_enable(0u);
    uart_puts(logo);
    while ((sysctrl_read(SYSCTRL_STATUS) & SYSCTRL_STATUS_MEM_READY) == 0u) {
    }
    system_info();
    uint32_t scratch = sysctrl_read(SYSCTRL_SCRATCH0);
    sysctrl_write(SYSCTRL_SCRATCH0, 0u);
    uint32_t released = 0u;
    uint64_t start = clint_time();
    uint64_t window = (uint64_t)sysctrl_read(SYSCTRL_CLK_SYS_HZ) *
                      BOOT_BUTTON_WINDOW_MS / 1000u;
    do {
        released |= gpio_read() & (1u << BOOT_BUTTON_BIT);
    } while (clint_time() - start < window);
    if (boot_download_requested(released, scratch)) {
        bios();
    }
    uart_puts("Boot SRAM\r\n");
    uart_drain();
    boot_enter(EDRV32_SRAM_BASE);
}
