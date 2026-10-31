/* File: rn17_compare.c
 * Spec: rnd-testplan RN-17/6; RND 2.3; confirmed AA-mask union classification.
 * Description: Observe SW AA masks and hardware coverage, without changing rendering.
 * Clock domain: clk_sys or host; active only during RN-17.
 */
#include "rn17_compare.h"
#include "s3_lvgl.h"
#include "src/draw/lv_draw_private.h"
#include "src/misc/lv_area_private.h"
#include "src/draw/sw/blend/lv_draw_sw_blend_private.h"
#include "src/draw/sw/lv_draw_sw_mask_private.h"

enum { WIDTH = 1280, HEIGHT = 720 };
static uint8_t edges[WIDTH * HEIGHT];
static bool recording;
static void geometry_reset(void);
static void geometry_flush(void);

void s3_compare_begin(void) { lv_memzero(edges, sizeof(edges)); geometry_reset(); recording = true; }
void s3_compare_end(void) { geometry_flush(); recording = false; }
bool s3_compare_edge(unsigned index) { return edges[index] != 0; }

void s3_compare_pixels(struct s3_lvgl_comparison *result, const uint16_t *reference,
                       const uint16_t *rendered, uint32_t pixels)
{
    geometry_flush();
    const unsigned shifts[3] = { 11, 5, 0 };
    const unsigned masks[3] = { 31, 63, 31 };
    *result = (struct s3_lvgl_comparison) { .pixels = pixels };
    for (uint32_t i = 0; i < pixels; ++i) {
        uint32_t delta = 0;
        for (unsigned c = 0; c < 3; ++c) {
            unsigned a = (reference[i] >> shifts[c]) & masks[c];
            unsigned b = (rendered[i] >> shifts[c]) & masks[c];
            unsigned d = a > b ? a - b : b - a;
            delta = LV_MAX(delta, d);
        }
        if (delta > 1) result->over1++;
        unsigned bin = delta <= 2 ? delta : delta <= 4 ? 3 : 4;
        result->histogram[bin]++;
        if (s3_compare_edge(i)) result->edge_max_lsb = LV_MAX(result->edge_max_lsb, delta);
        else result->full_max_lsb = LV_MAX(result->full_max_lsb, delta);
    }
}

bool s3_compare_passes(const struct s3_lvgl_comparison *result)
{
    /* rnd-testplan 6: edge pixels have no individual limit. */
    return result->full_max_lsb <= 1 && result->over1 * 100u <= result->pixels;
}

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

/* Keep geometric boundaries separate from opacity and color interpolation. */
static uint8_t geometry_plane[WIDTH * HEIGHT];
static lv_area_t geometry_area;
static const lv_draw_task_t *geometry_task;
static const void *geometry_descriptor;

static void geometry_reset(void)
{
    geometry_area = (lv_area_t) { WIDTH, HEIGHT, -1, -1 };
    geometry_task = NULL;
    geometry_descriptor = NULL;
}

static void geometry_flush(void)
{
    if (geometry_area.x1 > geometry_area.x2) return;
    int32_t x0 = LV_MAX(geometry_area.x1 - 1, 0), x1 = LV_MIN(geometry_area.x2 + 1, WIDTH - 1);
    int32_t y0 = LV_MAX(geometry_area.y1 - 1, 0), y1 = LV_MIN(geometry_area.y2 + 1, HEIGHT - 1);
    for (int32_t y = y0; y <= y1; ++y) {
        for (int32_t x = x0; x <= x1; ++x) {
            bool center = geometry_plane[y * WIDTH + x] != 0;
            bool boundary = false;
            for (int32_t dy = -1; dy <= 1; ++dy)
                for (int32_t dx = -1; dx <= 1; ++dx) {
                    int32_t px = x + dx, py = y + dy;
                    bool neighbor = px >= 0 && px < WIDTH && py >= 0 && py < HEIGHT &&
                                    geometry_plane[py * WIDTH + px] != 0;
                    if (center != neighbor) boundary = true;
                }
            if (boundary) edges[y * WIDTH + x] = 1;
        }
    }
    for (int32_t y = geometry_area.y1; y <= geometry_area.y2; ++y)
        lv_memzero(geometry_plane + y * WIDTH + geometry_area.x1,
                   lv_area_get_width(&geometry_area));
    geometry_reset();
}

static void geometry_extent(const lv_area_t *a)
{
    geometry_area.x1 = LV_MIN(geometry_area.x1, a->x1);
    geometry_area.y1 = LV_MIN(geometry_area.y1, a->y1);
    geometry_area.x2 = LV_MAX(geometry_area.x2, a->x2);
    geometry_area.y2 = LV_MAX(geometry_area.y2, a->y2);
}

