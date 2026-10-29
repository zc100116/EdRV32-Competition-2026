/* File: main.c
 * Spec: edrv32-soc-spec 6.1, 7.1, 7.4; rnd-spec 2.5/2.6 FILL, 4; Task B3-6.
 * Description: Check RND/DISP IDs, render 64x4 ARGB8888 pixels through DDR,
 *              service PLIC source 11 and compare all pixels via the uncached alias.
 * Clock domain: clk_sys (CPU), clk_mem (MMIO and DDR).
 */
#include "edrv32.h"
#include "mmio.h"
#include "plic.h"
#include "sysctrl.h"
#include "uart.h"
#include "regs/disp_regs.h"
#include "regs/rnd_regs.h"

#define DESC_PHYS 0x00001000u
#define DST_PHYS 0x00002000u
#define PIXELS (64u * 4u)
#define COLOR 0xff2468acu

static volatile uint32_t done;

static _Noreturn void finish(uint32_t code)
{
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    sysctrl_write(SYSCTRL_SIM_EXIT, code);
    edrv32_exit((int)code);
}

static void __attribute__((interrupt("machine"), aligned(4))) rnd_handler(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (cause != 0x8000000bu) {
        finish(3u);
    }
    unsigned int source = plic_claim();
    /* PLIC's registered MEIP can cause a trailing interrupt with claim zero. */
    if (source == EDRV32_PLIC_SOURCE_NONE) {
        return;
    }
    if (source != EDRV32_PLIC_SOURCE_RND ||
        mmio_read32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET) !=
        EDRV32_RND_IRQ_STAT_DONE_MASK) {
        finish(4u);
    }
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET,
                 EDRV32_RND_IRQ_STAT_DONE_MASK);
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    plic_complete(source);
    done = 1u;
}

int main(void)
{
    if (mmio_read32(EDRV32_RND_BASE + EDRV32_RND_ID_OFFSET) != EDRV32_RND_ID_RESET) {
        finish(1u);
    }
    if (mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_ID_OFFSET) != EDRV32_DISP_ID_RESET) {
        finish(2u);
    }
    volatile uint32_t *desc = (volatile uint32_t *)(EDRV32_DDR_UNCACHED_BASE + DESC_PHYS);
    volatile uint32_t *pixels = (volatile uint32_t *)(EDRV32_DDR_UNCACHED_BASE + DST_PHYS);
    for (unsigned int i = 0u; i < 16u; ++i) {
        desc[i] = 0u;
    }
    /* rnd-spec 2.5/2.6: FILL, ARGB8888, opaque, no rounding, inclusive rectangle. */
    desc[0] = 0x101u;
    desc[1] = DST_PHYS;
    desc[2] = 64u * 4u;
    desc[4] = (3u << 16) | 63u;
    desc[6] = (3u << 16) | 63u;
    desc[7] = COLOR;
    for (unsigned int i = 0u; i < PIXELS; ++i) {
        pixels[i] = 0u;
    }
    plic_set_priority(EDRV32_PLIC_SOURCE_RND, 1u);
    plic_set_threshold(0u);
    plic_set_enable(1u << EDRV32_PLIC_SOURCE_RND);
    uintptr_t handler = (uintptr_t)rnd_handler;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(handler) : "memory");
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 11) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_IRQ_EN_OFFSET,
                 EDRV32_RND_IRQ_EN_DONE_MASK | EDRV32_RND_IRQ_EN_ERROR_MASK);
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_DESC_BASE_OFFSET, DESC_PHYS);
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_DESC_COUNT_OFFSET, 1u);
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_DOORBELL_OFFSET, 1u);
    while (done == 0u) {
    }
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    for (unsigned int i = 0u; i < PIXELS; ++i) {
        uint32_t actual = pixels[i];
        if (actual != COLOR) {
            sysctrl_write(SYSCTRL_SCRATCH1, i);
            sysctrl_write(SYSCTRL_SCRATCH0, actual);
            finish(5u);
        }
    }
    uart_puts("board_render IDs and 256 pixels PASS\r\n");
    uart_drain();
    finish(0u);
}
