/* File: main.c
 * Spec: gpu-soc-testplan ST-09; gpu-soc-spec 6.1.
 * Description: Check media IDs, reserved-slot access faults and PLIC source routing.
 *              IRQ levels are requested through the external DDR-model mailbox.
 * Clock domain: clk_sys software; APB and DDR cross to clk_mem.
 */
#include "gpu_soc_map.h"
#include "sysctrl.h"
#include "uart.h"
#include "plic.h"
#include "regs/aud_regs.h"
#include "regs/disp_gpu_regs.h"
#include "regs/gpu_regs.h"
#include "regs/eth_regs.h"
#include "regs/mem_xbar_gpu_regs.h"

static volatile uint32_t expected_cause;
static volatile uint32_t fault_count;

static _Noreturn void finish(uint32_t code)
{
    uart_drain();
    sysctrl_write(SYSCTRL_SIM_EXIT, code);
    for (;;) __asm__ volatile ("wfi");
}
static void hex(uint32_t value)
{
    for (int digit = 7; digit >= 0; digit--)
        uart_putc("0123456789abcdef"[(value >> (4 * digit)) & 15u]);
}
static void equal(const char *name, uint32_t expected, uint32_t actual)
{
    if (actual != expected) {
        uart_puts("FAIL "); uart_puts(name);
        uart_puts(" expected="); hex(expected);
        uart_puts(" actual="); hex(actual); uart_puts("\r\n");
        finish(1u);
    }
}
static void __attribute__((interrupt("machine"), aligned(4))) trap(void)
{
    uint32_t cause;
    uint32_t pc;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    equal("reserved access cause", expected_cause, cause);
    fault_count++;
    __asm__ volatile ("csrr %0, mepc" : "=r"(pc));
    pc += 4u;
    __asm__ volatile ("csrw mepc, %0" :: "r"(pc));
}
static void reserved(unsigned int slot)
{
    uintptr_t address = EDRV32_MEDIA_APB_BASE + slot * EDRV32_APB_SLOT_SIZE;
    uint32_t before = fault_count;
    expected_cause = 5u;
    __asm__ volatile ("lw zero, 0(%0)" :: "r"(address) : "memory");
    equal("reserved read fault", before + 1u, fault_count);
    expected_cause = 7u;
    __asm__ volatile ("sw zero, 0(%0)" :: "r"(address) : "memory");
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    equal("reserved write fault", before + 2u, fault_count);
    expected_cause = 0u;
}
static void interrupt_source(unsigned int source)
{
    /* Mailbox words 0=request and 1=ack; DDR physical 0x003ff000. */
    volatile uint32_t *mail = (volatile uint32_t *)(EDRV32_DDR_UNCACHED_BASE + 0x003ff000u);
    plic_set_priority(source, 1u);
    plic_set_enable(1u << source);
    plic_set_threshold(0u);
    mail[0] = source;
    while (mail[1] != source) {}
    while ((plic_pending() & (1u << source)) == 0u) {}
    equal("PLIC pending route", 1u << source, plic_pending());
    equal("PLIC claim route", source, plic_claim());
    equal("PLIC pending claimed", 0u, plic_pending());
    mail[0] = 0u;
    while (mail[1] != 0u) {}
    plic_complete(source);
    equal("PLIC completed", 0u, plic_claim());
}
int main(void)
{
    uart_init();
    uart_set_baud(EDRV32_CLK_SYS_HZ, 115200u);
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uintptr_t)trap));
    equal("AUD ID", EDRV32_AUD_ID_RESET,
          mmio_read32(EDRV32_AUD_BASE + EDRV32_AUD_ID_OFFSET));
    equal("DISP ID", EDRV32_DISP_GPU_ID_RESET,
          mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_ID_OFFSET));
#ifndef GPU_PARTIAL
    equal("GPU ID", EDRV32_GPU_ID_RESET,
          mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_ID_OFFSET));
#endif
    equal("ETH ID", EDRV32_ETH_ID_RESET,
          mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_ID_OFFSET));
    equal("MEM_XBAR ID", EDRV32_MEM_XBAR_GPU_ID_RESET,
          mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_GPU_ID_OFFSET));
    const unsigned int slots[] = {0, 2, 3, 4, 9, 10, 11, 12, 13, 14, 15};
    for (unsigned int i = 0; i < sizeof(slots) / sizeof(slots[0]); i++) reserved(slots[i]);
    const unsigned int sources[] = {EDRV32_PLIC_SOURCE_AUD, EDRV32_PLIC_SOURCE_DISP,
#ifndef GPU_PARTIAL
        EDRV32_PLIC_SOURCE_GPU,
#endif
        EDRV32_PLIC_SOURCE_ETH, EDRV32_PLIC_SOURCE_MEM_XBAR};
    for (unsigned int i = 0; i < sizeof(sources) / sizeof(sources[0]); i++)
        interrupt_source(sources[i]);
#ifdef GPU_PARTIAL
    uart_puts("ST-09 non-GPU: 4 IDs, 22 SLVERR, 4 PLIC sources PASS\r\n");
#else
    uart_puts("ST-09: 5 IDs, 22 SLVERR, 5 PLIC sources PASS\r\n");
#endif
    finish(0u);
}
