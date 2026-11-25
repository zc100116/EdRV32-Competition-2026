/* ember_pacing_test.c — P-1: wall-clock 60 Hz ticks and measured render/tick rates.
 * Runs the real simulation/game with a synthetic host clock and captured HUD.
 * Clock domain: deterministic milliseconds; no window or audio device.
 */
#include "game.h"
#include "gfx2d/gfx.h"
#include "ui/ui.h"
#include "pc_soc.h"
#include "plat.h"
#include <assert.h>
#include <stdio.h>
static uint32_t millis;
static unsigned renders, fps, tick_rate;
uint32_t pc_frontend_millis(void) { return millis; }
uint32_t pc_frontend_keys(void) { return millis == 0 ? PLAT_START : 0; }
uint32_t pc_frontend_wait(void) { return 800; }
void pc_frontend_audio(const int16_t *samples, uint32_t frames)
{
    (void)samples;
    (void)frames;
}
void __wrap_ember_gfx_prepare(const struct ember_sim *sim, unsigned rate,
                              const struct ember_ui_state *ui)
{
    (void)sim;
    fps = rate;
    tick_rate = ui->tick_rate;
    ++renders;
}
void __wrap_ember_gfx_submit(unsigned frame) { (void)frame; }
int main(void)
{
    ember_game_init();
    static struct ember_replay replay = {.seed = 20261124u};
    ember_run_config_default(&replay.config);
    ember_game_replay(&replay);
    for (millis = 0; millis <= 1023; millis += 33) {
        pc_soc_game_input(millis == 0 ? PLAT_KEY_ENTER : 0, (struct plat_pointer_state){0});
        ember_game_realtime(renders + 1);
    }
    assert(renders == 32);
    assert(ember_game_state()->frame == 62);
    assert(fps == 31 && tick_rate == 60);
    millis = 1223;
    ember_game_realtime(renders + 1);
    assert(ember_game_state()->frame == 66); /* Four ticks; eight discarded. */
    millis = 1240;
    ember_game_realtime(renders + 1);
    assert(ember_game_state()->frame == 67); /* No retained overload debt. */
    millis = 2240;
    ember_game_realtime(renders + 1);
    assert(fps == 2 && tick_rate == 7); /* Both overload rates are visible. */
    pc_soc_destroy();
    puts("PASS 30 Hz render/60 Hz tick, four-tick cap, dropped debt, FPS/tick HUD");
    return 0;
}
