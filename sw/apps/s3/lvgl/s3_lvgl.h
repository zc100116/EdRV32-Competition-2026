/* File: s3_lvgl.h
 * Spec: SoC 1.2 S3; rnd-testplan RN-17; Task B3-3b.
 * Description: LVGL service called by the shared S3 main loop and menu.
 * Clock domain: clk_sys; display ownership follows DISP SWITCH.
 */
#ifndef S3_LVGL_H
#define S3_LVGL_H
#include <stdbool.h>
#include <stdint.h>
#include "lvgl.h"

void s3_lvgl_init(void);
void s3_lvgl_step(void);
void s3_lvgl_input(uint32_t keys);
void s3_lvgl_restore_display(void);
void s3_lvgl_start_widgets(void);
void s3_lvgl_start_benchmark(void);
void s3_lvgl_stop_demo(void);
void s3_lvgl_self_compare(void);
void s3_lvgl_set_rnd(bool enabled);
lv_display_t *s3_lvgl_display(void);

/* Last RN-17 pair, also accessible to the Linux runner for PPM export. */
struct s3_lvgl_comparison {
    uint32_t full_max_lsb;
    uint32_t edge_max_lsb;
    uint32_t over1;
    uint32_t pixels;
    /* Maximum R5/G6/B5 channel difference: 0, 1, 2, 3..4, >=5 LSB. */
    uint32_t histogram[5];
    uint32_t rnd_tasks;
    uint32_t sw_tasks;
};
const struct s3_lvgl_comparison *s3_lvgl_comparison(void);
const uint16_t *s3_lvgl_reference_pixels(void);
const uint16_t *s3_lvgl_rendered_pixels(void);
#endif
