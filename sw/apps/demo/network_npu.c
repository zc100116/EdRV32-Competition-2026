/* File: network_npu.c
 * Spec: design 2026-10-29-b2-software 3.4–3.5a; eth-spec 2.4/2.6.
 * Description: NPU model loading, image checks and detection/input/output transmission.
 * Clock domain: clk_sys; CPU-built DDR objects use the noncached alias.
 */
#include "runtime.h"

const uint32_t demo_network_rx_mask = EDRV32_ETH_IRQ_EN_RX_NOTIFY0_MASK |
    EDRV32_ETH_IRQ_EN_RX_NOTIFY1_MASK | EDRV32_ETH_IRQ_EN_RX_NOTIFY2_MASK |
    EDRV32_ETH_IRQ_EN_RX_NOTIFY3_MASK;

void demo_network_windows_init(void)
{
    eth_window_configure(0, DEMO_WINDOW_BASE, DEMO_WINDOW_SIZE);
    eth_window_configure(1, DEMO_WINDOW_BASE + DEMO_WINDOW_SIZE, DEMO_WINDOW_SIZE);
    eth_window_configure(2, DEMO_MODEL_WINDOW, DEMO_MODEL_WINDOW_SIZE);
    eth_window_configure(3, DEMO_COMMAND_WINDOW, DEMO_COMMAND_WINDOW_SIZE);
}

void demo_network_check_complete(void)
{
    if (demo.tx_check_buffer >= 0) {
        struct demo_inference *job = &demo.inference[demo.tx_check_buffer];
        demo.input_busy &= ~(1u << job->input_slot);
        vin_slots_busy(2, demo.input_busy);
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
        struct demo_inference *job = &demo.inference[check_buffer];
        eth_tx_descriptor_pack(&tx[count++],
            DEMO_INPUT_BASE + job->input_slot * DEMO_INPUT_SPACING,
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

static void copy_bytes(uint32_t destination, uint32_t source, uint32_t bytes)
{
    uint32_t *out = demo_uncached(destination);
    const uint32_t *in = demo_uncached(source);
    for (uint32_t i = 0; i < bytes / 4u; ++i) {
        out[i] = in[i];
    }
    uint8_t *tail = (uint8_t *)out;
    const uint8_t *source_tail = (const uint8_t *)in;
    for (uint32_t i = bytes & ~3u; i < bytes; ++i) {
        tail[i] = source_tail[i];
    }
}

void demo_network_receive(void)
{
    uint32_t lock = demo_irq_lock();
    uint32_t received = demo.received;
    demo.received = 0;
    demo_irq_unlock(lock);
    if (received & EDRV32_ETH_IRQ_STAT_RX_NOTIFY2_MASK) {
        const uint8_t *header = demo_uncached(DEMO_MODEL_WINDOW);
        uint32_t bytes = eth_window_bytes(2);
        info_number("WIN2_BYTES", bytes);
        const char *error = demo_model_header(header, bytes);
        if (error) {
            for (unsigned int i = 0; i < 8; ++i) {
                info_hex("EDNM word", demo_read32(header + i * 4));
            }
            demo_fail(error, ENGINE_ETH);
        }
        demo_pipeline_stop();
        copy_bytes(DEMO_DESC_BASE, DEMO_MODEL_WINDOW + 0x1000u, demo_read32(header + 12));
        copy_bytes(DEMO_MODEL_BASE, DEMO_MODEL_WINDOW + 0x100000u, demo_read32(header + 16));
        struct npu_config config = {DEMO_MODEL_BASE, DEMO_WORK_BASE, DEMO_INPUT_BASE,
            DEMO_OUTPUT_BASE, DEMO_DESC_BASE, demo_read32(header + 8)};
        npu_configure(&config);
        eth_window_configure(2, DEMO_MODEL_WINDOW, DEMO_MODEL_WINDOW_SIZE);
        info_text("EDNM", "loaded");
        demo_pipeline_configure(VIN_CAM0);
    }
    const uint32_t masks[] = {EDRV32_ETH_IRQ_STAT_RX_NOTIFY0_MASK,
                              EDRV32_ETH_IRQ_STAT_RX_NOTIFY1_MASK};
    for (unsigned int window = 0; window < 2; ++window) {
        if (!(received & masks[window])) {
            continue;
        }
        uint32_t bytes = eth_window_bytes(window);
        if (bytes != DEMO_IMAGE_BYTES) {
            info_number("WIN image bytes", bytes);
            demo_fail("RGB565 image length", ENGINE_ETH);
        }
        demo_pipeline_stop();
        demo_monitor_flush();
        demo.scene = 1;
        demo.checking = 1;
        demo.image_window = window;
        demo_pipeline_configure(VIN_MEMORY);
        vin_memory_start(DEMO_WINDOW_BASE + window * DEMO_WINDOW_SIZE,
                         DEMO_STRIDE, DEMO_WIDTH, DEMO_HEIGHT);
        info_number("YOLO image window", window);
        /* Only one image check is active; the host waits for final WIN2 NOTIFY. */
    }
    if (received & EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK) {
        eth_window_configure(3, DEMO_COMMAND_WINDOW, DEMO_COMMAND_WINDOW_SIZE);
    }
}
