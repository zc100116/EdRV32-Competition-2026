/* File: eth_monitor.c
 * Spec: design 2026-10-29-b2-software 3.4–3.5a; eth-spec 2.4/2.6/2.7.
 * Description: Demo endpoint initialization, learned peer and DDR sampling primitives.
 * Clock domain: clk_sys; PHY and ETH cross to clk_eth through hardware.
 */
#include "eth_monitor.h"
#include "eth.h"
#include "clint.h"

int eth_monitor_peer_known(void)
{
    return mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_PORT_OFFSET) != 0u;
}

void eth_monitor_peer_configure(void)
{
    uint32_t high = mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_MAC_HI_OFFSET);
    uint32_t low = mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_MAC_LO_OFFSET);
    uint32_t ip = mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_IP_OFFSET);
    struct eth_endpoint peer = {
        {(uint8_t)(high >> 8), (uint8_t)high, (uint8_t)(low >> 24),
         (uint8_t)(low >> 16), (uint8_t)(low >> 8), (uint8_t)low},
        {(uint8_t)(ip >> 24), (uint8_t)(ip >> 16), (uint8_t)(ip >> 8), (uint8_t)ip},
        (uint16_t)mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_PORT_OFFSET)
    };
    eth_peer_configure(&peer, 5000);
}

void eth_monitor_local_init(uint32_t clock_hz)
{
    const struct eth_endpoint local = {{0x02, 0x45, 0x44, 0x52, 0x56, 0x32},
                                      {192, 168, 1, 10}, 5000};
    eth_phy_reset(1);
    uint64_t until = clint_time() + clock_hz / 100u;
    while (clint_time() < until) {
        __asm__ volatile ("nop");
    }
    eth_phy_reset(0);
    until = clint_time() + clock_hz / 10u;
    while (clint_time() < until) {
        __asm__ volatile ("nop");
    }
    eth_local_configure(&local);
}

void eth_monitor_snapshot(struct eth_monitor *record, uint32_t clock_hz)
{
    record->time = clint_time();
    mem_xbar_snapshot(&record->memory);
    record->system_hz = clock_hz;
}
