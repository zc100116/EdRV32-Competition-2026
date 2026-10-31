/* File: eth_monitor_test.c
 * Spec: design 2026-10-29-b2-software 3.4–3.5a; eth-spec 2.4/2.6.
 * Description: Exercise WIN3 peer setup, EDTM batches and asynchronous TX ownership.
 * Clock domain: host; deterministic CLINT and MMIO model.
 */
#define _GNU_SOURCE
#include "eth_monitor.h"
#include "eth.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

static uint32_t eth_regs[1024];
static struct engine_event event = {.status = EDRV32_ETH_STATUS_IDLE_MASK};
static uint64_t now;
static uint64_t deadline;
static unsigned int peer_fields;
static unsigned int sends;

uint32_t mmio_read32(uintptr_t address)
{
    assert(address >= EDRV32_ETH_BASE && address < EDRV32_ETH_BASE + sizeof eth_regs);
    return eth_regs[(address - EDRV32_ETH_BASE) / 4u];
}

void mmio_write32(uintptr_t address, uint32_t value)
{
    assert(address >= EDRV32_ETH_BASE && address < EDRV32_ETH_BASE + sizeof eth_regs);
    eth_regs[(address - EDRV32_ETH_BASE) / 4u] = value;
    if (address == EDRV32_ETH_BASE + EDRV32_ETH_DOORBELL_OFFSET) {
        ++sends;
    }
}

uint64_t clint_time(void) { return now++; }
void clint_set_compare(uint64_t value) { deadline = value; }
void mem_xbar_snapshot(struct mem_xbar_stats *stats)
{
    *stats = (struct mem_xbar_stats){.window_cycles = 1250000, .downstream_busy = 1234};
}
void engine_control(enum engine_id engine, uint32_t control)
{
    assert(engine == ENGINE_ETH && control == EDRV32_ETH_CTRL_ENABLE_MASK);
}
struct engine_event engine_poll(enum engine_id engine)
{
    assert(engine == ENGINE_ETH);
    return event;
}
void engine_irq_clear(enum engine_id engine, uint32_t mask)
{
    assert(engine == ENGINE_ETH);
    event.irq &= ~mask;
}
uint32_t engine_perf(enum engine_id engine, unsigned int counter)
{
    assert(engine == ENGINE_ETH && counter == 2u);
    return 9u;
}
void info_hex(const char *key, uint32_t value)
{
    (void)value;
    assert(!strcmp(key, "ETH peer IP") || !strcmp(key, "ETH ERR_CODE"));
    ++peer_fields;
}
void info_number(const char *key, uint64_t value)
{
    assert(!strcmp(key, "ETH peer port") && value == 6000u);
    ++peer_fields;
}
static void tick(void)
{
    now = deadline;
    assert(eth_monitor_board_tick() == 0u);
    assert(deadline > now);
}

int main(void)
{
    void *storage = (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + 0x0a000000u);
    assert(mmap(storage, 0x200000, PROT_READ | PROT_WRITE,
                MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) == storage);
    eth_monitor_board_init(100000000u);
    assert(eth_regs[EDRV32_ETH_IP_ADDR_OFFSET / 4] == 0xc0a8010au);
    assert(eth_regs[EDRV32_ETH_RX_PORT_OFFSET / 4] == 5000u);
    for (unsigned int i = 0; i < 16u; ++i) { tick(); }
    assert(sends == 0u);
    eth_regs[EDRV32_ETH_PEER_IP_OFFSET / 4] = 0xc0a80114u;
    eth_regs[EDRV32_ETH_PEER_PORT_OFFSET / 4] = 6000u;
    event.irq = EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK;
    for (unsigned int i = 0; i < 16u; ++i) { tick(); }
    assert(sends == 1u && peer_fields == 2u && event.irq == 0u);
    assert(eth_regs[EDRV32_ETH_TX_DST_IP_OFFSET / 4] == 0xc0a80114u);
    uint8_t *payload = (uint8_t *)storage + 0x100800;
    assert(!memcmp(payload, "EDTM\1\0\1\0\20\0\0\0", 12));
    uint32_t *descriptor = (uint32_t *)((uint8_t *)storage + 0x100000);
    assert(descriptor[0] == 0x0a100800u && descriptor[1] == 16u * 320u);
    uint8_t saved[16u * 320u];
    memcpy(saved, payload, sizeof saved);
    for (unsigned int i = 0; i < 20u; ++i) { tick(); }
    assert(sends == 1u && !memcmp(saved, payload, sizeof saved));
    event.done_count = 1u;
    tick();
    assert(sends == 2u && memcmp(saved, payload, sizeof saved));
    event.error = 1u;
    assert(eth_monitor_board_tick() == 1u);
    assert(munmap(storage, 0x200000) == 0);
    puts("PASS ETH board monitor: peer, no-peer silence, EDTM batching, TX lifetime, error");
    return 0;
}
