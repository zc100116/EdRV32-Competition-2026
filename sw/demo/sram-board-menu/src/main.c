/*
 * PG2L200H Mini bring-up menu. Code, constants, writable data, test storage and
 * stack reside in the 32-KiB cacheable system SRAM.
 */
#if defined(__GNUC__)
#pragma GCC optimize ("Os")
#endif

#include "edrv32_gpio.h"
#include "edrv32_ddr.h"
#include "edrv32_ddr_monitor.h"
#include "edrv32_mmio.h"
#include "edrv32_soc_map.h"
#include "edrv32_uart.h"

#ifndef EDRV32_SOC_CLOCK_HZ
#define EDRV32_SOC_CLOCK_HZ 100000000u
#endif
#ifndef EDRV32_UART_BAUD
#define EDRV32_UART_BAUD 115200u
#endif
#ifndef EDRV32_BOARD_NAME
#define EDRV32_BOARD_NAME "PG2L200H Mini"
#endif
#ifndef EDRV32_COREMARK_ITERATIONS
#define EDRV32_COREMARK_ITERATIONS 4000
#endif

#define EDRV32_STRINGIFY_INNER(value) #value
#define EDRV32_STRINGIFY(value) EDRV32_STRINGIFY_INNER(value)

#if EDRV32_SOC_CLOCK_HZ == 100000000u
#define EDRV32_CLOCK_LABEL "100MHz"
#else
#define EDRV32_CLOCK_LABEL "50MHz"
#endif

#define GPIO_LED_MASK       0x000000ffu
#define GPIO_KEY_MASK       0x00000007u
#define KEY_NEXT            0x00000001u
#define KEY_RUN             0x00000002u
#define KEY_COREMARK        0x00000004u

#define CLINT_MSIP          (SOC_CLINT_BASE + 0x0000u)
#define CLINT_MTIME_LO      (SOC_CLINT_BASE + 0xbff8u)
#define CLINT_MTIME_HI      (SOC_CLINT_BASE + 0xbffcu)

#define PLIC_PRIORITY_UART  (SOC_PLIC_BASE + 0x0004u)
#define PLIC_ENABLE         (SOC_PLIC_BASE + 0x2000u)
#define PLIC_THRESHOLD      (SOC_PLIC_BASE + 0x200000u)

#define CACHE_CONTROL       (SOC_CACHE_MAINT_BASE + 0x00u)
#define CACHE_ADDRESS       (SOC_CACHE_MAINT_BASE + 0x04u)
#define CACHE_SIZE          (SOC_CACHE_MAINT_BASE + 0x08u)
#define CACHE_STATUS        (SOC_CACHE_MAINT_BASE + 0x0cu)
#define CACHE_IC_INVALIDATE (SOC_CACHE_MAINT_BASE + 0x10u)
#define CACHE_CLEAN_INVALIDATE 4u

#define DDR_MONITOR_TIMEOUT   200000000u
#define DDR_MONITOR_BASE      0x00100000u
#define DDR_MONITOR_BEATS     4096u
#define DDR_MONITOR_BURST_LEN 255u
#define DDR_MONITOR_LOOPS     2u

#define TEST_COUNT 9u
#define UART_SHORT_POLL 256u
#define CACHE_TIMEOUT 1000000u
#define UART_COMMAND_MAX 16u

extern unsigned int _sram_test_start;
extern unsigned int _sram_test_end;
int edrv32_coremark_run(void);
extern int edrv32_hpm_profile;

static void delay_cycles(unsigned int cycles)
{
    while (cycles != 0u) {
        __asm__ __volatile__("nop");
        cycles--;
    }
}

static unsigned int read_mcycle(void)
{
    unsigned int value;
    __asm__ __volatile__("csrr %0, mcycle" : "=r"(value));
    return value;
}

static void print_fail(const char *name, unsigned int address,
                       unsigned int expected, unsigned int actual)
{
    edrv32_uart_puts("[FAIL] ");
    edrv32_uart_puts(name);
    edrv32_uart_puts(" addr=");
    edrv32_uart_put_hex32(address);
    edrv32_uart_puts(" exp=");
    edrv32_uart_put_hex32(expected);
    edrv32_uart_puts(" got=");
    edrv32_uart_put_hex32(actual);
    edrv32_uart_puts("\n");
}

