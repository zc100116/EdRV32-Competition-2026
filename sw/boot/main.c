/* File: main.c
 * Spec: sys-subsys-spec 2.2, 2.6, 2.9; edrv32-soc-spec 7.5
 * Description: Print startup information, sample KEY1 and offer the load/run/baud BIOS.
 * Clock domain: clk_sys.
 */
#include "session.h"
#include "eth.h"
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

static void receive_data(uint32_t address, uint32_t length)
{
    volatile uint8_t *destination = (volatile uint8_t *)(uintptr_t)address;
    for (uint32_t byte = 0u; byte < length; ++byte) destination[byte] = uart_getc();
}

static _Noreturn void loaded(const struct boot_session *session, int external)
{
    cache_clean_all();
    if (external) {
        for (uint32_t i = 0u; i < session->count; ++i) {
            if (session->segments[i].address >= EDRV32_DDR_BASE)
                cache_invalidate(session->segments[i].address, session->segments[i].length);
        }
    }
    uint64_t total = 0u;
    for (uint32_t i = 0u; i < session->count; ++i) total += session->segments[i].length;
    info_load(total, session->count);
    uart_puts("Load result: PASS\r\n");
    info_hex("Run", session->entry);
    uart_drain();
    boot_enter(session->entry);
}

static void load(struct uart_input *input)
{
    uint8_t descriptor[8u + 8u * BOOT_MAX_SEGMENTS];
    struct boot_session session;
    uart_puts("UART load ready\r\n");
    uart_drain();
    uart_input_binary_begin(input);
    for (uint32_t i = 0u; i < 8u; ++i) descriptor[i] = uart_getc();
    uint32_t count = boot_word(descriptor);
    if (count >= 1u && count <= BOOT_MAX_SEGMENTS) {
        for (uint32_t i = 8u; i < 8u + 8u * count; ++i) descriptor[i] = uart_getc();
    }
    if (!boot_session_parse(&session, descriptor)) {
        uart_puts("Load result: FAIL range\r\n");
        return;
    }
    for (uint32_t i = 0u; i < session.count; ++i)
        receive_data(session.segments[i].address, session.segments[i].length);
    loaded(&session, 0);
}

static int eth_cancel(struct uart_input *input)
{
    if (mmio_read32(EDRV32_UART0_BASE + UART_STATUS) & UART_STATUS_RX_EMPTY) return 0;
    uint8_t character = uart_getc();
    if (character == '\n' && input->previous_cr) {
        input->previous_cr = 0u;
        return 0;
    }
    input->previous_cr = character == '\r';
    return uart_input_is_enter(character);
}

static int eth_delay(struct uart_input *input, uint32_t cycles)
{
    uint64_t start = clint_time();
    while (clint_time() - start < cycles) {
        if (eth_cancel(input)) return 0;
    }
    return 1;
}

static void eth_stop(void)
{
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_CTRL_OFFSET, 0u);
}

static void eth_load(struct uart_input *input)
{
    const struct eth_endpoint local = {{0x02, 0x45, 0x44, 0x52, 0x56, 0x32},
                                       {192, 168, 1, 10}, 5000};
    uint32_t hz = sysctrl_read(SYSCTRL_CLK_SYS_HZ);
    cache_clean_all();
    cache_clean_invalidate(EDRV32_SRAM_BASE, EDRV32_SRAM_SIZE);
    cache_clean_invalidate(EDRV32_DDR_BASE, EDRV32_DDR_SIZE);
    eth_stop();
    eth_phy_reset(1u);
    if (!eth_delay(input, hz / 100u)) return;
    eth_phy_reset(0u);
    if (!eth_delay(input, hz / 10u)) return;
    eth_local_configure(&local);
    eth_window_configure(2u, 0u, EDRV32_DDR_SIZE);
    eth_window_configure(3u, BOOT_ETH_STAGE_PHYSICAL, BOOT_ETH_STAGE_BYTES);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_IRQ_STAT_OFFSET,
                 EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK);
    /* BMSR link is latch-low: discard the first read and use the current second read. */
    for (;;) {
        if (eth_cancel(input)) return;
        (void)eth_mdio_read(BOOT_PHY_ADDRESS, 1u);
        if (eth_mdio_read(BOOT_PHY_ADDRESS, 1u) & 4u) break;
    }
    uart_puts("ETH link: up\r\n");
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_CTRL_OFFSET, EDRV32_ETH_CTRL_ENABLE_MASK);
    uart_puts("ETH load ready 192.168.1.10:5000\r\n");
    for (;;) {
        if (eth_cancel(input)) {
            eth_stop();
            return;
        }
        if (!(mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_IRQ_STAT_OFFSET) &
              EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK)) continue;
        mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_IRQ_STAT_OFFSET,
                     EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK);
        struct boot_session session;
        const volatile uint8_t *stage = (const volatile uint8_t *)(uintptr_t)
            (EDRV32_DDR_UNCACHED_BASE + BOOT_ETH_STAGE_PHYSICAL);
        if (!boot_session_parse(&session, stage)) {
            eth_stop();
            uart_puts("Load result: FAIL range\r\n");
            return;
        }
        uint32_t ddr_bytes = eth_window_bytes(2u);
        uint32_t stage_bytes = eth_window_bytes(3u);
        if (!boot_session_complete(&session, ddr_bytes, stage_bytes)) {
            uint32_t ddr_expected;
            uint32_t stage_expected;
            boot_session_bytes(&session, &ddr_expected, &stage_expected);
            /* Clear before printing so the host can resend upon the complete result line. */
            eth_window_configure(2u, 0u, EDRV32_DDR_SIZE);
            eth_window_configure(3u, BOOT_ETH_STAGE_PHYSICAL, BOOT_ETH_STAGE_BYTES);
            info_eth_bytes(ddr_bytes, ddr_expected, stage_bytes, stage_expected);
            continue;
        }
        eth_stop();
        for (uint32_t i = 0u; i < session.count; ++i) {
            const struct boot_segment *segment = &session.segments[i];
            if (segment->address >= EDRV32_DDR_BASE) continue;
            volatile uint8_t *destination = (volatile uint8_t *)(uintptr_t)segment->address;
            const volatile uint8_t *source = stage + BOOT_ETH_SRAM_OFFSET +
                                             (segment->address - EDRV32_SRAM_BASE);
            for (uint32_t j = 0u; j < segment->length; ++j) destination[j] = source[j];
        }
        loaded(&session, 1);
    }
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
        uart_puts("BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud\r\n");
        switch (uart_read_selection(&input)) {
        case '1': load(&input); break;
        case '2': eth_load(&input); break;
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
