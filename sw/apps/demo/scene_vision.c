/* File: scene_vision.c
 * Spec: Task B3-11; design 2026-10-29-b2-software 3.4 S2.
 * Description: B3V S2-only scene and WIN3 peer notification; NPU/RND are absent.
 * Clock domain: clk_sys; feature implementations selected by program.mk.
 */
#include "runtime.h"

const char demo_version[] = "demo_vision";
const unsigned int demo_vin_channels = 1;
const uint32_t demo_vin_frame_mask = EDRV32_VIN_IRQ_EN_FRAME_MASK;
const uint32_t demo_network_rx_mask = EDRV32_ETH_IRQ_EN_RX_NOTIFY3_MASK;

int demo_scene_allowed(unsigned int scene)
{
    return scene == 2u;
}

void demo_scene_frame(unsigned int channel, unsigned int slot, uint32_t frame_id)
{
    (void)channel;
    if (demo.ready_surface >= 0) {
        demo_reference((unsigned int)demo.ready_surface, 0, REF_READY);
    }
    demo_reference(slot, REF_READY, 0);
    demo.surface_frame[slot] = frame_id;
    demo.ready_surface = (int)slot;
}

void demo_network_windows_init(void)
{
    eth_window_configure(3, DEMO_COMMAND_WINDOW, DEMO_COMMAND_WINDOW_SIZE);
}

void demo_network_receive(void)
{
    uint32_t lock = demo_irq_lock();
    uint32_t received = demo.received;
    demo.received = 0;
    demo_irq_unlock(lock);
    if (received & EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK) {
        eth_window_configure(3, DEMO_COMMAND_WINDOW, DEMO_COMMAND_WINDOW_SIZE);
    }
}

unsigned int demo_network_detections(struct eth_tx_descriptor *tx,
                                     unsigned int detection_bytes, int check_buffer)
{
    (void)tx;
    (void)detection_bytes;
    (void)check_buffer;
    return 0;
}

/* These compile-selected feature hooks have no S2 work or absent-engine MMIO. */
void demo_scene_ids(void)
{
}

void demo_scene_status(void)
{
}

void demo_scene_init(void)
{
}

void demo_model_init(void)
{
}

void demo_scene_pair(void)
{
}

void demo_try_inference(void)
{
}

void demo_scene_stop(void)
{
}

void demo_scene_service(void)
{
}

void demo_network_check_complete(void)
{
}

void demo_scene_configure(enum vin_source source)
{
    (void)source;
}

void demo_overlay_ids(void)
{
}

void demo_overlay_status(void)
{
}

void demo_overlay_init(void)
{
    disp_layer_enable(DISP_L1, 0);
}

void demo_overlay_stop(void)
{
    disp_layer_enable(DISP_L1, 0);
}

void demo_overlay_hide(void)
{
    disp_layer_enable(DISP_L1, 0);
}

void demo_overlay_frame(uint32_t irq)
{
    (void)irq;
}

void demo_overlay_present(unsigned int initial)
{
    (void)initial;
}
