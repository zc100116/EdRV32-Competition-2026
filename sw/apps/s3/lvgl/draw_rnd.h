/* File: draw_rnd.h
 * Spec: RND 2.5/2.6/5.4; design rnd-disp 4.3.
 * Description: Synchronous IRQ-completed LVGL drawing unit and COPY service.
 * Clock domain: clk_sys, hardware execution in clk_mem.
 */
#ifndef S3_DRAW_RND_H
#define S3_DRAW_RND_H
#include "lvgl.h"
#include <stdbool.h>
#include <stdint.h>
enum { S3_RND_BATCH_COMMANDS = 32, S3_RND_TASK_TYPES = 16 };
struct s3_draw_rnd_stats {
    uint32_t claimed[S3_RND_TASK_TYPES];
    uint32_t unclaimed[S3_RND_TASK_TYPES];
    uint32_t executed;
    uint32_t software;
    uint32_t commands;
    uint32_t doorbells;
};
void s3_draw_rnd_init(void);
void s3_draw_rnd_enable(bool enabled);
bool s3_draw_rnd_enabled(void);
const struct s3_draw_rnd_stats *s3_draw_rnd_stats(void);
void s3_draw_rnd_print_stats(void);
void s3_draw_rnd_copy(void *dst, const void *src, uint16_t stride, const lv_area_t *area);
#endif
