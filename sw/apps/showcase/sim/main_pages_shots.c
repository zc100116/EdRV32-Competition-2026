/* main_pages_shots.c — R4 §5; native LVGL page checks and framebuffer captures.
 * Host clock timings include software rendering and RGB565 output composition.
 */
#define _POSIX_C_SOURCE 200809L
#include "widgets.h"
#include "detection.h"
#include "sim_data.h"
#include "motion.h"
#include "grab.h"
#include "sticker.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static uint16_t framebuffer[1280*720];
static uint32_t drawbuffer[1280*720];
static const char *output;
static uint64_t composition_ns;
static uint64_t host_ns(void)
{
    struct timespec time;
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&time);
    return (uint64_t)time.tv_sec*1000000000u+time.tv_nsec;
}
static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    uint64_t start=host_ns();
    const uint32_t *source = (const uint32_t *)pixels;
    const lv_image_dsc_t *background = sim_l0_image();
    for (int y = area->y1; y <= area->y2; ++y)
        for (int x = area->x1; x <= area->x2; ++x) {
            uint32_t c = sim_composite(background,*source++,(unsigned)x,(unsigned)y);
            framebuffer[y*1280+x] = (uint16_t)(((c >> 8)&0xf800) |
                ((c >> 5)&0x07e0) | ((c >> 3)&31));
        }
    composition_ns+=host_ns()-start;
    lv_display_flush_ready(display);
}
static void check_labels(lv_obj_t *parent)
{
    if (lv_obj_is_hidden(parent)) return;
    if (lv_obj_check_type(parent,&lv_label_class)) {
        const unsigned char *text = (const unsigned char *)lv_label_get_text(parent);
        const lv_font_t *font = lv_obj_get_style_text_font(parent,0);
        while (*text) {
            unsigned code = *text++;
            if (code >= 0xc0) {
                unsigned n = code >= 0xf0 ? 3 : code >= 0xe0 ? 2 : 1;
                code &= (1u << (6-n))-1;
                while (n--) code = (code << 6) | (*text++ & 0x3f);
            }
            if (code == '\n') continue;
            lv_font_glyph_dsc_t glyph;
            if (!lv_font_get_glyph_dsc(font,&glyph,code,0) || glyph.is_placeholder) {
                fprintf(stderr,"Missing glyph U+%04X in %s\n",code,lv_label_get_text(parent));
                exit(EXIT_FAILURE);
            }
        }
    }
    for (unsigned i = 0; i < lv_obj_get_child_count(parent); ++i)
        check_labels(lv_obj_get_child(parent,(int)i));
}
static void capture(const char *name)
{
    lv_tick_inc(200);
    ui_refresh();
    lv_obj_update_layout(lv_screen_active());
    lv_obj_invalidate(lv_screen_active());
    uint64_t start = host_ns();
    lv_refr_now(NULL);
    printf("frame %s draw_us=%llu\n",name,(unsigned long long)((host_ns()-start)/1000));
    check_labels(lv_screen_active());
    char path[1024];
    snprintf(path,sizeof path,"%s/%s.rgb565",output,name);
    FILE *file = fopen(path,"wb");
    if (!file) { perror(path); exit(EXIT_FAILURE); }
    assert(fwrite(framebuffer,sizeof framebuffer,1,file) == 1);
    assert(fclose(file) == 0);
}
static void measure(const char *name)
{
    uint64_t total=0,composition=0;
    for(unsigned f=0;f<30;++f) {
        lv_obj_invalidate(lv_screen_active());
        uint64_t before=composition_ns;
        uint64_t start=host_ns(); lv_refr_now(NULL); total+=host_ns()-start;
        composition+=composition_ns-before;
    }
    printf("mean %s draw_us=%.2f lvgl_us=%.2f composition_us=%.2f frames=30\n",
        name,total/30000.0,(total-composition)/30000.0,composition/30000.0);
}
#ifndef PAGES_BASELINE
static lv_obj_t *find_label(lv_obj_t *parent, const char *text)
{
    if(lv_obj_check_type(parent,&lv_label_class) &&
       !lv_strcmp(lv_label_get_text(parent),text)) return parent;
    for(unsigned i=0;i<lv_obj_get_child_count(parent);++i) {
        lv_obj_t *found=find_label(lv_obj_get_child(parent,(int)i),text);
        if(found) return found;
    }
    return NULL;
}
static lv_obj_t *find_type(lv_obj_t *parent,const lv_obj_class_t *type)
{
    if(lv_obj_check_type(parent,type)) return parent;
    for(unsigned i=0;i<lv_obj_get_child_count(parent);++i) {
        lv_obj_t *found=find_type(lv_obj_get_child(parent,(int)i),type);
        if(found) return found;
    }
    return NULL;
}
static lv_obj_t *switch_row(lv_obj_t *parent,const char *name)
{
    if(lv_obj_check_type(parent,&lv_label_class) &&
       !lv_strcmp(lv_label_get_text(parent),name)) {
        lv_obj_t *control=find_type(lv_obj_get_parent(parent),&lv_switch_class);
        if(control) return control;
    }
    for(unsigned i=0;i<lv_obj_get_child_count(parent);++i) {
        lv_obj_t *control=switch_row(lv_obj_get_child(parent,(int)i),name);
        if(control) return control;
    }
    return NULL;
}
static lv_obj_t *named_switch(const char *name)
{ return switch_row(lv_screen_active(),name); }
static void toggle(lv_obj_t *control,bool checked)
{
    assert(control); lv_obj_set_state(control,LV_STATE_CHECKED,checked);
    lv_obj_send_event(control,LV_EVENT_VALUE_CHANGED,NULL);
}
static void interactions(void)
{
    ui_open(16); toggle(named_switch("调试叠加"),true); assert(ui_debug_overlay);
    ui_open(10); assert(ui_debug_overlay);
    assert(!find_label(lv_screen_active(),"关键点 开关"));
    ui_open(11); assert(ui_debug_overlay); assert(!find_label(lv_screen_active(),"调试"));
    lv_obj_t *preset=find_label(lv_screen_active(),"派对"); assert(preset);
    lv_obj_send_event(lv_obj_get_parent(preset),LV_EVENT_CLICKED,NULL);
    assert(find_label(lv_screen_active(),"套装：派对"));
    ui_open(16); assert(lv_obj_has_state(named_switch("调试叠加"),LV_STATE_CHECKED));
    toggle(named_switch("调试叠加"),false); assert(!ui_debug_overlay);
    lv_obj_t *test=find_label(lv_screen_active(),"抓取测试"); assert(test);
    lv_obj_send_event(lv_obj_get_parent(test),LV_EVENT_CLICKED,NULL); assert(ui_page==14);
    ui_open(1); sim_data_many_categories(true); lv_tick_inc(1000); ui_refresh();
    lv_obj_update_layout(lv_screen_active());
    capture("vision-categories");
    const char *classes[]={"卡车","汽车","公交车","自行车","行人"};
    for(unsigned i=0;i<5;++i) {
        lv_obj_t *category=find_label(lv_screen_active(),classes[i]); assert(category);
        lv_area_t area; lv_obj_get_coords(category,&area); assert(area.y2<680);
    }
    sim_data_many_categories(false);
    ui_activate(2); lv_tick_inc(200); lv_timer_handler();
    lv_obj_t *threshold=find_type(lv_screen_active(),&lv_spinbox_class); assert(threshold);
    lv_spinbox_set_value(threshold,55); lv_obj_send_event(threshold,LV_EVENT_VALUE_CHANGED,NULL);
    assert(ui_data_detection_config().threshold==55);
    toggle(named_switch("行人"),false); assert(!(ui_data_detection_config().classes[0]&1));
    toggle(named_switch("行人"),true);
    lv_spinbox_set_value(threshold,50); lv_obj_send_event(threshold,LV_EVENT_VALUE_CHANGED,NULL);
    capture("detection-settings"); ui_back();
    ui_open(3); ui_process_config_t original=ui_data_process_config();
    toggle(named_switch("亮度 / 对比度"),true); assert(ui_data_process_config().enabled&1);
    ui_data_process_set(&original);
    ui_open(8); lv_obj_t *tabs=find_type(lv_screen_active(),&lv_tabview_class); assert(tabs);
    lv_tabview_set_active(tabs,1,LV_ANIM_OFF);
    lv_obj_send_event(tabs,LV_EVENT_VALUE_CHANGED,NULL);
    assert(ui_tab==1); capture("debug-network");
    ui_tab=0; ui_open(4);
    lv_obj_t *segment=find_type(lv_screen_active(),&lv_buttonmatrix_class); assert(segment);
    lv_buttonmatrix_set_selected_button(segment,1);
    lv_obj_send_event(segment,LV_EVENT_VALUE_CHANGED,NULL);
    assert(ui_tab==1); capture("graphics-renderers");
    ui_tab=0;
    puts("PASS: shared debug persistence, sticker preset, grab entry, filter, process and tabs");
}
#endif
int main(int argc, char **argv)
{
    assert(argc == 2); output=argv[1];
    lv_init();
    lv_display_t *d=lv_display_create(1280,720);
    lv_display_set_color_format(d,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(d,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(d,flush);
    sim_data_init(); ui_start();
    const unsigned pages[]={1,2,3,4,5,7,8,9,10,11,13,16};
    const char *names[]={"vision","image","process","graphics","games","chip","debug",
                         "pose","hand","face","helmet","settings"};
    extern const lv_image_dsc_t sim_indoor;
    ui_demo_t demo={0}; ui_hand_t hand={0};
    demo.count=1; demo.helmet=1;
    hand.count=1; hand.confidence=92; hand.state.cls=0; hand.people[0]=demo.objects[0];
    demo.objects[0]=(ui_detection_t){.x=320,.y=190,.width=180,.height=240,
        .confidence=92,.category="行人"};
    const ui_pose_point_t face_points[5]={{365,260,1},{435,260,1},{400,300,1},
                                            {375,340,1},{425,340,1}};
    for(unsigned k=0;k<5;++k) demo.points[0][k]=face_points[k];
    hand.people[0]=demo.objects[0];
    for(unsigned k=0;k<21;++k) hand.points[0][k]=(ui_pose_point_t){380+k*3,270+k*5,1};
    for(unsigned i=0;i<sizeof pages/sizeof pages[0];++i) {
        ui_open(pages[i]);
        if(pages[i]==9) sim_data_pose(1,0);
        if(pages[i]>=10 && pages[i]<=13) sim_data_demo(&demo,&hand,&sim_indoor);
        if(pages[i]==2) sim_data_image_status(UI_IMAGE_DONE);
        if(pages[i]>=10 && pages[i]<=13) {
            demo.objects[0].category=pages[i]==11 ? "人脸" : "安全帽";
            demo.size=240;
            sim_data_demo(&demo,&hand,&sim_indoor);
            for(unsigned f=0;f<8;++f) { ++sticker_revision; lv_tick_inc(33); ui_refresh(); }
        }
        capture(names[i]);
        measure(names[i]);
    }
    ui_open(0); ui_monitor_toggle();
    for(unsigned second=0;second<60;++second) { lv_tick_inc(1000); ui_monitor_update(); }
    capture("monitor");
    ui_monitor_toggle();
#ifndef PAGES_BASELINE
    interactions();
    ui_open(2); sim_data_image_status(UI_IMAGE_DETECTING); capture("image-loading");
    ui_open(7); ui_activate(0); capture("chip-running");
    ui_open(10); ui_hand_toggle(); capture("hand-debug"); measure("hand-debug");
    ui_open(11); capture("face-debug"); measure("face-debug");
    demo.count=2; demo.head=1; demo.helmet=1;
    demo.objects[0].category="安全帽";
    demo.objects[1]=demo.objects[0]; demo.objects[1].x+=240;
    demo.objects[1].class_id=1; demo.objects[1].category="未戴";
    ui_open(13); sim_data_demo(&demo,&hand,&sim_indoor); capture("helmet-warning");
    lv_obj_t *warning=find_label(lv_screen_active(),"警示：有人未戴安全帽"); assert(warning);
    assert(!lv_obj_is_hidden(warning));
    lv_area_t warning_area; lv_obj_get_coords(warning,&warning_area);
    assert(warning_area.x2<956 && warning_area.y2<680);
    ui_open(1); sim_data_session(UI_APP_CAMERA,UI_STATE_FAILED,"硬件不支持");
    capture("session-failed");
    lv_obj_t *failure=find_label(lv_screen_active(),"硬件不支持"); assert(failure);
    lv_obj_t *dialog=lv_obj_get_parent(failure);
    assert(lv_obj_is_ignore_layout(dialog));
    assert(lv_obj_get_style_x(dialog,0)==340 && lv_obj_get_style_y(dialog,0)==200);
#endif
    return 0;
}
