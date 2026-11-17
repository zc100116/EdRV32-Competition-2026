/* main_compact_shots.c — R4 §5; native LVGL page checks and framebuffer captures.
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
static unsigned covered;
static uint64_t host_ns(void)
{
    struct timespec time;
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&time);
    return (uint64_t)time.tv_sec*1000000000u+time.tv_nsec;
}
static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    const uint32_t *source = (const uint32_t *)pixels;
    const lv_image_dsc_t *background = sim_l0_image();
    for (int y = area->y1; y <= area->y2; ++y)
        for (int x = area->x1; x <= area->x2; ++x) {
            uint32_t c = sim_composite(background,*source++,(unsigned)x,(unsigned)y);
            framebuffer[y*1280+x] = (uint16_t)(((c >> 8)&0xf800) |
                ((c >> 5)&0x07e0) | ((c >> 3)&31));
        }
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
    covered=0;
    for(unsigned i=0;i<1280*720;++i) covered+=(drawbuffer[i]>>24)!=0;
    check_labels(lv_screen_active());
    printf("coverage %s pixels=%u ratio=%.3f%%\n",name,covered,covered*100.0/(1280*720));
    char path[1024];
    snprintf(path,sizeof path,"%s/%s.rgb565",output,name);
    FILE *file = fopen(path,"wb");
    if (!file) { perror(path); exit(EXIT_FAILURE); }
    assert(fwrite(framebuffer,sizeof framebuffer,1,file) == 1);
    assert(fclose(file) == 0);
}
static void measure(const char *name)
{
    uint64_t total=0;
    for(unsigned f=0;f<30;++f) {
        lv_obj_invalidate(lv_screen_active());
        uint64_t start=host_ns(); lv_refr_now(NULL); total+=host_ns()-start;
    }
    printf("mean %s draw_us=%.2f frames=30 full redraw+composition\n",name,total/30000.0);
}
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

static bool hidden(lv_obj_t *object)
{
    for(;object;object=lv_obj_get_parent(object))
        if(lv_obj_is_hidden(object)) return true;
    return false;
}
static void traverse(void)
{
    lv_group_t *group=lv_group_get_default();
    unsigned count=lv_group_get_obj_count(group);
    bool visited[256]={false};
    assert(count<256);
    for(unsigned i=0;i<count*2;++i) {
        ui_key(LV_KEY_NEXT);
        lv_obj_t *focused=lv_group_get_focused(group);
        for(unsigned j=0;j<count;++j)
            if(focused==lv_group_get_obj_by_index(group,j)) visited[j]=true;
    }
    for(unsigned j=0;j<count;++j) {
        lv_obj_t *object=lv_group_get_obj_by_index(group,j);
        if(!hidden(object) && !lv_obj_is_disabled(object)) assert(visited[j]);
    }
}
static void drawer_top(lv_obj_t *object)
{
    if(lv_obj_get_width(object)==320 && lv_obj_get_height(object)==672)
        lv_obj_scroll_to_y(object,0,LV_ANIM_OFF);
    for(unsigned i=0;i<lv_obj_get_child_count(object);++i)
        drawer_top(lv_obj_get_child(object,(int)i));
}
int main(int argc,char **argv)
{
    assert(argc==2); output=argv[1];
    setvbuf(stdout,NULL,_IOLBF,0);
    lv_init();
    lv_display_t *display=lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init(); ui_start();
    const unsigned pages[]={1,2,3,9,10,11,13};
    const char *names[]={"vision","image","process","pose","hand","face","helmet"};
    extern const lv_image_dsc_t sim_indoor;
    ui_demo_t demo={0}; ui_hand_t hand={0};
    demo.count=1; demo.helmet=1;
    hand.count=1; hand.confidence=92; hand.state.cls=0;
    demo.objects[0]=(ui_detection_t){.x=320,.y=190,.width=180,.height=240,
        .confidence=92,.category="行人"};
    const ui_pose_point_t points[5]={{365,260,1},{435,260,1},{400,300,1},
                                  {375,340,1},{425,340,1}};
    for(unsigned k=0;k<5;++k) demo.points[0][k]=points[k];
    hand.people[0]=demo.objects[0];
    for(unsigned k=0;k<21;++k) hand.points[0][k]=(ui_pose_point_t){380+k*3,270+k*5,1};
    for(unsigned i=0;i<7;++i) {
        ui_open(pages[i]);
        if(pages[i]==9) sim_data_pose(1,0);
        if(pages[i]==2) sim_data_image_status(UI_IMAGE_DONE);
        if(pages[i]>=10) {
            demo.objects[0].category=pages[i]==11 ? "人脸" : "安全帽";
            demo.size=240;
            sim_data_demo(&demo,&hand,&sim_indoor);
            for(unsigned f=0;f<8;++f) { ++sticker_revision; lv_tick_inc(33); ui_refresh(); }
        }
        capture(names[i]);
        assert(covered*100<=1280*720*15);
        measure(names[i]);
        traverse();
        const char *button_name=pages[i]<=2 ? "检测设置" : pages[i]==11 ? "贴纸" : "设置";
        lv_obj_t *label=find_label(lv_screen_active(),button_name); assert(label);
        lv_obj_t *button=lv_obj_get_parent(label);
        lv_obj_send_event(button,LV_EVENT_CLICKED,NULL);
        lv_tick_inc(200); lv_timer_handler();
        traverse();
        if(pages[i]<=2) {
            lv_obj_t *threshold=find_type(lv_screen_active(),&lv_spinbox_class); assert(threshold);
            lv_spinbox_set_value(threshold,55);
            lv_obj_send_event(threshold,LV_EVENT_VALUE_CHANGED,NULL);
            assert(ui_data_detection_config().threshold==55);
            toggle(named_switch("行人"),false);
            assert(!(ui_data_detection_config().classes[0]&1));
            toggle(named_switch("行人"),true);
            lv_spinbox_set_value(threshold,50);
            lv_obj_send_event(threshold,LV_EVENT_VALUE_CHANGED,NULL);
        }
        if(pages[i]==11) {
            assert(!find_type(lv_screen_active(),&lv_dropdown_class));
            lv_obj_t *party=find_label(lv_screen_active(),"派对"); assert(party);
            lv_obj_send_event(lv_obj_get_parent(party),LV_EVENT_CLICKED,NULL);
            assert(find_label(lv_screen_active(),"套装：派对"));
        }
        if(pages[i]==3) {
            ui_process_config_t original=ui_data_process_config();
            toggle(named_switch("亮度 / 对比度"),true);
            assert(ui_data_process_config().enabled&1);
            ui_data_process_set(&original);
        }
        lv_group_focus_obj(button); drawer_top(lv_screen_active());
        char name[80]; snprintf(name,sizeof name,"%s-drawer",names[i]); capture(name);
        ui_back(); assert(ui_page==pages[i]);
        assert(!ui_camera_drawer_close());
        ui_hide_interface(); assert(ui_restore_interface());
    }
    puts("PASS: seven compact pages, <=15% pixels, drawers, four-key traversal and settings");
    return 0;
}
