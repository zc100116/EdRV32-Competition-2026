/* latency.h — showcase 4.6.4; consumed-input to NES-frame latency, clk_sys. */
#ifndef SHOWCASE_LATENCY_H
#define SHOWCASE_LATENCY_H
#include <stdint.h>
struct input_latency { uint64_t total,max; unsigned count; };
static inline void input_latency_add(struct input_latency *s,uint64_t elapsed)
{
    s->total+=elapsed; if(elapsed>s->max) s->max=elapsed; ++s->count;
}
void board_nes_latency(unsigned source,unsigned *maximum_us,unsigned *average_us);
#endif
