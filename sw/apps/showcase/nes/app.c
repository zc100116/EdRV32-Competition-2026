/* app.c — showcase 4.5.2/4.5.5; selected EDG2 ROM, one frame per step.
 * Display handoff is asynchronous; return requires two pressed edges, clk_sys. */
#include "../app.h"
#include "../platform.h"
#include "../board/games.h"
#include "display.h"
#include "../board/overlay.h"
#include "../board/latency.h"
static const char *rom_data;
static uint64_t next_frame;
static unsigned cadence;
static struct input_latency latency[3];
static unsigned input_sequence;
void board_nes_latency(unsigned source,unsigned *maximum_us,unsigned *average_us)
{
    const struct input_latency *s=&latency[source];
    *maximum_us=(unsigned)(s->max*1000000/platform_clock_hz());
    *average_us=s->count ? (unsigned)(s->total*1000000/platform_clock_hz()/s->count) : 0;
}

static enum { STARTING, PLAYING, STOPPING } state;
void board_nes_select(unsigned i) { rom_data=(const char *)board_game(i)->rom; }
char *osd_getromdata(void) { return (char *)rom_data; }
uint64_t nes_ticks(void) { return platform_ticks(); }
uint64_t nes_tick_hz(void) { return platform_clock_hz(); }
uint64_t nes_instructions(void) { return 0; }
unsigned nes_buttons(void)
{
    unsigned b=0; uint32_t k=platform_keys();
    unsigned sequence=platform_input_sequence();
    if(sequence!=input_sequence) {
        input_sequence=sequence;
        input_latency_add(&latency[platform_input_source()],platform_ticks()-platform_input_tick());
    }
    if(k&PLATFORM_LEFT) b|=1u<<6;
    if(k&PLATFORM_RIGHT) b|=1u<<7;
    if(k&PLATFORM_ENTER) b|=1u;
    return nes_merge_virtual(b,platform_virtual_input().keys);
}
void nes_frame(const uint8_t *pixels,const struct nes_rgb *palette,unsigned frame)
{ (void)frame; nes_display_frame(pixels,palette); }
static void enter(void)
{
    app_gui_pause(1); engine_control(ENGINE_DISP,0);
    input_sequence=platform_input_sequence();
    for(unsigned i=0;i<3;++i) latency[i]=(struct input_latency){0};
    state=STARTING; cadence=0; app_wake_at(platform_ticks());
}
static void step(void)
{
    uint64_t now=platform_ticks();
    if(state==STARTING) {
        if(!platform_display_idle()) { app_wake_at(now+platform_clock_hz()/1000); return; }
        platform_media_callbacks(nes_display_rnd_irq,nes_display_disp_irq,0);
        nes_display_init(); board_overlay_enter(); nes_start(); next_frame=now; state=PLAYING;
    }
    if(state==PLAYING) {
        nes_display_check();
        board_overlay_step();
        if((app_events()&PLATFORM_INPUT) && (platform_pressed()&PLATFORM_BACK)) {
            nes_display_stop(); nes_stop(); state=STOPPING;
        }
        if(state==PLAYING) {
            if(now>=next_frame) {
                nes_step(); uint32_t hz=platform_clock_hz(); cadence+=hz%60;
                next_frame+=hz/60+cadence/60; cadence%=60;
                now=platform_ticks(); if(next_frame<now) next_frame=now;
            }
            app_wake_at(next_frame); return;
        }
    }
    if(nes_display_idle()) { platform_media_callbacks(0,0,0); app_return(); }
    else app_wake_at(now+platform_clock_hz()/1000);
}
static void leave(void) { board_overlay_exit(); platform_media_callbacks(0,0,0); }
const struct app nes_app={"NES",0,APP_HW_RND,1,enter,step,leave};
