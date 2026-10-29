/* File: rn17_compare.h
 * Spec: rnd-testplan RN-17/6; coordinator-confirmed AA mask union.
 * Description: Shared host/board coverage classification for real LVGL frames.
 * Clock domain: clk_sys or host.
 */
#ifndef S3_RN17_COMPARE_H
#define S3_RN17_COMPARE_H
#include "lvgl.h"
void s3_compare_begin(void);
void s3_compare_end(void);
bool s3_compare_edge(unsigned index);
void s3_compare_shape(lv_draw_task_t *t, const lv_area_t *area, int32_t radius,
                      int32_t border, uint8_t sides);
void s3_compare_mask(lv_draw_task_t *t, const lv_area_t *area,
                     const uint8_t *mask, uint32_t stride);
void s3_compare_shadow(lv_draw_task_t *t, const lv_area_t *area);
void s3_compare_image(lv_draw_task_t *t, const lv_draw_buf_t *buf,
                      const lv_area_t *area, int32_t scale_x, int32_t scale_y);
#endif