static int wait_cache_idle(void)
{
    unsigned int timeout = CACHE_TIMEOUT;
    while ((edrv32_mmio_read32(CACHE_STATUS) & 1u) != 0u) {
        if (--timeout == 0u)
            return 1;
    }
    return 0;
}

static int cache_clean_invalidate(unsigned int address, unsigned int size)
{
    edrv32_mmio_write32(CACHE_ADDRESS, address);
    edrv32_mmio_write32(CACHE_SIZE, size);
    edrv32_mmio_write32(CACHE_CONTROL, CACHE_CLEAN_INVALIDATE);
    return wait_cache_idle();
}

static int test_uart(void)
{
    char value;
    unsigned int count = 0u;
    unsigned int checksum = 0u;
    int status;

    edrv32_uart_puts("[UART_LOOPBACK_BEGIN] send text, finish with ENTER\n");
    while (count < 64u) {
        status = edrv32_uart_getc_timeout(
            &value, count == 0u ? EDRV32_SOC_CLOCK_HZ * 10u :
                                  EDRV32_SOC_CLOCK_HZ / 10u);
        if (status != EDRV32_UART_OK) {
            if (count != 0u)
                break;
            edrv32_uart_puts("[FAIL] UART RX timeout\n");
            return 1;
        }
        if (value == '\r' || value == '\n')
            break;
        edrv32_uart_putc(value);
        checksum = (checksum << 5) ^ (checksum >> 27) ^
                   (unsigned int)(unsigned char)value;
        count++;
    }
    if (count == 0u) {
        edrv32_uart_puts("[FAIL] UART loopback empty frame\n");
        return 1;
    }
    edrv32_uart_puts("\n[PASS] UART data loopback bytes=");
    edrv32_uart_put_hex32(count);
    edrv32_uart_puts(" checksum=");
    edrv32_uart_put_hex32(checksum);
    edrv32_uart_puts("\n");
    return 0;
}

static int test_gpio(void)
{
    static const unsigned int patterns[] = {
        0x01u, 0x02u, 0x04u, 0x08u, 0x10u, 0x20u, 0x40u, 0x80u
    };
    unsigned int index;

    edrv32_gpio_set_direction(GPIO_LED_MASK);
    if ((edrv32_gpio_read_direction() & GPIO_LED_MASK) != GPIO_LED_MASK) {
        print_fail("GPIO DIR", SOC_GPIO0_BASE, GPIO_LED_MASK,
                   edrv32_gpio_read_direction() & GPIO_LED_MASK);
        return 1;
    }
    for (index = 0u; index < 8u; index++) {
        edrv32_gpio_write(patterns[index]);
        delay_cycles(EDRV32_SOC_CLOCK_HZ / 20u);
    }
    edrv32_uart_puts("[GPIO] KEY2..4=");
    edrv32_uart_put_hex32(edrv32_gpio_read() & GPIO_KEY_MASK);
    edrv32_uart_puts("\n[PASS] GPIO register/LED walk\n");
    return 0;
}

static unsigned int lfsr_next(unsigned int value)
{
    unsigned int feedback = 0u - (value & 1u);
    return (value >> 1) ^ (0x80200003u & feedback);
}

static int sram_pattern(unsigned int seed, unsigned int mode)
{
    volatile unsigned int *word = (volatile unsigned int *)&_sram_test_start;
    volatile unsigned int *end = (volatile unsigned int *)&_sram_test_end;
    unsigned int value = seed;
    unsigned int expected;

    for (; word < end; word++) {
        if (mode == 1u)
            value = seed ^ (unsigned int)word;
        else if (mode == 2u)
            value = lfsr_next(value);
        *word = value;
    }
    if (cache_clean_invalidate((unsigned int)&_sram_test_start,
                               (unsigned int)&_sram_test_end -
                               (unsigned int)&_sram_test_start) != 0) {
        edrv32_uart_puts("[FAIL] SRAM cache maintenance timeout\n");
        return 1;
    }

    word = (volatile unsigned int *)&_sram_test_start;
    value = seed;
    for (; word < end; word++) {
        if (mode == 1u)
            expected = seed ^ (unsigned int)word;
        else if (mode == 2u) {
            value = lfsr_next(value);
            expected = value;
        } else
            expected = seed;
        if (*word != expected) {
            print_fail("SRAM", (unsigned int)word, expected, *word);
            return 1;
        }
    }
    return 0;
}

