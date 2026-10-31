/* File: main.c
 * Spec: Task T-BN1; edrv32-soc-spec 6.1/7.1/7.4; npu-spec 3/4.
 * Description: Read NPU/ETH IDs and removed VIN slot, start one preloaded CONV,
 *              service PLIC13 DONE and compare every output byte via uncached DDR.
 * Clock domain: clk_sys (CPU), clk_mem/clk_npu (MMIO and DDR).
 */
#include "edrv32.h"
#include "mmio.h"
#include "plic.h"
#include "sysctrl.h"
#include "uart.h"
#include "regs/eth_regs.h"
#include "regs/vin_regs.h"
#include "regs/npu_regs.h"
#include "npu_case.h"

static volatile uint32_t done;
static volatile uint32_t fault_count;

static _Noreturn void finish(uint32_t code)
{
    uart_drain();
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    sysctrl_write(SYSCTRL_SIM_EXIT, code);
    edrv32_exit((int)code);
}

static void print_hex(uint32_t value)
{
    static const char digits[] = "0123456789abcdef";
    for (unsigned int i = 0; i < 8; ++i) {
        uart_putc((uint8_t)digits[(value >> (28u - 4u * i)) & 15u]);
    }
}

static void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (cause == 5u) {
        uint32_t addr;
        uintptr_t pc;
        __asm__ volatile ("csrr %0, mtval" : "=r"(addr));
        if (addr != EDRV32_VIN_BASE + EDRV32_VIN_ID_OFFSET) {
            finish(6u);
        }
        ++fault_count;
        /* rv32im has fixed 4-byte instructions; skip the one deliberate LW. */
        __asm__ volatile ("csrr %0, mepc" : "=r"(pc));
        pc += 4u;
        __asm__ volatile ("csrw mepc, %0" :: "r"(pc) : "memory");
        return;
    }
    if (cause != 0x8000000bu) {
        finish(3u);
    }
    unsigned int source = plic_claim();
    /* PLIC's registered MEIP can cause a trailing interrupt with claim zero. */
    if (source == EDRV32_PLIC_SOURCE_NONE) {
        return;
    }
    if (source != EDRV32_PLIC_SOURCE_NPU ||
        mmio_read32(EDRV32_NPU_BASE + EDRV32_NPU_IRQ_STAT_OFFSET) !=
        EDRV32_NPU_IRQ_STAT_DONE_MASK) {
        finish(4u);
    }
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_IRQ_STAT_OFFSET,
                 EDRV32_NPU_IRQ_STAT_DONE_MASK);
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    plic_complete(source);
    done = 1u;
}

int main(void)
{
    if (mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_ID_OFFSET) != EDRV32_ETH_ID_RESET) {
        finish(8u);
    }
    uintptr_t handler = (uintptr_t)trap_handler;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(handler) : "memory");
    uint32_t id = mmio_read32(EDRV32_NPU_BASE + EDRV32_NPU_ID_OFFSET);
    uart_puts("NPU ID actual=");
    print_hex(id);
    uart_puts(" expected=");
    print_hex(EDRV32_NPU_ID_RESET);
    uart_puts("\r\n");
    if (id != EDRV32_NPU_ID_RESET) {
        sysctrl_write(SYSCTRL_SCRATCH0, id);
        sysctrl_write(SYSCTRL_SCRATCH1, EDRV32_NPU_ID_RESET);
        finish(1u);
    }
    uart_puts("NPU ID PASS\r\n");
    /* B3-10 empty-slot contract: exactly one read to the removed VIN slot. */
    uintptr_t empty = EDRV32_VIN_BASE + EDRV32_VIN_ID_OFFSET;
    __asm__ volatile ("lw zero, 0(%0)" :: "r"(empty) : "memory");
    if (fault_count != 1u) {
        finish(7u);
    }
    uart_puts("NPU removed VIN SLVERR PASS\r\n");
    plic_set_priority(EDRV32_PLIC_SOURCE_NPU, 1u);
    plic_set_threshold(0u);
    plic_set_enable(1u << EDRV32_PLIC_SOURCE_NPU);
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 11) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_IRQ_EN_OFFSET,
                 EDRV32_NPU_IRQ_EN_DONE_MASK | EDRV32_NPU_IRQ_EN_ERROR_MASK);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_MODEL_BASE_OFFSET, NPU_CASE_MODEL_BASE);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_WORK_BASE_OFFSET, NPU_CASE_WORK_BASE);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_INPUT_BASE_OFFSET, NPU_CASE_INPUT_BASE);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_OUTPUT_BASE_OFFSET, NPU_CASE_OUTPUT_BASE);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_DESC_BASE_OFFSET, NPU_CASE_DESC_BASE);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_DESC_COUNT_OFFSET, NPU_CASE_DESC_COUNT);
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_DOORBELL_OFFSET, 1u);
    while (done == 0u) {
    }
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    uart_puts("NPU DONE PLIC13 PASS\r\n");
    volatile const uint8_t *output = (volatile const uint8_t *)(EDRV32_DDR_UNCACHED_BASE +
                                                             NPU_CASE_OUTPUT_ADDRESS);
    for (unsigned int i = 0; i < sizeof(npu_expected); ++i) {
        uint8_t actual = output[i];
        if (actual != npu_expected[i]) {
            uart_puts("NPU output FAIL address=");
            print_hex(NPU_CASE_OUTPUT_ADDRESS + i);
            uart_puts(" expected=");
            print_hex(npu_expected[i]);
            uart_puts(" actual=");
            print_hex(actual);
            uart_puts("\r\n");
            finish(5u);
        }
    }
    uart_puts("NPU output compare PASS 64 bytes\r\n");
    finish(0u);
}
