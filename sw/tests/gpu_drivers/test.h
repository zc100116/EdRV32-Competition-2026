/* File: test.h
 * Spec: gpu-soc-testplan ST-10-ST-14; visual SoC 9.2.
 * Description: Shared software assertions and uncached external-check mailbox.
 * Clock domain: clk_sys software.
 */
#ifndef GPU_TEST_H
#define GPU_TEST_H
#include "gpu.h"
#include "sysctrl.h"
#include "uart.h"
#include "plic.h"

/* Test memory allocations are physical DDR byte offsets. */
#define GPU_TEST_MAIL 0x003ff000u
static inline volatile uint32_t *test_mail(void)
{
    return (volatile uint32_t *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + GPU_TEST_MAIL);
}
static inline void test_init(void)
{
    uart_init();
    uart_set_baud(EDRV32_CLK_SYS_HZ, 115200u);
}
static inline void test_finish(uint32_t code)
{
    uart_drain();
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    sysctrl_write(SYSCTRL_SIM_EXIT, code);
    for (;;) {
        __asm__ volatile ("wfi");
    }
}
static inline void test_equal(const char *label, uint32_t expected, uint32_t actual)
{
    if (actual != expected) {
        uart_puts("FAIL ");
        uart_puts(label);
        uart_puts("\r\n");
        test_finish(1u);
    }
}
static inline void test_external(uint32_t operation)
{
    test_mail()[1] = 0u;
    test_mail()[0] = operation;
    while (test_mail()[1] == 0u) {
    }
}
#endif
