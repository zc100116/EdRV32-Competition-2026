/* File: network_video_npu.c
 * Spec: Task T-NETN-R; SoC 7.2/7.4; eth-spec 2.4/2.6.
 * Description: RGB565 image checks, CH2 returns and VIN ownership for B3F/B3VN.
 * Clock domain: clk_sys; CPU-built DDR objects use the uncached alias.
 */
#include "runtime.h"
#include <string.h>

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
            DEMO_POST_TX,
            4u + demo.inference[check_buffer].post_count * 24u, 1, 0, 0);
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
        demo_pipeline_stop();
        demo_network_model_load(header);
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
        const uint8_t *command = demo_uncached(DEMO_COMMAND_WINDOW);
        uint32_t bytes = eth_window_bytes(3);
        if (bytes == 6u && memcmp(command, "camera", 6) == 0) {
            demo_pipeline_stop();
            demo_monitor_flush();
            demo.scene = 1;
            demo_pipeline_configure(VIN_CAM0);
            info_text("YOLO source", "camera");
        } else if (bytes != 0u && !(bytes == 1u && command[0] == 0)) {
            info_text("Input error", "unknown WIN3 command");
        }
        eth_window_configure(3, DEMO_COMMAND_WINDOW, DEMO_COMMAND_WINDOW_SIZE);
    }
}
