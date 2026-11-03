/* File: draw_rnd.h
 * Spec: RND 2.5/2.6/5.4; design rnd-disp 4.3.
 * Description: Synchronous IRQ-completed LVGL drawing unit and COPY service.
 * Clock domain: clk_sys, hardware execution in clk_mem.
 */
#ifndef SHOWCASE_DRAW_RND_H
#define SHOWCASE_DRAW_RND_H
#include "lvgl.h"
#include <stdbool.h>
#include <stdint.h>
#include "showcase_lvgl.h"
enum { SHOWCASE_RND_BATCH_COMMANDS = 32, SHOWCASE_RND_TASK_TYPES = 16 };
struct showcase_rnd_measurement {
    uint64_t ticks;
    uint64_t perf[6];
    uint32_t commands;
    uint32_t doorbells;
};
struct showcase_draw_rnd_stats {
    uint32_t claimed[SHOWCASE_RND_TASK_TYPES];
    uint32_t unclaimed[SHOWCASE_RND_TASK_TYPES];
    uint32_t executed;
    uint32_t software;
    uint32_t commands;
    uint32_t doorbells;
    uint64_t rnd_ticks;
    uint64_t sw_ticks;
    uint64_t perf[6];
    struct showcase_rnd_measurement copy;
    struct showcase_rnd_timing timing;
    uint64_t glyph_cpu_ticks;
    uint64_t clear_rnd, clear_cpu, clear_cpu_bytes;
};
void showcase_draw_rnd_init(void);
void showcase_draw_rnd_clear(lv_draw_buf_t *buf, const lv_area_t *area, lv_layer_t *layer);
void showcase_draw_rnd_enable(bool enabled);
bool showcase_draw_rnd_enabled(void);
const struct showcase_draw_rnd_stats *showcase_draw_rnd_stats(void);
void showcase_draw_rnd_print_stats(void);
/* Immutable, already-clean DDR source, also exposed to the host pixel model. */
struct rnd_range showcase_draw_rnd_glyph_cache(void);
void showcase_draw_rnd_copy(void *dst, const void *src, uint16_t stride, const lv_area_t *area);
#endif
