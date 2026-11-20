/* process_autoplay.c — live demo L12; actual LVGL events and page lifetime.
 * Host ticks exercise order, 3 s boundaries, animation and manual takeover.
 */
#include "widgets.h"
#include "live_demo.h"
#include "sim_data.h"
#include "geo_matrix.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint32_t pixels[1280*720];
static void flush(lv_display_t *display,const lv_area_t *area,uint8_t *data)
{ (void)area; (void)data; lv_display_flush_ready(display); }
static lv_obj_t *label(lv_obj_t *parent,const char *text)
{
    if (lv_obj_check_type(parent,&lv_label_class) &&
        strcmp(lv_label_get_text(parent),text)==0) return parent;
    for (unsigned i=0;i<lv_obj_get_child_count(parent);++i) {
        lv_obj_t *found=label(lv_obj_get_child(parent,(int)i),text);
        if (found) return found;
    }
    return NULL;
}
static lv_obj_t *toggle(const char *name)
{
    lv_obj_t *text=label(lv_screen_active(),name);
    assert(text);
    return lv_obj_get_child(lv_obj_get_parent(text),-1);
}
static void change_toggle(const char *name,bool checked)
{
    lv_obj_t *control=toggle(name);
    lv_obj_set_state(control,LV_STATE_CHECKED,checked);
    lv_obj_send_event(control,LV_EVENT_VALUE_CHANGED,NULL);
}
static void advance(unsigned ms) { lv_tick_inc(ms); ui_process_update(); }
static void same(ui_process_config_t expected)
{
    ui_process_config_t got=ui_data_process_config();
    assert(got.enabled==expected.enabled && got.original==expected.original);
    assert(got.brightness==expected.brightness && got.contrast==expected.contrast);
    assert(got.gamma_tenths==expected.gamma_tenths && got.stage1==expected.stage1);
    assert(got.stage2==expected.stage2 && got.threshold==expected.threshold);
    assert(got.angle==expected.angle && got.scale_percent==expected.scale_percent);
    assert(got.translate_x==expected.translate_x && got.translate_y==expected.translate_y);
}
int main(void)
{
    lv_init();
    lv_display_t *display=lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,pixels,NULL,sizeof pixels,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init(); ui_start(); ui_open(3);
    assert(!lv_obj_has_state(toggle("自动演示"),LV_STATE_CHECKED));
    ui_process_config_t saved={.enabled=UI_PROC_LEVEL|UI_PROC_SCALE,.brightness=-32,
        .contrast=300,.gamma_tenths=14,.stage1=3,.stage2=6,.threshold=77,
        .angle=-45,.scale_percent=125,.translate_x=-30,.translate_y=40,.original=true};
    ui_data_process_set(&saved);
    change_toggle("自动演示",true);
    static const char *const names[]={"原图","亮度 / 对比度","Gamma","3×3 均值滤波",
        "3×3 高斯平滑","锐化","Sobel 边缘","腐蚀","膨胀","灰度","二值化",
        "反色","旋转","缩放","平移","水平镜像","垂直镜像",
        "组合：高斯 + Sobel + 旋转","回到原图"};
    const unsigned stages[]={0,1,2,4,4,4,4,4,4,16,32,64,128,256,512,1024,2048,140,0};
    for (unsigned i=0;i<19;++i) {
        char text[120]; snprintf(text,sizeof text,"%u / 19  %s",i+1,names[i]);
        assert(label(lv_screen_active(),text));
        ui_process_config_t c=ui_data_process_config();
        assert(c.enabled==stages[i] && c.original==(i==0 || i==18));
        if (i>=3 && i<=8) assert(c.stage1==(int)i-2);
        if (i==1) assert(c.brightness==48 && c.contrast==320);
        if (i==2) assert(pix_gamma_value(32,(unsigned)c.gamma_tenths)>32);
        if (i==14) assert(c.translate_x==160 && c.translate_y==80);
        if (i==17) assert(c.stage1==2 && c.stage2==4 && c.angle==30);
        if (i==12 || i==13) {
            const int expected_angle[]={90,180,-90};
            const int expected_scale[]={125,200,125};
            for (unsigned j=0;j<3;++j) {
                advance(750); c=ui_data_process_config();
                assert((i==12 ? c.angle : c.scale_percent)==
                       (i==12 ? expected_angle[j] : expected_scale[j]));
            }
            advance(749);
        } else advance(2999);
        assert(label(lv_screen_active(),text));
        advance(1);
    }
    assert(label(lv_screen_active(),"1 / 19  原图"));
    change_toggle("自动演示",false); same(saved);
    advance(6000); same(saved);
    change_toggle("自动演示",true);
    advance(18000); ui_open(0); same(saved);
    ui_live_command(0,6);
    assert(lv_obj_has_state(toggle("自动演示"),LV_STATE_CHECKED));
    advance(3000);
    lv_group_t *group=lv_group_get_default();
    lv_obj_t *slider=NULL;
    for (unsigned i=0;i<lv_group_get_obj_count(group);++i) {
        lv_obj_t *o=lv_group_get_obj_by_index(group,i);
        if (lv_obj_check_type(o,&lv_slider_class)) { slider=o; break; }
    }
    assert(slider); lv_slider_set_value(slider,73,LV_ANIM_OFF);
    lv_obj_send_event(slider,LV_EVENT_VALUE_CHANGED,NULL);
    assert(!lv_obj_has_state(toggle("自动演示"),LV_STATE_CHECKED));
    saved=ui_data_process_config(); assert(saved.brightness==73);
    advance(9000); same(saved); ui_back(); same(saved);
    ui_live_command(0,6); advance(3000);
    change_toggle("原图",true); saved=ui_data_process_config();
    advance(6000); same(saved); ui_open(0); same(saved);
    ui_live_exit(); ui_open(3); change_toggle("自动演示",true);
    advance(18000); ui_process_action(2);
    saved=ui_data_process_config(); assert(saved.enabled==0 && !saved.original);
    advance(6000); same(saved); ui_open(0); same(saved);
    ui_open(3); change_toggle("自动演示",true);
    lv_tick_inc(3000); lv_timer_handler();
    assert(ui_data_process_config().enabled==UI_PROC_LEVEL);
    ui_open(0);
    puts("PASS process autoplay: 19 steps, 3 s, loop, animations, restore, manual stop, timer");
}
