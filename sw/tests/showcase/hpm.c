/* hpm.c — CPU 7.1 / showcase 4.6.7; two runs preserve event ordering. */
#include "coremark.h"
#include <assert.h>
#include <stdio.h>
int main(void)
{
    uint64_t events[16]={0};
    for(unsigned round=0;round<2;++round) {
        uint64_t counters[8];
        for(unsigned slot=0;slot<8;++slot) {
            assert(ui_hpm_event(round,slot)==round*8+slot+1);
            counters[slot]=(1ull<<35)+ui_hpm_event(round,slot)*101;
        }
        ui_hpm_store(events,round,counters);
    }
    for(unsigned event=0;event<16;++event)
        assert(events[event]==(1ull<<35)+(event+1)*101);
    assert(events[12]==(1ull<<35)+13*101); /* I$ miss */
    assert(events[13]==(1ull<<35)+14*101); /* D$ miss */
    puts("PASS HPM: two rounds, eight slots, all sixteen events, 64-bit counts");
}
