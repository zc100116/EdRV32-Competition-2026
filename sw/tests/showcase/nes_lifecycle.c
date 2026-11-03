/* nes_lifecycle.c — P5 3.2; switching away before NES STARTING completes. */
#include "../../apps/showcase/nes/app.c"
#include <assert.h>
#include <stdio.h>
static unsigned stopped, display_stops, overlay_exits;
static bool idle;
void app_gui_pause(uint8_t p) { assert(p); }
void engine_control(enum engine_id engine, uint32_t ctrl)
{ assert(engine==ENGINE_DISP && ctrl==0); }
unsigned platform_input_sequence(void) { return 0; }
uint64_t platform_ticks(void) { return 0; }
void app_wake_at(uint64_t tick) { (void)tick; }
void nes_stop(void) { ++stopped; }
void nes_display_stop(void) { ++display_stops; }
int nes_display_idle(void) { return idle; }
void board_overlay_exit(void) { ++overlay_exits; }
void platform_media_callbacks(rnd_callback rnd, engine_irq_callback disp, void *context)
{ assert(!rnd && !disp && !context); }
int main(void)
{
    enter(); leave();
    assert(!board_nes_ready(UI_STATE_IDLE));
    idle=true; assert(board_nes_ready(UI_STATE_IDLE));
    assert(!stopped && !display_stops && !overlay_exits);
    enter(); state=PLAYING; leave();
    assert(stopped==1 && display_stops==1);
    assert(board_nes_ready(UI_STATE_IDLE) && overlay_exits==1);
    puts("PASS NES STARTING cancellation releases only acquired resources; PLAYING exits overlay");
}
