#include <stdarg.h>

#include "coremark.h"
#include "edrv32_uart.h"
#include "hpm_profile.h"

volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1u;

static CORE_TICKS start_cycle_r;
static CORE_TICKS stop_cycle_r;
static ee_u32 start_instret_r;
static ee_u32 stop_instret_r;

static ee_u32 read_cycle(void)
{
    ee_u32 value;
    __asm__ __volatile__("csrr %0, mcycle" : "=r"(value) :: "memory");
    return value;
}

static ee_u32 read_instret(void)
{
    ee_u32 value;
    __asm__ __volatile__("csrr %0, minstret" : "=r"(value) :: "memory");
    return value;
}

void start_time(void)
{
    /* Inline CSR writes keep this timer boundary a leaf function. */
    __asm__ __volatile__(
        "csrw 0x7f0, zero\n\t"
        "csrw 0x320, zero" ::: "memory");
    start_instret_r = read_instret();
    start_cycle_r = read_cycle();
}

void stop_time(void)
{
    /* The cycle snapshot closes the timed window before HPM control. */
    stop_cycle_r = read_cycle();
    stop_instret_r = read_instret();
    __asm__ __volatile__(
        "addi t0, zero, -8\n\t"
        "csrw 0x320, t0\n\t"
        "addi t0, zero, -1\n\t"
        "csrw 0x7f0, t0" ::: "t0", "memory");
}

CORE_TICKS get_time(void)
{
    return stop_cycle_r - start_cycle_r;
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ticks / 100000000u;
}

void portable_init(core_portable *port, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    port->portable_id = 1u;
}

void portable_fini(core_portable *port)
{
    unsigned int cycles = stop_cycle_r - start_cycle_r;
    unsigned int score_x1000 = cycles == 0u ? 0u :
        (unsigned int)(((unsigned long long)ITERATIONS * 1000000000ull) /
                       (unsigned long long)cycles);

    ee_printf("CoreMark/MHz x1000: %u\n", score_x1000);
    hpm_capture();
    hpm_report(cycles, stop_instret_r - start_instret_r);
    port->portable_id = 0u;
}

void *portable_malloc(ee_size_t size)
{
    (void)size;
    return NULL;
}

void portable_free(void *memory)
{
    (void)memory;
}

static int put_character(char value)
{
    if (value == '\n')
        edrv32_uart_putc('\r');
    edrv32_uart_putc(value);
    return 1;
}

static int put_unsigned(unsigned int value, unsigned int radix,
                        unsigned int width, char pad)
{
    static const char digits[] = "0123456789abcdef";
    char buffer[16];
    unsigned int count = 0u;
    unsigned int index = 0u;

    do {
        buffer[index++] = digits[value % radix];
        value /= radix;
    } while (value != 0u);

    while (index < width) {
        count += put_character(pad);
        width--;
    }
    while (index != 0u)
        count += put_character(buffer[--index]);
    return (int)count;
}

int ee_printf(const char *format, ...)
{
    va_list arguments;
    int written = 0;

    va_start(arguments, format);
    while (*format != '\0') {
        unsigned int width = 0u;
        char pad = ' ';
        int long_value = 0;

        if (*format != '%') {
            written += put_character(*format++);
            continue;
        }

        format++;
        if (*format == '0') {
            pad = '0';
            format++;
        }
        while (*format >= '0' && *format <= '9') {
            width = width * 10u + (unsigned int)(*format - '0');
            format++;
        }
        if (*format == 'l') {
            long_value = 1;
            format++;
        }

        if (*format == 's') {
            const char *text = va_arg(arguments, const char *);
            while (*text != '\0')
                written += put_character(*text++);
        } else if (*format == 'x') {
            unsigned int value = long_value
                ? (unsigned int)va_arg(arguments, unsigned long)
                : va_arg(arguments, unsigned int);
            written += put_unsigned(value, 16u, width, pad);
        } else if (*format == 'u') {
            unsigned int value = long_value
                ? (unsigned int)va_arg(arguments, unsigned long)
                : va_arg(arguments, unsigned int);
            written += put_unsigned(value, 10u, width, pad);
        } else if (*format == 'd') {
            int value = long_value
                ? (int)va_arg(arguments, long)
                : va_arg(arguments, int);
            unsigned int magnitude;
            if (value < 0) {
                written += put_character('-');
                magnitude = 0u - (unsigned int)value;
            } else {
                magnitude = (unsigned int)value;
            }
            written += put_unsigned(magnitude, 10u, width, pad);
        } else if (*format == '%') {
            written += put_character('%');
        }

        if (*format != '\0')
            format++;
    }
    va_end(arguments);
    return written;
}
