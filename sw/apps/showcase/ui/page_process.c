/* page_process.c — P5 design 3.6/8.3; PIX → GEO stages and retained parameters.
 * Live demo L12: timed PIX/GEO sequence, snapshot restore and manual takeover.
 */
#include "widgets.h"
#include "live_demo.h"
#include <stddef.h>
static lv_obj_t *autoplay_switch;
static lv_obj_t *step_label;
static lv_timer_t *autoplay_timer;
static bool autoplay;
static uint32_t autoplay_start;
static unsigned autoplay_step;
static ui_process_config_t saved_config;
static void autoplay_apply(void);
static void autoplay_stop(bool restore)
{
    if (!autoplay) return;
    autoplay = false;
    lv_timer_pause(autoplay_timer);
    if (restore) ui_data_process_set(&saved_config);
    lv_obj_remove_state(autoplay_switch,LV_STATE_CHECKED);
    lv_obj_set_hidden(step_label,true);
}
/* Each step starts from defaults, so the labelled effect is isolated. */
static void autoplay_apply(void)
{
    static const char *const names[] = {
        "原图", "亮度 / 对比度", "Gamma", "3×3 均值滤波", "3×3 高斯平滑",
        "锐化", "Sobel 边缘", "腐蚀", "膨胀", "灰度", "二值化", "反色",
        "旋转", "缩放", "平移", "水平镜像", "垂直镜像",
        "组合：高斯 + Sobel + 旋转", "回到原图"
    };
    static const uint32_t stages[] = {
        0, UI_PROC_LEVEL, UI_PROC_GAMMA, UI_PROC_S1, UI_PROC_S1, UI_PROC_S1,
        UI_PROC_S1, UI_PROC_S1, UI_PROC_S1, UI_PROC_GRAY, UI_PROC_BINARY,
        UI_PROC_INVERT, UI_PROC_ROTATE, UI_PROC_SCALE, UI_PROC_TRANSLATE,
        UI_PROC_MIRROR_X, UI_PROC_MIRROR_Y, UI_PROC_S1|UI_PROC_S2|UI_PROC_ROTATE, 0
    };
    uint32_t elapsed = lv_tick_get()-autoplay_start;
    unsigned step = elapsed/3000%19;
    unsigned phase = elapsed%3000;
    if (step==autoplay_step && step!=12 && step!=13) return;
    autoplay_step = step;
    ui_process_config_t c = {.enabled=stages[step], .contrast=256, .gamma_tenths=10,
        .stage1=2, .stage2=2, .threshold=128, .scale_percent=100};
    c.original = step==0 || step==18;
    if (step==1) { c.brightness=48; c.contrast=320; }
    if (step==2) c.gamma_tenths=18;
    if (step>=3 && step<=8) c.stage1=(int)step-2;
    if (step==12) {
        c.angle=(int)(phase*360/3000);
        if (c.angle>180) c.angle-=360;
    }
    if (step==13) c.scale_percent=50+(int)((phase<=1500 ? phase : 3000-phase)*150/1500);
    if (step==14) { c.translate_x=160; c.translate_y=80; }
    if (step==17) { c.stage2=4; c.angle=30; }
    ui_data_process_set(&c);
    char text[120];
    lv_snprintf(text,sizeof text,"%u / 19  %s",step+1,names[step]);
    ui_text(step_label,text);
}
static void autoplay_changed(lv_event_t *e)
{
    if (lv_obj_has_state(lv_event_get_target_obj(e),LV_STATE_CHECKED)) {
        saved_config = ui_data_process_config();
        autoplay = true;
        autoplay_start = lv_tick_get();
        autoplay_step = 19;
        lv_timer_resume(autoplay_timer);
        autoplay_apply();
        lv_obj_set_hidden(step_label,false);
    } else autoplay_stop(true);
    ui_process_update();
}
static void autoplay_tick(lv_timer_t *timer)
{
    (void)timer;
    ui_process_update();
}
static void process_deleted(lv_event_t *e)
{
    (void)e;
    autoplay_stop(true);
    lv_timer_delete(autoplay_timer);
}
static lv_obj_t *metrics;
static lv_obj_t *view_switch;
static lv_obj_t *enables[12];
static lv_obj_t *controls[10];
static lv_obj_t *values[10];
struct parameter { const char *name; size_t offset; int low, high; unsigned stage; };
#define PARAM(name,field,low,high,stage) \
    {name,offsetof(ui_process_config_t,field),low,high,stage}
