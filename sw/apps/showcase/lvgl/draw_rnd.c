/* File: draw_rnd.c
 * Spec: RND v0.4 2.1–2.6/5.4; design rnd-disp 4.2/4.3.
 * Description: LVGL v9.6 draw-task translation; synchronous shared IRQ completion.
 * Clock domain: clk_sys, descriptor execution in clk_mem.
 */
#include "draw_rnd.h"
#include "showcase_lvgl.h"
#include "cache.h"
#include "src/draw/lv_draw_private.h"
#include "src/draw/lv_draw_label_private.h"
#include "src/draw/lv_draw_image_private.h"
#include "src/image/lv_image_decoder_private.h"
#include "src/font/lv_font_private.h"
#include "src/misc/lv_area_private.h"

enum { RND_UNIT = 2, GLYPH_CACHE_BYTES = 1046976, TEMP_BYTES = 6 * 1024 * 1024 };
static _Alignas(64) struct rnd_command command_storage[SHOWCASE_RND_BATCH_COMMANDS + 1];
static struct rnd_command *commands;
static _Alignas(64) uint32_t parameter_storage[SHOWCASE_RND_BATCH_COMMANDS][32];
/* CJK glyph IDs are sparse and exceed the Montserrat descriptor count.
 * Cache only glyphs actually drawn, keyed by font and glyph ID.
 */
static _Alignas(64) uint8_t glyph_cache[GLYPH_CACHE_BYTES] __attribute__((section(".noinit")));
static struct glyph_entry {
    const lv_font_t *font;
    uint32_t glyph_id;
    uint32_t offset_plus_one;
    uint16_t stride;
} glyph_entries[4096];
static unsigned glyph_entry_count;
static _Alignas(64) uint8_t temporary[TEMP_BYTES] __attribute__((section(".noinit")));
static struct rnd_range sources[3]; /* Target, image/decoded layer, parameter arena. */
static struct rnd_range target;
static uint16_t command_count;
static unsigned source_count;
static uint32_t glyph_cache_bytes;
static uint64_t glyph_clean_ticks;
static bool enabled = true;
static struct showcase_draw_rnd_stats stats;
static bool initializing_sw;
static lv_draw_unit_t *sw_unit;
static int32_t (*sw_dispatch)(lv_draw_unit_t *, lv_layer_t *);

void *__real_lv_draw_create_unit(size_t size);
void __real_lv_draw_sw_init(void);

void *__wrap_lv_draw_create_unit(size_t size)
{
    void *unit = __real_lv_draw_create_unit(size);
    if (initializing_sw) sw_unit = unit;
    return unit;
}

static int32_t timed_sw_dispatch(lv_draw_unit_t *unit, lv_layer_t *layer)
{
    uint64_t start = platform_ticks();
    int32_t count = sw_dispatch(unit, layer);
    uint64_t elapsed = platform_ticks() - start;
    /* LV_OS_NONE dispatch executes the complete SW task synchronously. */
    if (count > 0) {
        stats.software += (uint32_t)count;
        stats.sw_ticks += elapsed;
    }
    return count;
}

void __wrap_lv_draw_sw_init(void)
{
    initializing_sw = true;
    __real_lv_draw_sw_init();
    initializing_sw = false;
    sw_dispatch = sw_unit->dispatch_cb;
    sw_unit->dispatch_cb = timed_sw_dispatch;
}

static void run_batch(const struct rnd_batch *batch, bool copy)
{
    uint32_t perf[6];
    showcase_rnd_run(batch);
    struct showcase_rnd_timing timing = showcase_rnd_last_timing();
    stats.timing.clean_ticks += timing.clean_ticks;
    stats.timing.wait_ticks += timing.wait_ticks;
    stats.timing.finish_ticks += timing.finish_ticks;
    stats.timing.cache_ops += timing.cache_ops;
    rnd_read_perf(perf);
    if (copy) {
        stats.copy.ticks += showcase_rnd_elapsed_ticks();
        stats.copy.commands += batch->count;
        stats.copy.doorbells++;
        for (unsigned i = 0; i < 6; ++i) stats.copy.perf[i] += perf[i];
    } else {
        stats.rnd_ticks += showcase_rnd_elapsed_ticks();
        stats.commands += batch->count;
        stats.doorbells++;
        for (unsigned i = 0; i < 6; ++i) stats.perf[i] += perf[i];
    }
}

static uint32_t rgb(lv_color_t color)
{
    /* lv_color_to_u32 includes FF alpha; RND keeps OPA in a separate field. */
    return lv_color_to_u32(color) & 0xffffffu;
}

static struct rnd_rect rect(const lv_area_t *a, const lv_layer_t *layer)
{
    return (struct rnd_rect) {
        a->x1 - layer->buf_area.x1, a->y1 - layer->buf_area.y1,
        a->x2 - layer->buf_area.x1, a->y2 - layer->buf_area.y1
    };
}

static enum rnd_format format(lv_color_format_t cf)
{
    switch (cf) {
    case LV_COLOR_FORMAT_ARGB8888: return RND_ARGB8888;
    case LV_COLOR_FORMAT_I8: return RND_I8;
    case LV_COLOR_FORMAT_I4: return RND_I4;
    case LV_COLOR_FORMAT_I2: return RND_I2;
    case LV_COLOR_FORMAT_I1: return RND_I1;
    default: return RND_RGB565;
    }
}

static bool image_format(lv_color_format_t cf)
{
    return cf == LV_COLOR_FORMAT_RGB565 || cf == LV_COLOR_FORMAT_ARGB8888 ||
           cf == LV_COLOR_FORMAT_I8 || cf == LV_COLOR_FORMAT_I4 ||
           cf == LV_COLOR_FORMAT_I2 || cf == LV_COLOR_FORMAT_I1;
}

static struct rnd_common common(lv_draw_task_t *t, const lv_area_t *area,
                                lv_color_t color, uint8_t opa)
{
    lv_layer_t *layer = t->target_layer;
    lv_area_t clip;
    lv_area_intersect(&clip, &t->clip_area, &layer->buf_area);
    struct rnd_common c = {
        .dst_base = rnd_physical(layer->draw_buf->data),
        .dst_stride = layer->draw_buf->header.stride,
        .dst_fmt = format(layer->color_format),
        .clip = rect(&clip, layer), .rect = rect(area, layer),
        .color = rgb(color), .opa = opa
    };
    return c;
}

static uint16_t radius(int32_t r, const lv_area_t *a)
{
    int32_t limit = LV_MIN(lv_area_get_width(a), lv_area_get_height(a)) / 2;
    return LV_MIN(r, limit);
}

