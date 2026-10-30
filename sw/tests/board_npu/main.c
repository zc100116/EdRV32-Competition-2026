/* File: main.c
 * Spec: npu-spec 2-5, 7; SoC 3.5, 7.1, 7.4; board-npu-test design section 4.
 * Description: Check registers, small operators, YOLO output and 20 repeated frames.
 *              Compare host reference bytes and report counters over the BIOS UART.
 * Clock domain: clk_sys CPU, clk_npu engine (150 MHz, npu-spec 7).
 */
#include "cache.h"
#include "edrv32.h"
#include "gpio.h"
#include "npu.h"
#include "uart.h"
#include "board_data.h"

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define NPU_CLOCK_HZ 150000000u
#define STABILITY_RUNS 20u
#define TOTAL_ITEMS (3u + ARRAY_SIZE(board_cases) + STABILITY_RUNS)
#define LED_PASS (1u << 4)
#define LED_FAIL (1u << 5)

static uint32_t passed;
static uint32_t failed;
static void performance(void);

static uint32_t npu_read(uint32_t offset)
{
    return mmio_read32(EDRV32_NPU_BASE + offset);
}

static void npu_write(uint32_t offset, uint32_t value)
{
    mmio_write32(EDRV32_NPU_BASE + offset, value);
}

static void decimal(uint32_t value)
{
    char digits[10];
    unsigned int count = 0u;
    do {
        digits[count++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value != 0u);
    while (count != 0u) {
        uart_putc((uint8_t)digits[--count]);
    }
}

static void hex(uint32_t value)
{
    static const char digits[] = "0123456789abcdef";
    for (unsigned int n = 8u; n != 0u; --n) {
        uart_putc((uint8_t)digits[(value >> ((n - 1u) * 4u)) & 15u]);
    }
}

static void field(const char *name, uint32_t value)
{
    uart_puts(name);
    decimal(value);
}

static void hex_field(const char *name, uint32_t value)
{
    uart_puts(name);
    hex(value);
}

static void item(const char *name, const char *result)
{
    uart_puts("NPU ");
    uart_puts(name);
    uart_puts(result);
}

static _Noreturn void finish(uint32_t failed)
{
    uart_puts(failed == 0u ? "NPU board: PASS " : "NPU board: FAIL ");
    decimal(failed == 0u ? passed : failed);
    uart_putc('/');
    decimal(TOTAL_ITEMS);
    uart_puts("\r\n");
    gpio_write(failed == 0u ? LED_PASS : LED_FAIL);
    uart_drain();
    edrv32_exit((int)failed);
}

static _Noreturn void fail(const char *name, uint32_t descriptor, uint32_t address,
                          uint32_t expected, uint32_t actual, uint32_t differences)
{
    item(name, " FAIL");
    field(" desc=", descriptor);
    hex_field(" addr=", address);
    hex_field(" expected=", expected);
    hex_field(" actual=", actual);
    field(" mismatches=", differences);
    performance();
    field(" passed=", passed);
    uart_puts("\r\n");
    finish(failed + 1u);
}

static void pass(const char *name)
{
    ++passed;
    item(name, " PASS\r\n");
}

static void equal_register(const char *name, uint32_t offset, uint32_t expected)
{
    uint32_t actual = npu_read(offset);
    if (actual != expected) {
        uint32_t first = 0u;
        uint32_t differences = 0u;
        for (uint32_t byte = 0u; byte < 4u; ++byte) {
            if (((actual >> (byte * 8u)) & 255u) != ((expected >> (byte * 8u)) & 255u)) {
                if (differences == 0u) {
                    first = byte;
                }
                ++differences;
            }
        }
        fail(name, npu_current_descriptor(), EDRV32_NPU_BASE + offset + first,
             (expected >> (first * 8u)) & 255u, (actual >> (first * 8u)) & 255u, differences);
    }
}

static void wait_done(const char *name)
{
    uint32_t irq;
    do {
        irq = npu_read(EDRV32_NPU_IRQ_STAT_OFFSET);
    } while ((irq & (EDRV32_NPU_IRQ_STAT_DONE_MASK | EDRV32_NPU_IRQ_STAT_ERROR_MASK)) == 0u);
    if ((irq & EDRV32_NPU_IRQ_STAT_ERROR_MASK) != 0u) {
        fail(name, npu_current_descriptor(), EDRV32_NPU_BASE + EDRV32_NPU_ERR_CODE_OFFSET,
             0u, npu_read(EDRV32_NPU_ERR_CODE_OFFSET), 1u);
    }
}

static void registers(void)
{
    equal_register("A-ID", EDRV32_NPU_ID_OFFSET, EDRV32_NPU_ID_RESET);
    pass("A-ID");
    npu_write(EDRV32_NPU_CTRL_OFFSET, EDRV32_NPU_CTRL_SOFT_RST_MASK);
    npu_write(EDRV32_NPU_DOORBELL_OFFSET, 1u);
    wait_done("A-empty");
    equal_register("A-empty", EDRV32_NPU_DONE_COUNT_OFFSET, 1u);
    equal_register("A-empty", EDRV32_NPU_STATUS_OFFSET, EDRV32_NPU_STATUS_RESET);
    pass("A-empty");

    /* Leave writable registers and DONE_COUNT nonzero before SOFT_RST. */
    npu_configure(&board_cases[0].config);
    npu_write(EDRV32_NPU_CTRL_OFFSET, EDRV32_NPU_CTRL_ENABLE_MASK);
    npu_write(EDRV32_NPU_IRQ_EN_OFFSET,
              EDRV32_NPU_IRQ_EN_DONE_MASK | EDRV32_NPU_IRQ_EN_ERROR_MASK);
    npu_write(EDRV32_NPU_CTRL_OFFSET, EDRV32_NPU_CTRL_SOFT_RST_MASK);
#define CHECK_RESET(name) equal_register("A-reset", EDRV32_NPU_##name##_OFFSET, \
                                         EDRV32_NPU_##name##_RESET)
    CHECK_RESET(ID);
    CHECK_RESET(CTRL);
    CHECK_RESET(STATUS);
    CHECK_RESET(IRQ_EN);
    CHECK_RESET(IRQ_STAT);
    CHECK_RESET(ERR_CODE);
    CHECK_RESET(DESC_BASE);
    CHECK_RESET(DESC_COUNT);
    CHECK_RESET(DOORBELL);
    CHECK_RESET(DONE_COUNT);
    CHECK_RESET(MODEL_BASE);
    CHECK_RESET(WORK_BASE);
    CHECK_RESET(INPUT_BASE);
    CHECK_RESET(OUTPUT_BASE);
    CHECK_RESET(CUR_DESC);
#undef CHECK_RESET
    for (unsigned int i = 0u; i < EDRV32_NPU_PERF_N_COUNT; ++i) {
        equal_register("A-reset", EDRV32_NPU_PERF_OFFSET(i), EDRV32_NPU_PERF_RESET);
    }
    pass("A-reset");
}

static uint8_t *cached(uint32_t physical)
{
    return (uint8_t *)(EDRV32_DDR_BASE + physical);
}

static void prepare(const struct board_case *test)
{
    for (uint32_t i = 0u; i < test->span_count; ++i) {
        const struct board_span *span = &test->spans[i];
        uint8_t *destination = cached(span->address);
        for (uint32_t byte = 0u; byte < span->size; ++byte) {
            destination[byte] = 0u;
        }
    }
    for (uint32_t i = 0u; i < test->load_count; ++i) {
        const struct board_load *load = &test->loads[i];
        uint8_t *destination = cached(load->address);
        const uint8_t *source = _binary_cases_bin_start + load->offset;
        for (uint32_t byte = 0u; byte < load->size; ++byte) {
            destination[byte] = source[byte];
        }
    }
    npu_configure(&test->config);
}

static void run(const struct board_case *test, const char *name)
{
    npu_write(EDRV32_NPU_IRQ_STAT_OFFSET, EDRV32_NPU_IRQ_STAT_DONE_MASK);
    /* SoC 7.4: clean all CPU-initialized inputs, residuals, descriptors and padding. */
    for (uint32_t i = 0u; i < test->span_count; ++i) {
        cache_clean((uintptr_t)cached(test->spans[i].address), test->spans[i].size);
    }
    npu_start(test->config.input, test->config.output);
    wait_done(name);
    for (uint32_t i = 0u; i < test->check_count; ++i) {
        cache_invalidate((uintptr_t)cached(test->checks[i].address), test->checks[i].size);
    }
}

static void channel_errors(const struct board_case *test)
{
    const uint32_t bases[] = {
        test->config.model, test->config.work, test->config.input, test->config.output
    };
    for (uint32_t i = 0u; i < test->check_count; ++i) {
        const struct board_check *check = &test->checks[i];
        const uint32_t *descriptor = (const uint32_t *)cached(
            test->config.descriptors + 64u * check->descriptor);
        uint32_t stride = descriptor[4];
        uint32_t output = bases[(descriptor[0] >> 14) & 3u] + descriptor[3];
        const uint8_t *actual = cached(check->address);
        const uint8_t *expected = _binary_cases_bin_start + check->offset;
        uint32_t counts[256];
        uint32_t differences = 0u;
        for (uint32_t channel = 0u; channel < ARRAY_SIZE(counts); ++channel) {
            counts[channel] = 0u;
        }
        for (uint32_t byte = 0u; byte < check->size; ++byte) {
            if (actual[byte] != expected[byte]) {
                uint32_t offset = check->address - output + byte;
                /* npu-spec 4.1: C16 planes, then pixels, then channel bytes. */
                uint32_t channel = offset / stride * 16u + offset % stride % 16u;
                ++counts[channel];
                ++differences;
            }
        }
        if (differences != 0u) {
            item(test->name, " channels");
            field(" desc=", check->descriptor);
            for (uint32_t channel = 0u; channel < ARRAY_SIZE(counts); ++channel) {
                if (counts[channel] != 0u) {
                    uart_putc(' ');
                    decimal(channel);
                    uart_putc(':');
                    decimal(counts[channel]);
                }
            }
            uart_puts("\r\n");
        }
    }
}

static void compare(const struct board_case *test, const char *name, uint32_t small)
{
    uint32_t differences = 0u;
    uint32_t first_address = 0u;
    uint32_t first_expected = 0u;
    uint32_t first_actual = 0u;
    uint32_t first_descriptor = 0u;
    for (uint32_t i = 0u; i < test->check_count; ++i) {
        const struct board_check *check = &test->checks[i];
        const uint8_t *actual = cached(check->address);
        const uint8_t *expected = _binary_cases_bin_start + check->offset;
        for (uint32_t byte = 0u; byte < check->size; ++byte) {
            if (actual[byte] != expected[byte]) {
                if (differences == 0u) {
                    first_address = check->address + byte;
                    first_expected = expected[byte];
                    first_actual = actual[byte];
                    first_descriptor = check->descriptor;
                }
                ++differences;
            }
        }
    }
    if (small != 0u) {
        item(name, differences == 0u ? " PASS" : " FAIL");
        field(" mismatches=", differences);
        field(" desc=", first_descriptor);
        hex_field(" addr=", first_address);
        hex_field(" expected=", first_expected);
        hex_field(" actual=", first_actual);
        performance();
        uart_puts("\r\n");
        if (differences != 0u) {
            ++failed;
            channel_errors(test);
        } else {
            ++passed;
        }
    } else if (differences != 0u) {
        fail(name, first_descriptor, first_address, first_expected, first_actual, differences);
    }
}

static uint32_t crc32(const struct board_case *test)
{
    uint32_t crc = 0xffffffffu;
    for (uint32_t i = 0u; i < test->check_count; ++i) {
        const struct board_check *check = &test->checks[i];
        const uint8_t *data = cached(check->address);
        for (uint32_t byte = 0u; byte < check->size; ++byte) {
            crc ^= data[byte];
            for (unsigned int bit = 0u; bit < 8u; ++bit) {
                crc = (crc >> 1) ^ ((0u - (crc & 1u)) & 0xedb88320u);
            }
        }
    }
    return ~crc;
}

static void performance(void)
{
    field(" PERF0=", npu_read(EDRV32_NPU_PERF_OFFSET(0)));
    field(" MAC=", npu_read(EDRV32_NPU_PERF_OFFSET(1)));
}

static void milli(uint32_t value)
{
    decimal(value / 1000u);
    uart_putc('.');
    uart_putc((uint8_t)('0' + (value / 100u) % 10u));
    uart_putc((uint8_t)('0' + (value / 10u) % 10u));
    uart_putc((uint8_t)('0' + value % 10u));
}

int main(void)
{
    /* BIOS has already selected the 2 Mbaud UART; keep its baud setting. */
    gpio_set_output_enable(LED_PASS | LED_FAIL);
    gpio_write(0u);
    registers();
    for (unsigned int i = 0u; i + 1u < ARRAY_SIZE(board_cases); ++i) {
        const struct board_case *test = &board_cases[i];
        prepare(test);
        run(test, test->name);
        compare(test, test->name, 1u);
    }

    const struct board_case *network = &board_cases[ARRAY_SIZE(board_cases) - 1u];
    prepare(network);
    run(network, network->name);
    compare(network, network->name, 0u);
    uint32_t reference_crc = crc32(network);
    uint32_t cycles = npu_read(EDRV32_NPU_PERF_OFFSET(0));
    ++passed;
    item(network->name, " PASS");
    performance();
    uart_puts(" ms/frame=");
    milli((uint32_t)((uint64_t)cycles * 1000000u / NPU_CLOCK_HZ));
    uart_puts(" fps=");
    milli((uint32_t)((uint64_t)NPU_CLOCK_HZ * 1000u / cycles));
    hex_field(" CRC32=", reference_crc);
    uart_puts("\r\n");
    for (unsigned int iteration = 1u; iteration <= STABILITY_RUNS; ++iteration) {
        char name[] = "D-00";
        name[2] = (char)('0' + iteration / 10u);
        name[3] = (char)('0' + iteration % 10u);
        run(network, name);
        uint32_t actual_crc = crc32(network);
        if (actual_crc != reference_crc) {
            /* C passed against the same bytes; report the first differing output byte. */
            compare(network, name, 0u);
        }
        ++passed;
        item(name, " PASS");
        hex_field(" CRC32=", actual_crc);
        performance();
        uart_puts("\r\n");
    }
    finish(failed);
}
