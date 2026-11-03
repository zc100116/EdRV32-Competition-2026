/* coremark.h — CPU spec 7.1; shared two-round HPM event mapping.
 * Counter slots 3..10 map to event IDs 1..8, then 9..16; clk_sys.
 */
#ifndef SHOWCASE_COREMARK_H
#define SHOWCASE_COREMARK_H
#include <stdint.h>
static inline unsigned ui_hpm_event(unsigned round, unsigned slot)
{ return round * 8 + slot + 1; }
static inline void ui_hpm_store(uint64_t events[16], unsigned round,
                                const uint64_t counters[8])
{
    for(unsigned slot=0;slot<8;++slot) events[ui_hpm_event(round,slot)-1]=counters[slot];
}
extern const char *const ui_hpm_names[16];

#endif
