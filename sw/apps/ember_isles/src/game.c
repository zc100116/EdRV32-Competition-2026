/* File: game.c
 * Spec: ember_isles tech 2-3 and E1/E2 scope.
 * Description: Fixed-step simulation, read-only presentation and audio submission.
 * Clock domain: 60 Hz game frame; 48 kHz audio ring.
 */
#include "game.h"
#include "gfx2d/gfx.h"
#include "audio/audio.h"
#include "ui/ui.h"
#include "plat.h"
#include "aud.h"
#include <stdlib.h>
static struct ember_sim simulation;
static struct aud_ring audio_ring;
static uint32_t samples[1024];
static uint32_t previous_millis;
static unsigned fps_frames, measured_fps = 60;
static struct ember_ui_state ui;
static uint8_t previous_keys;
static unsigned replay_mode;
static uint32_t run_number;
static struct ember_replay recording;
static void refill(void)
{
    unsigned count = aud_space(&audio_ring) / 4u;
    if (count > 1024) count = 1024;
    count &= ~7u;
    ember_audio_mix(samples, count);
    aud_write(&audio_ring, samples, count);
}
void ember_game_init(void)
{
    plat_init();
    ember_sim_init(&simulation, 20261124u);
    ember_audio_reset();
    ember_gfx_init();
    aud_init(&audio_ring, plat_dma_alloc(16384, 512), 16384, 4096);
    refill();
    refill();
    aud_enable(1);
    previous_millis = plat_millis();
}
void ember_game_replay(uint32_t seed)
{
    replay_mode = 1;
    ember_sim_init(&simulation, seed);
}
const struct ember_replay *ember_game_recording(void) { return &recording; }
const struct ember_sim *ember_game_state(void) { return &simulation; }
void ember_game_frame(unsigned frame)
{
    uint8_t keys = (uint8_t)plat_keys();
    uint8_t pressed = keys & (uint8_t)~previous_keys;
    previous_keys = keys;
    if (pressed & EMBER_SELECT) ui.show_perf ^= 1;
    unsigned returned_to_menu = 0;
    if (!replay_mode && (pressed & EMBER_START)) {
        if (simulation.phase == EMBER_WON || simulation.phase == EMBER_LOST) {
            ember_sim_init(&simulation, recording.seed);
            simulation.previous_input = keys;
            returned_to_menu = 1;
        } else if (simulation.phase == EMBER_MENU) {
            recording.seed = 20261124u + ++run_number + plat_millis();
            recording.count = 0;
            ember_sim_init(&simulation, recording.seed);
            ember_audio_reset();
        }
    }
    if (!replay_mode && !returned_to_menu && simulation.phase != EMBER_WON &&
        simulation.phase != EMBER_LOST &&
        (simulation.phase != EMBER_MENU || (pressed & EMBER_START))) {
        if (recording.count == EMBER_REPLAY_FRAMES) {
            plat_printf("Replay recording capacity exhausted\n");
            abort();
        }
        recording.input[recording.count++] = keys;
    }
    ember_sim_step(&simulation, keys);
    for (unsigned i = 0; i < simulation.events.count; ++i) {
        unsigned kind = simulation.events.item[i].kind;
        if (kind < 10) ember_audio_event(kind);
    }
    uint32_t now = plat_millis();
    ++fps_frames;
    if (now - previous_millis >= 1000) {
        measured_fps = fps_frames * 1000u / (now - previous_millis);
        previous_millis = now;
        fps_frames = 0;
    }
    ember_gfx_prepare(&simulation, measured_fps, &ui);
    ember_gfx_submit(frame);
    refill();
    struct aud_event audio = aud_status();
    if (audio.error) { plat_printf("AUD error %u\n", (unsigned)audio.error); abort(); }
}