static int64_t geometry_edge(const uint32_t *p, int64_t x, int64_t y)
{
    return (int64_t)(int32_t)p[0] * 8 + x * (int32_t)p[1] + y * (int32_t)p[2];
}

static bool geometry_circle(const uint32_t *p, int64_t a, int64_t b)
{
    int64_t q = (int64_t)(int16_t)(p[1] & 65535u) * INT64_C(4294967296) + p[0];
    int64_t dx = (int32_t)p[2], dy = (int32_t)p[3];
    return q + a * ((dx - 64) / 8) + b * ((dy - 64) / 8) + a * a + b * b <= 0;
}

static bool geometry_inside(const struct rnd_common *c, const uint32_t *p,
                             unsigned op, int64_t x, int64_t y)
{
    if (op == 9) {
        for (unsigned i = 0; i < 3; ++i) {
            int64_t e = geometry_edge(p + 3 * i, x, y);
            if (c->flags & (2u << i) ? e < 0 : e <= 0) return false;
        }
        return true;
    }
    if (op == 10) {
        int64_t t = geometry_edge(p, x, y), n = geometry_edge(p + 3, x, y);
        return (t >= 0 && t <= (int64_t)p[6] * 8 && n >= -(int64_t)p[7] * 8 &&
                n <= (int64_t)p[7] * 8) ||
               ((c->flags & RND_CAP_START) && geometry_circle(p + 8, x - 1, y - 1)) ||
               ((c->flags & RND_CAP_END) && geometry_circle(p + 12, x - 1, y - 1));
    }
    bool ring = geometry_circle(p, x - 1, y - 1) &&
                ((c->flags & RND_INNER_EMPTY) || !geometry_circle(p + 4, x - 1, y - 1));
    if (c->flags & RND_FULL_CIRCLE) return ring;
    bool b0 = geometry_edge(p + 16, x, y) >= 0, b1 = geometry_edge(p + 19, x, y) >= 0;
    bool angle = c->flags & RND_LARGE_ARC ? b0 || b1 : b0 && b1;
    return (ring && angle) ||
           ((c->flags & RND_CAP_START) && geometry_circle(p + 8, x - 1, y - 1)) ||
           ((c->flags & RND_CAP_END) && geometry_circle(p + 12, x - 1, y - 1));
}

void s3_compare_geometry(lv_draw_task_t *t, const struct rnd_common *c,
                         const uint32_t *p, uint8_t op)
{
    if (!recording || c->rect.x1 < c->rect.x0 || c->rect.y1 < c->rect.y0) return;
    geometry_flush();
    lv_area_t area = { c->rect.x0, c->rect.y0, c->rect.x1, c->rect.y1 };
    lv_area_move(&area, t->target_layer->buf_area.x1, t->target_layer->buf_area.y1);
    lv_area_t clip;
    if (!clipped(t, &area, &clip)) return;
    geometry_extent(&clip);
    for (int32_t y = clip.y1; y <= clip.y2; ++y)
        for (int32_t x = clip.x1; x <= clip.x2; ++x) {
            int64_t ox = (int64_t)(x - t->target_layer->buf_area.x1 - c->rect.x0) * 8;
            int64_t oy = (int64_t)(y - t->target_layer->buf_area.y1 - c->rect.y0) * 8;
            bool inside = false;
            unsigned samples = c->flags & RND_AA ? 4u : 1u;
            for (unsigned j = 0; j < samples; ++j)
                for (unsigned i = 0; i < samples; ++i)
                    inside |= geometry_inside(c, p, op, ox + (samples == 4 ? 2 * i + 1 : 4),
                                              oy + (samples == 4 ? 2 * j + 1 : 4));
            geometry_plane[y * WIDTH + x] = inside;
        }
    geometry_flush();
}

static void software_geometry(lv_draw_task_t *t, const lv_draw_sw_blend_dsc_t *d)
{
    if (geometry_task != t || geometry_descriptor != t->draw_dsc) {
        geometry_flush();
        geometry_task = t;
        geometry_descriptor = t->draw_dsc;
    }
    lv_area_t a;
    if (!clipped(t, d->blend_area, &a)) return;
    if (d->mask_buf && !lv_area_intersect(&a, &a, d->mask_area)) return;
    geometry_extent(&a);
    for (int32_t y = a.y1; y <= a.y2; ++y)
        for (int32_t x = a.x1; x <= a.x2; ++x) {
            uint8_t cov = 255;
            if (d->mask_buf && d->mask_res == LV_DRAW_SW_MASK_RES_CHANGED) {
                uint32_t stride = d->mask_stride ? d->mask_stride : lv_area_get_width(d->mask_area);
                cov = d->mask_buf[(y - d->mask_area->y1) * stride + x - d->mask_area->x1];
            }
            geometry_plane[y * WIDTH + x] |= cov != 0;
        }
}

