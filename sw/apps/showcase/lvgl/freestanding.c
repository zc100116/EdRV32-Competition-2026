/* File: freestanding.c
 * Spec: CLAUDE 9.3; Task B3-3b freestanding LVGL support.
 * Description: Compiler-emitted structure initialization support, without a libc heap.
 * Clock domain: clk_sys.
 */
#include <stddef.h>

void *memset(void *destination, int value, size_t count)
{
    unsigned char *p = destination;
    for (size_t i = 0; i < count; ++i) p[i] = (unsigned char)value;
    return destination;
}
