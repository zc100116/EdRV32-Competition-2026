/* File: overlay_cpu.c
 * Spec: Task B3-11; rnd 2.1/2.6 BORDER/FILL/GLYPH; SoC 7.4.
 * Description: CPU equivalents of the demo's square border, solid label and A1 glyph.
 * Clock domain: clk_sys; caller exclusively owns the cached ARGB8888 Surface.
 */
#include "overlay.h"
#include "cache.h"
#include "font8x16.h"

/* Match RND's Surface CLIP, including labels extending past the right edge. */
static struct demo_rect clip(struct demo_rect r)
{
    if (r.x0 < 0) {
        r.x0 = 0;
    }
    if (r.y0 < 0) {
        r.y0 = 0;
    }
    if (r.x1 >= (int)DEMO_WIDTH) {
        r.x1 = DEMO_WIDTH - 1;
    }
    if (r.y1 >= (int)DEMO_HEIGHT) {
        r.y1 = DEMO_HEIGHT - 1;
    }
    return r;
}

static void fill(uint32_t *pixels, struct demo_rect r, uint32_t color)
{
    r = clip(r);
    for (int y = r.y0; y <= r.y1; ++y) {
        for (int x = r.x0; x <= r.x1; ++x) {
            pixels[(unsigned int)y * DEMO_WIDTH + (unsigned int)x] = color;
        }
    }
}

static void clean(uint32_t *pixels, struct demo_rect r)
{
    r = clip(r);
    /* rnd 2.5: an empty RECT intersection performs no target access. */
    if (r.x1 < r.x0 || r.y1 < r.y0) {
        return;
    }
    /* One range includes row gaps; all included pixels belong to this CPU slot. */
    uint32_t first = (uint32_t)r.y0 * DEMO_WIDTH + (uint32_t)r.x0;
    uint32_t last = (uint32_t)r.y1 * DEMO_WIDTH + (uint32_t)r.x1;
    cache_clean((uintptr_t)&pixels[first], (last - first + 1u) * sizeof *pixels);
}

static void border(uint32_t *pixels, struct demo_rect r)
{
    /* rnd 2.5 empty RECT; 2.6 BORDER radius=0, width=1, sides=15. */
    if (r.x1 < r.x0 || r.y1 < r.y0) {
        return;
    }
    fill(pixels, (struct demo_rect){r.x0, r.y0, r.x1, r.y0}, 0xff00ff00u);
    fill(pixels, (struct demo_rect){r.x0, r.y1, r.x1, r.y1}, 0xff00ff00u);
    fill(pixels, (struct demo_rect){r.x0, r.y0, r.x0, r.y1}, 0xff00ff00u);
    fill(pixels, (struct demo_rect){r.x1, r.y0, r.x1, r.y1}, 0xff00ff00u);
}

void demo_overlay_cpu_draw(uint32_t *pixels, struct demo_dirty *dirty,
                          const yolo_detection *detections, unsigned int count)
{
    for (unsigned int i = 0; i < dirty->count; ++i) {
        fill(pixels, dirty->rect[i], 0);
        clean(pixels, dirty->rect[i]);
    }
    dirty->count = 0;
    for (unsigned int i = 0; i < count; ++i) {
        const yolo_detection *d = &detections[i];
        char label[32];
        unsigned int length = demo_overlay_label(label, d);
        int16_t y = d->y0 >= 16 ? (int16_t)(d->y0 - 16) : d->y0;
        struct demo_rect box = {d->x0, d->y0, (int16_t)(d->x1 - 1),
                                (int16_t)(d->y1 - 1)};
        struct demo_rect bar = {d->x0, y, (int16_t)(d->x0 + length * 8u - 1u),
                                (int16_t)(y + 15)};
        border(pixels, box);
        fill(pixels, bar, 0xff00ff00u);
        dirty->rect[dirty->count++] = box;
        dirty->rect[dirty->count++] = bar;
        for (unsigned int j = 0; j < length; ++j) {
            const uint8_t *glyph = font8x16[(uint8_t)label[j] - 32u];
            for (unsigned int row = 0; row < 16u && y + row < DEMO_HEIGHT; ++row) {
                for (unsigned int bit = 0; bit < 8u; ++bit) {
                    unsigned int x = (unsigned int)d->x0 + j * 8u + bit;
                    if (x < DEMO_WIDTH && (glyph[row] & (0x80u >> bit))) {
                        pixels[(y + row) * DEMO_WIDTH + x] = 0xffffffffu;
                    }
                }
            }
        }
    }
    /* Flush after all glyph writes, before this slot can be published to DISP. */
    for (unsigned int i = 0; i < dirty->count; ++i) {
        clean(pixels, dirty->rect[i]);
    }
}
