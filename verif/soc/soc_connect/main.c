/* File: main.c
 * Spec: B2-1a connection smoke; edrv32-soc-spec 6.1, 7.4; cpu-spec 6.
 * Description: Check media decode, DDR aliases, directional P2 statistics and GEO MEIP.
 *              Private register constants are authorized for this connection test only.
 * Clock domain: clk_sys software; hardware bridges reach the other domains.
 */
#include <stdint.h>
#include "soc_map.h"
#include "cache.h"
#include "sysctrl.h"
#include "plic.h"

/* SoC 7.1 public media register layout; GEO 4.1 uses these offsets. */
#define MEDIA_ID 0x000u
#define MEDIA_IRQ_EN 0x00cu
#define MEDIA_IRQ_STAT 0x010u
#define MEDIA_DESC_BASE 0x020u
#define MEDIA_DESC_COUNT 0x024u
#define MEDIA_DOORBELL 0x028u
#define MEDIA_DONE_COUNT 0x02cu
/* mem-subsys-spec v0.4 4.1: STAT_CTRL and P2's four directional snapshots. */
#define MX_STAT_CTRL 0x110u
#define MX_P2_RD_TXN 0x440u
#define MX_P2_RD_BEAT 0x444u
#define MX_P2_WR_TXN 0x454u
#define MX_P2_WR_BEAT 0x458u

static volatile uint32_t expected_fault;
static volatile uint32_t fault_count;
static volatile uint32_t geo_interrupts;

static uint32_t read_reg(uintptr_t base, uint32_t offset)
{
    return *(volatile uint32_t *)(base + offset);
}

static void write_reg(uintptr_t base, uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(base + offset) = value;
}

static _Noreturn void finish(uint32_t code)
{
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    sysctrl_write(SYSCTRL_SIM_EXIT, code);
    for (;;) {
        __asm__ volatile ("wfi");
    }
}

static void require(int condition, uint32_t code)
{
    if (!condition) {
        finish(code);
    }
}

/* cpu-spec 4.5, 6: load access faults report cause=5 and the fault address in mtval. */
static void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void)
{
    uint32_t cause;
    uint32_t value;
    uint32_t pc;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    __asm__ volatile ("csrr %0, mtval" : "=r"(value));
    if (cause == 5u && expected_fault != 0u) {
        require(value == expected_fault, 0x101u);
        fault_count++;
        __asm__ volatile ("csrr %0, mepc" : "=r"(pc));
        pc += 4u;
        __asm__ volatile ("csrw mepc, %0" :: "r"(pc));
    } else if (cause == 0x8000000bu) {
        uint32_t source = plic_claim();
        require(source == EDRV32_PLIC_SOURCE_GEO, 0x102u);
        require((read_reg(EDRV32_GEO_BASE, MEDIA_IRQ_STAT) & 1u) != 0u, 0x103u);
        write_reg(EDRV32_GEO_BASE, MEDIA_IRQ_STAT, 1u);
        plic_complete(source);
        geo_interrupts++;
    } else {
        finish(0x180u | cause);
    }
}

static void media_decode(void)
{
    static const uint32_t connected[] = {1u, 2u, 3u, 5u, 6u, 7u, 8u, 9u};
    static const uint32_t reserved[] = {0u, 4u, 10u, 11u, 12u, 13u, 14u, 15u};
    for (unsigned int i = 0; i < sizeof(connected) / sizeof(connected[0]); i++) {
        uint32_t slot = connected[i];
        /* Engine-spec 4 ID tables; DISP v0.3 (two layers) reports version 2. */
        require(read_reg(EDRV32_MEDIA_APB_BASE + slot * 0x1000u, MEDIA_ID) ==
                ((slot << 16) | (slot == 5u ? 2u : 1u)), 0x200u + slot);
    }
    for (unsigned int i = 0; i < sizeof(reserved) / sizeof(reserved[0]); i++) {
        uintptr_t address = EDRV32_MEDIA_APB_BASE + reserved[i] * 0x1000u;
        expected_fault = address;
        __asm__ volatile ("lw zero, 0(%0)" :: "r"(address) : "memory");
        expected_fault = 0u;
        require(fault_count == i + 1u, 0x220u + reserved[i]);
    }
}