static void submit(void)
{
    if (command_count == 0) return;
    struct rnd_batch batch = {
        .commands = commands, .count = command_count,
        .sources = sources, .source_count = source_count,
        .targets = &target, .target_count = 1
    };
    /* RND 5.4: destination is a source too, for CPU-written RMW pixels. The
     * shared driver cleans every source, waits DONE IRQ and invalidates target.
     */
    run_batch(&batch, false);
    command_count = 0;
    sources[0] = target;
    source_count = 1;
}

static struct rnd_command *next_command(void)
{
    if (command_count == SHOWCASE_RND_BATCH_COMMANDS) submit();
    return &commands[command_count++];
}

static void merge_source(struct rnd_range *ranges, unsigned *count,
                         const void *address, uint32_t bytes)
{
    uintptr_t begin = (uintptr_t)address;
    uintptr_t end = begin + bytes;
    /* Collapse every overlap/adjacency, including a new range bridging two
     * earlier ones. Target remains among the sources and is always cleaned.
     */
    for (unsigned i = 0; i < *count;) {
        uintptr_t other = (uintptr_t)ranges[i].address;
        uintptr_t stop = other + ranges[i].bytes;
        if (begin <= stop && other <= end) {
            begin = LV_MIN(begin, other);
            end = LV_MAX(end, stop);
            ranges[i] = ranges[--(*count)];
            i = 0;
        } else {
            ++i;
        }
    }
    ranges[(*count)++] = (struct rnd_range) { (const void *)begin, end - begin };
}

static void add_source(const void *address, uint32_t bytes)
{
    merge_source(sources, &source_count, address, bytes);
}

static uint64_t geometry_sqrt(uint64_t value)
{
    uint64_t result = 0;
    uint64_t bit = UINT64_C(1) << 62;
    while (bit > value) bit >>= 2;
    while (bit) {
        if (value >= result + bit) {
            value -= result + bit;
            result = (result >> 1) + bit;
        } else result >>= 1;
        bit >>= 2;
    }
    return result;
}

static int64_t nearest_divide(int64_t numerator, int64_t denominator)
{
    return (numerator + (numerator < 0 ? -denominator / 2 : denominator / 2)) / denominator;
}

static uint16_t geometry_aa(void)
{
    return lv_display_get_antialiasing(lv_display_get_default()) ? RND_AA : 0;
}

static void circle_parameters(uint32_t *p, const struct rnd_common *c,
                               int32_t cx8, int32_t cy8, int32_t radius8)
{
    int64_t x = (int64_t)c->rect.x0 * 8 + 1 - cx8;
    int64_t y = (int64_t)c->rect.y0 * 8 + 1 - cy8;
    int64_t q = x * x + y * y - (int64_t)radius8 * radius8;
    p[0] = (uint32_t)q;
    p[1] = (uint32_t)((uint64_t)q >> 32);
    p[2] = (uint32_t)(16 * x + 64);
    p[3] = (uint32_t)(16 * y + 64);
}

static bool edge_parameters(uint32_t *p, int32_t ex, int32_t ey,
                             int32_t x, int32_t y)
{
    int64_t initial = (int64_t)x * ex + (int64_t)y * ey;
    if (initial < INT32_MIN || initial > INT32_MAX) return false;
    p[0] = (uint32_t)initial;
    p[1] = (uint32_t)ex;
    p[2] = (uint32_t)ey;
    return true;
}

static uint32_t parameter_block(unsigned words, const uint32_t *value)
{
    uint32_t *p = parameter_storage[command_count - 1u];
    for (unsigned i = 0; i < words; ++i) p[i] = value[i];
    /* One contiguous range also covers unused slots between parameter commands. */
    add_source(parameter_storage, (uint32_t)command_count * sizeof(parameter_storage[0]));
    return rnd_physical(p);
}

/* rnd-spec 2.3/5.4: extrema over the clipped sample rectangle. */
static bool geometry_range(const struct rnd_common *c, const uint32_t *p, uint8_t op)
{
    int32_t left = LV_MAX(c->rect.x0, c->clip.x0);
    int32_t right = LV_MIN(c->rect.x1, c->clip.x1);
    int32_t top = LV_MAX(c->rect.y0, c->clip.y0);
    int32_t bottom = LV_MIN(c->rect.y1, c->clip.y1);
    if (left > right || top > bottom) return true;
    const int64_t minimum = -INT64_C(34359738368), maximum = INT64_C(34359738367);
    int32_t first = c->flags & RND_AA ? 1 : 4;
    int32_t last = c->flags & RND_AA ? 7 : 4;
    int64_t xs[2] = {8 * ((int64_t)left - c->rect.x0) + first,
                     8 * ((int64_t)right - c->rect.x0) + last};
    int64_t ys[2] = {8 * ((int64_t)top - c->rect.y0) + first,
                     8 * ((int64_t)bottom - c->rect.y0) + last};
    unsigned edges = op == 9 ? 3 : 2, edge_base = op == 11 ? 16 : 0;
    for (unsigned k = 0; k < edges; ++k) {
        const uint32_t *e = p + edge_base + 3 * k;
        for (unsigned j = 0; j < 2; ++j)
            for (unsigned i = 0; i < 2; ++i) {
                int64_t value = 8 * (int64_t)(int32_t)e[0] +
                                xs[i] * (int32_t)e[1] + ys[j] * (int32_t)e[2];
                if (value < minimum || value > maximum) return false;
            }
    }
    unsigned circles = op == 9 ? 0 : op == 10 ? 2 : 4;
    for (unsigned k = 0; k < circles; ++k) {
        const uint32_t *q = p + (op == 10 ? 8 : 0) + 4 * k;
        int64_t initial = (int64_t)(int32_t)q[1] * INT64_C(4294967296) + q[0];
        int64_t dx = (int32_t)q[2], dy = (int32_t)q[3];
        int64_t x = (dx - 64) / 16, y = (dy - 64) / 16;
        int64_t radius_squared = x * x + y * y - initial;
        if (initial < minimum || initial > maximum || -radius_squared < minimum ||
            dx < -8388608 || dx > 8388607 || dy < -8388608 || dy > 8388607)
            return false;
        for (unsigned j = 0; j < 2; ++j)
            for (unsigned i = 0; i < 2; ++i) {
                int64_t vx = x + xs[i] - 1, vy = y + ys[j] - 1;
                int64_t value = vx * vx + vy * vy - radius_squared;
                int64_t step_x = 16 * vx + 64, step_y = 16 * vy + 64;
                if (value > maximum || step_x < -8388608 || step_x > 8388607 ||
                    step_y < -8388608 || step_y > 8388607) return false;
            }
    }
    return true;
}

