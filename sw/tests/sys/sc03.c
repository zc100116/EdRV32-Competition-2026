/* File: sc03.c
 * Spec: sys-subsys-testplan 3.6 SC-03; sys-subsys-spec 2.5, 2.7
 * Description: Claim and complete the GPIO rising-edge interrupt through PLIC.
 * Clock domain: clk_sys.
 */
#include "gpio.h"
#include "plic.h"
#include "sc.h"

#define SC_GPIO_BIT 1u
static volatile uint32_t gpio_seen;

static void __attribute__((interrupt("machine"), aligned(4))) gpio_handler(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (cause != 0x8000000bu) {
        sc_finish(3u);
    }
    unsigned int source = plic_claim();
    /* PLIC MEIP deassertion is registered; a trailing interrupt may claim zero. */
    if (source == EDRV32_PLIC_SOURCE_NONE) {
        return;
    }
    if (source != EDRV32_PLIC_SOURCE_GPIO0 ||
        gpio_irq_status() != (1u << SC_GPIO_BIT)) {
        sc_finish(4u);
    }
    gpio_irq_clear(1u << SC_GPIO_BIT);
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    plic_complete(source);
    gpio_seen = 1u;
}

int main(void)
{
    uintptr_t handler = (uintptr_t)gpio_handler;
    gpio_set_output_enable(0u);
    gpio_set_debounce(0u);
    gpio_irq_clear(GPIO_PIN_MASK);
    gpio_set_edges(1u << SC_GPIO_BIT, 0u);
    plic_set_priority(EDRV32_PLIC_SOURCE_GPIO0, 1u);
    plic_set_threshold(0u);
    plic_set_enable(1u << EDRV32_PLIC_SOURCE_GPIO0);
    __asm__ volatile ("csrw mtvec, %0" :: "r"(handler) : "memory");
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 11) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    sysctrl_write(SYSCTRL_SCRATCH1, 0x53430003u);
    while (gpio_seen == 0u) {
    }
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    sc_finish(0u);
}
