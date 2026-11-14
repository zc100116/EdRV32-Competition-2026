/* page_process.c — P5 design 3.6/8.3; PIX → GEO stages and retained parameters.
 * L1 scroll panel; changes use the frozen backend contract on the UI thread.
 */
#include "theme.h"
#include <stddef.h>
static bool collapsed;
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
    (void)ui_data_process(0);
    ui_process_config_t c=ui_data_process_config();
    lv_obj_set_state(view_switch,LV_STATE_CHECKED,c.original);
    if(collapsed) return;
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
    unsigned i=(unsigned)(uintptr_t)lv_event_get_user_data(e);
    ui_process_config_t c=ui_data_process_config();
    lv_obj_t *o=lv_event_get_target_obj(e);
    *field(&c,i)=i==3 || i==4 ? (int)lv_dropdown_get_selected(o)+1 : lv_slider_get_value(o);
    ui_data_process_set(&c); ui_process_update();
}
static void enabled_changed(lv_event_t *e)
{
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
    if(action==0) { collapsed=!collapsed; ui_open(3); return; }
    if(action==2) ui_data_process_defaults(UI_PROC_ALL);
    else if(action>=100) ui_data_process_defaults(1u<<(action-100));
    ui_process_update();
}
void ui_page_process(lv_obj_t *p)
{
    ui_video_surface(p);
    ui_label(p,"图像处理",24,12,&sim_font_28,TEXT);
    ui_button(p,collapsed ? "展开参数" : "收起参数",660,6,156,0);
    ui_label(p,"原图",842,17,&sim_font_16,TEXT);
    view_switch=ui_switch(p,894,14);
    lv_obj_add_event_cb(view_switch,enabled_changed,LV_EVENT_VALUE_CHANGED,(void *)12);
    ui_button(p,"全部恢复默认",982,6,282,2);
    if(collapsed) return;
    lv_obj_t *panel=ui_box(p,834,62,430,548,PANEL);
    lv_obj_set_style_bg_opa(panel,LV_OPA_90,0);
    lv_obj_set_scrollable(panel,true); lv_obj_set_scroll_dir(panel,LV_DIR_VER);
    lv_obj_set_style_width(panel,4,LV_PART_SCROLLBAR);
    lv_obj_set_style_bg_color(panel,lv_color_hex(MUTED),LV_PART_SCROLLBAR);
    lv_obj_set_style_bg_opa(panel,LV_OPA_40,LV_PART_SCROLLBAR);
    lv_obj_set_style_pad_bottom(panel,20,0);
    const char *names[]={"亮度 / 对比度","伽马","第一级滤波 S1","第二级滤波 S2",
        "灰度","二值化","反色","旋转","缩放","平移","水平镜像","垂直镜像"};
    ui_label(panel,"摄像头 → PIX → GEO → 显示",20,16,&sim_font_16,TEAL);
    int y=54;
    for(unsigned stage=0;stage<12;++stage) {
        if(stage==0 || stage==7) {
            ui_label(panel,stage==0 ? "PIX  ↓ 点运算 → S1 → S2 → 点运算" :
                "GEO  ↓ 旋转 → 缩放 → 平移 → 镜像",20,y,&sim_font_14,ACCENT);
            y+=34;
        }
        unsigned count=0;
        for(unsigned i=0;i<10;++i) count+=parameters[i].stage==stage;
        lv_obj_t *row=ui_box(panel,14,y,398,100+(int)count*62,PANEL);
        enables[stage]=ui_switch(row,16,16);
        lv_obj_add_event_cb(enables[stage],enabled_changed,LV_EVENT_VALUE_CHANGED,
            (void *)(uintptr_t)stage);
        ui_label(row,names[stage],74,16,&sim_font_20,TEXT);
        int py=54;
        for(unsigned i=0;i<10;++i) if(parameters[i].stage==stage) {
            if(i==3 || i==4) {
                controls[i]=ui_dropdown(row,18,py,360,"均值\n高斯\n锐化\nSobel\n腐蚀\n膨胀");
            } else {
                values[i]=ui_label(row,"",18,py,&sim_font_14,MUTED);
                controls[i]=ui_slider(row,24,py+34,344,parameters[i].low,parameters[i].high);
            }
            lv_obj_add_event_cb(controls[i],parameter_changed,LV_EVENT_VALUE_CHANGED,
                (void *)(uintptr_t)i);
            py+=62;
        }
        ui_button(row,"本项恢复默认",18,py,360,100+stage);
        y+=112+(int)count*62;
    }
    ui_hint("前后键选择 · Enter 编辑 · 编辑时前后键调整 · Enter / Esc 退出编辑");
}