/* Evaluation precedes target allocation; geometry uses only coordinates and color. */
static struct rnd_common geometry_common(lv_draw_task_t *t, const lv_area_t *area,
                                          lv_color_t color, uint8_t opa)
{
    lv_layer_t *layer = t->target_layer;
    lv_area_t clip;
    lv_area_intersect(&clip, &t->clip_area, &layer->buf_area);
    return (struct rnd_common) {
        .rect = rect(area, layer), .clip = rect(&clip, layer),
        .color = rgb(color), .opa = opa
    };
}

static bool geometry_command(lv_draw_task_t *t, struct rnd_common *c,
                              uint32_t *p, uint8_t op, bool emit)
{
    if (!emit) return geometry_range(c, p, op);
    lv_layer_t *layer = t->target_layer;
    c->dst_base = rnd_physical(layer->draw_buf->data);
    c->dst_stride = layer->draw_buf->header.stride;
    c->dst_fmt = format(layer->color_format);
    struct rnd_command *cmd = next_command();
    uint32_t physical = parameter_block(32, p);
    if (op == 9) rnd_triangle(cmd, c, physical);
    else if (op == 10) rnd_line(cmd, c, physical);
    else rnd_arc(cmd, c, physical);
    return true;
}

static bool triangle(lv_draw_task_t *t, const lv_draw_triangle_dsc_t *d, bool emit)
{
    struct rnd_common c = geometry_common(t, &t->area, d->color, d->opa);
    c.flags = geometry_aa();
    uint32_t p[32] = {0};
    lv_point_t v[3];
    for (unsigned i = 0; i < 3; ++i) v[i] = lv_point_from_precise(&d->p[i]);
    int64_t winding = (int64_t)(v[1].x - v[0].x) * (v[2].y - v[0].y) -
                      (int64_t)(v[1].y - v[0].y) * (v[2].x - v[0].x);
    if (winding == 0) {
        c.rect.x1 = c.rect.x0 - 1;
        return geometry_command(t, &c, p, 9, emit);
    }
    if (winding < 0) {
        lv_point_t swap = v[1]; v[1] = v[2]; v[2] = swap;
    }
    for (unsigned i = 0; i < 3; ++i) {
        const lv_point_t *a = &v[i], *b = &v[(i + 1u) % 3u];
        int32_t dx = b->x - a->x, dy = b->y - a->y;
        int64_t length = (int64_t)geometry_sqrt((uint64_t)((int64_t)dx * dx + (int64_t)dy * dy));
        int32_t ex = (int32_t)(-(int64_t)dy * 65536 / length);
        int32_t ey = (int32_t)((int64_t)dx * 65536 / length);
        /* Canonical origin keeps the quantized shared edge exactly opposite on both sides. */
        const lv_point_t *anchor = a->x < b->x || (a->x == b->x && a->y < b->y) ? a : b;
        if (!edge_parameters(p + i * 3u, ex, ey,
                             t->area.x1 - anchor->x, t->area.y1 - anchor->y)) return false;
        if (dy < 0 || (dy == 0 && dx > 0)) c.flags |= (uint16_t)(2u << i);
    }
    if (d->grad.dir == LV_GRAD_DIR_NONE || d->grad.stops_count < 2) {
        return geometry_command(t, &c, p, 9, emit);
    }
    bool vertical = d->grad.dir == LV_GRAD_DIR_VER;
    int32_t length = vertical ? lv_area_get_height(&t->area) : lv_area_get_width(&t->area);
    c.flags |= RND_TRI_GRAD | (vertical ? RND_TRI_GRAD_V : 0);
    if (d->grad.stops_count == 2 && d->grad.stops[0].frac == 0 &&
        d->grad.stops[1].frac == 255 && length > 1) {
        const lv_grad_stop_t *one = &d->grad.stops[0], *two = &d->grad.stops[1];
        int32_t end = (255 * length) >> 8;
        p[9] = rgb(one->color) | ((uint32_t)one->opa << 24);
        p[10] = (uint32_t)(((int32_t)two->opa - one->opa) * 65536 / end);
        p[11] = (uint32_t)(((int32_t)two->color.red - one->color.red) * 65536 / end);
        p[12] = (uint32_t)(((int32_t)two->color.green - one->color.green) * 65536 / end);
        p[13] = (uint32_t)(((int32_t)two->color.blue - one->color.blue) * 65536 / end);
        return geometry_command(t, &c, p, 9, emit);
    }
    for (int32_t k = 0; k < length; ++k) {
        unsigned i = 1;
        while (i < d->grad.stops_count - 1u && k > (d->grad.stops[i].frac * length >> 8)) ++i;
        const lv_grad_stop_t *one = &d->grad.stops[i - 1], *two = &d->grad.stops[i];
        int32_t lo = one->frac * length >> 8, hi = two->frac * length >> 8;
        uint8_t mix = k <= lo ? 0 : k >= hi ? 255 : (k - lo) * 255 / (hi - lo);
        uint8_t alpha = (two->opa * mix + one->opa * (255u - mix) + 127u) / 255u;
        p[9] = rgb(lv_color_mix(two->color, one->color, mix)) | ((uint32_t)alpha << 24);
        struct rnd_common stripe = c;
        if (vertical) {
            stripe.clip.y0 = LV_MAX(c.clip.y0, c.rect.y0 + k);
            stripe.clip.y1 = LV_MIN(c.clip.y1, c.rect.y0 + k);
        } else {
            stripe.clip.x0 = LV_MAX(c.clip.x0, c.rect.x0 + k);
            stripe.clip.x1 = LV_MIN(c.clip.x1, c.rect.x0 + k);
        }
        if (stripe.clip.x0 <= stripe.clip.x1 && stripe.clip.y0 <= stripe.clip.y1)
            if (!geometry_command(t, &stripe, p, 9, emit)) return false;
    }
    return true;
}

