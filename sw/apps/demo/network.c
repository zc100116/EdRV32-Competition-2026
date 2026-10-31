/* File: network.c
 * Spec: design 2026-10-29-b2-software 3.4–3.5a; eth-spec 2.4/2.6.
 * Description: Shared ETH initialization, availability, byte accounting and polling.
 * Clock domain: clk_sys; CPU-built DDR objects use the noncached alias.
 */
#include "runtime.h"

int demo_network_available(void)
{
    return !demo.tx_active && eth_monitor_peer_known() &&
        (engine_poll(ENGINE_ETH).status & EDRV32_ETH_STATUS_IDLE_MASK);
}

uint32_t demo_network_bytes(void)
{
    uint32_t bytes = demo.sent_bytes;
    if (demo.tx_active) {
        /* PERF10 counts transmitted UDP packets, including a descriptor's short tail. */
        uint32_t packets = engine_perf(ENGINE_ETH, 10);
        for (unsigned int i = 0; i < demo.tx_count; ++i) {
            uint32_t length = demo.tx_lengths[i];
            uint32_t count = length ? (length + 1023u) / 1024u : 1u;
            if (packets >= count) {
                bytes += length;
                packets -= count;
            } else {
                bytes += packets * 1024u;
                break;
            }
        }
    }
    return bytes;
}

void demo_network_service(void)
{
    uint32_t lock = demo_irq_lock();
    struct engine_event event = engine_poll(ENGINE_ETH);
    /* Polling shares the callback path; interrupt flags remain owned by the dispatcher. */
    event.irq &= EDRV32_ETH_IRQ_STAT_ERROR_MASK;
    demo_network_event(&event, NULL);
    demo_irq_unlock(lock);
}

void demo_network_wait(void)
{
    while (demo.tx_active ||
           !(engine_poll(ENGINE_ETH).status & EDRV32_ETH_STATUS_IDLE_MASK)) {
        demo_network_service();
    }
}

void demo_network_init(void)
{
    eth_monitor_local_init(demo.clock_hz);
    demo_network_windows_init();
    engine_irq_register(ENGINE_ETH, EDRV32_ETH_IRQ_EN_ERROR_MASK |
        EDRV32_ETH_IRQ_EN_DONE_MASK | demo_network_rx_mask, 3, demo_network_event, NULL);
    engine_control(ENGINE_ETH, EDRV32_ETH_CTRL_ENABLE_MASK);
    info_text("Network", "02:45:44:52:56:32 192.168.1.10:5000; peer from PC UDP source");
}
