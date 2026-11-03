/* overlay.c — showcase 4.6.5 / DISP 5.3; NES owns RND, overlay uses software.
 * Double buffers release at SWITCH1; only the small L1 rectangle is scanned.
 */
#include "overlay.h"
#include "../ui/theme.h"
#include "../platform.h"
#include "../lvgl/showcase_lvgl.h"
#include "../lvgl/draw_rnd.h"
#include "cache.h"
#include <string.h>
_Alignas(4096) static uint32_t buffers[2][320*240];
static lv_display_t *display,*main_display;
static volatile bool pending,ready,scanning;
static uint64_t next_refresh,busy_ticks;
static uint64_t max_ticks;
static const void *front;
uint64_t board_overlay_ticks(void) { return busy_ticks; }
unsigned board_overlay_max_us(void)
{ return (unsigned)(max_ticks*1000000/platform_clock_hz()); }
static void window(const void *base)
{
    int x,y; ui_monitor_position(&x,&y);
    showcase_display_l1_window(x,y,320,240,base,1280);
}
static void flush(lv_display_t *d,const lv_area_t *a,uint8_t *pixels)
{
    (void)a;
    if(!lv_display_flush_is_last(d)) { lv_display_flush_ready(d); return; }
    cache_clean((uintptr_t)pixels,sizeof(buffers[0]));
    front=pixels; pending=true; ready=false; window(pixels);
}
void board_overlay_irq(uint32_t irq)
{
    if(!display) return;
    if((irq&EDRV32_DISP_IRQ_STAT_SWITCH1_MASK) ||
       (!scanning && (irq&EDRV32_DISP_IRQ_STAT_FRAME_MASK))) ready=true;
    if(irq&EDRV32_DISP_IRQ_STAT_FRAME_MASK) scanning=true;
}
void board_overlay_enter(void)
{
    main_display=lv_display_get_default();
    display=lv_display_create(320,240);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,buffers[0],buffers[1],sizeof(buffers[0]),
        LV_DISPLAY_RENDER_MODE_DIRECT);
    lv_display_set_flush_cb(display,flush);
    lv_timer_pause(lv_display_get_refr_timer(display));
    lv_obj_t *screen=lv_display_get_screen_active(display);
    lv_obj_remove_style_all(screen);
    lv_obj_set_style_bg_opa(screen,LV_OPA_TRANSP,0);
    lv_display_set_default(display);
    ui_monitor_parent(screen,true);
    lv_display_set_default(main_display);
    memset(buffers,0,sizeof(buffers));
    cache_clean((uintptr_t)buffers,sizeof(buffers));
    front=buffers[1]; pending=ready=scanning=false;
    window(front); disp_layer_enable(DISP_L1,ui_monitor_visible());
    next_refresh=0;
}
void board_overlay_step(void)
{
    if(!display) return;
    if(pending && ready) {
        pending=false; ready=false; lv_display_flush_ready(display);
    }
    static uint8_t mouse;
    struct virtual_input_state input=platform_virtual_input();
    if((input.mouse&1) && !(mouse&1) && ui_monitor_visible()) {
        int x,y; ui_monitor_position(&x,&y);
        if(input.y>=y && input.y<y+24) {
            if(input.x>=x+224 && input.x<x+268) ui_monitor_corner();
            if(input.x>=x+276 && input.x<x+320) ui_monitor_toggle();
        }
    }
    mouse=input.mouse;
    uint64_t now=platform_ticks();
    if(now<next_refresh || pending) return;
    next_refresh=now+platform_clock_hz()/2;
    uint64_t start=platform_ticks();
    ui_monitor_update();
    if(!ui_monitor_visible()) { disp_layer_enable(DISP_L1,0); scanning=false; return; }
    /* No RND submission can overlap this cooperative software-only refresh. */
    bool accelerated=showcase_draw_rnd_enabled();
    showcase_draw_rnd_enable(false);
    lv_display_set_default(display);
    lv_refr_now(display);
    lv_display_set_default(main_display);
    showcase_draw_rnd_enable(accelerated);
    window(front); disp_layer_enable(DISP_L1,1);
    uint64_t elapsed=platform_ticks()-start;
    busy_ticks+=elapsed; if(elapsed>max_ticks) max_ticks=elapsed;
}
void board_overlay_exit(void)
{
    lv_display_set_default(main_display);
    ui_monitor_parent(lv_display_get_layer_sys(main_display),false);
    lv_display_delete(display); display=NULL;
}