static bool line(lv_draw_task_t *t, const lv_draw_line_dsc_t *d, bool emit)
{
    struct rnd_common c = geometry_common(t, &t->_real_area, d->color, d->opa);
    c.flags = geometry_aa() | (d->round_start ? RND_CAP_START : 0) |
              (d->round_end ? RND_CAP_END : 0);
    uint32_t p[32] = {0};
    int32_t dx = (int32_t)d->p2.x - (int32_t)d->p1.x;
    int32_t dy = (int32_t)d->p2.y - (int32_t)d->p1.y;
    uint64_t squared = (uint64_t)((int64_t)dx * dx + (int64_t)dy * dy);
    uint32_t length = (uint32_t)geometry_sqrt(squared * UINT64_C(4294967296));
    int32_t phase = (d->width & 1) ? 4 : 0;
    int32_t x = 8 * (t->_real_area.x1 - (int32_t)d->p1.x) - phase;
    int32_t y = 8 * (t->_real_area.y1 - (int32_t)d->p1.y) - phase;
    if (length) {
        int32_t tx = (int32_t)((int64_t)dx * INT64_C(4294967296) / length);
        int32_t ty = (int32_t)((int64_t)dy * INT64_C(4294967296) / length);
        int64_t along = nearest_divide((int64_t)x * tx + (int64_t)y * ty, 8);
        int64_t normal = nearest_divide(-(int64_t)x * ty + (int64_t)y * tx, 8);
        if (along < INT32_MIN || along > INT32_MAX ||
            normal < INT32_MIN || normal > INT32_MAX) return false;
        p[0] = (uint32_t)along;
        p[1] = (uint32_t)tx; p[2] = (uint32_t)ty;
        p[3] = (uint32_t)normal;
        p[4] = (uint32_t)-ty; p[5] = (uint32_t)tx;
    } else {
        p[0] = (uint32_t)-65536;
        c.flags |= RND_CAP_START;
    }
    p[6] = length;
    p[7] = (uint32_t)d->width * 32768u;
    int32_t ox = t->target_layer->buf_area.x1, oy = t->target_layer->buf_area.y1;
    circle_parameters(p + 8, &c, ((int32_t)d->p1.x - ox) * 8 + phase,
                      ((int32_t)d->p1.y - oy) * 8 + phase, d->width * 4);
    circle_parameters(p + 12, &c, ((int32_t)d->p2.x - ox) * 8 + phase,
                      ((int32_t)d->p2.y - oy) * 8 + phase, d->width * 4);
    return geometry_command(t, &c, p, 10, emit);
}

static bool arc(lv_draw_task_t *t, const lv_draw_arc_dsc_t *d, bool emit)
{
    struct rnd_common c = geometry_common(t, &t->_real_area, d->color, d->opa);
    int32_t start = (int32_t)d->start_angle, end = (int32_t)d->end_angle;
    int32_t sweep = ((end - start) % 360 + 360) % 360;
    bool full = LV_ABS(end - start) >= 360;
    int32_t width = LV_MIN(d->width, d->radius);
    c.flags = geometry_aa() | (d->rounded ? RND_CAP_START | RND_CAP_END : 0) |
              (sweep > 180 ? RND_LARGE_ARC : 0) | (full ? RND_FULL_CIRCLE : 0) |
              (width == d->radius ? RND_INNER_EMPTY : 0);
    if ((!full && sweep == 0) || width == 0) c.rect.x1 = c.rect.x0 - 1;
    uint32_t p[32] = {0};
    int32_t cx = d->center.x - t->target_layer->buf_area.x1;
    int32_t cy = d->center.y - t->target_layer->buf_area.y1;
    circle_parameters(p, &c, cx * 8, cy * 8, d->radius * 8);
    circle_parameters(p + 4, &c, cx * 8, cy * 8, (d->radius - width) * 8);
    const int32_t angles[2] = { start, end };
    for (unsigned i = 0; i < 2; ++i) {
        int32_t angle = (angles[i] % 360 + 360) % 360;
        int32_t sine = lv_trigo_sin(angle), cosine = lv_trigo_sin(angle + 90);
        int32_t middle = d->radius * 8 - width * 4;
        int32_t ex = i == 0 ? -sine * 2 : sine * 2;
        int32_t ey = i == 0 ? cosine * 2 : -cosine * 2;
        if (!edge_parameters(p + 16 + i * 3, ex, ey,
                             t->_real_area.x1 - d->center.x,
                             t->_real_area.y1 - d->center.y)) return false;
        circle_parameters(p + 8 + i * 4, &c,
            cx * 8 + (int32_t)nearest_divide((int64_t)middle * cosine, 1 << LV_TRIGO_SHIFT),
            cy * 8 + (int32_t)nearest_divide((int64_t)middle * sine, 1 << LV_TRIGO_SHIFT),
            width * 4);
    }
    return geometry_command(t, &c, p, 11, emit);
}

static void fill(lv_draw_task_t *t, const lv_draw_fill_dsc_t *d, const lv_area_t *a)
{
    struct rnd_common c = common(t, a, d->color, d->opa);
    int32_t steps[4] = {0, 0, 0, 0};
    uint16_t r = radius(d->radius, a);
    if (d->grad.dir == LV_GRAD_DIR_NONE || d->grad.stops_count < 2) {
        rnd_fill(next_command(), &c, r, 0, steps);
        return;
    }
    bool vertical = d->grad.dir == LV_GRAD_DIR_VER;
    int32_t length = vertical ? lv_area_get_height(a) : lv_area_get_width(a);
    /* Preserve the full rectangle and its round corners when splitting stops.
     * General stops use one constant-color strip per pixel. The common two
     * endpoint case uses a single hardware Q16 gradient instead.
     */
    if (d->grad.stops_count == 2 && d->grad.stops[0].frac == 0 &&
        d->grad.stops[1].frac == 255 && length > 1) {
        int32_t end = (255 * length) >> 8;
        const lv_grad_stop_t *one = &d->grad.stops[0];
        const lv_grad_stop_t *two = &d->grad.stops[1];
        uint32_t start = rgb(one->color) | ((uint32_t)one->opa << 24);
        steps[0] = ((int32_t)two->opa - one->opa) * 65536 / end;
        steps[1] = ((int32_t)two->color.red - one->color.red) * 65536 / end;
        steps[2] = ((int32_t)two->color.green - one->color.green) * 65536 / end;
        steps[3] = ((int32_t)two->color.blue - one->color.blue) * 65536 / end;
        c.flags = RND_GRAD | (vertical ? RND_GRAD_V : 0);
        rnd_fill(next_command(), &c, r, start, steps);
        return;
    }
    for (int32_t k = 0; k < length; ++k) {
        unsigned i = 1;
        while (i < d->grad.stops_count - 1u &&
               k > (d->grad.stops[i].frac * length >> 8)) ++i;
        const lv_grad_stop_t *one = &d->grad.stops[i - 1];
        const lv_grad_stop_t *two = &d->grad.stops[i];
        int32_t lo = one->frac * length >> 8;
        int32_t hi = two->frac * length >> 8;
        uint8_t mix = k <= lo ? 0 : k >= hi ? 255 : (k - lo) * 255 / (hi - lo);
        c.color = rgb(lv_color_mix(two->color, one->color, mix));
        uint32_t alpha = (two->opa * mix + one->opa * (255u - mix) + 127u) / 255u;
        c.opa = (d->opa * alpha + 127u) / 255u;
        struct rnd_common stripe = c;
        if (vertical) {
            stripe.clip.y0 = LV_MAX(c.clip.y0, c.rect.y0 + k);
            stripe.clip.y1 = LV_MIN(c.clip.y1, c.rect.y0 + k);
        } else {
            stripe.clip.x0 = LV_MAX(c.clip.x0, c.rect.x0 + k);
            stripe.clip.x1 = LV_MIN(c.clip.x1, c.rect.x0 + k);
        }
        if (stripe.clip.x0 <= stripe.clip.x1 && stripe.clip.y0 <= stripe.clip.y1)
            rnd_fill(next_command(), &stripe, r, 0, steps);
    }
}

