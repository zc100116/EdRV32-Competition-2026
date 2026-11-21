/* metrics.h — T-SMOOTH-P0; per-second scheduler and vision timing snapshots.
 * Task context drains counters; IRQ context only counts and accumulates ticks.
 */
#ifndef SHOWCASE_VISION_METRICS_H
#define SHOWCASE_VISION_METRICS_H
#include <stdbool.h>
#include <stdint.h>
struct smooth_irq { unsigned count; uint64_t ticks; };
struct smooth_gui { uint64_t render, rnd, sw, vsync; uint32_t frames, scans; };
void smooth_tasks(uint64_t busy[3], uint64_t maximum[3]);
void smooth_irqs(struct smooth_irq out[7]);
void smooth_gui_take(struct smooth_gui *out);
/* Temporary board evaluation mode; shared by all synchronized pages. */
extern bool showcase_pace_even;
bool vision_result_pending(void);
uint64_t vision_result_taken(void);
void ui_data_exposure_toggle(void);
bool ui_data_exposure_short(void);
#endif
