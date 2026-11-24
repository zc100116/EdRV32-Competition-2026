/* File: game_flow_test.c
 * Spec: E1/E2 basic menus, per-run seeds and presentation-only SELECT state.
 * Description: Check game-loop transitions using real simulation and media stubs.
 * Clock domain: deterministic host test frames.
 */
#include "game.h"
#include "ui/ui.h"
#include "audio/audio.h"
#include "aud.h"
#include "plat.h"
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned keys, millis, show_perf;
static struct plat_pointer_state pointer;
void plat_init(void) {}
uint32_t plat_game_keys(void) { return keys; }
struct plat_pointer_state plat_pointer(void) { return pointer; }
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
void ember_audio_result(unsigned kind, unsigned damage_type, unsigned outcome)
{
    (void)kind; (void)damage_type; (void)outcome;
}
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
void plat_irq_register(unsigned source, plat_irq_handler handler, void *context)
{
    (void)source; (void)handler; (void)context;
}
void aud_irq_register(unsigned priority, aud_refill refill, void *context)
{
    (void)priority; (void)refill; (void)context;
}
struct aud_event aud_irq_handle(struct aud_ring *ring)
{
    (void)ring;
    return (struct aud_event){0};
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
    pointer = (struct plat_pointer_state){320, 250, 1};
    step(0);
    assert(ember_game_state()->phase == EMBER_PLAY);
    uint32_t seed = ember_game_state()->rng_seed;
    assert(ember_game_recording()->seed == seed && ember_game_recording()->count == 1);
    pointer.buttons = 0;
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
    fixture->phase = EMBER_UPGRADE;
    fixture->selected = 0;
    fixture->choices[2] = (struct ember_choice){0, 0, 0};
    pointer = (struct plat_pointer_state){450, 150, 1};
    step(0);
    assert(fixture->phase == EMBER_UPGRADE && fixture->selected == 2);
    pointer.buttons = 0;
    step(0);
    assert(fixture->phase == EMBER_PLAY);
    unsigned recorded = ember_game_recording()->count;
    assert(ember_game_recording()->input[recorded - 2] == EMBER_LEFT);
    assert(ember_game_recording()->input[recorded - 1] == EMBER_J);
    pointer = (struct plat_pointer_state){450, 150, 1};
    step(0);
    assert(fixture->phase == EMBER_PLAY);
    assert(ember_game_recording()->input[recorded] == 0);
    pointer.buttons = 0;
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
    fixture->phase = EMBER_PLAY;
    fixture->paused = 0;
    fixture->rest = 10000;
    step(0);
    unsigned main = fixture->player.main_weapon;
    step(EMBER_SWAP);
    assert(fixture->player.sub_weapon == main);
    assert(ember_game_recording()->input[0] == EMBER_START);
    puts("PASS game flow: title, run seed/recording, SELECT edge, pause, return, replay end");
    return 0;
}