static void glyph_core(lv_draw_task_t *t, lv_draw_glyph_dsc_t *g,
                       lv_draw_fill_dsc_t *f, const lv_area_t *fill_area)
{
    if (f && fill_area) fill(t, f, fill_area);
    if (g == NULL) return;
    if (g->format == LV_FONT_GLYPH_FORMAT_NONE) {
        if (g->bg_coords) {
            struct rnd_common c = common(t, g->bg_coords, g->color, g->opa);
            rnd_border(next_command(), &c, 0, 1, 15);
        }
        return;
    }
    unsigned index = 0;
    while (index < glyph_entry_count &&
           (glyph_entries[index].font != g->g->resolved_font ||
            glyph_entries[index].glyph_id != g->g->gid.index)) ++index;
    if (index == glyph_entry_count) {
        if (glyph_entry_count == sizeof(glyph_entries) / sizeof(glyph_entries[0])) {
            platform_puts("showcase glyph entries full\r\n");
            platform_stop();
        }
        ++glyph_entry_count;
        glyph_entries[index].font = g->g->resolved_font;
        glyph_entries[index].glyph_id = g->g->gid.index;
    }
    struct glyph_entry *entry = &glyph_entries[index];
    if (entry->offset_plus_one == 0) {
        /* LVGL's iterator owns the reusable A8 buffer. Convert/copy only once
         * and hand the immutable cache entry to RND (rnd 5.4 / SoC 7.4).
         */
        const lv_draw_buf_t *bitmap = lv_font_get_glyph_bitmap_internal(g->g, g->_draw_buf);
        uint32_t bytes = bitmap->header.stride * bitmap->header.h;
        uint32_t allocated = LV_ROUND_UP(bytes, 64);
        if (glyph_cache_bytes + allocated > sizeof(glyph_cache)) {
            platform_puts("S3 glyph cache full\r\n");
            platform_stop();
        }
        uint8_t *data = glyph_cache + glyph_cache_bytes;
        lv_memcpy(data, bitmap->data, bytes);
        uint64_t clean_start = platform_ticks();
        cache_clean((uintptr_t)data, bytes);
        uint64_t elapsed = platform_ticks() - clean_start;
        glyph_clean_ticks += elapsed;
        stats.timing.clean_ticks += elapsed;
        stats.timing.cache_ops++;
        entry->offset_plus_one = glyph_cache_bytes + 1u;
        entry->stride = bitmap->header.stride;
        glyph_cache_bytes += allocated;
    }
    const uint8_t *data = glyph_cache + entry->offset_plus_one - 1u;
    struct rnd_common c = common(t, g->letter_coords, g->color, g->opa);
    c.src_fmt = RND_A8;
    struct rnd_source src = { rnd_physical(data), entry->stride, 0, 0 };
    rnd_glyph(next_command(), &c, &src);
}

static void glyph(lv_draw_task_t *t, lv_draw_glyph_dsc_t *g,
                  lv_draw_fill_dsc_t *f, const lv_area_t *fill_area)
{
    uint64_t start = platform_ticks();
    uint64_t rnd_before = stats.rnd_ticks;
    uint64_t clean_before = glyph_clean_ticks;
    glyph_core(t, g, f, fill_area);
    /* A full batch may submit inside next_command; keep its wait/clean outside
     * the callback's CPU conversion/lookup/command measurement.
     */
    stats.glyph_cpu_ticks += platform_ticks() - start - (stats.rnd_ticks - rnd_before) -
                            (glyph_clean_ticks - clean_before);
}

static uint16_t blend_mode(lv_blend_mode_t mode)
{
    switch (mode) {
    case LV_BLEND_MODE_ADDITIVE: return RND_ADD;
    case LV_BLEND_MODE_SUBTRACTIVE: return RND_SUBTRACT;
    case LV_BLEND_MODE_MULTIPLY: return RND_MULTIPLY;
    default: return RND_NORMAL;
    }
}

static uint32_t packed_xy(int16_t x, int16_t y)
{
    return (uint16_t)x | ((uint32_t)(uint16_t)y << 16);
}

static int32_t sine_tenths(int32_t angle)
{
    int32_t low = angle / 10, rem = angle - low * 10;
    return (lv_trigo_sin(low) * (10 - rem) + lv_trigo_sin(low + 1) * rem) / 10;
}

/* Match LVGL's Q10 interpolated trigonometry and source-center phase. */
static void image_inverse(const lv_draw_image_dsc_t *d, int32_t matrix[4], int64_t origin[2])
{
    int32_t angle = -d->rotation;
    int32_t sine = sine_tenths(angle);
    int32_t cosine = sine_tenths(angle + 900);
    sine >>= LV_TRIGO_SHIFT - 10;
    cosine >>= LV_TRIGO_SHIFT - 10;
    if (angle == 0) { sine = 0; cosine = 1024; }
    matrix[0] = (int32_t)((int64_t)cosine * 16384 / d->scale_x);
    matrix[1] = (int32_t)(-(int64_t)sine * 16384 / d->scale_x);
    matrix[2] = (int32_t)((int64_t)sine * 16384 / d->scale_y);
    matrix[3] = (int32_t)((int64_t)cosine * 16384 / d->scale_y);
    origin[0] = (((-(int64_t)cosine * d->pivot.x + (int64_t)sine * d->pivot.y) * 64) /
                 d->scale_x + (int64_t)d->pivot.x * 256 + 128) * 256;
    origin[1] = (((-(int64_t)sine * d->pivot.x - (int64_t)cosine * d->pivot.y) * 64) /
                 d->scale_y + (int64_t)d->pivot.y * 256 + 128) * 256;
    if (d->skew_x || d->skew_y) {
        int64_t tx = (int64_t)sine_tenths(d->skew_x) * 65536 / sine_tenths(d->skew_x + 900);
        int64_t ty = (int64_t)sine_tenths(d->skew_y) * 65536 / sine_tenths(d->skew_y + 900);
        int64_t det = INT64_C(4294967296) - tx * ty;
        int32_t a = matrix[0], b = matrix[1], c = matrix[2], e = matrix[3];
        matrix[0] = (int32_t)(((int64_t)a * 65536 - tx * c) * 65536 / det);
        matrix[1] = (int32_t)(((int64_t)b * 65536 - tx * e) * 65536 / det);
        matrix[2] = (int32_t)(((int64_t)c * 65536 - ty * a) * 65536 / det);
        matrix[3] = (int32_t)(((int64_t)e * 65536 - ty * b) * 65536 / det);
        origin[0] = (int64_t)d->pivot.x * 65536 + 32768 -
            (int64_t)matrix[0] * d->pivot.x - (int64_t)matrix[1] * d->pivot.y;
        origin[1] = (int64_t)d->pivot.y * 65536 + 32768 -
            (int64_t)matrix[2] * d->pivot.x - (int64_t)matrix[3] * d->pivot.y;
    }
}