static void ddr_aliases(void)
{
    uintptr_t cached = EDRV32_DDR_BASE + 0x1000u;
    uintptr_t uncached = EDRV32_DDR_UNCACHED_BASE + 0x1000u;
    for (uint32_t i = 0; i < 16u; i++) {
        *(volatile uint32_t *)(cached + 4u * i) = 0x12340000u + i;
    }
    cache_clean(cached, 64u);
    for (uint32_t i = 0; i < 16u; i++) {
        require(*(volatile uint32_t *)(uncached + 4u * i) == 0x12340000u + i,
                0x300u + i);
        *(volatile uint32_t *)(uncached + 4u * i) = 0xabcd0000u + i;
    }
    cache_invalidate(cached, 64u);
    for (uint32_t i = 0; i < 16u; i++) {
        require(*(volatile uint32_t *)(cached + 4u * i) == 0xabcd0000u + i,
                0x320u + i);
    }
}

static void gateway_statistics(void)
{
    write_reg(EDRV32_MEM_XBAR_BASE, MX_STAT_CTRL, 2u);
    for (uint32_t i = 0; i < 3u; i++) {
        volatile uint32_t *word = (volatile uint32_t *)(EDRV32_DDR_UNCACHED_BASE +
                                                       0x4000u + 32u * i);
        *word = 0x76540000u + i;
        require(*word == 0x76540000u + i, 0x400u + i);
    }
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    write_reg(EDRV32_MEM_XBAR_BASE, MX_STAT_CTRL, 1u);
    require(read_reg(EDRV32_MEM_XBAR_BASE, MX_P2_RD_TXN) == 3u, 0x410u);
    require(read_reg(EDRV32_MEM_XBAR_BASE, MX_P2_RD_BEAT) == 3u, 0x411u);
    require(read_reg(EDRV32_MEM_XBAR_BASE, MX_P2_WR_TXN) == 3u, 0x412u);
    require(read_reg(EDRV32_MEM_XBAR_BASE, MX_P2_WR_BEAT) == 3u, 0x413u);
}

static void geo_meip(void)
{
    /* GEO 2.3, 2.6, 5.1: one 64-byte descriptor with a zero-size rectangle
       completes normally, increments DONE_COUNT and sets IRQ_STAT.DONE. */
    volatile uint32_t *descriptor = (volatile uint32_t *)(EDRV32_DDR_UNCACHED_BASE + 0x8000u);
    for (uint32_t i = 0; i < 16u; i++) {
        descriptor[i] = 0u;
    }
    descriptor[0] = 0x9000u;
    descriptor[1] = 32u;
    descriptor[2] = (1u << 16) | 2u;
    descriptor[3] = 0xa000u;
    descriptor[4] = 32u;
    descriptor[8] = 0x10000u;
    descriptor[12] = 0x10000u;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    plic_set_priority(EDRV32_PLIC_SOURCE_GEO, 1u);
    plic_set_threshold(0u);
    plic_set_enable(1u << EDRV32_PLIC_SOURCE_GEO);
    write_reg(EDRV32_GEO_BASE, MEDIA_IRQ_EN, 1u);
    write_reg(EDRV32_GEO_BASE, MEDIA_DESC_BASE, 0x8000u);
    write_reg(EDRV32_GEO_BASE, MEDIA_DESC_COUNT, 1u);
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 11));
    __asm__ volatile ("csrsi mstatus, 8");
    write_reg(EDRV32_GEO_BASE, MEDIA_DOORBELL, 1u);
    while (geo_interrupts == 0u) {
        __asm__ volatile ("nop");
    }
    __asm__ volatile ("csrci mstatus, 8");
    require(geo_interrupts == 1u, 0x500u);
    require(read_reg(EDRV32_GEO_BASE, MEDIA_DONE_COUNT) == 1u, 0x501u);
}

int main(void)
{
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uintptr_t)trap_handler));
    media_decode();
    ddr_aliases();
    gateway_statistics();
    geo_meip();
    finish(0u);
}