static int test_sram(void)
{
    if (sram_pattern(0x00000000u, 0u) ||
        sram_pattern(0xffffffffu, 0u) ||
        sram_pattern(0xaaaaaaaau, 0u) ||
        sram_pattern(0x55555555u, 0u) ||
        sram_pattern(0x13570000u, 1u) ||
        sram_pattern(0x1aceb00cu, 2u))
        return 1;
    edrv32_uart_puts("[PASS] SRAM 2 KiB pattern/cache refill test\n");
    return 0;
}

static unsigned int read_mtime_lo_stable(void)
{
    unsigned int hi0;
    unsigned int lo;
    unsigned int hi1;
    do {
        hi0 = edrv32_mmio_read32(CLINT_MTIME_HI);
        lo = edrv32_mmio_read32(CLINT_MTIME_LO);
        hi1 = edrv32_mmio_read32(CLINT_MTIME_HI);
    } while (hi0 != hi1);
    return lo;
}

static int test_clint(void)
{
    unsigned int time0 = read_mtime_lo_stable();
    unsigned int cycle0 = read_mcycle();
    unsigned int time1;
    unsigned int cycle1;

    delay_cycles(1024u);
    time1 = read_mtime_lo_stable();
    cycle1 = read_mcycle();
    if (time1 == time0 || cycle1 == cycle0) {
        print_fail("CLINT TIME", CLINT_MTIME_LO, time0 + 1u, time1);
        return 1;
    }
    edrv32_mmio_write32(CLINT_MSIP, 1u);
    if ((edrv32_mmio_read32(CLINT_MSIP) & 1u) == 0u) {
        print_fail("CLINT MSIP", CLINT_MSIP, 1u,
                   edrv32_mmio_read32(CLINT_MSIP));
        edrv32_mmio_write32(CLINT_MSIP, 0u);
        return 1;
    }
    edrv32_mmio_write32(CLINT_MSIP, 0u);
    edrv32_uart_puts("[PASS] CLINT mtime/mcycle/MSIP\n");
    return 0;
}

static int test_plic(void)
{
    unsigned int old_priority = edrv32_mmio_read32(PLIC_PRIORITY_UART);
    unsigned int old_enable = edrv32_mmio_read32(PLIC_ENABLE);
    unsigned int old_threshold = edrv32_mmio_read32(PLIC_THRESHOLD);
    int failed = 0;

    edrv32_mmio_write32(PLIC_PRIORITY_UART, 5u);
    edrv32_mmio_write32(PLIC_ENABLE, 1u << PLIC_SRC_UART0);
    edrv32_mmio_write32(PLIC_THRESHOLD, 3u);
    if (edrv32_mmio_read32(PLIC_PRIORITY_UART) != 5u)
        failed = 1;
    if (edrv32_mmio_read32(PLIC_ENABLE) != (1u << PLIC_SRC_UART0))
        failed = 1;
    if (edrv32_mmio_read32(PLIC_THRESHOLD) != 3u)
        failed = 1;

    edrv32_mmio_write32(PLIC_THRESHOLD, old_threshold);
    edrv32_mmio_write32(PLIC_ENABLE, old_enable);
    edrv32_mmio_write32(PLIC_PRIORITY_UART, old_priority);
    if (failed) {
        edrv32_uart_puts("[FAIL] PLIC priority/enable/threshold R/W\n");
        return 1;
    }
    edrv32_uart_puts("[PASS] PLIC priority/enable/threshold R/W\n");
    return 0;
}