static lv_area_t image_bounds(const lv_draw_image_dsc_t *d, const lv_area_t *coords,
                               const int32_t inverse[4])
{
    lv_area_t result;
    int32_t width = lv_area_get_width(coords), height = lv_area_get_height(coords);
    if (!d->skew_x && !d->skew_y) {
        lv_image_buf_get_transformed_area(&result, width, height, d->rotation,
                                          d->scale_x, d->scale_y, &d->pivot);
        lv_area_move(&result, coords->x1, coords->y1);
        return result;
    }
    int64_t det = (int64_t)inverse[0] * inverse[3] - (int64_t)inverse[1] * inverse[2];
    int64_t forward[4] = {
        (int64_t)inverse[3] * INT64_C(4294967296) / det,
        -(int64_t)inverse[1] * INT64_C(4294967296) / det,
        -(int64_t)inverse[2] * INT64_C(4294967296) / det,
        (int64_t)inverse[0] * INT64_C(4294967296) / det
    };
    int64_t min_x = INT64_MAX, min_y = INT64_MAX, max_x = INT64_MIN, max_y = INT64_MIN;
    for (unsigned i = 0; i < 4; ++i) {
        int32_t x = (i & 1u ? width : 0) - d->pivot.x;
        int32_t y = (i & 2u ? height : 0) - d->pivot.y;
        int64_t px = (int64_t)(coords->x1 + d->pivot.x) * 65536 + forward[0] * x + forward[1] * y;
        int64_t py = (int64_t)(coords->y1 + d->pivot.y) * 65536 + forward[2] * x + forward[3] * y;
        min_x = LV_MIN(min_x, px); max_x = LV_MAX(max_x, px);
        min_y = LV_MIN(min_y, py); max_y = LV_MAX(max_y, py);
    }
    return (lv_area_t) { (int32_t)(min_x >> 16) - 1, (int32_t)(min_y >> 16) - 1,
                         (int32_t)((max_x + 65535) >> 16), (int32_t)((max_y + 65535) >> 16) };
}

static void image_core(lv_draw_task_t *t, const lv_draw_image_dsc_t *d,
                       const lv_image_decoder_dsc_t *decoder, lv_draw_image_sup_t *sup,
                       const lv_area_t *coords, const lv_area_t *clipped)
{
    (void)sup;
    const lv_draw_buf_t *image = decoder->decoded;
    struct rnd_common c = common(t, coords, lv_color_black(), d->opa);
    if (image->header.cf == LV_COLOR_FORMAT_A8) {
        c.src_fmt = RND_A8;
        c.color = rgb(d->recolor);
        struct rnd_source source = { rnd_physical(image->data), image->header.stride, 0, 0 };
        rnd_glyph(next_command(), &c, &source);
            add_source(image->data, image->data_size);
        submit();
        return;
    }
    c.src_fmt = format(image->header.cf);
    c.flags = blend_mode(d->blend_mode);
    bool scaled = d->scale_x != LV_SCALE_NONE || d->scale_y != LV_SCALE_NONE;
    bool affine = d->rotation || d->skew_x || d->skew_y || (scaled && d->antialias);
    int32_t matrix[4] = {0};
    int64_t origin[2] = {0};
    lv_area_t dest = *coords;
    if (scaled || affine) {
        image_inverse(d, matrix, origin);
        dest = image_bounds(d, coords, matrix);
        c.rect = rect(&dest, t->target_layer);
    }
    lv_area_t clip;
    if (d->skew_x || d->skew_y) clip = t->clip_area;
    else lv_area_intersect(&clip, clipped, &t->clip_area);
    lv_area_intersect(&clip, &clip, &t->target_layer->buf_area);
    c.clip = rect(&clip, t->target_layer);
    const uint8_t *data = image->data;
    uint32_t palette_bytes = LV_COLOR_FORMAT_IS_INDEXED(image->header.cf) ?
                             4u << lv_color_format_get_bpp(image->header.cf) : 0;
    if (palette_bytes) data += palette_bytes;
    struct rnd_blit blit = {
        .source = { rnd_physical(data), image->header.stride, 0, 0 },
        .scale_x = (uint32_t)((UINT64_C(65536) * 256) / d->scale_x),
        .scale_y = (uint32_t)((UINT64_C(65536) * 256) / d->scale_y),
        .palette = palette_bytes ? rnd_physical(image->data) : 0,
        .rc_color = rgb(d->recolor), .rc_opa = d->recolor_opa
    };
    if (d->recolor_opa) c.flags |= RND_RECOLOR;
    if (d->colorkey) {
        c.flags |= RND_COLORKEY;
        blit.key = lv_color_to_u16(d->colorkey->low);
    }
    struct rnd_rect image_area = rect(&d->image_area, t->target_layer);
    if (d->clip_radius) c.flags |= RND_ROUND_CLIP;
    if (affine) {
        uint32_t p[16] = {0};
        int32_t x = dest.x1 - coords->x1, y = dest.y1 - coords->y1;
        p[0] = (uint32_t)(origin[0] + (int64_t)x * matrix[0] + (int64_t)y * matrix[1]);
        p[1] = (uint32_t)(origin[1] + (int64_t)x * matrix[2] + (int64_t)y * matrix[3]);
        p[2] = (uint32_t)matrix[0]; p[3] = (uint32_t)matrix[2];
        p[4] = (uint32_t)matrix[1]; p[5] = (uint32_t)matrix[3];
        p[6] = packed_xy(image_area.x0, image_area.y0);
        p[7] = packed_xy(image_area.x1, image_area.y1);
        if (d->antialias) c.flags |= RND_BILINEAR;
        struct rnd_command *cmd = next_command();
        struct rnd_affine a = {
            .base = blit.source.base, .stride = blit.source.stride,
            .width = image->header.w, .height = image->header.h,
            .parameters = parameter_block(16, p), .palette = blit.palette, .key = blit.key,
            .clip_radius = radius(d->clip_radius, &d->image_area),
            .rc_color = blit.rc_color, .rc_opa = blit.rc_opa
        };
        rnd_affine_blit(cmd, &c, &a);
        } else {
        struct rnd_command *cmd = next_command();
        if (d->clip_radius) {
            uint32_t p[16] = {0};
            p[0] = blit.palette;
            p[1] = packed_xy(image_area.x0, image_area.y0);
            p[2] = packed_xy(image_area.x1, image_area.y1);
            blit.round_parameters = parameter_block(16, p);
            blit.clip_radius = radius(d->clip_radius, &d->image_area);
                }
        rnd_blit(cmd, &c, &blit);
        }
    add_source(image->data, image->data_size);
    /* Decoders may free or overwrite their buffer at the next callback. */
    submit();
}

