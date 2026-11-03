/* vision_refresh.c — P5 replan 11.1; host DIRECT refresh area and CPU measurement.
 * Reuses simulator fixtures; excludes the presentation copy from render time. */
#define main shots_main
#include "../../apps/showcase/sim/main_shots.c"
#undef main
#include <string.h>
#include "src/draw/lv_draw_private.h"
static uint64_t area_px, sw_ns;
static lv_draw_unit_t *software_unit;
static int32_t (*dispatch_sw)(lv_draw_unit_t *, lv_layer_t *);
void *__real_lv_draw_create_unit(size_t size);
void __real_lv_draw_sw_init(void);
void *__wrap_lv_draw_create_unit(size_t size)
{
    software_unit=__real_lv_draw_create_unit(size);
    return software_unit;
}
static int32_t timed_dispatch(lv_draw_unit_t *unit,lv_layer_t *layer)
{
    uint64_t start=host_ns();
    int32_t count=dispatch_sw(unit,layer);
    if(count>0) sw_ns+=host_ns()-start;
    return count;
}
void __wrap_lv_draw_sw_init(void)
{
    __real_lv_draw_sw_init();
    dispatch_sw=software_unit->dispatch_cb;
    software_unit->dispatch_cb=timed_dispatch;
}
static void count_flush(lv_display_t *d,const lv_area_t *a,uint8_t *p)
{
    (void)p;
    area_px+=(uint64_t)lv_area_get_width(a)*lv_area_get_height(a);
    lv_display_flush_ready(d);
}
static void measure(bool metrics)
{
    uint64_t total=0,maximum=0;
    area_px=sw_ns=0;
    for(unsigned i=0;i<120;++i) {
        lv_tick_inc(1000);
        uint64_t start=host_ns();
        if(metrics) ui_vision_update(false); else ui_vision_frame(false);
        lv_refr_now(NULL);
        uint64_t elapsed=host_ns()-start;
        total+=elapsed;
        if(elapsed>maximum) maximum=elapsed;
    }
    printf("vision host %s refreshes=120 render_us=%llu max_us=%llu area_px=%llu "
           "sw_us=%llu other_us=%llu\n",metrics ? "boxes+metrics" : "boxes",
        (unsigned long long)(total/120/1000),(unsigned long long)(maximum/1000),
        (unsigned long long)(area_px/120),(unsigned long long)(sw_ns/120/1000),
        (unsigned long long)((total-sw_ns)/120/1000));
}
int main(void)
{
    lv_init();
    lv_display_t *d=lv_display_create(1280,720);
    lv_display_set_color_format(d,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(d,drawbuffer,NULL,sizeof(drawbuffer),LV_DISPLAY_RENDER_MODE_DIRECT);
    lv_display_set_flush_cb(d,count_flush);
    sim_data_init(); ui_start(); ui_open(1);
    lv_refr_now(d);
    measure(false); measure(true);
    uint64_t before=area_px;
    ui_vision_frame(false); lv_refr_now(d);
    assert(area_px==before);
    static uint32_t reference[1280*720];
    memcpy(reference,drawbuffer,sizeof(reference));
    lv_obj_invalidate(lv_screen_active()); lv_refr_now(d);
    assert(!memcmp(reference,drawbuffer,sizeof(reference)));
    puts("PASS unchanged boxes cause no refresh; incremental pixels equal full redraw");
    ui_data_boxes(); ui_vision_frame(false); lv_refr_now(d);
    memcpy(reference,drawbuffer,sizeof(reference));
    lv_obj_invalidate(lv_screen_active()); lv_refr_now(d);
    assert(!memcmp(reference,drawbuffer,sizeof(reference)));
    puts("PASS hiding boxes erases old borders and tags");
    lv_deinit();
    return 0;
}
