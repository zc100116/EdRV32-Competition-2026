/* File: network.c
 * Spec: Task T-NETN-R; SoC 7.2/7.4; eth-spec 2.4/2.6.
 * Description: RGB565 reception and CH2/OUTPUT/EDDT transmission ownership.
 * Clock domain: clk_sys; CPU-built DDR objects use the uncached alias.
 */
#include "runtime.h"

void demo_network_submit(unsigned int count, int surface, int check_buffer)
{
    struct eth_tx_descriptor *descriptors = demo_uncached(DEMO_TX_DESCRIPTORS);
    eth_monitor_peer_configure();
    demo.tx_count = count;
    for (unsigned int i = 0; i < count; ++i) {
        demo.tx_lengths[i] = descriptors[i].word[
            EDRV32_ETH_TX_DESC_LEN_OFFSET / sizeof(uint32_t)];
    }
    demo.tx_done = engine_poll(ENGINE_ETH).done_count;
    demo.tx_surface = surface;
    demo.tx_check_buffer = check_buffer;
    demo.tx_active = 1;
    eth_send(DEMO_TX_DESCRIPTORS, count);
}

void demo_network_event(const struct engine_event *event, void *context)
{
    (void)context;
    if (event->error || (event->irq & EDRV32_ETH_IRQ_STAT_ERROR_MASK)) {
        demo_fail("ETH", ENGINE_ETH);
    }
    demo.received |= event->irq & (EDRV32_ETH_IRQ_STAT_RX_NOTIFY0_MASK |
        EDRV32_ETH_IRQ_STAT_RX_NOTIFY1_MASK | EDRV32_ETH_IRQ_STAT_RX_NOTIFY2_MASK |
        EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK);
    if (demo.tx_active && event->done_count - demo.tx_done == demo.tx_count) {
        for (unsigned int i = 0; i < demo.tx_count; ++i) {
            demo.sent_bytes += demo.tx_lengths[i];
        }
        demo_network_check_complete();
        demo.tx_surface = -1;
        demo.tx_check_buffer = -1;
        demo.tx_active = 0;
    }
}

void demo_network_check_complete(void)
{
    if (demo.tx_check_buffer >= 0) {
        struct demo_inference *job = &demo.inference[demo.tx_check_buffer];
        demo.input_busy &= ~(1u << job->input_slot);
        job->state = BUFFER_FREE;
        eth_window_configure(demo.image_window,
            DEMO_WINDOW_BASE + demo.image_window * DEMO_WINDOW_SIZE, DEMO_WINDOW_SIZE);
        demo.checking = 0;
    }
}

unsigned int demo_network_detections(struct eth_tx_descriptor *tx,
                                     unsigned int detection_bytes, int check_buffer)
{
    unsigned int count = 0;
    if (check_buffer >= 0) {
        eth_tx_descriptor_pack(&tx[count++],
            DEMO_INPUT_BASE + (unsigned int)check_buffer * DEMO_INPUT_SPACING,
            DEMO_INPUT_BYTES, 0, 0, 0);
        eth_tx_descriptor_pack(&tx[count++],
            DEMO_OUTPUT_BASE + (unsigned int)check_buffer * DEMO_OUTPUT_SPACING,
            DEMO_OUTPUT_BYTES, 1, 0, 0);
    }
    if (detection_bytes) {
        eth_tx_descriptor_pack(&tx[count++], DEMO_TX_DETECTIONS,
                                detection_bytes, 2, 1, 0);
    }
    return count;
}

void demo_network_receive(void)
{
    uint32_t lock = demo_irq_lock();
    uint32_t received = demo.received;
    demo.received = 0;
    demo_irq_unlock(lock);
    if (received & EDRV32_ETH_IRQ_STAT_RX_NOTIFY2_MASK) {
        const uint8_t *header = demo_network_model_header();
        demo_network_wait();
        demo_network_model_load(header);
    }
    const uint32_t masks[] = {EDRV32_ETH_IRQ_STAT_RX_NOTIFY0_MASK,
                              EDRV32_ETH_IRQ_STAT_RX_NOTIFY1_MASK};
    for (unsigned int window = 0; window < 2; ++window) {
        if (!(received & masks[window])) {
            continue;
        }
        demo_npu_receive(window);
    }
    if (received & EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK) {
        eth_window_configure(3, DEMO_COMMAND_WINDOW, DEMO_COMMAND_WINDOW_SIZE);
        info_hex("ETH peer IP", mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_IP_OFFSET));
        info_number("ETH peer port", mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_PORT_OFFSET));
    }
}
