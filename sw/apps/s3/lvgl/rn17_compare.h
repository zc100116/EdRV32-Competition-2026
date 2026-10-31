/* File: rn17_compare.h
 * Spec: rnd-testplan RN-17/6; coordinator-confirmed AA mask union.
 * Description: Shared host/board coverage classification for real LVGL frames.
 * Clock domain: clk_sys or host.
 */
#ifndef S3_RN17_COMPARE_H
#define S3_RN17_COMPARE_H
#include "lvgl.h"
#include "rnd.h"
struct s3_lvgl_comparison;
void s3_compare_pixels(struct s3_lvgl_comparison *result, const uint16_t *reference,
                       const uint16_t *rendered, uint32_t pixels);
bool s3_compare_passes(const struct s3_lvgl_comparison *result);
void s3_compare_begin(void);
void s3_compare_end(void);
bool s3_compare_edge(unsigned index);
void s3_compare_shape(lv_draw_task_t *t, const lv_area_t *area, int32_t radius,
                      int32_t border, uint8_t sides);
void s3_compare_mask(lv_draw_task_t *t, const lv_area_t *area,
                     const uint8_t *mask, uint32_t stride);
void s3_compare_shadow(lv_draw_task_t *t, const lv_area_t *area);
void s3_compare_geometry(lv_draw_task_t *t, const struct rnd_common *c,
                         const uint32_t *p, uint8_t op);
void s3_compare_affine(lv_draw_task_t *t, const struct rnd_common *c, const uint32_t *p,
                       const struct rnd_affine *a, const lv_draw_buf_t *image);
void s3_compare_image(lv_draw_task_t *t, const lv_draw_buf_t *buf,
                      const lv_area_t *area, int32_t scale_x, int32_t scale_y);
#endif
