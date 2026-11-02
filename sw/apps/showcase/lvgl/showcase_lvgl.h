/* File: showcase_lvgl.h
 * Design: showcase 4.3; SoC 7.4.
 * Description: DIRECT GUI service, benchmark split counters and synchronous RND timing.
 * Clock domain: clk_sys.
 */
#ifndef SHOWCASE_LVGL_H
#define SHOWCASE_LVGL_H
#include "lvgl.h"
#include "platform.h"
struct showcase_rnd_timing {
    uint64_t clean_ticks;
    uint64_t wait_ticks;
    uint64_t finish_ticks;
    uint32_t cache_ops;
};
struct showcase_cpu_counters {
    uint64_t cycles;
    uint64_t instructions;
    uint64_t events[8];
};
void showcase_cpu_begin(void);
void showcase_cpu_end(struct showcase_cpu_counters *counters);
void showcase_rnd_run(const struct rnd_batch *batch);
uint64_t showcase_rnd_elapsed_ticks(void);
struct showcase_rnd_timing showcase_rnd_last_timing(void);
void showcase_lvgl_init(void);
void showcase_lvgl_input(uint32_t keys);
void showcase_lvgl_start_widgets(void);
void showcase_lvgl_start_benchmark(void);
void showcase_lvgl_stop_demo(void);
lv_display_t *showcase_lvgl_display(void);
#endif
