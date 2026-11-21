/* main_farm_bench.c — T-FARM-LAG-OK; real LVGL per-frame work comparison.
 * Scripted 1280x720 DIRECT updates; process CPU time excludes camera inference.
 */
#define _POSIX_C_SOURCE 200809L
#include "widgets.h"
#include "detection.h"
#include "sim_data.h"
#include "farm.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static uint32_t buffers[2][1280*720], reference[1280*720], *front;
static ui_detection_t detections[100];
static unsigned count, invalidations, objects, texts, styles, creates, deletes;
static lv_obj_t *invalidated[1024];
static uint64_t pixels, rules_ns;
static bool measuring;
static unsigned frame_ms=16;
static uint64_t host_ns(void)
{
    struct timespec now;
    if(clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&now)) { perror("clock_gettime"); exit(1); }
    return (uint64_t)now.tv_sec*1000000000+now.tv_nsec;
}
static void invalidation(const lv_obj_t *obj)
{
    if(!measuring) return;
    ++invalidations;
    unsigned i=0;
    while(i<objects && invalidated[i]!=obj) ++i;
    if(i==objects) { assert(objects<1024); invalidated[objects++]=(lv_obj_t *)obj; }
}
lv_result_t __real_lv_obj_invalidate_area(const lv_obj_t *,const lv_area_t *);
lv_result_t __wrap_lv_obj_invalidate_area(const lv_obj_t *obj,const lv_area_t *area)
{
    invalidation(obj);
    return __real_lv_obj_invalidate_area(obj,area);
}
lv_result_t __real_lv_obj_invalidate(const lv_obj_t *);
lv_result_t __wrap_lv_obj_invalidate(const lv_obj_t *obj)
{
    invalidation(obj);
    return __real_lv_obj_invalidate(obj);
}
void __real_lv_label_set_text(lv_obj_t *,const char *);
void __wrap_lv_label_set_text(lv_obj_t *obj,const char *text)
{ if(measuring) ++texts; __real_lv_label_set_text(obj,text); }
void __real_lv_obj_set_style_bg_color(lv_obj_t *,lv_color_t,lv_style_selector_t);
void __wrap_lv_obj_set_style_bg_color(lv_obj_t *o,lv_color_t c,lv_style_selector_t s)
{ if(measuring) ++styles; __real_lv_obj_set_style_bg_color(o,c,s); }
lv_obj_t *__real_lv_obj_class_create_obj(const lv_obj_class_t *,lv_obj_t *);
lv_obj_t *__wrap_lv_obj_class_create_obj(const lv_obj_class_t *c,lv_obj_t *p)
{ if(measuring) ++creates; return __real_lv_obj_class_create_obj(c,p); }
void __real_lv_obj_delete(lv_obj_t *);
void __wrap_lv_obj_delete(lv_obj_t *o)
{ if(measuring) ++deletes; __real_lv_obj_delete(o); }
void __real_farm_frame(farm_t *,const farm_box_t *,unsigned,uint32_t);
void __wrap_farm_frame(farm_t *f,const farm_box_t *b,unsigned n,uint32_t now)
{
    uint64_t start=host_ns();
    __real_farm_frame(f,b,n,now);
    if(measuring) rules_ns+=host_ns()-start;
}
ui_vision_t __real_ui_data_vision(void);
ui_vision_t __wrap_ui_data_vision(void)
{
    ui_vision_t d=__real_ui_data_vision();
    d.count=count<5 ? count : 5;
    for(unsigned i=0;i<d.count;++i) d.targets[i]=detections[i];
    return d;
}
static void flush(lv_display_t *d,const lv_area_t *a,uint8_t *data)
{
    if(measuring) pixels+=(uint64_t)(a->x2-a->x1+1)*(a->y2-a->y1+1);
    front=(uint32_t *)data;
    lv_display_flush_ready(d);
}
static void frame(bool farm,unsigned n,unsigned jitter)
{
    count=n;
    for(unsigned i=0;i<n;++i) {
        unsigned id=farm_class_ids[i%4];
        detections[i]=(ui_detection_t){ui_coco_names[id],95,
            40+(int)(i%10)*110+(int)jitter,150+(int)(i/10)*50,80,45,id};
    }
    sim_data_farm(detections,n);
    lv_tick_inc(frame_ms);
    if(farm) ui_farm_update(); else ui_vision_update(false);
    lv_obj_update_layout(lv_screen_active());
    lv_refr_now(NULL);
}
static void bench(bool farm,unsigned n,bool moving,bool drawer)
{
    ui_open(farm ? FARM_PAGE : 1);
    if(drawer) ui_camera_drawer_toggle();
    for(unsigned i=0;i<24;++i) { frame(farm,n,0); lv_timer_handler(); }
    pixels=rules_ns=0;
    unsigned total_invalid=0,total_objects=0,total_texts=0,total_styles=0;
    creates=deletes=0;
    uint64_t start=host_ns();
    measuring=true;
    for(unsigned i=0;i<120;++i) {
        invalidations=objects=texts=styles=0;
        frame(farm,n,moving ? i%3 : 0);
        total_invalid+=invalidations; total_objects+=objects;
        total_texts+=texts; total_styles+=styles;
    }
    measuring=false;
    printf("%s n=%u moving=%u drawer=%u interval_ms=%u pixels=%.1f invalid=%.2f objects=%.2f "
           "labels=%.2f bg_styles=%.2f create=%u delete=%u frame_us=%.2f farm_frame_us=%.3f\n",
           farm ? "farm" : "vision",n,moving,drawer,frame_ms,pixels/120.0,total_invalid/120.0,
           total_objects/120.0,total_texts/120.0,total_styles/120.0,creates,deletes,
           (host_ns()-start)/120000.0,rules_ns/120000.0);
    /* Both movement and removal must match a complete redraw, including old tags. */
    memcpy(reference,front,sizeof reference);
    lv_obj_invalidate(lv_screen_active()); lv_refr_now(NULL);
    assert(!memcmp(reference,front,sizeof reference));
    frame(farm,0,0);
    memcpy(reference,front,sizeof reference);
    lv_obj_invalidate(lv_screen_active()); lv_refr_now(NULL);
    assert(!memcmp(reference,front,sizeof reference));
}
static void reuse_tag(void)
{
    frame_ms=16;
    ui_open(FARM_PAGE);
    frame(true,1,0);
    memcpy(reference,front,sizeof reference);
    detections[0].class_id=0;
    detections[0].category=ui_coco_names[0];
    sim_data_farm(detections,1);
    ui_farm_update();
    lv_tick_inc(500); ui_farm_update(); lv_refr_now(NULL);
    frame(true,0,0);
    lv_tick_inc(1000); ui_farm_update(); lv_refr_now(NULL);
    frame(true,1,0);
    /* Reusing a vanished red person tag for a cow must restore its teal color. */
    assert(!memcmp(reference+1280*48,front+1280*48,
                   (720-48)*1280*sizeof *front));
    puts("PASS farm tag reuse: red person -> absent -> teal animal");
}
int main(void)
{
    lv_init();
    lv_display_t *d=lv_display_create(1280,720);
    lv_display_set_color_format(d,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(d,buffers[0],buffers[1],sizeof buffers[0],LV_DISPLAY_RENDER_MODE_DIRECT);
    lv_display_set_flush_cb(d,flush);
    sim_data_init(); ui_start();
    for(unsigned moving=0;moving<2;++moving) {
        bench(false,5,moving,false);
        bench(true,5,moving,false);
        bench(true,9,moving,false);
        bench(true,9,moving,true);
        bench(true,100,moving,false);
    }
    frame_ms=10000;
    bench(true,9,false,false);
    bench(true,9,false,true);
    puts("PASS farm repaint: movement and box removal equal full redraw");
    reuse_tag();
    lv_deinit();
    return 0;
}
