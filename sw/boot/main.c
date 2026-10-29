/* File: main.c
 * Spec: sys-subsys-spec 2.2, 2.6, 2.9; edrv32-soc-spec 7.5
 * Description: Print startup information, sample KEY1 and offer the load/run/baud BIOS.
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

static uint32_t read_binary_word(void)
{
    uint32_t value = 0u;
    for (unsigned int byte = 0u; byte < 4u; ++byte) {
        value |= (uint32_t)uart_getc() << (8u * byte);
    }
    return value;
}

static void receive_data(uint32_t address, uint32_t length)
{
    volatile uint8_t *destination = (volatile uint8_t *)(uintptr_t)address;
    for (uint32_t byte = 0u; byte < length; ++byte) {
        destination[byte] = uart_getc();
    }
    cache_clean_all();
}

static void program_sram(struct uart_input *input)
{
    uart_puts("UART download ready\r\n");
    uart_drain();
    uart_input_binary_begin(input);
    uint32_t length = read_binary_word();
    if (length == 0u || length > EDRV32_SRAM_SIZE - BOOT_STACK_BYTES) {
        uart_puts("Program SRAM result: FAIL length\r\n");
        return;
    }
    receive_data(EDRV32_SRAM_BASE, length);
    info_number("Program SRAM bytes", length);
    uart_puts("Program SRAM result: PASS, press reset to run\r\n");
}

static void load(struct uart_input *input)
{
    uart_puts("UART load ready\r\n");
    uart_drain();
    uart_input_binary_begin(input);
    uint32_t address = read_binary_word();
    uint32_t length = read_binary_word();
    if (!boot_load_range(address, length)) {
        uart_puts("Load result: FAIL range\r\n");
        return;
    }
    receive_data(address, length);
    info_load(length, address);
    uart_puts("Load result: PASS\r\n");
}

/* Consume the complete text line even when its syntax or uint32_t value is invalid. */
static int read_number(struct uart_input *input, unsigned int base, uint32_t *value)
{
    uint8_t character = uart_input_getc(input);
    int valid = 1;
    int digits = 0;
    *value = 0u;
    if (base == 16u) {
        if (character != '0') valid = 0;
        if (!uart_input_is_enter(character)) character = uart_input_getc(input);
        if (character != 'x') valid = 0;
        if (!uart_input_is_enter(character)) character = uart_input_getc(input);
    }
    while (!uart_input_is_enter(character)) {
        unsigned int digit = base;
        if (character >= '0' && character <= '9') digit = character - '0';
        else if (character >= 'a' && character <= 'f') digit = character - 'a' + 10u;
        else if (character >= 'A' && character <= 'F') digit = character - 'A' + 10u;
        if (digit >= base || *value > (UINT32_MAX - digit) / base) valid = 0;
        if (valid) *value = *value * base + digit;
        digits = 1;
        character = uart_input_getc(input);
    }
    return valid && digits;
}

static void run(struct uart_input *input)
{
    uint32_t address;
    uart_puts("Run address:\r\n");
    if (!read_number(input, 16u, &address) || !boot_run_address(address)) {
        uart_puts("Run result: FAIL address\r\n");
        return;
    }
    info_hex("Run", address);
    uart_drain();
    boot_enter(address);
}

static void baud(struct uart_input *input)
{
    uint32_t value;
    uart_puts("Baud:\r\n");
    if (!read_number(input, 10u, &value) ||
        (value != 115200u && value != 921600u && value != 2000000u)) {
        uart_puts("Baud result: FAIL\r\n");
        return;
    }
    info_number("Baud result", value);
    uart_drain();
    uart_set_baud(sysctrl_read(SYSCTRL_CLK_SYS_HZ), value);
}

static _Noreturn void bios(void)
{
    struct uart_input input = {0u};
    uart_puts("BIOS: EdRV32\r\n");
    for (;;) {
        uart_puts("BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud\r\n");
        switch (uart_read_selection(&input)) {
        case '1': program_sram(&input); break;
        case '2': load(&input); break;
        case '3': run(&input); break;
        case '4': baud(&input); break;
        default: uart_puts("Input error: type 1-4 then Enter\r\n"); break;
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
