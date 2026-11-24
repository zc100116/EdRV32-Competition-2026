/* File: game_flow_test.c
 * Spec: E1/E2 basic menus, per-run seeds and presentation-only SELECT state.
 * Description: Check game-loop transitions using real simulation and media stubs.
 * Clock domain: deterministic host test frames.
 */
#include "game.h"
#include "ui/ui.h"
#include "aud.h"
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned keys, millis, show_perf;
void plat_init(void) {}
uint32_t plat_keys(void) { return keys; }
uint32_t plat_millis(void) { return millis; }
void *plat_dma_alloc(size_t bytes, size_t alignment)
{
    (void)alignment;
    return malloc(bytes);
}
int plat_printf(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    int count = vprintf(format, args);
    va_end(args);
    return count;
}
void ember_gfx_init(void) {}
void ember_gfx_prepare(const struct ember_sim *sim, unsigned fps,
                       const struct ember_ui_state *ui)
{
    (void)sim; (void)fps;
    show_perf = ui->show_perf;
}
void ember_gfx_submit(unsigned frame) { (void)frame; }
void ember_audio_reset(void) {}
void ember_audio_event(unsigned event) { (void)event; }
void ember_audio_mix(uint32_t *samples, unsigned frames) { (void)samples; (void)frames; }
void aud_init(struct aud_ring *ring, uint32_t *samples, uint32_t bytes, uint32_t level)
{
    (void)ring; (void)samples; (void)bytes; (void)level;
}
uint32_t aud_space(const struct aud_ring *ring) { (void)ring; return 0; }
void aud_write(struct aud_ring *ring, const uint32_t *samples, uint32_t frames)
{
    (void)ring; (void)samples; (void)frames;
}
void aud_enable(unsigned enable) { (void)enable; }
struct aud_event aud_status(void) { return (struct aud_event){0}; }
static void step(unsigned input)
{
    keys = input;
    millis += 17;
    ember_game_frame(millis);
}
int main(void)
{
    ember_game_init();
    assert(ember_game_state()->phase == EMBER_MENU);
    step(EMBER_START);
    assert(ember_game_state()->phase == EMBER_PLAY);
    uint32_t seed = ember_game_state()->rng_seed;
    assert(ember_game_recording()->seed == seed && ember_game_recording()->count == 1);
    step(0);
    step(EMBER_SELECT);
    assert(show_perf);
    step(EMBER_SELECT);
    assert(show_perf);
    step(0);
    step(EMBER_SELECT);
    assert(!show_perf);
    step(0);
    step(EMBER_START);
    assert(ember_game_state()->paused);
    step(0);
    step(EMBER_START);
    assert(!ember_game_state()->paused);
    struct ember_sim *fixture = (struct ember_sim *)(uintptr_t)ember_game_state();
    fixture->phase = EMBER_WON;
    step(0);
    unsigned count = ember_game_recording()->count;
    step(EMBER_START);
    assert(ember_game_state()->phase == EMBER_MENU);
    assert(ember_game_recording()->count == count);
    step(0);
    step(EMBER_START);
    assert(ember_game_state()->phase == EMBER_PLAY && ember_game_state()->rng_seed != seed);
    assert(ember_game_recording()->count == 1);
    ember_game_replay(7);
    step(0);
    step(EMBER_START);
    assert(ember_game_state()->rng_seed == 7);
    fixture->phase = EMBER_WON;
    step(0);
    step(EMBER_START);
    assert(ember_game_state()->phase == EMBER_WON);
    puts("PASS game flow: title, run seed/recording, SELECT edge, pause, return, replay end");
    return 0;
}