static int test_cache_control(void)
{
    unsigned int address = (unsigned int)&_sram_test_start;
    unsigned int size = (unsigned int)&_sram_test_end - address;

    edrv32_mmio_write32(CACHE_ADDRESS, address);
    edrv32_mmio_write32(CACHE_SIZE, size);
    if (edrv32_mmio_read32(CACHE_ADDRESS) != address ||
        edrv32_mmio_read32(CACHE_SIZE) != size) {
        edrv32_uart_puts("[FAIL] Cache maintenance register R/W\n");
        return 1;
    }
    if (cache_clean_invalidate(address, size) != 0) {
        edrv32_uart_puts("[FAIL] D-cache maintenance timeout\n");
        return 1;
    }
    edrv32_mmio_write32(CACHE_IC_INVALIDATE, 1u);
    __asm__ __volatile__("fence.i" ::: "memory");
    edrv32_uart_puts("[PASS] D-cache range + I-cache invalidate control\n");
    return 0;
}

static int test_cpu_ddr(void)
{
    volatile unsigned char *byte_ptr;
    volatile unsigned short *half_ptr;
    unsigned int bad_index;
    unsigned int expected;
    unsigned int actual;

    if (edrv32_ddr_test_alias(0x00002000u, 0x13579bdfu, &actual) !=
        EDRV32_DDR_OK) {
        print_fail("DDR alias", 0x80002000u, 0x13579bdfu, actual);
        return 1;
    }

    if (edrv32_ddr_test_uncached(0x00010000u, 1024u, 0x20260918u,
                                 &bad_index, &expected, &actual) !=
        EDRV32_DDR_OK) {
        print_fail("DDR word", 0xc0010000u + bad_index * 4u,
                   expected, actual);
        return 1;
    }

    byte_ptr = (volatile unsigned char *)
        edrv32_ddr_uncached_address(0x00020001u);
    half_ptr = (volatile unsigned short *)
        edrv32_ddr_uncached_address(0x00020006u);
    *byte_ptr = 0xa5u;
    *half_ptr = 0x5aa5u;
    edrv32_mmio_fence();
    if (*byte_ptr != 0xa5u) {
        print_fail("DDR byte", (unsigned int)byte_ptr, 0xa5u, *byte_ptr);
        return 1;
    }
    if (*half_ptr != 0x5aa5u) {
        print_fail("DDR half", (unsigned int)half_ptr, 0x5aa5u,
                   *half_ptr);
        return 1;
    }

    edrv32_uart_puts("[PASS] CPU DDR cached/uncached and narrow access\n");
    return 0;
}

static void print_monitor_metric(const char *name, unsigned int value)
{
    edrv32_uart_puts(name);
    edrv32_uart_put_hex32(value);
    edrv32_uart_puts("\n");
}

static int test_ddr_monitor(void)
{
    struct edrv32_ddr_monitor_result result;
    unsigned int timeout = DDR_MONITOR_TIMEOUT;
    unsigned int status;
    unsigned int expected_beats = DDR_MONITOR_BEATS * DDR_MONITOR_LOOPS;

    if (edrv32_ddr_monitor_read(EDRV32_DDR_MON_ID) != 0x4444524du) {
        print_monitor_metric("[FAIL] monitor ID=",
            edrv32_ddr_monitor_read(EDRV32_DDR_MON_ID));
        return 1;
    }

    edrv32_ddr_monitor_write(EDRV32_DDR_MON_CONTROL,
                             EDRV32_DDR_MON_CONTROL_CLEAR);
    status = edrv32_ddr_monitor_read(EDRV32_DDR_MON_STATUS);
    if ((status & EDRV32_DDR_MON_STATUS_CMD_READY) == 0u) {
        print_monitor_metric("[FAIL] monitor status=", status);
        return 1;
    }

    edrv32_ddr_monitor_start(EDRV32_DDR_MON_MODE_WRITE_READ,
                             DDR_MONITOR_BASE,
                             DDR_MONITOR_BEATS,
                             DDR_MONITOR_BURST_LEN,
                             0x1aceb00cu,
                             DDR_MONITOR_LOOPS);
    do {
        status = edrv32_ddr_monitor_read(EDRV32_DDR_MON_STATUS);
        if ((status & EDRV32_DDR_MON_STATUS_DONE) != 0u)
            break;
        timeout--;
    } while (timeout != 0u);

    if (timeout == 0u) {
        print_monitor_metric("[FAIL] monitor timeout status=", status);
        return 1;
    }

    edrv32_ddr_monitor_get_result(&result);
    print_monitor_metric("[DDR MON] cycles=", result.total_cycles);
    print_monitor_metric("[DDR MON] write beats=", result.write_beats);
    print_monitor_metric("[DDR MON] read beats=", result.read_beats);
    print_monitor_metric("[DDR MON] AW stall=", result.aw_stall_cycles);
    print_monitor_metric("[DDR MON] W stall=", result.w_stall_cycles);
    print_monitor_metric("[DDR MON] AR stall=", result.ar_stall_cycles);
    print_monitor_metric("[DDR MON] R wait=", result.r_wait_cycles);

    if ((status & EDRV32_DDR_MON_STATUS_ERROR) != 0u ||
        result.error_count != 0u) {
        print_fail("DDR monitor", result.first_error_addr,
                   result.expected_data, result.actual_data);
        return 1;
    }
    if (result.write_beats != expected_beats ||
        result.read_beats != expected_beats) {
        print_fail("DDR monitor beats", DDR_MONITOR_BASE,
                   expected_beats, result.read_beats);
        return 1;
    }

    edrv32_uart_puts("[PASS] DDR monitor write/read/verify\n");
    return 0;
}

