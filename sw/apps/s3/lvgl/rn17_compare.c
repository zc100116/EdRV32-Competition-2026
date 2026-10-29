/* File: rn17_compare.c
 * Spec: rnd-testplan RN-17/6; RND 2.3; confirmed AA-mask union classification.
 * Description: Observe SW AA masks and hardware coverage, without changing rendering.
 * Clock domain: clk_sys or host; active only during RN-17.
 */
#include "rn17_compare.h"
#include "src/draw/lv_draw_private.h"
#include "src/misc/lv_area_private.h"
#include "src/draw/sw/blend/lv_draw_sw_blend_private.h"
#include "src/draw/sw/lv_draw_sw_mask_private.h"

enum { WIDTH = 1280, HEIGHT = 720 };
static uint8_t edges[WIDTH * HEIGHT];
static bool recording;

void s3_compare_begin(void) { lv_memzero(edges, sizeof(edges)); recording = true; }
void s3_compare_end(void) { recording = false; }
bool s3_compare_edge(unsigned index) { return edges[index] != 0; }

static bool clipped(lv_draw_task_t *t, const lv_area_t *area, lv_area_t *result)
{
    const lv_area_t screen = { 0, 0, WIDTH - 1, HEIGHT - 1 };
    return recording && lv_area_intersect(result, area, &t->clip_area) &&
           lv_area_intersect(result, result, &screen);
}

static uint32_t isqrt(uint32_t n)
{
    uint32_t result = 0;
    uint32_t bit = 1u << 30;
    while (bit > n) bit >>= 2;
    while (bit) {
        if (n >= result + bit) {
            n -= result + bit;
            result = (result >> 1) + bit;
        } else result >>= 1;
        bit >>= 2;
    }
    return result;
}

static uint32_t coverage(const lv_area_t *a, int32_t radius, int32_t x, int32_t y)
{
    if (x < a->x1 || x > a->x2 || y < a->y1 || y > a->y2) return 0;
    int32_t w = lv_area_get_width(a);
    int32_t h = lv_area_get_height(a);
    int32_t r = LV_MIN(radius, LV_MIN(w, h) / 2);
    int32_t j = LV_MIN(y - a->y1, a->y2 - y);
    int32_t edge = 0;
    if (r && j < r) {
        int32_t dy = 16 * (r - j) - 8;
        edge = 16 * r - isqrt(256 * r * r - dy * dy);
    }
    int32_t room = LV_MIN(16 * (x - a->x1 + 1) - edge, 16 * (a->x2 - x + 1) - edge);
    return room <= 0 ? 0 : room >= 16 ? 255 : 16 * room;
}

void s3_compare_shape(lv_draw_task_t *t, const lv_area_t *a, int32_t r,
                      int32_t border, uint8_t sides)
{
    lv_area_t clip;
    if (!clipped(t, a, &clip)) return;
    r = LV_MIN(r, LV_MIN(lv_area_get_width(a), lv_area_get_height(a)) / 2);
    lv_area_t inner = {
        a->x1 + ((sides & 4) ? border : -r - 1),
        a->y1 + ((sides & 1) ? border : -r - 1),
        a->x2 - ((sides & 8) ? border : -r - 1),
        a->y2 - ((sides & 2) ? border : -r - 1)
    };
    for (int32_t y = clip.y1; y <= clip.y2; ++y) {
        for (int32_t x = clip.x1; x <= clip.x2; ++x) {
            uint32_t cov = coverage(a, r, x, y);
            if (border >= 0) {
                uint32_t in = coverage(&inner, LV_MAX(r - border, 0), x, y);
                cov = (cov * (255u - in) + 127u) / 255u;
            }
            if (cov != 255) edges[y * WIDTH + x] = 1;
        }
    }
}

void s3_compare_mask(lv_draw_task_t *t, const lv_area_t *area,
                     const uint8_t *mask, uint32_t stride)
{
    lv_area_t clip;
    if (!clipped(t, area, &clip)) return;
    for (int32_t y = clip.y1; y <= clip.y2; ++y)
        for (int32_t x = clip.x1; x <= clip.x2; ++x)
            if (mask[(y - area->y1) * stride + x - area->x1] != 255)
                edges[y * WIDTH + x] = 1;
}

void s3_compare_shadow(lv_draw_task_t *t, const lv_area_t *area)
{
    lv_area_t clip;
    if (!clipped(t, area, &clip)) return;
    for (int32_t y = clip.y1; y <= clip.y2; ++y)
        lv_memset(&edges[y * WIDTH + clip.x1], 1, lv_area_get_width(&clip));
}

void s3_compare_image(lv_draw_task_t *t, const lv_draw_buf_t *buf,
                      const lv_area_t *area, int32_t sx, int32_t sy)
{
    lv_area_t clip;
    if (!clipped(t, area, &clip)) return;
    if (buf->header.cf != LV_COLOR_FORMAT_ARGB8888 &&
        buf->header.cf != LV_COLOR_FORMAT_ARGB8888_PREMULTIPLIED) return;
    for (int32_t y = clip.y1; y <= clip.y2; ++y) {
        for (int32_t x = clip.x1; x <= clip.x2; ++x) {
            uint32_t u = (x - area->x1) * 256 / sx;
            uint32_t v = (y - area->y1) * 256 / sy;
            if (buf->data[v * buf->header.stride + u * 4 + 3] != 255)
                edges[y * WIDTH + x] = 1;
        }
    }
}

void __real_lv_draw_sw_blend(lv_draw_task_t *t, const lv_draw_sw_blend_dsc_t *d);
void __wrap_lv_draw_sw_blend(lv_draw_task_t *t, const lv_draw_sw_blend_dsc_t *d)
{
    if (recording) {
        lv_area_t clip;
        if (d->mask_buf && d->mask_res == LV_DRAW_SW_MASK_RES_CHANGED &&
            lv_area_intersect(&clip, d->blend_area, d->mask_area)) {
            lv_draw_task_t observer = *t;
            lv_area_intersect(&observer.clip_area, &t->clip_area, &clip);
            s3_compare_mask(&observer, d->mask_area, d->mask_buf,
                d->mask_stride ? d->mask_stride : lv_area_get_width(d->mask_area));
        }
        if (t->type == LV_DRAW_TASK_TYPE_BOX_SHADOW) s3_compare_shadow(t, d->blend_area);
        if (d->src_buf && d->src_area &&
            (d->src_color_format == LV_COLOR_FORMAT_ARGB8888 ||
             d->src_color_format == LV_COLOR_FORMAT_ARGB8888_PREMULTIPLIED)) {
            lv_draw_buf_t buf = { .header = { .cf = d->src_color_format,
                                              .stride = d->src_stride },
                                  .data = (uint8_t *)d->src_buf };
            lv_draw_task_t observer = *t;
            lv_area_intersect(&observer.clip_area, &t->clip_area, d->blend_area);
            s3_compare_image(&observer, &buf, d->src_area, 256, 256);
        }
    }
    __real_lv_draw_sw_blend(t, d);
}
