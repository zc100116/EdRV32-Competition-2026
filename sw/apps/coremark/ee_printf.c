/* File: ee_printf.c
 * Spec: infra-plan I-07; CLAUDE.md 9.2
 * Description: Format the integer and string conversions used by CoreMark.
 *              Output characters through the BSP HTIF console.
 * Clock domain: clk_sys.
 */
#include <stdarg.h>
#include "core_portme.h"
#include "edrv32.h"

static int print_number(uint32_t value, unsigned base, unsigned width, char pad)
{
    const char digits[] = "0123456789abcdef";
    char buffer[32];
    unsigned length = 0;
    int count = 0;
    do {
        buffer[length++] = digits[value % base];
        value /= base;
    } while (value != 0);
    while (width > length) {
        edrv32_putchar(pad);
        --width;
        ++count;
    }
    while (length != 0) {
        edrv32_putchar(buffer[--length]);
        ++count;
    }
    return count;
}

int ee_printf(const char *format, ...)
{
    va_list args;
    int count = 0;
    va_start(args, format);
    while (*format != '\0') {
        if (*format != '%') {
            edrv32_putchar(*format++);
            ++count;
            continue;
        }
        ++format;
        char pad = ' ';
        unsigned width = 0;
        if (*format == '0') {
            pad = '0';
            ++format;
        }
        while (*format >= '0' && *format <= '9') {
            width = width * 10 + (unsigned)(*format++ - '0');
        }
        int long_value = (*format == 'l');
        if (long_value) {
            ++format;
        }
        switch (*format++) {
        case 's': {
            const char *value = va_arg(args, const char *);
            while (*value != '\0') {
                edrv32_putchar(*value++);
                ++count;
            }
            break;
        }
        case 'd': {
            int32_t value = long_value ? va_arg(args, long) : va_arg(args, int);
            uint32_t magnitude = (uint32_t)value;
            if (value < 0) {
                edrv32_putchar('-');
                ++count;
                magnitude = 0u - magnitude;
                if (width != 0) --width;
            }
            count += print_number(magnitude, 10, width, pad);
            break;
        }
        case 'u':
            count += print_number(long_value ? va_arg(args, unsigned long) :
                                  va_arg(args, unsigned int), 10, width, pad);
            break;
        case 'x':
            count += print_number(long_value ? va_arg(args, unsigned long) :
                                  va_arg(args, unsigned int), 16, width, pad);
            break;
        case '%':
            edrv32_putchar('%');
            ++count;
            break;
        default:
            edrv32_exit(1);
        }
    }
    va_end(args);
    return count;
}