static bool font_supported(const lv_font_t *font)
{
    /* All configured S3 fonts are LVGL's raster fmt_txt fonts. */
    return font->get_glyph_bitmap == lv_font_get_bitmap_fmt_txt;
}

static bool supported(lv_draw_task_t *t)
{
    if (t->target_layer->color_format != LV_COLOR_FORMAT_RGB565 &&
        t->target_layer->color_format != LV_COLOR_FORMAT_ARGB8888) return false;
    switch (t->type) {
    case LV_DRAW_TASK_TYPE_FILL: {
        const lv_draw_fill_dsc_t *d = t->draw_dsc;
        return d->grad.dir == LV_GRAD_DIR_NONE || d->grad.dir == LV_GRAD_DIR_HOR ||
               d->grad.dir == LV_GRAD_DIR_VER;
    }
    case LV_DRAW_TASK_TYPE_BORDER: return true;
    case LV_DRAW_TASK_TYPE_LINE: {
        const lv_draw_line_dsc_t *d = t->draw_dsc;
        return d->dash_width == 0 && d->dash_gap == 0 && d->points == NULL &&
               line(t, d, false);
    }
    case LV_DRAW_TASK_TYPE_ARC:
        return ((const lv_draw_arc_dsc_t *)t->draw_dsc)->img_src == NULL &&
               arc(t, t->draw_dsc, false);
    case LV_DRAW_TASK_TYPE_TRIANGLE: {
        const lv_draw_triangle_dsc_t *d = t->draw_dsc;
        return (d->grad.dir == LV_GRAD_DIR_NONE || d->grad.dir == LV_GRAD_DIR_HOR ||
                d->grad.dir == LV_GRAD_DIR_VER) && triangle(t, d, false);
    }
    case LV_DRAW_TASK_TYPE_MASK_RECTANGLE:
        return t->target_layer->color_format == LV_COLOR_FORMAT_ARGB8888;
    case LV_DRAW_TASK_TYPE_LABEL: {
        const lv_draw_label_dsc_t *d = t->draw_dsc;
        return d->rotation == 0 && d->outline_stroke_opa == 0 && font_supported(d->font);
    }
    case LV_DRAW_TASK_TYPE_LETTER: {
        const lv_draw_letter_dsc_t *d = t->draw_dsc;
        return d->rotation == 0 && d->scale_x == 256 && d->scale_y == 256 &&
               d->skew_x == 0 && d->skew_y == 0 && d->outline_stroke_opa == 0 &&
               d->blend_mode == LV_BLEND_MODE_NORMAL && font_supported(d->font);
    }
    case LV_DRAW_TASK_TYPE_IMAGE:
    case LV_DRAW_TASK_TYPE_LAYER: {
        const lv_draw_image_dsc_t *d = t->draw_dsc;
        lv_color_format_t cf = d->header.cf;
        if (t->type == LV_DRAW_TASK_TYPE_LAYER)
            cf = ((const lv_layer_t *)d->src)->color_format;
        bool a8 = cf == LV_COLOR_FORMAT_A8 && d->scale_x == 256 && d->scale_y == 256 &&
                  d->blend_mode == LV_BLEND_MODE_NORMAL && d->colorkey == NULL;
        if (d->colorkey && (cf != LV_COLOR_FORMAT_RGB565 ||
            !lv_color_eq(d->colorkey->low, d->colorkey->high))) return false;
        if (a8) return d->rotation == 0 && d->skew_x == 0 && d->skew_y == 0 &&
                       d->clip_radius == 0 && d->bitmap_mask_src == NULL;
        return d->bitmap_mask_src == NULL && d->scale_x > 0 && d->scale_y > 0 &&
               image_format(cf) && d->blend_mode <= LV_BLEND_MODE_MULTIPLY;
    }
    case LV_DRAW_TASK_TYPE_BOX_SHADOW: {
        const lv_draw_box_shadow_dsc_t *d = t->draw_dsc;
        return d->width <= 62;
    }
    case LV_DRAW_TASK_TYPE_BLUR: {
        const lv_draw_blur_dsc_t *d = t->draw_dsc;
        return d->blur_radius <= 31 && d->corner_radius == 0;
    }
    default: return false;
    }
}

static int32_t evaluate(lv_draw_unit_t *unit, lv_draw_task_t *t)
{
    (void)unit;
    if (enabled && supported(t)) {
        stats.claimed[t->type]++;
        t->preference_score = 50;
        t->preferred_draw_unit_id = RND_UNIT;
    } else {
        stats.unclaimed[t->type]++;
    }
    return 0;
}

