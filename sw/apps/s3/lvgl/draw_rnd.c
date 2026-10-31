/* File: draw_rnd.c
 * Spec: RND v0.2 2.1–2.6/5.4; design rnd-disp 4.2/4.3.
 * Description: LVGL v9.6 draw-task translation; synchronous shared IRQ completion.
 * Clock domain: clk_sys, descriptor execution in clk_mem.
 */
#include "draw_rnd.h"
#include "rn17_compare.h"
#include "../s3_platform.h"
#include "cache.h"
#include "src/draw/lv_draw_private.h"
#include "src/draw/lv_draw_label_private.h"
#include "src/draw/lv_draw_image_private.h"
#include "src/image/lv_image_decoder_private.h"
#include "src/font/lv_font_private.h"
#include "src/misc/lv_area_private.h"

enum { RND_UNIT = 2, GLYPH_CACHE_BYTES = 1046976, TEMP_BYTES = 6 * 1024 * 1024 };
static _Alignas(64) struct rnd_command command_storage[S3_RND_BATCH_COMMANDS + 1];
static struct rnd_command *commands;
/* lv_conf enables Montserrat 12/14/16/18/20/22/24/26/28/32/40, each 158
 * descriptors (including reserved/empty). Sum align64(align32(box_w)*box_h):
 * 51264+55808+61504+70848+77248+84416+90752+102720+113024+133312+206080
 * = 1046976 B. Per-glyph 64 B alignment keeps a newly written glyph from
 * dirtying an already-clean glyph's cache line. No eviction or staging path.
 */
static _Alignas(64) uint8_t glyph_cache[GLYPH_CACHE_BYTES];
/* Populate font slots on first use, so unused enabled font data can still be
 * removed by the linker. All configured fonts have 158 glyph descriptors.
 */