static const struct parameter parameters[]={
    PARAM("亮度",brightness,-256,255,0),
    PARAM("对比度",contrast,0,512,0),
    PARAM("伽马",gamma_tenths,3,30,1),
    PARAM("滤波运算",stage1,1,6,2),
    PARAM("滤波运算",stage2,1,6,3),
    PARAM("阈值",threshold,0,255,5),
    PARAM("角度 °",angle,-180,180,7),
    PARAM("缩放 %",scale_percent,50,400,8),
    PARAM("平移 X",translate_x,-1280,1280,9),
    PARAM("平移 Y",translate_y,-720,720,9)
};
static int *field(ui_process_config_t *c,unsigned i)
{ return (int *)((char *)c+parameters[i].offset); }
void ui_process_update(void)
{
    if (autoplay) autoplay_apply();
    (void)ui_data_process(0);
    ui_process_config_t c=ui_data_process_config();
    lv_obj_set_state(view_switch,LV_STATE_CHECKED,c.original);
    ui_camera_metrics_update(metrics);
    for(unsigned i=0;i<12;++i) lv_obj_set_state(enables[i],LV_STATE_CHECKED,
        (c.enabled&(1u<<i))!=0);
    for(unsigned i=0;i<10;++i) {
        int n=*field(&c,i);
        bool filter=i==3 || i==4;
        lv_obj_set_state(controls[i],LV_STATE_DISABLED,
            (c.enabled&(1u<<parameters[i].stage))==0);
        if(filter) {
            if(!lv_dropdown_is_open(controls[i]))
                lv_dropdown_set_selected(controls[i],(unsigned)n-1);
        }
        else {
            lv_slider_set_value(controls[i],n,LV_ANIM_OFF);
            char text[64];
            if(i==1) lv_snprintf(text,sizeof text,"%s  %d.%02d",parameters[i].name,
                n/256,n%256*100/256);
            else if(i==2) lv_snprintf(text,sizeof text,"%s  %d.%d",parameters[i].name,n/10,n%10);
            else lv_snprintf(text,sizeof text,"%s  %d",parameters[i].name,n);
            ui_text(values[i],text);
        }
    }
    lv_group_t *g=lv_group_get_default();
    if(lv_obj_is_disabled(lv_group_get_focused(g))) {
        lv_group_set_editing(g,false); lv_group_focus_next(g);
    }
}
static void parameter_changed(lv_event_t *e)
{
    autoplay_stop(false);
    unsigned i=(unsigned)(uintptr_t)lv_event_get_user_data(e);
    ui_process_config_t c=ui_data_process_config();
    lv_obj_t *o=lv_event_get_target_obj(e);
    *field(&c,i)=i==3 || i==4 ? (int)lv_dropdown_get_selected(o)+1 : lv_slider_get_value(o);
    ui_data_process_set(&c); ui_process_update();
}
static void enabled_changed(lv_event_t *e)
{
    autoplay_stop(false);
    unsigned stage=(unsigned)(uintptr_t)lv_event_get_user_data(e);
    ui_process_config_t c=ui_data_process_config();
    bool on=lv_obj_has_state(lv_event_get_target_obj(e),LV_STATE_CHECKED);
    if(stage==12) c.original=on;
    else if(on) c.enabled|=1u<<stage;
    else c.enabled&=~(1u<<stage);
    ui_data_process_set(&c); ui_process_update();
}
void ui_process_action(unsigned action)
{
    if(action==0) { ui_camera_drawer_toggle(); return; }
    autoplay_stop(false);
    if(action==2) ui_data_process_defaults(UI_PROC_ALL);
    else if(action>=100) ui_data_process_defaults(1u<<(action-100));
    ui_process_update();
}
void ui_page_process(lv_obj_t *p)
{
    lv_obj_t *header=ui_camera_layout(p,"图像处理");
    metrics=ui_camera_metrics(header);
    view_switch=ui_flex_switch(header,"原图",false);
    lv_obj_set_width(lv_obj_get_parent(view_switch),180);
    lv_obj_add_event_cb(view_switch,enabled_changed,LV_EVENT_VALUE_CHANGED,(void *)12);
    autoplay_switch=ui_flex_switch(header,"自动演示",false);
    lv_obj_set_width(lv_obj_get_parent(autoplay_switch),184);
    lv_obj_add_event_cb(autoplay_switch,autoplay_changed,LV_EVENT_VALUE_CHANGED,NULL);
    ui_action_button(header,"全部恢复默认",2);
    step_label=ui_label(p,"",24,72,&sim_font_40,TEXT);
    lv_obj_set_ignore_layout(step_label,true);
    lv_obj_set_style_bg_color(step_label,lv_color_hex(PANEL),0);
    lv_obj_set_style_bg_opa(step_label,LV_OPA_COVER,0);
    lv_obj_set_style_pad_all(step_label,12,0);
    lv_obj_set_hidden(step_label,true);
    autoplay_timer=lv_timer_create(autoplay_tick,50,NULL);
    lv_timer_pause(autoplay_timer);
    lv_obj_add_event_cb(p,process_deleted,LV_EVENT_DELETE,NULL);
    lv_obj_t *panel=ui_camera_drawer(p,header,"设置");
    lv_obj_set_style_pad_row(panel,6,0);
    lv_obj_set_scrollable(panel,true); lv_obj_set_scroll_dir(panel,LV_DIR_VER);
    const char *names[]={"亮度 / 对比度","伽马","第一级滤波 S1","第二级滤波 S2",
        "灰度","二值化","反色","旋转","缩放","平移","水平镜像","垂直镜像"};
    ui_text_label(panel,"摄像头 → PIX → GEO → 显示",&sim_font_16,TEAL);
    for(unsigned stage=0;stage<12;++stage) {
        if(stage==0 || stage==7)
            ui_text_label(panel,stage==0 ? "PIX · 点运算 / 滤波" : "GEO · 几何变换",
                          &sim_font_20,ACCENT);
        lv_obj_t *row=ui_panel(panel,LV_PCT(100));
        lv_obj_set_style_pad_all(row,8,0);
        lv_obj_set_style_pad_row(row,6,0);
        enables[stage]=ui_flex_switch(row,names[stage],false);
        lv_obj_set_style_pad_ver(lv_obj_get_parent(enables[stage]),0,0);
        lv_obj_add_event_cb(enables[stage],enabled_changed,LV_EVENT_VALUE_CHANGED,
                            (void *)(uintptr_t)stage);
        for(unsigned i=0;i<10;++i) if(parameters[i].stage==stage) {
            if(i==3 || i==4) controls[i]=ui_select(row,"均值\n高斯\n锐化\nSobel\n腐蚀\n膨胀");
            else {
                values[i]=ui_text_label(row,"",&sim_font_16,TEXT);
                controls[i]=lv_slider_create(row); ui_widget_style(controls[i]);
                lv_obj_set_width(controls[i],LV_PCT(100));
                lv_slider_set_range(controls[i],parameters[i].low,parameters[i].high);
                ui_control(controls[i]);
            }
            lv_obj_add_event_cb(controls[i],parameter_changed,LV_EVENT_VALUE_CHANGED,
                                (void *)(uintptr_t)i);
        }
        ui_action_button(row,"本项恢复默认",100+stage);
    }
    if (ui_live_scene()==6) {
        lv_obj_add_state(autoplay_switch,LV_STATE_CHECKED);
        lv_obj_send_event(autoplay_switch,LV_EVENT_VALUE_CHANGED,NULL);
    }
    ui_hint("前后键选择 · Enter 编辑 · 编辑时前后键调整 · Enter / Esc 退出编辑");
}
