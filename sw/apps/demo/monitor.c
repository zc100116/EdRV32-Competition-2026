/* File: monitor.c
 * Spec: design 2026-10-29-b2-software 3.5/3.5a.
 * Description: CLINT snapshots, exact EDTM type-1 fields and 16-record UDP batching.
 * Clock domain: clk_sys; DDR statistics count clk_mem cycles.
 */
#include "runtime.h"

static uint32_t previous_inferences;
static uint32_t previous_received;
static uint32_t previous_sent;

void demo_monitor_tick(void)
{
    struct eth_monitor record;
    record.sequence = demo.monitor_sequence++;
    record.scene = demo.scene;
    eth_monitor_snapshot(&record, demo.clock_hz);
    demo_monitor_media(&record);
    record.npu[0] = demo.inference_count - previous_inferences;
    previous_inferences = demo.inference_count;
    record.npu[1] = demo.inference_cycles;
    /* CPU candidate sorting/NMS/mapping; hardware DFL is included in npu[1]. */
    record.npu[2] = demo.post_cycles;
    record.npu[3] = demo.detection_count;
    uint32_t received = engine_perf(ENGINE_ETH, 2);
    uint32_t sent = demo_network_bytes();
    record.eth[0] = received - previous_received;
    record.eth[1] = sent - previous_sent;
    previous_received = received;
    previous_sent = sent;
    record.idle_cycles = demo.idle_cycles;
    demo.idle_cycles = 0;
    record.video_skips = demo.video_skips;
    demo.video_skips = 0;
    /* Coordinator decision: discard newest if no peer or ring full; seq still advances. */
    if (!mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_PORT_OFFSET) ||
        demo.monitor_produced - demo.monitor_consumed == DEMO_MONITOR_CAPACITY) {
        ++demo.monitor_dropped;
    } else {
        eth_monitor_pack(demo_uncached(DEMO_MONITOR_RING +
            (demo.monitor_produced % DEMO_MONITOR_CAPACITY) * DEMO_MONITOR_BYTES), &record);
        ++demo.monitor_produced;
    }
    demo.deadline = record.time + demo.clock_hz / demo.sample_hz;
    clint_set_compare(demo.deadline);
}

static void monitor_send(unsigned int limit)
{
    uint32_t lock = demo_irq_lock();
    uint32_t available = demo.monitor_produced - demo.monitor_consumed;
    if (!demo_network_available() || !available ||
        (available < 16u && !demo.monitor_flush)) {
        demo_irq_unlock(lock);
        return;
    }
    unsigned int count = available < 16u ? available : 16u;
    if (count > limit) {
        count = limit;
    }
    uint32_t *destination = demo_uncached(DEMO_TX_MONITOR);
    for (unsigned int i = 0; i < count; ++i) {
        const uint32_t *source = demo_uncached(DEMO_MONITOR_RING +
            ((demo.monitor_consumed + i) % DEMO_MONITOR_CAPACITY) * DEMO_MONITOR_BYTES);
        for (unsigned int word = 0; word < DEMO_MONITOR_BYTES / 4u; ++word) {
            destination[i * (DEMO_MONITOR_BYTES / 4u) + word] = source[word];
        }
    }
    demo.monitor_consumed += count;
    if (demo.monitor_consumed == demo.monitor_produced) {
        demo.monitor_flush = 0;
    }
    eth_tx_descriptor_pack(demo_uncached(DEMO_TX_DESCRIPTORS),
        DEMO_TX_MONITOR, count * DEMO_MONITOR_BYTES, 3, 1, 0);
    demo_network_submit(1, -1, -1);
    demo_irq_unlock(lock);
}

void demo_monitor_send(void)
{
    monitor_send(16u);
}

void demo_monitor_flush(void)
{
    uint32_t lock = demo_irq_lock();
    demo_monitor_tick();
    uint32_t target = demo.monitor_produced;
    demo_irq_unlock(lock);
    /* Sampling continues during TX: only the records present at entry belong to this flush. */
    while ((int32_t)(target - demo.monitor_consumed) > 0) {
        demo_network_wait();
        lock = demo_irq_lock();
        demo.monitor_flush = 1;
        monitor_send(target - demo.monitor_consumed);
        demo_irq_unlock(lock);
    }
    demo.monitor_flush = 0;
    demo_network_wait();
}
