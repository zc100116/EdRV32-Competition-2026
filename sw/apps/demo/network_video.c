/* File: network_video.c
 * Spec: Task T-NETN-R; SoC 7.2/7.4; eth-spec 2.4/2.6.
 * Description: Video Surface ownership, presentation and ETH completion.
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
    if (surface >= 0) {
        demo_reference((unsigned int)surface, REF_ETH, 0);
    }
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
        if (demo.tx_surface >= 0) {
            demo_reference((unsigned int)demo.tx_surface, 0, REF_ETH);
        }
        demo_network_check_complete();
        demo.tx_surface = -1;
        demo.tx_check_buffer = -1;
        demo.tx_active = 0;
        demo_try_inference();
    }
}

void demo_present(unsigned int slot, uint32_t frame_id, unsigned int detection_bytes,
                  int check_buffer)
{
    uint32_t lock = demo_irq_lock();
    uint32_t surface = demo_surface_address(slot);
    if (demo.output == DEMO_ETHERNET) {
        demo_switch_complete(slot);
    }
    if (demo.output != DEMO_ETHERNET) {
        demo_reference(slot, REF_DISPLAY, 0);
        if (demo.scene == 1u) {
            demo_overlay_present(!demo.display_enabled);
        }
        if (!demo.display_enabled) {
            disp_submit(DISP_L0, surface, DEMO_STRIDE);
            demo.display_next = (int)slot;
            demo.display_enabled = 1;
            ++demo.submitted;
            engine_control(ENGINE_DISP, EDRV32_DISP_CTRL_ENABLE_MASK);
        } else {
            if (demo.display_queue >= 0) {
                demo_reference((unsigned int)demo.display_queue, 0, REF_DISPLAY);
            }
            demo.display_queue = (int)slot;
        }
    }
    unsigned int video = !demo.checking && check_buffer != -2 &&
        demo.output != DEMO_HDMI &&
        demo_frame_due(frame_id, demo_frame_divisor(DEMO_CAMERA_FPS, demo.fps));
    if (video && !demo_network_available()) {
        /* Only an unfinished transfer counts as a video skip, not an unknown peer. */
        if (demo.tx_active) {
            ++demo.video_skips;
        }
        video = 0;
    }
    if (demo_network_available() && (video || detection_bytes)) {
        struct eth_tx_descriptor *tx = demo_uncached(DEMO_TX_DESCRIPTORS);
        unsigned int count = demo_network_detections(tx, detection_bytes, check_buffer);
        if (video) {
            demo_video_pack(demo_uncached(DEMO_TX_VIDEO), frame_id, clint_time(), demo.scene);
            eth_tx_descriptor_pack(&tx[count++], DEMO_TX_VIDEO, DEMO_VIDEO_BYTES, 0, 0, 0);
            eth_tx_descriptor_pack(&tx[count++], surface, DEMO_IMAGE_BYTES, 0, 1, 32);
        }
        demo_network_submit(count, video ? (int)slot : -1, check_buffer >= 0 ?
                             check_buffer : -1);
    }
    demo_irq_unlock(lock);
}
