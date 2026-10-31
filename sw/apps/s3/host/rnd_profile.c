/* File: rnd_profile.c
 * Task T-RND2D: host-only observations of the unchanged supported() predicate.
 * Both implementation files are included to observe their private scene/state;
 * this translation unit replaces them only in the profiling shared library.
 * Clock domain: deterministic host milliseconds.
 */
#define s3_draw_rnd_init original_rnd_init
#include "../lvgl/draw_rnd.c"
#undef s3_draw_rnd_init
void s3_draw_rnd_init(void);
#include "../lvgl/s3_lvgl.c"
#include <stdio.h>

enum {
    GEOMETRY = 1, MASK_RECT = 2, CUTOUT = 4, ROTATION = 8, SKEW = 16,
    CLIP_RADIUS = 32, SCALE_AA = 64, BITMAP_MASK = 128, OTHER = 256
};
static uint64_t counts[16][14][512];
static uint64_t pixels[16][14][512];

static unsigned reasons(lv_draw_task_t *t)
{
    if (t->target_layer->color_format != LV_COLOR_FORMAT_RGB565 &&
        t->target_layer->color_format != LV_COLOR_FORMAT_ARGB8888) return OTHER;
    switch (t->type) {
    case LV_DRAW_TASK_TYPE_LINE: {
        const lv_draw_line_dsc_t *d = t->draw_dsc;
        return GEOMETRY | (d->dash_width || d->dash_gap || d->points ? OTHER : 0);
    }
    case LV_DRAW_TASK_TYPE_ARC: {
        const lv_draw_arc_dsc_t *d = t->draw_dsc;
        return GEOMETRY | (d->img_src ? OTHER : 0);
    }
    case LV_DRAW_TASK_TYPE_TRIANGLE: {
        const lv_draw_triangle_dsc_t *d = t->draw_dsc;
        return GEOMETRY | (d->grad.dir != LV_GRAD_DIR_NONE &&
            d->grad.dir != LV_GRAD_DIR_HOR && d->grad.dir != LV_GRAD_DIR_VER ? OTHER : 0);
    }
    case LV_DRAW_TASK_TYPE_MASK_RECTANGLE: return MASK_RECT;
    case LV_DRAW_TASK_TYPE_MASK_BITMAP: return BITMAP_MASK;
    case LV_DRAW_TASK_TYPE_IMAGE:
    case LV_DRAW_TASK_TYPE_LAYER: {
        const lv_draw_image_dsc_t *d = t->draw_dsc;
        lv_color_format_t cf = t->type == LV_DRAW_TASK_TYPE_LAYER ?
            ((const lv_layer_t *)d->src)->color_format : d->header.cf;
        unsigned r = 0;
        if (d->rotation) r |= ROTATION;
        if (d->skew_x || d->skew_y) r |= SKEW;
        if (d->clip_radius) r |= CLIP_RADIUS;
        if (d->antialias && (d->scale_x != 256 || d->scale_y != 256 ||
            d->rotation || d->skew_x || d->skew_y)) r |= SCALE_AA;
        if (d->bitmap_mask_src) r |= BITMAP_MASK;
        bool a8 = cf == LV_COLOR_FORMAT_A8 && d->scale_x == 256 && d->scale_y == 256 &&
                  d->blend_mode == LV_BLEND_MODE_NORMAL && d->colorkey == NULL;
        if ((!image_format(cf) && !a8) || d->scale_x <= 0 || d->scale_y <= 0 ||
            d->blend_mode > LV_BLEND_MODE_MULTIPLY ||
            (d->colorkey && (cf != LV_COLOR_FORMAT_RGB565 ||
             !lv_color_eq(d->colorkey->low, d->colorkey->high)))) r |= OTHER;
        return r;
    }
    case LV_DRAW_TASK_TYPE_BOX_SHADOW: {
        const lv_draw_box_shadow_dsc_t *d = t->draw_dsc;
        return (d->bg_cover ? 0 : CUTOUT) | (d->width > 62 ? OTHER : 0);
    }
    default: return OTHER;
    }
}

static int32_t profile_evaluate(lv_draw_unit_t *unit, lv_draw_task_t *t)
{
    (void)unit;
    if (benchmark_running && benchmark_scene < 16) {
        unsigned r = supported(t) ? 0 : reasons(t);
        lv_area_t a;
        uint64_t n = lv_area_intersect(&a, &t->_real_area, &t->clip_area) ?
            (uint64_t)lv_area_get_width(&a) * lv_area_get_height(&a) : 0;
        counts[benchmark_scene][t->type][r]++;
        pixels[benchmark_scene][t->type][r] += n;
    }
    /* Leave SW's preference intact: all tasks are rasterized by native LVGL.
     * The baseline predicate above still decides which tasks count as fallback.
     */
    return 0;
}

void s3_draw_rnd_init(void)
{
    lv_draw_unit_t *unit = lv_draw_create_unit(sizeof(*unit));
    unit->name = "RND profile";
    unit->evaluate_cb = profile_evaluate;
    unit->dispatch_cb = dispatch;
}

void s3_profile_dump(void)
{
    static const char *const names[] = {
        "NONE", "FILL", "BORDER", "BOX_SHADOW", "LETTER", "LABEL", "IMAGE", "LAYER",
        "LINE", "ARC", "TRIANGLE", "MASK_RECT", "MASK_BITMAP", "BLUR"
    };
    printf("PROFILE_LAST_FRAMES,%u,%u\n", benchmark_scene, benchmark_window.frames);
    for (unsigned s = 0; s < 16; ++s)
        for (unsigned t = 1; t < 14; ++t)
            for (unsigned r = 0; r < 512; ++r)
                if (counts[s][t][r])
                    printf("PROFILE,%u,%s,%s,%u,%llu,%llu\n", s, benchmark_names[s],
                           names[t], r, (unsigned long long)counts[s][t][r],
                           (unsigned long long)pixels[s][t][r]);
}

void s3_profile_native_sync(void)
{
    lv_display_set_sync_cb(display, NULL);
}
