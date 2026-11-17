/* page_detection.c — P5 3.8; native threshold spinbox and COCO switch rows.
 * A scrollable visual order serves pointer, keypad and encoder input.
 */
#include "widgets.h"
#include "detection.h"
static lv_obj_t *threshold,*threshold_spinbox,*selected,*classes[80],*class_mode;
static void changed(lv_event_t *e);
static void update(void)
{
    ui_detection_config_t c=ui_data_detection_config();
    char text[80]; unsigned count=0;
    lv_snprintf(text,sizeof text,"显示门槛  %u.%02u",c.threshold/100,c.threshold%100);
    ui_text(threshold,text);
    /* Spinbox setters emit VALUE_CHANGED, including display synchronization. */
    lv_obj_remove_event_cb(threshold_spinbox,changed);
    lv_spinbox_set_value(threshold_spinbox,(int)c.threshold);
    lv_obj_add_event_cb(threshold_spinbox,changed,LV_EVENT_VALUE_CHANGED,(void *)80);
    for(unsigned i=0;i<80;++i) {
        bool checked=(c.classes[i/32]&(1u<<(i%32)))!=0;
        count+=checked;
        lv_obj_set_state(classes[i],LV_STATE_CHECKED,checked);
    }
    lv_snprintf(text,sizeof text,"已选择 %u / 80 类",count); ui_text(selected,text);
    lv_dropdown_set_selected(class_mode,count==80 ? 1 : count==0 ? 2 : 0);
}
static void changed(lv_event_t *e)
{
    unsigned id=(unsigned)(uintptr_t)lv_event_get_user_data(e);
    if(id==80) ui_data_detection_threshold((unsigned)lv_spinbox_get_value(threshold_spinbox));
    else ui_data_detection_class(id,lv_obj_has_state(classes[id],LV_STATE_CHECKED));
    update();
}
static void class_mode_changed(lv_event_t *event)
{
    unsigned mode=lv_dropdown_get_selected(lv_event_get_target_obj(event));
    if(mode) ui_data_detection_all(mode==1);
    update();
}
void ui_detection_controls(lv_obj_t *p)
{
    lv_obj_t *header=p;
    class_mode=ui_select(header,"自选类别\n全选\n全不选");
    lv_obj_set_width(class_mode,240);
    lv_obj_add_event_cb(class_mode,class_mode_changed,LV_EVENT_VALUE_CHANGED,NULL);
    lv_obj_t *panel=ui_panel(p,LV_PCT(100));
    threshold=ui_text_label(panel,"",&sim_font_20,TEXT);
    threshold_spinbox=ui_flex_number(panel,"%",50);
    lv_obj_set_width(threshold_spinbox,88);
    lv_spinbox_set_range(threshold_spinbox,25,90); lv_spinbox_set_step(threshold_spinbox,5);
    lv_obj_add_event_cb(threshold_spinbox,changed,LV_EVENT_VALUE_CHANGED,(void *)80);
    selected=ui_text_label(panel,"",&sim_font_16,MUTED);
    lv_obj_t *grid=ui_stack(p,LV_FLEX_FLOW_ROW_WRAP,UI_SPACE_SM);

    lv_obj_set_scrollable(grid,true); lv_obj_set_scroll_dir(grid,LV_DIR_VER);
    for(unsigned i=0;i<80;++i) {
        lv_obj_t *cell=ui_stack(grid,LV_FLEX_FLOW_COLUMN,0);
        lv_obj_set_width(cell,LV_PCT(100));
        classes[i]=ui_flex_switch(cell,ui_coco_names[i],false);
        lv_obj_add_event_cb(classes[i],changed,LV_EVENT_VALUE_CHANGED,(void *)(uintptr_t)i);
    }
    update();
    ui_hint("前后键选择 · Enter 切换类别 / 编辑门槛 · Esc 返回识别画面");
}
void ui_page_detection_settings(lv_obj_t *p)
{
    ui_page_layout(p,"检测设置",false);
    ui_detection_controls(p);
}
void ui_detection_settings_action(unsigned action)
{
    ui_data_detection_all(action==2); update();
}
