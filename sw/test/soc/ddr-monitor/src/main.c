#include "edrv32_ddr.h"
#include "edrv32_ddr_monitor.h"
#include "edrv32_uart.h"

#define SOC_CLOCK_HZ       100000000u
#define UART_BAUD          115200u
#define MONITOR_ID_VALUE   0x4444524du
#define MONITOR_VERSION    0x00010000u
#define MONITOR_TIMEOUT    200000000u
#define MONITOR_BASE       0x00100000u
#define MONITOR_BEATS      4096u
#define MONITOR_BURST_LEN  255u
#define MONITOR_LOOPS      2u

static int fail(const char *name, unsigned int value)
{
    edrv32_uart_puts("[FAIL] ");
    edrv32_uart_puts(name);
    edrv32_uart_puts(" value=");
    edrv32_uart_put_hex32(value);
    edrv32_uart_puts("\n");
    return 1;
}

static void print_metric(const char *name, unsigned int value)
{
    edrv32_uart_puts(name);
    edrv32_uart_put_hex32(value);
    edrv32_uart_puts("\n");
}

static int test_cpu_ddr(void)
{
    unsigned int bad_index;
    unsigned int expected;
    unsigned int actual;

    if (edrv32_ddr_test_alias(0x00002000u, 0x13579bdfu, &actual) !=
        EDRV32_DDR_OK)
        return fail("CPU DDR cached/uncached alias", actual);

    if (edrv32_ddr_test_uncached(0x00010000u, 1024u, 0x20260918u,
                                 &bad_index, &expected, &actual) !=
        EDRV32_DDR_OK) {
        print_metric("bad_index=", bad_index);
        print_metric("expected=", expected);
        return fail("CPU DDR data", actual);
    }

    edrv32_uart_puts("[PASS] CPU DDR access\n");
    return 0;
}

static int wait_monitor_done(void)
{
    unsigned int timeout = MONITOR_TIMEOUT;
    unsigned int status;

    do {
        status = edrv32_ddr_monitor_read(EDRV32_DDR_MON_STATUS);
        if ((status & EDRV32_DDR_MON_STATUS_DONE) != 0u)
            return 0;
        timeout--;
    } while (timeout != 0u);

    return fail("DDR monitor timeout", status);
}

static int test_ddr_monitor(void)
{
    struct edrv32_ddr_monitor_result result;
    unsigned int expected_beats = MONITOR_BEATS * MONITOR_LOOPS;
    unsigned int status;

    if (edrv32_ddr_monitor_read(EDRV32_DDR_MON_ID) != MONITOR_ID_VALUE)
        return fail("DDR monitor ID",
                    edrv32_ddr_monitor_read(EDRV32_DDR_MON_ID));
    if (edrv32_ddr_monitor_read(EDRV32_DDR_MON_VERSION) != MONITOR_VERSION)
        return fail("DDR monitor version",
                    edrv32_ddr_monitor_read(EDRV32_DDR_MON_VERSION));

    edrv32_ddr_monitor_write(EDRV32_DDR_MON_CONTROL,
                             EDRV32_DDR_MON_CONTROL_CLEAR);
    status = edrv32_ddr_monitor_read(EDRV32_DDR_MON_STATUS);
    if ((status & EDRV32_DDR_MON_STATUS_CMD_READY) == 0u)
        return fail("DDR monitor not ready", status);

    edrv32_ddr_monitor_start(EDRV32_DDR_MON_MODE_WRITE_READ,
                             MONITOR_BASE,
                             MONITOR_BEATS,
                             MONITOR_BURST_LEN,
                             0x1aceb00cu,
                             MONITOR_LOOPS);
    if (wait_monitor_done() != 0)
        return 1;

    status = edrv32_ddr_monitor_read(EDRV32_DDR_MON_STATUS);
    edrv32_ddr_monitor_get_result(&result);

    print_metric("total_cycles=", result.total_cycles);
    print_metric("write_beats=", result.write_beats);
    print_metric("read_beats=", result.read_beats);
    print_metric("aw_stall_cycles=", result.aw_stall_cycles);
    print_metric("w_stall_cycles=", result.w_stall_cycles);
    print_metric("ar_stall_cycles=", result.ar_stall_cycles);
    print_metric("r_wait_cycles=", result.r_wait_cycles);
    print_metric("error_count=", result.error_count);

    if ((status & EDRV32_DDR_MON_STATUS_ERROR) != 0u ||
        result.error_count != 0u) {
        print_metric("first_error_addr=", result.first_error_addr);
        print_metric("expected_data=", result.expected_data);
        return fail("DDR monitor compare", result.actual_data);
    }
    if (result.write_beats != expected_beats)
        return fail("DDR monitor write beat count", result.write_beats);
    if (result.read_beats != expected_beats)
        return fail("DDR monitor read beat count", result.read_beats);

    edrv32_uart_puts("[PASS] DDR monitor write/read/verify\n");
    return 0;
}

int main(void)
{
    int failed = 0;

    edrv32_uart_init(EDRV32_UART_DIVISOR(SOC_CLOCK_HZ, UART_BAUD));
    edrv32_uart_puts("\nEDRV32_DDR_BOARD_TEST_START\n");

    failed |= test_cpu_ddr();
    failed |= test_ddr_monitor();

    edrv32_uart_puts(failed ? "EDRV32_DDR_BOARD_TEST_FAIL\n" :
                               "EDRV32_DDR_BOARD_TEST_PASS\n");
    for (;;) {
        __asm__ __volatile__("wfi");
    }
}
