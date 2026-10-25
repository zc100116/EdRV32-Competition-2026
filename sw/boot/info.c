/* File: info.c
 * Spec: edrv32-soc-spec 7.5; cache-spec 2.1; sys-subsys-spec 4.6.
 * Description: Print fixed UART keys and 64-bit measurements without libc.
 * Clock domain: clk_sys.
 */
#include "info.h"
#include "sysctrl.h"
#include "uart.h"

static void number(uint64_t value, unsigned int base, unsigned int width)
{
    const char digits[] = "0123456789abcdef";
    char buffer[20];
    unsigned int length = 0u;
    do {
        buffer[length++] = digits[value % base];
        value /= base;
    } while (value != 0u);
    while (width > length) {
        uart_putc('0');
        --width;
    }
    while (length != 0u) {
        uart_putc((uint8_t)buffer[--length]);
    }
}

static void key_start(const char *key)
{
    uart_puts(key);
    uart_puts(": ");
}

void info_text(const char *key, const char *value)
{
    key_start(key);
    uart_puts(value);
    uart_puts("\r\n");
}

void info_number(const char *key, uint64_t value)
{
    key_start(key);
    number(value, 10u, 0u);
    uart_puts("\r\n");
}

void info_hex(const char *key, uint32_t value)
{
    key_start(key);
    uart_puts("0x");
    number(value, 16u, 8u);
    uart_puts("\r\n");
}

void info_ratio(const char *key, uint64_t numerator, uint64_t denominator)
{
    key_start(key);
    if (denominator == 0u) {
        /* An unobserved event has no defined rate; do not print a fabricated zero. */
        uart_puts("N/A (denominator=0)\r\n");
        return;
    }
    number(numerator / denominator, 10u, 0u);
    uart_putc('.');
    number((numerator % denominator) * 1000u / denominator, 10u, 3u);
    uart_puts("\r\n");
}

void system_info(uint32_t boot_mode)
{
    info_hex("CHIP_ID", sysctrl_read(SYSCTRL_CHIP_ID));
    info_number("CLK_SYS_HZ", sysctrl_read(SYSCTRL_CLK_SYS_HZ));
    info_number("ROM bytes", EDRV32_ROM_SIZE);
    info_number("SRAM bytes", EDRV32_SRAM_SIZE);
    info_number("I-cache bytes", SYSTEM_ICACHE_BYTES);
    info_number("D-cache bytes", SYSTEM_DCACHE_BYTES);
    info_number("MEM_READY", sysctrl_read(SYSCTRL_STATUS) & SYSCTRL_STATUS_MEM_READY);
    info_text("Boot mode", boot_mode == BOOT_MODE_UART ? "UART download" : "SRAM app");
    info_text("Build commit", BUILD_COMMIT);
    info_text("Compiler version", BUILD_COMPILER);
}
