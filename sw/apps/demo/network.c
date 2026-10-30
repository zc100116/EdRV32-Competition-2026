/* File: network.c
 * Spec: design 2026-10-29-b2-software 3.4–3.5a; eth-spec 2.4/2.6.
 * Description: Shared zero-copy EDVF output, ETH initialization and TX source lifetime.
 * Clock domain: clk_sys; CPU-built DDR objects use the noncached alias.
 */
#include "runtime.h"

static int peer_known(void)
{
    return mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_PORT_OFFSET) != 0u;
}

int demo_network_available(void)
{
    return !demo.tx_active && peer_known() &&
        (engine_poll(ENGINE_ETH).status & EDRV32_ETH_STATUS_IDLE_MASK);
}

static void peer_configure(void)
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

void demo_network_submit(unsigned int count, int surface, int check_buffer)
{
    struct eth_tx_descriptor *descriptors = demo_uncached(DEMO_TX_DESCRIPTORS);
    peer_configure();
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

void demo_network_init(void)
{
    const struct eth_endpoint local = {{0x02, 0x45, 0x44, 0x52, 0x56, 0x32},
                                      {192, 168, 1, 10}, 5000};
    eth_phy_reset(1);
    uint64_t until = clint_time() + demo.clock_hz / 100u;
    while (clint_time() < until) {
        __asm__ volatile ("nop");
    }
    eth_phy_reset(0);
    until = clint_time() + demo.clock_hz / 10u;
    while (clint_time() < until) {
        __asm__ volatile ("nop");
    }
    eth_local_configure(&local);
    demo_network_windows_init();
    engine_irq_register(ENGINE_ETH, EDRV32_ETH_IRQ_EN_ERROR_MASK |
        EDRV32_ETH_IRQ_EN_DONE_MASK | demo_network_rx_mask, 3, demo_network_event, NULL);
    engine_control(ENGINE_ETH, EDRV32_ETH_CTRL_ENABLE_MASK);
    info_text("Network", "02:45:44:52:56:32 192.168.1.10:5000; peer from PC UDP source");
}
