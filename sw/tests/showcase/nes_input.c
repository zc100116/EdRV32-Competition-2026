/* nes_input.c — showcase 4.6.4; input precedes every emulated frame. */
#include "nes_port.h"
#include <assert.h>
#include <stdio.h>
static unsigned samples,frames;
unsigned nes_buttons(void) { assert(samples==frames); return ++samples; }
void osd_getinput(void);
void nes_emulate_frame(void)
{
    assert(samples==frames+1);
    osd_getinput();
    assert(samples==frames+1); /* End-of-frame callback must not resample. */
    ++frames;
}
int main(void)
{
    nes_step(); nes_step(); nes_step();
    assert(samples==3 && frames==3 && nes_frames==3);
    puts("PASS NES input: latest buttons latched before each simulated frame");
}
