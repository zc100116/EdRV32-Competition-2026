/* File: memory.c
 * Spec: CLAUDE.md 9.3; gpu-soc-testplan software builds.
 * Description: Freestanding aggregate initialization support emitted by the C compiler.
 * Clock domain: clk_sys software.
 */
#include <stddef.h>
void *memset(void *destination, int value, size_t bytes)
{
    volatile unsigned char *out = destination;
    for (size_t i = 0; i < bytes; ++i) {
        out[i] = (unsigned char)value;
    }
    return destination;
}