static int32_t dispatch(lv_draw_unit_t *unit, lv_layer_t *layer)
{
    (void)unit;
    lv_draw_task_t *t = lv_draw_get_available_task(layer, NULL, RND_UNIT);
    if (t == NULL) return LV_DRAW_UNIT_IDLE;
    lv_area_t written;
    if (!lv_area_intersect(&written, &t->_real_area, &t->clip_area) ||
        !lv_area_intersect(&written, &written, &layer->buf_area)) {
        t->state = LV_DRAW_TASK_STATE_FINISHED;
        lv_draw_dispatch_request();
        return 1;
    }
    lv_draw_layer_alloc_buf(layer);
    uint32_t first_row = written.y1 - layer->buf_area.y1;
    target = (struct rnd_range) {
        layer->draw_buf->data + first_row * layer->draw_buf->header.stride,
        layer->draw_buf->header.stride * lv_area_get_height(&written)
    };
    sources[0] = target;
    source_count = 1;
    t->state = LV_DRAW_TASK_STATE_IN_PROGRESS;
    switch (t->type) {
    case LV_DRAW_TASK_TYPE_FILL: fill(t, t->draw_dsc, &t->area); break;
    case LV_DRAW_TASK_TYPE_LINE: line(t, t->draw_dsc, true); break;
    case LV_DRAW_TASK_TYPE_ARC: arc(t, t->draw_dsc, true); break;
    case LV_DRAW_TASK_TYPE_TRIANGLE: triangle(t, t->draw_dsc, true); break;
    case LV_DRAW_TASK_TYPE_MASK_RECTANGLE: {
        const lv_draw_mask_rect_dsc_t *d = t->draw_dsc;
        struct rnd_common c = common(t, &t->_real_area, lv_color_black(), 255);
        struct rnd_rect mask = rect(&d->area, t->target_layer);
        c.flags = d->keep_outside ? RND_KEEP_OUTSIDE : 0;
        rnd_mask_rect(next_command(), &c, &mask, radius(d->radius, &d->area));
            break;
    }
    case LV_DRAW_TASK_TYPE_BORDER: {
        const lv_draw_border_dsc_t *d = t->draw_dsc;
        struct rnd_common c = common(t, &t->area, d->color, d->opa);
        uint8_t sides = ((d->side & LV_BORDER_SIDE_TOP) ? 1 : 0) |
                        ((d->side & LV_BORDER_SIDE_BOTTOM) ? 2 : 0) |
                        (d->side & (LV_BORDER_SIDE_LEFT | LV_BORDER_SIDE_RIGHT));
        rnd_border(next_command(), &c, radius(d->radius, &t->area), d->width, sides);
            break;
    }
    case LV_DRAW_TASK_TYPE_LABEL:
        lv_draw_label_iterate_characters(t, t->draw_dsc, &t->area, glyph);
        break;
    case LV_DRAW_TASK_TYPE_LETTER: {
        const lv_draw_letter_dsc_t *d = t->draw_dsc;
        lv_draw_glyph_dsc_t g;
        lv_draw_glyph_dsc_init(&g);
        g.opa = d->opa;
        g.color = d->color;
        g.pivot = d->pivot;
        lv_point_t pos = { t->area.x1, t->area.y1 };
        lv_draw_unit_draw_letter(t, &g, &pos, d->font, d->unicode, glyph);
        if (g._draw_buf) lv_draw_buf_destroy(g._draw_buf);
        break;
    }
    case LV_DRAW_TASK_TYPE_IMAGE:
    case LV_DRAW_TASK_TYPE_LAYER: {
        lv_draw_image_dsc_t d = *(lv_draw_image_dsc_t *)t->draw_dsc;
        if (t->type == LV_DRAW_TASK_TYPE_LAYER) {
            lv_layer_t *source = (lv_layer_t *)d.src;
            if (source->draw_buf == NULL) break;
            d.src = source->draw_buf;
        }
        lv_image_decoder_args_t args = { .premultiply = false, .use_indexed = true };
        if (d.tile) lv_draw_image_tiled_helper(t, &d, &t->area, image_core, &args);
        else lv_draw_image_normal_helper(t, &d, &t->area, image_core, &args);
        break;
    }
    case LV_DRAW_TASK_TYPE_BOX_SHADOW: {
        const lv_draw_box_shadow_dsc_t *d = t->draw_dsc;
        lv_area_t area = t->area;
        lv_area_move(&area, d->ofs_x, d->ofs_y);
        lv_area_increase(&area, d->spread, d->spread);
        struct rnd_common c = common(t, &area, d->color, d->opa);
        if (d->bg_cover) {
            rnd_box_shadow(next_command(), &c, radius(d->radius, &area),
                           d->width / 2, rnd_physical(temporary));
        } else {
            /* LVGL removes the shadow using a background mask inset by one pixel. */
            lv_area_t bg_area = t->area;
            lv_area_increase(&bg_area, -1, -1);
            struct rnd_rect background = rect(&bg_area, t->target_layer);
            rnd_box_shadow_cutout(next_command(), &c, radius(d->radius, &area),
                d->width / 2, rnd_physical(temporary), &background, radius(d->radius, &bg_area));
        }
        lv_area_increase(&area, d->width / 2, d->width / 2);
            break;
    }
    case LV_DRAW_TASK_TYPE_BLUR: {
        const lv_draw_blur_dsc_t *d = t->draw_dsc;
        struct rnd_common c = common(t, &t->area, lv_color_black(), 255);
        rnd_blur(next_command(), &c, d->blur_radius, rnd_physical(temporary));
        break;
    }
    default: break;
    }
    submit();
    stats.executed++;
    t->state = LV_DRAW_TASK_STATE_FINISHED;
    lv_draw_dispatch_request();
    return 1;
}

void showcase_draw_rnd_init(void)
{
    /* Startup zeroed the cached BSS alias; discard it before uncached writes.
     * Afterwards only RND reads descriptors (SoC 7.4).
     */
    cache_clean_invalidate((uintptr_t)command_storage, sizeof(command_storage));
    commands = platform_uncached(command_storage);
    lv_draw_unit_t *unit = lv_draw_create_unit(sizeof(*unit));
    unit->name = "RND";
    unit->evaluate_cb = evaluate;
    unit->dispatch_cb = dispatch;
}

void showcase_draw_rnd_enable(bool value) { enabled = value; }
bool showcase_draw_rnd_enabled(void) { return enabled; }
const struct showcase_draw_rnd_stats *showcase_draw_rnd_stats(void) { return &stats; }
struct rnd_range showcase_draw_rnd_glyph_cache(void)
{
    return (struct rnd_range) { glyph_cache, glyph_cache_bytes };
}

void showcase_draw_rnd_print_stats(void)
{
    for (unsigned i = 1; i < SHOWCASE_RND_TASK_TYPES; ++i) {
        platform_puts("RND type="); platform_put_u32(i);
        platform_puts(" claimed="); platform_put_u32(stats.claimed[i]);
        platform_puts(" unclaimed="); platform_put_u32(stats.unclaimed[i]);
        platform_puts("\r\n");
    }
    platform_puts("RND batch="); platform_put_u32(SHOWCASE_RND_BATCH_COMMANDS);
    platform_puts(" commands="); platform_put_u32(stats.commands);
    platform_puts(" doorbells="); platform_put_u32(stats.doorbells); platform_puts("\r\n");
}

void showcase_draw_rnd_copy(void *dst, const void *src, uint16_t stride, const lv_area_t *area)
{
    struct rnd_command *copy = &commands[SHOWCASE_RND_BATCH_COMMANDS];
    struct rnd_common c = {
        .dst_base = rnd_physical(dst), .dst_stride = stride,
        .dst_fmt = RND_RGB565, .src_fmt = RND_RGB565,
        .clip = { area->x1, area->y1, area->x2, area->y2 },
        .rect = { area->x1, area->y1, area->x2, area->y2 }
    };
    struct rnd_source source = { rnd_physical(src), stride, area->x1, area->y1 };
    rnd_copy(copy, &c, &source);
    /* Range includes whole rows so invalidating a partial cache line never
     * discards CPU pixels beside the copied rectangle. */
    struct rnd_range ranges[2] = {
        { src, (uint32_t)stride * (area->y2 + 1) },
        { dst, (uint32_t)stride * (area->y2 + 1) }
    };
    struct rnd_range copy_target = ranges[1];
    unsigned count = 1;
    merge_source(ranges, &count, copy_target.address, copy_target.bytes);
    struct rnd_batch batch = { copy, 1, ranges, count, &copy_target, 1 };
    run_batch(&batch, true);
}
