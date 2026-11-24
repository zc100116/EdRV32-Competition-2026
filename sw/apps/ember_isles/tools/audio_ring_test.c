/* File: audio_ring_test.c
 * Spec: ember_isles tech 1-2; aud-spec 2; PC design 4.3.
 * Description: Exercise the real game refill IRQ across long frontend intervals.
 * Clock domain: virtual 48 kHz playback, 60 Hz game input.
 */
#include "game.h"
#include "plat.h"
#include "aud.h"
#include "pc_soc.h"
#include <assert.h>
#include <stdio.h>
static unsigned frame, consumed, nonzero;
uint32_t pc_frontend_keys(void) { return frame == 1 ? PLAT_START : 0; }
uint32_t pc_frontend_millis(void) { return frame * 1000u / 60u; }
uint32_t pc_frontend_wait(void) { return 9600; }
void pc_frontend_audio(const int16_t *samples, uint32_t frames)
{
    consumed += frames;
    for (unsigned i = 0; i < frames * 2; ++i) nonzero += samples[i] != 0;
}
int main(void)
{
    ember_game_init();
    for (frame = 1; frame <= 3; ++frame) {
        ember_game_frame(frame);
        plat_wait_vsync();
    }
    assert(consumed == 28800);
    assert(nonzero > 0);
    assert(aud_underruns() == 0);
    puts("PASS audio ring: three 200 ms frontend intervals, 28800 frames, zero underruns");
    pc_soc_destroy();
    return 0;
}
