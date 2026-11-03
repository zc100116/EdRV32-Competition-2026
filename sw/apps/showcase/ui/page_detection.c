/* page_detection.c — showcase 4.5.10; four-key and pointer display settings.
 * Encoder navigation uses the shell's same focus group; no hardware access. */
#include "theme.h"
#include "detection.h"
static lv_obj_t *threshold,*selected,*classes[80];
static void update(void)
{
    ui_detection_config_t c=ui_data_detection_config();
    char text[80]; unsigned count=0;
    lv_snprintf(text,sizeof(text),"显示门槛  %u.%02u",c.threshold/100,c.threshold%100);
    ui_text(threshold,text);
    for(unsigned i=0;i<80;++i) {
        bool checked=(c.classes[i/32]&(1u<<(i%32)))!=0;
        count+=checked;
        lv_snprintf(text,sizeof(text),"%s  %s",checked ? LV_SYMBOL_OK : "  ",ui_coco_names[i]);
        ui_text(lv_obj_get_child(classes[i],0),text);
        lv_obj_set_style_bg_color(classes[i],lv_color_hex(checked ? SELECTED : PANEL),0);
    }
    lv_snprintf(text,sizeof(text),"已选择 %u / 80 类",count); ui_text(selected,text);
}
void ui_page_detection_settings(lv_obj_t *p)
{
    ui_title(p, "检测设置");
    threshold=ui_label(p,"",40,126,&sim_font_20,TEXT);
    ui_button(p,"−",284,118,64,0);
    ui_button(p,"+",364,118,64,1);
    selected=ui_label(p,"",480,128,&sim_font_16,MUTED);
    ui_button(p,"全选",824,118,190,2);
    ui_button(p,"全不选",1030,118,210,3);
    lv_obj_t *grid=ui_box(p,40,184,1200,420,BG);
    lv_obj_set_style_border_width(grid,0,0);
    lv_obj_set_scrollable(grid,true); lv_obj_set_scroll_dir(grid,LV_DIR_VER);
    for(unsigned i=0;i<80;++i) {
        ui_button(grid,"",(int)(i%6)*200,(int)(i/6)*48,184,i+4);
        classes[i]=lv_obj_get_child(grid,-1);
    }
    update();
    ui_hint("← → 或滚轮选择    确认修改    Esc 返回识别画面    门槛范围 0.25–0.90");
}
void ui_detection_settings_action(unsigned action)
{
    ui_detection_config_t c=ui_data_detection_config();
    if(action==0 && c.threshold>25) ui_data_detection_threshold(c.threshold-5);
    if(action==1 && c.threshold<90) ui_data_detection_threshold(c.threshold+5);
    if(action==2 || action==3) ui_data_detection_all(action==2);
    if(action>=4) {
        unsigned id=action-4;
        ui_data_detection_class(id,(c.classes[id/32]&(1u<<(id%32)))==0);
    }
    update();
}
