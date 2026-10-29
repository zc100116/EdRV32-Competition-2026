/* File: main.c
 * Spec: edrv32-soc-spec 6.1, 7.1, 7.4; geo-spec 2.1/2.6, 4; Task B3-10.
 * Description: Check six engine IDs and the omitted RND read fault, transform
 *              64x4 RGB565 pixels, service PLIC10 and compare uncached DDR words.
 * Clock domain: clk_sys (CPU), clk_mem (MMIO and DDR).
 */
#include "edrv32.h"
#include "mmio.h"
#include "plic.h"
#include "sysctrl.h"
#include "uart.h"
#include "regs/vin_regs.h"
#include "regs/pix_regs.h"
#include "regs/geo_regs.h"
#include "regs/disp_regs.h"
#include "regs/eth_regs.h"
#include "regs/npu_regs.h"
#include "regs/rnd_regs.h"

#define DESC_PHYS 0x00001000u
#define SRC_PHYS 0x00002000u
#define DST_PHYS 0x00003000u
#define WORDS (64u * 4u / 2u)

static volatile uint32_t done;
static volatile uint32_t fault_count;
static volatile uint32_t fault_addr;

static _Noreturn void finish(uint32_t code)
{
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    sysctrl_write(SYSCTRL_SIM_EXIT, code);
    edrv32_exit((int)code);
}

static void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (cause == 5u) {
        uint32_t addr;
        uintptr_t pc;
        __asm__ volatile ("csrr %0, mtval" : "=r"(addr));
        if (addr != fault_addr) {
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
    if (source != EDRV32_PLIC_SOURCE_GEO ||
        mmio_read32(EDRV32_GEO_BASE + EDRV32_GEO_IRQ_STAT_OFFSET) !=
        EDRV32_GEO_IRQ_STAT_DONE_MASK) {
        finish(4u);
    }
    mmio_write32(EDRV32_GEO_BASE + EDRV32_GEO_IRQ_STAT_OFFSET,
                 EDRV32_GEO_IRQ_STAT_DONE_MASK);
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    plic_complete(source);
    done = 1u;
}

static void check_id(uintptr_t addr, uint32_t expected)
{
    uint32_t actual = mmio_read32(addr);
    if (actual != expected) {
        sysctrl_write(SYSCTRL_SCRATCH0, actual);
        sysctrl_write(SYSCTRL_SCRATCH1, expected);
        finish(1u);
    }
}

static void check_empty(uintptr_t addr)
{
    fault_addr = addr;
    fault_count = 0u;
    __asm__ volatile ("lw zero, 0(%0)" :: "r"(addr) : "memory");
    if (fault_count != 1u) {
        finish(7u);
    }
}

static uint32_t pattern(unsigned int index)
{
    return 0x13572468u ^ (index * 0x01020408u);
}

int main(void)
{
    uintptr_t handler = (uintptr_t)trap_handler;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(handler) : "memory");
    check_id(EDRV32_VIN_BASE + EDRV32_VIN_ID_OFFSET, EDRV32_VIN_ID_RESET);
    check_id(EDRV32_PIX_BASE + EDRV32_PIX_ID_OFFSET, EDRV32_PIX_ID_RESET);
    check_id(EDRV32_GEO_BASE + EDRV32_GEO_ID_OFFSET, EDRV32_GEO_ID_RESET);
    check_id(EDRV32_DISP_BASE + EDRV32_DISP_ID_OFFSET, EDRV32_DISP_ID_RESET);
    check_id(EDRV32_ETH_BASE + EDRV32_ETH_ID_OFFSET, EDRV32_ETH_ID_RESET);
    check_id(EDRV32_NPU_BASE + EDRV32_NPU_ID_OFFSET, EDRV32_NPU_ID_RESET);
    /* B3-10 board contract: exactly one read to the omitted RND slot. */
    check_empty(EDRV32_RND_BASE + EDRV32_RND_ID_OFFSET);
    volatile uint32_t *desc = (volatile uint32_t *)(EDRV32_DDR_UNCACHED_BASE + DESC_PHYS);
    volatile uint32_t *src = (volatile uint32_t *)(EDRV32_DDR_UNCACHED_BASE + SRC_PHYS);
    volatile uint32_t *dst = (volatile uint32_t *)(EDRV32_DDR_UNCACHED_BASE + DST_PHYS);
    for (unsigned int i = 0u; i < EDRV32_GEO_DESC_SIZE / 4u; ++i) {
        desc[i] = 0u;
    }
    /* geo-spec 2.6: 64x4 RGB565, tightly packed rows, identity Q16.16 matrix. */
    desc[EDRV32_GEO_DESC_SRC_BASE_OFFSET / 4u] = SRC_PHYS;
    desc[EDRV32_GEO_DESC_SRC_STRIDE_OFFSET / 4u] = 64u * 2u;
    desc[EDRV32_GEO_DESC_SRC_W_OFFSET / 4u] = (4u << EDRV32_GEO_DESC_SRC_H_POS) | 64u;
    desc[EDRV32_GEO_DESC_DST_BASE_OFFSET / 4u] = DST_PHYS;
    desc[EDRV32_GEO_DESC_DST_STRIDE_OFFSET / 4u] = 64u * 2u;
    desc[EDRV32_GEO_DESC_RECT_W_OFFSET / 4u] = (4u << EDRV32_GEO_DESC_RECT_H_POS) | 64u;
    desc[EDRV32_GEO_DESC_A_OFFSET / 4u] = 1u << 16;
    desc[EDRV32_GEO_DESC_D_OFFSET / 4u] = 1u << 16;
    for (unsigned int i = 0u; i < WORDS; ++i) {
        src[i] = pattern(i);
        dst[i] = 0u;
    }
    plic_set_priority(EDRV32_PLIC_SOURCE_GEO, 1u);
    plic_set_threshold(0u);
    plic_set_enable(1u << EDRV32_PLIC_SOURCE_GEO);
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 11) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    mmio_write32(EDRV32_GEO_BASE + EDRV32_GEO_IRQ_EN_OFFSET,
                 EDRV32_GEO_IRQ_EN_DONE_MASK | EDRV32_GEO_IRQ_EN_ERROR_MASK);
    mmio_write32(EDRV32_GEO_BASE + EDRV32_GEO_DESC_BASE_OFFSET, DESC_PHYS);
    mmio_write32(EDRV32_GEO_BASE + EDRV32_GEO_DESC_COUNT_OFFSET, 1u);
    mmio_write32(EDRV32_GEO_BASE + EDRV32_GEO_DOORBELL_OFFSET, 1u);
    while (done == 0u) {
    }
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    for (unsigned int i = 0u; i < WORDS; ++i) {
        uint32_t actual = dst[i];
        if (actual != pattern(i)) {
            sysctrl_write(SYSCTRL_SCRATCH1, i);
            sysctrl_write(SYSCTRL_SCRATCH0, actual);
            finish(5u);
        }
    }
    uart_puts("board_vnpu IDs and 256 pixels PASS\r\n");
    uart_drain();
    finish(0u);
}
