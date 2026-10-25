/* File: sc02.c
 * Spec: sys-subsys-testplan 3.6 SC-02; sys-subsys-spec 2.4
 * Description: Program a CLINT deadline and verify a machine timer interrupt.
 * Clock domain: clk_sys.
 */
#include "clint.h"
#include "sc.h"

static volatile uint32_t timer_seen;

static void __attribute__((interrupt("machine"), aligned(4))) timer_handler(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (cause != 0x80000007u) {
        sc_finish(2u);
    }
    clint_set_compare(UINT64_MAX);
    timer_seen = 1u;
}

int main(void)
{
    uintptr_t handler = (uintptr_t)timer_handler;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(handler) : "memory");
    clint_set_compare(clint_time() + 4096u);
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 7) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    while (timer_seen == 0u) {
    }
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    sc_finish(0u);
}
