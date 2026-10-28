/* File: main.c
 * Spec: edrv32-soc-spec 7.5.
 * Description: UART command menu for CoreMark, peripherals and system information.
 *              Menu selections and the iteration count are each one Enter-terminated line.
 *              Every completed operation returns to the menu without SIM_EXIT.
 * Clock domain: clk_sys.
 */
#include "monitor.h"
#include "gpio.h"
#include "sysctrl.h"
#include "uart.h"

/* Terminals send CR, LF or CR LF after a line; an LF right after a CR is the same Enter. */
static uint8_t previous_cr;

static uint8_t input_getc(void)
{
    for (;;) {
        uint8_t character = uart_getc();
        if (character == '\n' && previous_cr) {
            previous_cr = 0u;
            continue;
        }
        previous_cr = character == '\r';
        return character;
    }
}

static int is_enter(uint8_t character)
{
    return character == '\r' || character == '\n';
}

/* A menu selection is one line: the first character selects, Enter confirms. */
static uint8_t read_selection(void)
{
    uint8_t selection;
    do {
        selection = input_getc();
    } while (is_enter(selection));
    int extra = 0;
    while (!is_enter(input_getc())) {
        extra = 1;
    }
    return extra ? 0u : selection;
}

static uint32_t read_iterations(void)
{
    info_number("Iterations default", MONITOR_DEFAULT_ITERATIONS);
    info_text("Iterations input", "decimal 1..4294967295 then Enter; Enter selects default");
    uint32_t value = 0u;
    int digits = 0;
    int invalid = 0;
    for (;;) {
        uint8_t character = input_getc();
        if (is_enter(character)) {
            break;
        }
        if (character < '0' || character > '9') {
            invalid = 1;
        } else {
            uint32_t digit = character - '0';
            /* This is the numeric UART input boundary, not an internal fallback. */
            if (value > (UINT32_MAX - digit) / 10u) {
                invalid = 1;
            } else {
                value = value * 10u + digit;
            }
        }
        digits = 1;
    }
    if (!digits) {
        return MONITOR_DEFAULT_ITERATIONS;
    }
    if (invalid || value == 0u) {
        info_text("Input error", "iterations must be decimal 1..4294967295");
        return 0u;
    }
    return value;
}

static void configuration(void)
{
    system_info(sysctrl_read(SYSCTRL_SCRATCH1));
    info_number("Cache ways", SYSTEM_CACHE_WAYS);
    info_number("Cache line bytes", SYSTEM_CACHE_LINE_BYTES);
    info_text("D-cache policy", "write-back, write-allocate");
    info_text("Cache configuration source", "cache-spec 2.1 constants");
    info_text("Compiler flags", BUILD_CFLAGS);
    info_text("ISA", BUILD_ISA);
    info_text("HPM event 00", "disabled");
    for (unsigned int event = 0u; event < 16u; ++event) {
        /* The value is the mhpmevent code; names match the measurement keys. */
        info_number(monitor_hpm_names[event], event + 1u);
    }
    info_text("HPM events 17-31", "reserved, no counting");
    info_text("System info result", "PASS");
}

int main(void)
{
    uint32_t clock_hz = sysctrl_read(SYSCTRL_CLK_SYS_HZ);
    uart_init();
    uart_set_baud(clock_hz, 115200u);
    gpio_set_output_enable(0u);
    info_text("Monitor", "EdRV32");
    for (;;) {
        info_text("Menu", "1=CoreMark 2=Peripheral tests 3=System info");
        switch (read_selection()) {
        case '1': {
            uint32_t iterations = read_iterations();
            if (iterations != 0u) {
                monitor_coremark(iterations, clock_hz);
            }
            break;
        }
        case '2':
            monitor_peripherals(clock_hz);
            break;
        case '3':
            configuration();
            break;
        default:
            info_text("Input error", "type 1, 2 or 3 then Enter");
            break;
        }
    }
}