static int test_coremark(void)
{
    int result;

    edrv32_uart_puts("[COREMARK] "
                     EDRV32_STRINGIFY(EDRV32_COREMARK_ITERATIONS)
                     " iterations, please wait...\n");
    (void)edrv32_uart_flush_timeout(EDRV32_SOC_CLOCK_HZ);
    edrv32_hpm_profile = 0;
    result = edrv32_coremark_run();
    edrv32_hpm_profile = 1;
    result |= edrv32_coremark_run();
    return result;
}

static int run_test(unsigned int selection)
{
    int result;
    edrv32_gpio_write(1u << ((selection - 1u) & 7u));
    switch (selection) {
    case 1u: result = test_uart(); break;
    case 2u: result = test_gpio(); break;
    case 3u: result = test_sram(); break;
    case 4u: result = test_clint(); break;
    case 5u: result = test_plic(); break;
    case 6u: result = test_coremark(); break;
    case 7u: result = test_cache_control(); break;
    case 8u: result = test_cpu_ddr(); break;
    default: result = test_ddr_monitor(); break;
    }
    edrv32_gpio_write(result == 0 ? 0xa5u : 0xe1u);
    return result;
}

static int run_automatic_suite(void)
{
    unsigned int selection;
    int failed = 0;
    edrv32_uart_puts("[AUTO] UART menu RX/TX already active; run 2..9\n");
    for (selection = 2u; selection <= TEST_COUNT; selection++)
        failed |= run_test(selection);
    edrv32_uart_puts(failed ? "EDRV32_SOC_SUITE_FAIL\n" :
                               "EDRV32_SOC_SUITE_PASS\n");
    return failed;
}

static void print_menu(unsigned int selection)
{
    edrv32_uart_puts("\n=== EdRV32 " EDRV32_BOARD_NAME
                     " SoC bring-up ===\n");
    edrv32_uart_puts("1 UART echo      2 GPIO/LED       3 SRAM/cache\n");
    edrv32_uart_puts("4 CLINT          5 PLIC           6 CoreMark\n");
    edrv32_uart_puts("7 Cache control  8 CPU DDR        9 DDR monitor\n");
    edrv32_uart_puts("a automatic      h help\n");
    edrv32_uart_puts("KEY2 next, KEY3 run, KEY4 CoreMark; selected=");
    edrv32_uart_put_hex32(selection);
    edrv32_uart_puts("\n> ");
}

static void print_prompt(void)
{
    edrv32_uart_puts("> ");
}

