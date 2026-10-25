/* File: spike.c
 * Spec: edrv32-soc-spec 7.5; S-W2 software-only acceptance.
 * Description: Run the real CoreMark computation and UART metric formatting on Spike.
 *              HTIF replaces only the UART transport; no peripheral/HPM result is simulated.
 * Clock domain: Spike instruction clock (not an RTL performance measurement).
 */
#include "monitor.h"
#include "edrv32.h"
#include "soc_map.h"
#include "uart.h"

static char captured[1024];
static unsigned int captured_length;
static int capture_enabled;

void uart_putc(uint8_t value)
{
    if (capture_enabled) {
        captured[captured_length++] = (char)value;
    }
    edrv32_putchar((char)value);
}

void uart_puts(const char *value)
{
    while (*value != '\0') {
        uart_putc((uint8_t)*value++);
    }
}

static int same_text(const char *expected)
{
    unsigned int position = 0u;
    while (expected[position] != '\0') {
        if (position == captured_length || expected[position] != captured[position]) {
            return 0;
        }
        ++position;
    }
    return position == captured_length;
}

int main(void)
{
    const uint32_t iterations[] = {1u, 10u};
    coremark_set_clock(EDRV32_CLK_SYS_HZ);
    for (unsigned int run = 0u; run < 2u; ++run) {
        core_results result;
        monitor_core_init(&result, iterations[run]);
        start_time();
        iterate(&result);
        stop_time();
        info_number("Spike iterations", iterations[run]);
        info_number("Spike ticks", get_time());
        if (!monitor_core_crc(&result)) {
            edrv32_exit(1);
        }
    }

    const uint64_t cycles[2] = {1000u, 2000u};
    const uint64_t events[16] = {
        200u, 300u, 500u, 100u, 0u, 0u, 0u, 0u,
        100u, 20u, 10u, 40u, 3u, 6u, 0u, 5u
    };
    capture_enabled = 1;
    monitor_metrics(cycles, 1500u, events);
    info_ratio("Iterations/Sec", 150000000u, 200000u);
    info_ratio("CoreMark/MHz", 1000000u, 200000u);
    info_ratio("Zero denominator", 0u, 0u);
    info_number("Wide count", UINT64_C(4294967297));
    capture_enabled = 0;
    if (!same_text("IPC: 1.500\r\n"
                   "Dual retire ratio: 0.200\r\n"
                   "Load-use stall ratio: 0.050\r\n"
                   "Divide stall ratio: 0.010\r\n"
                   "Device wait ratio: 0.005\r\n"
                   "Frontend empty ratio: 0.020\r\n"
                   "Branch mispredict rate: 0.050\r\n"
                   "I-cache MPKI: 2.000\r\n"
                   "D-cache MPKI: 4.000\r\n"
                   "Iterations/Sec: 750.000\r\n"
                   "CoreMark/MHz: 5.000\r\n"
                   "Zero denominator: N/A (denominator=0)\r\n"
                   "Wide count: 4294967297\r\n")) {
        info_text("Spike formula result", "FAIL");
        edrv32_exit(2);
    }
    info_text("Spike formula result", "PASS");
    edrv32_exit(0);
}
