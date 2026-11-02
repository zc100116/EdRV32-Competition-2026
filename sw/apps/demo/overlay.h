/* File: overlay.h
 * Spec: Task B3-11; rnd 2.6; SoC 7.3–7.4.
 * Description: Shared overlay labels, L1 ownership and CPU renderer contract.
 * Clock domain: none (software declarations).
 */
#ifndef EDRV32_DEMO_OVERLAY_H
#define EDRV32_DEMO_OVERLAY_H
#include "demo.h"

struct demo_rect {
    int16_t x0;
    int16_t y0;
    int16_t x1;
    int16_t y1;
};
struct demo_dirty {
    struct demo_rect rect[5u * DEMO_MAX_BOXES];
    unsigned int count;
};
unsigned int demo_overlay_label(char label[32], const yolo_detection *detection);
uint32_t demo_overlay_address(unsigned int slot);
void demo_overlay_backend_init(void);
void demo_overlay_render(unsigned int buffer, const yolo_detection *detections,
                         unsigned int count);
/* CPU writes cached pixels, cleans cleared/new rectangles through BSP before return. */
void demo_overlay_cpu_draw(uint32_t *pixels, struct demo_dirty *dirty,
                          const yolo_detection *detections, unsigned int count);
#endif
