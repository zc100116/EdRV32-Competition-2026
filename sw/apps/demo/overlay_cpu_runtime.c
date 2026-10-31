/* File: overlay_cpu_runtime.c
 * Spec: Task B3-11; SoC 7.3–7.4.
 * Description: B3VN cached L1 initialization and per-frame mcycle measurement.
 * Clock domain: clk_sys; shared overlay code owns acquisition and DISP submission.
 */
#include "runtime.h"
#include "overlay.h"
#include "cache.h"

const char demo_version[] = "demo_vnpu";
static struct demo_dirty dirty[2];
static uint32_t draw_cycles;

void demo_overlay_ids(void)
{
}

void demo_overlay_status(void)
{
    info_number("Overlay CPU cycles", draw_cycles);
}

void demo_overlay_backend_init(void)
{
    for (unsigned int buffer = 0; buffer < 2u; ++buffer) {
        uint32_t *pixels = (uint32_t *)demo_cached(demo_overlay_address(buffer));
        for (unsigned int i = 0; i < DEMO_OVERLAY_BYTES / 4u; ++i) {
            pixels[i] = 0;
        }
        cache_clean((uintptr_t)pixels, DEMO_OVERLAY_BYTES);
    }
}

void demo_overlay_render(unsigned int buffer, const yolo_detection *detections,
                         unsigned int count)
{
    uint32_t start;
    uint32_t end;
    /* Unsigned subtraction measures this frame across low-mcycle wrap. */
    __asm__ volatile ("csrr %0, mcycle" : "=r"(start) :: "memory");
    demo_overlay_cpu_draw((uint32_t *)demo_cached(demo_overlay_address(buffer)),
                          &dirty[buffer], detections, count);
    __asm__ volatile ("csrr %0, mcycle" : "=r"(end) :: "memory");
    draw_cycles = end - start;
}
