/* File: host.c
 * Spec: CLAUDE.md 9.2; infra-plan I-07
 * Description: Implement the tohost exit and HTIF write-system-call conventions.
 *              Exit value is (status << 1) | 1; zero status therefore writes 1.
 * Clock domain: clk_sys.
 */
#include "edrv32.h"

volatile uint64_t tohost __attribute__((section(".tohost"), aligned(64))) = 0;
volatile uint64_t fromhost __attribute__((section(".tohost"), aligned(64))) = 0;

_Noreturn void edrv32_exit(int status)
{
    __asm__ volatile ("fence rw, rw" ::: "memory");
    tohost = ((uint64_t)(uint32_t)status << 1) | 1;
    for (;;) {
        __asm__ volatile ("wfi");
    }
}

void edrv32_putchar(char value)
{
    volatile uint64_t request[8] __attribute__((aligned(16)));
    request[0] = 64;
    request[1] = 1;
    request[2] = (uintptr_t)&value;
    request[3] = 1;
    request[4] = 0;
    request[5] = 0;
    request[6] = 0;
    request[7] = 0;
    __asm__ volatile ("fence rw, rw" ::: "memory");
    tohost = (uintptr_t)request;
    while (fromhost == 0) {
    }
    fromhost = 0;
    __asm__ volatile ("fence rw, rw" ::: "memory");
}