static const lv_font_t *fonts[11];
static struct glyph_entry {
    uint32_t offset_plus_one;
    uint16_t stride;
} glyph_entries[sizeof(fonts) / sizeof(fonts[0])][158];
static _Alignas(64) uint8_t temporary[TEMP_BYTES];
static struct rnd_range sources[2]; /* Target plus the current image/decoded layer. */
static struct rnd_range target;
static uint16_t command_count;
static unsigned source_count;
static uint32_t glyph_cache_bytes;
static uint64_t glyph_clean_ticks;
static bool enabled = true;
static struct s3_draw_rnd_stats stats;
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
    uint64_t start = s3_ticks();
    int32_t count = sw_dispatch(unit, layer);
    uint64_t elapsed = s3_ticks() - start;
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
    s3_rnd_run(batch);
    struct s3_rnd_timing timing = s3_rnd_last_timing();
    stats.timing.clean_ticks += timing.clean_ticks;
    stats.timing.wait_ticks += timing.wait_ticks;
    stats.timing.finish_ticks += timing.finish_ticks;
    stats.timing.cache_ops += timing.cache_ops;
    rnd_read_perf(perf);
    if (copy) {
        stats.copy.ticks += s3_rnd_elapsed_ticks();
        stats.copy.commands += batch->count;
        stats.copy.doorbells++;
        for (unsigned i = 0; i < 6; ++i) stats.copy.perf[i] += perf[i];
    } else {
        stats.rnd_ticks += s3_rnd_elapsed_ticks();
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
    if (command_count == S3_RND_BATCH_COMMANDS) submit();
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

static void fill(lv_draw_task_t *t, const lv_draw_fill_dsc_t *d, const lv_area_t *a)
{
    struct rnd_common c = common(t, a, d->color, d->opa);
    int32_t steps[4] = {0, 0, 0, 0};
    uint16_t r = radius(d->radius, a);
    s3_compare_shape(t, a, r, -1, 0);
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
    unsigned font = 0;
    while (fonts[font] != NULL && fonts[font] != g->g->resolved_font) ++font;
    if (fonts[font] == NULL) fonts[font] = g->g->resolved_font;
    struct glyph_entry *entry = &glyph_entries[font][g->g->gid.index];
    if (entry->offset_plus_one == 0) {
        /* LVGL's iterator owns the reusable A8 buffer. Convert/copy only once
         * and hand the immutable cache entry to RND (rnd 5.4 / SoC 7.4).
         */
        const lv_draw_buf_t *bitmap = lv_font_get_glyph_bitmap_internal(g->g, g->_draw_buf);
        uint32_t bytes = bitmap->header.stride * bitmap->header.h;
        uint32_t allocated = LV_ROUND_UP(bytes, 64);
        if (glyph_cache_bytes + allocated > sizeof(glyph_cache)) {
            s3_puts("S3 glyph cache full\r\n");
            s3_stop();
        }
        uint8_t *data = glyph_cache + glyph_cache_bytes;
        lv_memcpy(data, bitmap->data, bytes);
        uint64_t clean_start = s3_ticks();
        cache_clean((uintptr_t)data, bytes);
        uint64_t elapsed = s3_ticks() - clean_start;
        glyph_clean_ticks += elapsed;
        stats.timing.clean_ticks += elapsed;
        stats.timing.cache_ops++;
        entry->offset_plus_one = glyph_cache_bytes + 1u;
        entry->stride = bitmap->header.stride;
        glyph_cache_bytes += allocated;
    }
    const uint8_t *data = glyph_cache + entry->offset_plus_one - 1u;
    s3_compare_mask(t, g->letter_coords, data, entry->stride);
    struct rnd_common c = common(t, g->letter_coords, g->color, g->opa);
    c.src_fmt = RND_A8;
    struct rnd_source src = { rnd_physical(data), entry->stride, 0, 0 };
    rnd_glyph(next_command(), &c, &src);
}

static void glyph(lv_draw_task_t *t, lv_draw_glyph_dsc_t *g,
                  lv_draw_fill_dsc_t *f, const lv_area_t *fill_area)
{
    uint64_t start = s3_ticks();
    uint64_t rnd_before = stats.rnd_ticks;
    uint64_t clean_before = glyph_clean_ticks;
    glyph_core(t, g, f, fill_area);
    /* A full batch may submit inside next_command; keep its wait/clean outside
     * the callback's CPU conversion/lookup/command measurement.
     */
    stats.glyph_cpu_ticks += s3_ticks() - start - (stats.rnd_ticks - rnd_before) -
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
        s3_compare_mask(t, coords, image->data, image->header.stride);
        add_source(image->data, image->data_size);
        submit();
        return;
    }
    c.src_fmt = format(image->header.cf);
    c.flags = blend_mode(d->blend_mode);
    lv_area_t dest = *coords;
    if (d->scale_x != LV_SCALE_NONE || d->scale_y != LV_SCALE_NONE) {
        lv_area_t transformed;
        lv_image_buf_get_transformed_area(&transformed, lv_area_get_width(coords),
            lv_area_get_height(coords), 0, d->scale_x, d->scale_y, &d->pivot);
        lv_area_move(&transformed, coords->x1, coords->y1);
        dest = transformed;
        c.rect = rect(&dest, t->target_layer);
    }
    lv_area_t clip;
    lv_area_intersect(&clip, clipped, &t->clip_area);
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
    rnd_blit(next_command(), &c, &blit);
    s3_compare_image(t, image, &dest, d->scale_x, d->scale_y);
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
        return d->rotation == 0 && d->skew_x == 0 && d->skew_y == 0 &&
               d->clip_radius == 0 && d->bitmap_mask_src == NULL &&
               d->scale_x > 0 && d->scale_y > 0 && (image_format(cf) || a8) &&
               (d->scale_x == 256 && d->scale_y == 256 ? true : !d->antialias) &&
               d->blend_mode <= LV_BLEND_MODE_MULTIPLY;
    }
    case LV_DRAW_TASK_TYPE_BOX_SHADOW: {
        const lv_draw_box_shadow_dsc_t *d = t->draw_dsc;
        /* The hardware macro has no inverse rounded-background cutout. */
        return d->width <= 62 && d->bg_cover;
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
    case LV_DRAW_TASK_TYPE_BORDER: {
        const lv_draw_border_dsc_t *d = t->draw_dsc;
        struct rnd_common c = common(t, &t->area, d->color, d->opa);
        uint8_t sides = ((d->side & LV_BORDER_SIDE_TOP) ? 1 : 0) |
                        ((d->side & LV_BORDER_SIDE_BOTTOM) ? 2 : 0) |
                        (d->side & (LV_BORDER_SIDE_LEFT | LV_BORDER_SIDE_RIGHT));
        rnd_border(next_command(), &c, radius(d->radius, &t->area), d->width, sides);
        s3_compare_shape(t, &t->area, d->radius, d->width, sides);
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
        rnd_box_shadow(next_command(), &c, radius(d->radius, &area),
                       d->width / 2, rnd_physical(temporary));
        lv_area_increase(&area, d->width / 2, d->width / 2);
        s3_compare_shadow(t, &area);
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

void s3_draw_rnd_init(void)
{
    /* Startup zeroed the cached BSS alias; discard it before uncached writes.
     * Afterwards only RND reads descriptors (SoC 7.4).
     */
    cache_clean_invalidate((uintptr_t)command_storage, sizeof(command_storage));
    commands = s3_uncached(command_storage);
    /* The hardware-only scratch must not retain dirty startup BSS cache lines. */
    cache_clean_invalidate((uintptr_t)temporary, sizeof(temporary));
    lv_draw_unit_t *unit = lv_draw_create_unit(sizeof(*unit));
    unit->name = "RND";
    unit->evaluate_cb = evaluate;
    unit->dispatch_cb = dispatch;
}

void s3_draw_rnd_enable(bool value) { enabled = value; }
bool s3_draw_rnd_enabled(void) { return enabled; }
const struct s3_draw_rnd_stats *s3_draw_rnd_stats(void) { return &stats; }
struct rnd_range s3_draw_rnd_glyph_cache(void)
{
    return (struct rnd_range) { glyph_cache, glyph_cache_bytes };
}

void s3_draw_rnd_print_stats(void)
{
    for (unsigned i = 1; i < S3_RND_TASK_TYPES; ++i) {
        s3_puts("RND type="); s3_put_u32(i);
        s3_puts(" claimed="); s3_put_u32(stats.claimed[i]);
        s3_puts(" unclaimed="); s3_put_u32(stats.unclaimed[i]);
        s3_puts("\r\n");
    }
    s3_puts("RND batch="); s3_put_u32(S3_RND_BATCH_COMMANDS);
    s3_puts(" commands="); s3_put_u32(stats.commands);
    s3_puts(" doorbells="); s3_put_u32(stats.doorbells); s3_puts("\r\n");
}

void s3_draw_rnd_copy(void *dst, const void *src, uint16_t stride, const lv_area_t *area)
{
    struct rnd_command *copy = &commands[S3_RND_BATCH_COMMANDS];
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
