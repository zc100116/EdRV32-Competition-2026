/* File: overlay_surface.c
 * Spec: rnd-disp design 3.5–3.6; rnd 2.6/5.4; DISP 5.3; SoC 7.3 R3.
 * Description: Shared L1 double-buffer acquisition, publication and release ownership.
 * Clock domain: clk_sys; display ownership changes in the FRAME interrupt.
 */
#include "runtime.h"
#include "overlay.h"

static volatile int current;
static volatile int next;
static volatile int queued;
static int rendered;

uint32_t demo_overlay_address(unsigned int slot)
{
    return DEMO_OVERLAY_BASE + slot * DEMO_OVERLAY_SPACING;
}

void demo_overlay_init(void)
{
    demo_overlay_backend_init();
    disp_l1_geometry(0, 0, DEMO_WIDTH, DEMO_HEIGHT, 255);
    demo_overlay_stop();
}

void demo_overlay_stop(void)
{
    /* Called only after DISP IDLE, so both buffers are now writable. */
    disp_layer_enable(DISP_L1, 0);
    current = -1;
    next = -1;
    queued = -1;
    rendered = -1;
}

void demo_overlay_present(unsigned int initial)
{
    /* Called with the L0 submission lock held: camera and overlay latch together. */
    if (initial) {
        next = rendered;
        disp_submit(DISP_L1, demo_overlay_address((unsigned int)next), DEMO_OVERLAY_STRIDE);
        disp_layer_enable(DISP_L1, 1);
    } else {
        queued = rendered;
    }
    rendered = -1;
}

void demo_overlay_frame(uint32_t irq)
{
    if ((irq & EDRV32_DISP_IRQ_STAT_SWITCH1_MASK) && current >= 0 &&
        disp_released(DISP_L1) == demo_overlay_address((unsigned int)current)) {
        current = -1;
    }
    if (!(irq & EDRV32_DISP_IRQ_STAT_FRAME_MASK)) {
        return;
    }
    if (next >= 0 && disp_current(DISP_L1) == demo_overlay_address((unsigned int)next)) {
        current = next;
        next = -1;
    }
    if (!demo.transitioning && next < 0 && queued >= 0) {
        next = queued;
        queued = -1;
        disp_submit(DISP_L1, demo_overlay_address((unsigned int)next), DEMO_OVERLAY_STRIDE);
        disp_layer_enable(DISP_L1, 1);
    }
}

void demo_overlay_draw(const yolo_detection *detections, unsigned int count)
{
    int buffer;
    /* FRAME/SWITCH1 interrupts release a slot; never draw current or shadow-next. */
    for (;;) {
        uint32_t lock = demo_irq_lock();
        buffer = -1;
        for (int i = 0; i < 2; ++i) {
            if (current != i && next != i && queued != i) {
                buffer = i;
                break;
            }
        }
        demo_irq_unlock(lock);
        if (buffer >= 0) {
            break;
        }
    }
    demo_overlay_render((unsigned int)buffer, detections, count);
    uint32_t lock = demo_irq_lock();
    rendered = buffer;
    demo_irq_unlock(lock);
}