static void print_command_state(const char *state, char command, int failed)
{
    edrv32_uart_puts("[");
    edrv32_uart_puts(state);
    edrv32_uart_puts("] command=");
    edrv32_uart_putc(command);
    if (state[0] == 'D')
        edrv32_uart_puts(failed ? " result=FAIL\n" : " result=PASS\n");
    else
        edrv32_uart_puts("\n");
}

static void execute_command(char command, unsigned int *selection)
{
    int failed;

    if (command == 'h' || command == 'H') {
        print_menu(*selection);
        return;
    }

    if (!((command >= '1' && command <= '9') ||
          command == 'a' || command == 'A')) {
        edrv32_uart_puts("[ERROR] unknown command\n");
        print_prompt();
        return;
    }

    print_command_state("BUSY", command, 0);
    (void)edrv32_uart_flush_timeout(EDRV32_SOC_CLOCK_HZ);
    if (command >= '1' && command <= '9') {
        *selection = (unsigned int)(command - '0');
        failed = run_test(*selection);
    } else {
        failed = run_automatic_suite();
    }

    // Tests are deliberately blocking.  Bytes transmitted while BUSY are
    // stale commands, and a burst can set the UART's sticky overrun bit.
    // Discard both before accepting the next complete command line.
    edrv32_uart_clear_rx();
    print_command_state("DONE", command, failed);
    print_prompt();
}

int main(void)
{
    unsigned int selection = 1u;
    unsigned int old_keys = 0u;
    unsigned int command_length = 0u;
    int command_overflow = 0;
    int uart_status;
    char command_line[UART_COMMAND_MAX + 1u];
    char command;

    edrv32_gpio_set_direction(GPIO_LED_MASK);
    edrv32_gpio_write(1u);
    edrv32_uart_init(EDRV32_UART_DIVISOR(EDRV32_SOC_CLOCK_HZ,
                                         EDRV32_UART_BAUD));
    edrv32_uart_puts("\nBootROM -> cached SRAM code/data, "
                     EDRV32_CLOCK_LABEL ", DDR enabled\n");
    print_menu(selection);

    for (;;) {
        unsigned int keys = edrv32_gpio_read() & GPIO_KEY_MASK;
        unsigned int pressed = keys & ~old_keys;

        uart_status = edrv32_uart_getc_timeout(&command, UART_SHORT_POLL);
        if (uart_status == EDRV32_UART_OK) {
            if (command == '\r' || command == '\n') {
                if (command_length != 0u || command_overflow) {
                    edrv32_uart_puts("\n");
                    if (!command_overflow && command_length == 1u) {
                        command_line[command_length] = '\0';
                        execute_command(command_line[0], &selection);
                    } else {
                        edrv32_uart_puts(command_overflow
                            ? "[ERROR] command too long\n"
                            : "[ERROR] unknown command\n");
                        print_prompt();
                    }
                    command_length = 0u;
                    command_overflow = 0;
                }
            } else if (command == '\b' || command == 0x7f) {
                if (command_length != 0u) {
                    command_length--;
                    edrv32_uart_puts("\b \b");
                }
            } else if ((unsigned char)command >= 0x20u &&
                       (unsigned char)command <= 0x7eu) {
                edrv32_uart_putc(command);
                if (command_length < UART_COMMAND_MAX)
                    command_line[command_length++] = command;
                else
                    command_overflow = 1;
            }
        } else if (uart_status == EDRV32_UART_ERROR) {
            command_length = 0u;
            command_overflow = 0;
            edrv32_uart_puts("\n[WARN] UART RX error recovered\n");
            print_prompt();
        }

        if ((pressed & KEY_NEXT) != 0u) {
            selection = (selection % TEST_COUNT) + 1u;
            edrv32_gpio_write(1u << (selection - 1u));
            edrv32_uart_puts("\n[SELECT] test=");
            edrv32_uart_put_hex32(selection);
            edrv32_uart_puts("\n");
            print_prompt();
        }
        if ((pressed & KEY_RUN) != 0u) {
            (void)run_test(selection);
            print_prompt();
        }
        if ((pressed & KEY_COREMARK) != 0u) {
            selection = 6u;
            (void)run_test(selection);
            print_prompt();
        }
        old_keys = keys;
        delay_cycles(2000u);
    }
}
