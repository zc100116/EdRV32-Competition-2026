/* page_detection.c — P5 3.8; native threshold slider and COCO checkboxes.
 * A scrollable visual order serves pointer, keypad and encoder input.
 */
#include "theme.h"
#include "detection.h"
static lv_obj_t *threshold,*threshold_slider,*selected,*classes[80];
static void update(void)
{
    ui_detection_config_t c=ui_data_detection_config();
    char text[80]; unsigned count=0;
    lv_snprintf(text,sizeof text,"显示门槛  %u.%02u",c.threshold/100,c.threshold%100);
    ui_text(threshold,text);
    lv_slider_set_value(threshold_slider,(int)c.threshold/5,LV_ANIM_OFF);
    for(unsigned i=0;i<80;++i) {
        bool checked=(c.classes[i/32]&(1u<<(i%32)))!=0;
        count+=checked;
        lv_obj_set_state(classes[i],LV_STATE_CHECKED,checked);
    }
    lv_snprintf(text,sizeof text,"已选择 %u / 80 类",count); ui_text(selected,text);
}
static void changed(lv_event_t *e)
{
    unsigned id=(unsigned)(uintptr_t)lv_event_get_user_data(e);
    if(id==80) ui_data_detection_threshold((unsigned)lv_slider_get_value(threshold_slider)*5);
    else ui_data_detection_class(id,lv_obj_has_state(classes[id],LV_STATE_CHECKED));
    update();
}
void ui_page_detection_settings(lv_obj_t *p)
{
    ui_title(p,"检测设置");
    threshold=ui_label(p,"",40,98,&sim_font_20,TEXT);
    threshold_slider=ui_slider(p,54,152,350,5,18);
    lv_obj_add_event_cb(threshold_slider,changed,LV_EVENT_VALUE_CHANGED,(void *)80);
    selected=ui_label(p,"",480,128,&sim_font_16,MUTED);
    ui_button(p,"全选",824,118,190,2);
    ui_button(p,"全不选",1030,118,210,3);
    lv_obj_t *grid=ui_box(p,40,184,1200,420,BG);
    lv_obj_set_style_border_width(grid,0,0);
    lv_obj_set_scrollable(grid,true); lv_obj_set_scroll_dir(grid,LV_DIR_VER);
    for(unsigned i=0;i<80;++i) {
        lv_obj_t *o=lv_checkbox_create(grid); ui_control_style(o);
        lv_obj_set_pos(o,(int)(i%6)*200+4,(int)(i/6)*52+4);
        lv_obj_set_size(o,184,40);
        lv_obj_set_style_pad_all(o,8,0);
        lv_obj_set_style_pad_column(o,8,0);
        lv_obj_set_style_bg_color(o,lv_color_hex(PANEL),LV_PART_INDICATOR);
        lv_obj_set_style_bg_opa(o,LV_OPA_COVER,LV_PART_INDICATOR);
        lv_obj_set_style_border_color(o,lv_color_hex(LINE),LV_PART_INDICATOR);
        lv_obj_set_style_border_width(o,1,LV_PART_INDICATOR);
        lv_obj_set_style_radius(o,4,LV_PART_INDICATOR);
        lv_obj_set_style_bg_color(o,lv_color_hex(TEAL),LV_PART_INDICATOR | LV_STATE_CHECKED);
        lv_obj_set_style_bg_image_src(o,LV_SYMBOL_OK,LV_PART_INDICATOR | LV_STATE_CHECKED);
        lv_obj_set_style_bg_image_recolor(o,lv_color_hex(PANEL),LV_PART_INDICATOR);
        lv_obj_set_style_bg_image_recolor_opa(o,LV_OPA_COVER,LV_PART_INDICATOR);
        lv_obj_set_style_text_color(o,lv_color_hex(PANEL),LV_PART_INDICATOR);
        lv_checkbox_set_text(o,ui_coco_names[i]); classes[i]=o;
        lv_obj_add_event_cb(o,changed,LV_EVENT_VALUE_CHANGED,(void *)(uintptr_t)i);
        ui_control(o);
    }
    update();
    ui_hint("前后键选择 · Enter 切换类别 / 编辑门槛 · Esc 返回识别画面");
}
void ui_detection_settings_action(unsigned action)
{
    ui_data_detection_all(action==2); update();
}