static uint8_t image_alpha(const struct rnd_common *c, const struct rnd_affine *a,
                            const lv_draw_buf_t *image, int32_t x, int32_t y)
{
    if (x < 0 || y < 0 || x >= a->width || y >= a->height) return 0;
    const uint8_t *data = image->data;
    if (c->src_fmt >= RND_I8) {
        unsigned bits = c->src_fmt == RND_I8 ? 8 : c->src_fmt == RND_I4 ? 4 :
                        c->src_fmt == RND_I2 ? 2 : 1;
        const uint8_t *indices = data + (4u << bits);
        unsigned position = (unsigned)x * bits;
        unsigned index = (indices[y * a->stride + position / 8] >>
                         (8 - bits - position % 8)) & ((1u << bits) - 1u);
        return data[index * 4 + 3];
    }
    if (c->src_fmt == RND_ARGB8888) return data[y * a->stride + x * 4 + 3];
    uint16_t value = data[y * a->stride + x * 2] | ((uint16_t)data[y * a->stride + x * 2 + 1] << 8);
    return c->flags & RND_COLORKEY && value == a->key ? 0 : 255;
}

void s3_compare_affine(lv_draw_task_t *t, const struct rnd_common *c, const uint32_t *p,
                       const struct rnd_affine *a, const lv_draw_buf_t *image)
{
    if (!recording) return;
    lv_area_t area = { c->rect.x0, c->rect.y0, c->rect.x1, c->rect.y1 };
    lv_area_move(&area, t->target_layer->buf_area.x1, t->target_layer->buf_area.y1);
    lv_area_t clip;
    if (!clipped(t, &area, &clip)) return;
    for (int32_t y = clip.y1; y <= clip.y2; ++y)
        for (int32_t x = clip.x1; x <= clip.x2; ++x) {
            int64_t kx = x - area.x1, ky = y - area.y1;
            int64_t u = (int32_t)p[0] + kx * (int32_t)p[2] + ky * (int32_t)p[4];
            int64_t v = (int32_t)p[1] + kx * (int32_t)p[3] + ky * (int32_t)p[5];
            bool edge;
            if (c->flags & RND_BILINEAR) {
                int64_t s = u - 32768, r = v - 32768;
                uint32_t f = (uint32_t)(s >> 8) & 255u, g = (uint32_t)(r >> 8) & 255u;
                int32_t i = (int32_t)(s >> 16), j = (int32_t)(r >> 16);
                uint32_t alpha = (256-f)*(256-g)*image_alpha(c,a,image,i,j) +
                    f*(256-g)*image_alpha(c,a,image,i+1,j) +
                    (256-f)*g*image_alpha(c,a,image,i,j+1) + f*g*image_alpha(c,a,image,i+1,j+1);
                edge = ((alpha + 32768u) >> 16) != 255;
            } else edge = image_alpha(c,a,image,(int32_t)(u >> 16),(int32_t)(v >> 16)) != 255;
            if (edge) edges[y * WIDTH + x] = 1;
        }
    if (c->flags & RND_ROUND_CLIP) {
        lv_area_t mask = { (int16_t)p[6], (int16_t)(p[6] >> 16),
                           (int16_t)p[7], (int16_t)(p[7] >> 16) };
        lv_area_move(&mask, t->target_layer->buf_area.x1, t->target_layer->buf_area.y1);
        s3_compare_shape(t, &mask, a->clip_radius, -1, 0);
    }
}

void __real_lv_draw_sw_blend(lv_draw_task_t *t, const lv_draw_sw_blend_dsc_t *d);
void __wrap_lv_draw_sw_blend(lv_draw_task_t *t, const lv_draw_sw_blend_dsc_t *d)
{
    if (recording) {
        lv_area_t clip;
        bool geometric = t->type == LV_DRAW_TASK_TYPE_TRIANGLE ||
                         t->type == LV_DRAW_TASK_TYPE_LINE || t->type == LV_DRAW_TASK_TYPE_ARC;
        if (geometric) software_geometry(t, d);
        if (!geometric && d->mask_buf && d->mask_res == LV_DRAW_SW_MASK_RES_CHANGED &&
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
