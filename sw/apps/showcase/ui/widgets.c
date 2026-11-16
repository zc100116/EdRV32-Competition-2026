/* widgets.c — R4 design §5; LVGL components with flex and shared design tokens.
 * GUI clock. Gradient badges and scene cards are static-area styles only.
 * Dynamic widgets deliberately use opaque fills without shadows or blur.
 */
#include "widgets.h"
/* R4 explicitly requires lv_menu, deprecated in the locked LVGL 9.6 API. */
LV_DEPRECATIONS_IGNORE_BEGIN
static void action(lv_event_t *event)
{
    ui_activate((unsigned)(uintptr_t)lv_event_get_user_data(event));
}
lv_obj_t *ui_stack(lv_obj_t *parent, lv_flex_flow_t flow, int gap)
{
    lv_obj_t *o = lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_set_size(o,LV_PCT(100),LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(o,flow);
    lv_obj_set_style_pad_gap(o,gap,0);
    lv_obj_set_scrollable(o,false);
    return o;
}
lv_obj_t *ui_text_label(lv_obj_t *parent, const char *text,
                        const lv_font_t *font, uint32_t color)
{
    lv_obj_t *o = lv_label_create(parent);
    lv_obj_set_style_text_font(o,font,0);
    lv_obj_set_style_text_color(o,lv_color_hex(color),0);
    lv_label_set_text(o,text);
    return o;
}
lv_obj_t *ui_action_button(lv_obj_t *parent, const char *text, unsigned id)
{
    lv_obj_t *o = lv_button_create(parent);
    ui_widget_style(o);
    lv_obj_set_size(o,LV_SIZE_CONTENT,40);
    lv_obj_set_flex_flow(o,LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(o,LV_FLEX_ALIGN_CENTER,LV_FLEX_ALIGN_CENTER,LV_FLEX_ALIGN_CENTER);
    ui_text_label(o,text,&sim_font_16,TEXT);
    lv_obj_add_event_cb(o,action,LV_EVENT_CLICKED,(void *)(uintptr_t)id);
    ui_control(o);
    return o;
}
static lv_obj_t *card(lv_obj_t *parent, unsigned required, unsigned id)
{
    lv_obj_t *o = ui_action_button(parent,"",id);
    lv_obj_clean(o);
    lv_obj_set_style_radius(o,UI_RADIUS_LG,0);
    lv_obj_set_style_pad_all(o,UI_SPACE_MD,0);
    lv_obj_set_style_pad_gap(o,UI_SPACE_SM,0);
    lv_obj_set_flex_align(o,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_CENTER,LV_FLEX_ALIGN_CENTER);
    if ((ui_data_hardware() & required) != required) lv_obj_add_state(o,LV_STATE_DISABLED);
    return o;
}
lv_obj_t *ui_app_card(lv_obj_t *parent, const lv_image_dsc_t *icon,
                      const char *name, const char *description,
                      unsigned required, unsigned id)
{
    lv_obj_t *o = card(parent,required,id);
    lv_obj_set_size(o,282,124);
    lv_obj_t *image = lv_image_create(o);
    lv_image_set_src(image,icon);
    lv_obj_set_size(image,72,72);
    lv_image_set_inner_align(image,LV_IMAGE_ALIGN_STRETCH);
    lv_obj_t *copy = ui_stack(o,LV_FLEX_FLOW_COLUMN,UI_SPACE_XS);
    lv_obj_set_flex_grow(copy,1);
    lv_obj_t *label = ui_text_label(copy,name,&sim_font_20,TEXT);
    lv_obj_set_width(label,LV_PCT(100));
    label = ui_text_label(copy,lv_obj_has_state(o,LV_STATE_DISABLED) ?
                          "当前硬件无此模块" : description,&sim_font_14,MUTED);
    lv_obj_set_width(label,LV_PCT(100));
    lv_label_set_long_mode(label,LV_LABEL_LONG_DOT);
    return o;
}
lv_obj_t *ui_scene_card(lv_obj_t *parent, const lv_image_dsc_t *art,
                        const char *title, const char *description,
                        unsigned required, unsigned id)
{
    lv_obj_t *o = card(parent,required,id);
    lv_obj_set_size(o,LV_PCT(49),200);
    lv_obj_set_style_bg_color(o,lv_color_hex(SELECTED),0);
    lv_obj_t *copy = ui_stack(o,LV_FLEX_FLOW_COLUMN,UI_SPACE_SM);
    lv_obj_set_width(copy,LV_PCT(57));
    lv_obj_t *label = ui_emphasis(copy,title,false);
    lv_obj_set_width(label,LV_PCT(100));
    label = ui_text_label(copy,description,&sim_font_16,MUTED);
    lv_obj_set_width(label,LV_PCT(100));
    lv_obj_t *image = lv_image_create(o);
    lv_image_set_src(image,art);
    lv_obj_set_size(image,216,150);
    lv_image_set_inner_align(image,LV_IMAGE_ALIGN_CONTAIN);
    return o;
}
static void segment_key(lv_event_t *event)
{
    uint32_t key = lv_event_get_key(event);
    if (key == LV_KEY_LEFT || key == LV_KEY_RIGHT) {
        lv_obj_t *o = lv_event_get_target_obj(event);
        unsigned selected = lv_buttonmatrix_get_selected_button(o);
        lv_buttonmatrix_set_button_ctrl(o,selected,LV_BUTTONMATRIX_CTRL_CHECKED);
        lv_obj_send_event(o,LV_EVENT_VALUE_CHANGED,NULL);
    }
}
lv_obj_t *ui_segment(lv_obj_t *parent, const char *const *map, unsigned selected)
{
    lv_obj_t *o = lv_buttonmatrix_create(parent);
    ui_widget_style(o);
    lv_buttonmatrix_set_map(o,map);
    lv_buttonmatrix_set_button_ctrl_all(o,LV_BUTTONMATRIX_CTRL_CHECKABLE);
    lv_buttonmatrix_set_one_checked(o,true);
    lv_buttonmatrix_set_selected_button(o,selected);
    lv_buttonmatrix_set_button_ctrl(o,selected,LV_BUTTONMATRIX_CTRL_CHECKED);
    lv_obj_set_size(o,360,44);
    lv_obj_add_event_cb(o,segment_key,LV_EVENT_KEY,NULL);
    ui_control(o);
    return o;
}
static lv_obj_t *row(lv_obj_t *parent, const char *text)
{
    lv_obj_t *o = lv_menu_cont_create(parent);
    lv_obj_set_width(o,LV_PCT(100));
    lv_obj_set_style_pad_all(o,UI_SPACE_SM,0);
    lv_obj_set_style_pad_gap(o,UI_SPACE_SM,0);
    lv_obj_set_flex_align(o,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_CENTER,LV_FLEX_ALIGN_CENTER);
    lv_obj_t *label = ui_text_label(o,text,&sim_font_20,TEXT);
    lv_obj_set_flex_grow(label,1);
    return o;
}
lv_obj_t *ui_switch_row(lv_obj_t *parent, const char *text, bool checked)
{
    lv_obj_t *o = lv_switch_create(row(parent,text));
    ui_widget_style(o);
    lv_obj_set_size(o,56,30);
    if (checked) lv_obj_add_state(o,LV_STATE_CHECKED);
    ui_control(o);
    return o;
}
static void step(lv_event_t *event)
{
    lv_obj_t *button = lv_event_get_target_obj(event);
    lv_obj_t *spin = lv_event_get_user_data(event);
    if (lv_obj_get_index(button) == 1) lv_spinbox_decrement(spin);
    else lv_spinbox_increment(spin);
}
lv_obj_t *ui_number_row(lv_obj_t *parent, const char *text, int value)
{
    lv_obj_t *container = row(parent,text);
    lv_obj_t *minus = ui_action_button(container,"−",0);
    lv_obj_remove_event_cb(minus,action);
    lv_obj_t *spin = lv_spinbox_create(container);
    ui_widget_style(spin);
    lv_obj_set_size(spin,140,44);
    lv_spinbox_set_range(spin,-999,999);
    lv_spinbox_set_digit_format(spin,3,0);
    lv_spinbox_set_value(spin,value);
    lv_spinbox_set_step(spin,5);
    ui_control(spin);
    lv_obj_t *plus = ui_action_button(container,"+",0);
    lv_obj_remove_event_cb(plus,action);
    lv_obj_add_event_cb(minus,step,LV_EVENT_CLICKED,spin);
    lv_obj_add_event_cb(plus,step,LV_EVENT_CLICKED,spin);
    return spin;
}
lv_obj_t *ui_emphasis(lv_obj_t *parent, const char *text, bool large)
{
    return ui_text_label(parent,text,large ? &showcase_bold_48 : &showcase_bold_32,TEXT);
}
lv_obj_t *ui_badge(lv_obj_t *parent, const char *text)
{
    lv_obj_t *o = ui_text_label(parent,text,&sim_font_14,PANEL);
    lv_obj_set_style_bg_opa(o,LV_OPA_COVER,0);
    lv_obj_set_style_bg_color(o,lv_color_hex(ACCENT),0);
    lv_obj_set_style_bg_grad_color(o,lv_color_hex(TEAL),0);
    lv_obj_set_style_bg_grad_dir(o,LV_GRAD_DIR_HOR,0);
    lv_obj_set_style_pad_hor(o,UI_SPACE_SM,0);
    lv_obj_set_style_pad_ver(o,6,0);
    lv_obj_set_style_radius(o,LV_RADIUS_CIRCLE,0);
    return o;
}
lv_obj_t *ui_number(lv_obj_t *parent, const char *text, bool large)
{
    return ui_text_label(parent,text,large ? &showcase_digits_96 : &showcase_digits_64,ACCENT);
}
lv_obj_t *ui_hold_arc(lv_obj_t *parent, unsigned maximum)
{
    lv_obj_t *o = lv_arc_create(parent);
    ui_widget_style(o);
    lv_obj_set_size(o,64,64);
    lv_arc_set_range(o,0,(int)maximum);
    lv_arc_set_bg_angles(o,0,360);
    lv_arc_set_rotation(o,270);
    lv_arc_set_value(o,0);
    lv_obj_remove_style(o,NULL,LV_PART_KNOB);
    lv_obj_set_clickable(o,false);
    return o;
}

LV_DEPRECATIONS_IGNORE_END

/* Page roots share the shell's content bounds and use only layout positioning. */
lv_obj_t *ui_page_layout(lv_obj_t *parent, const char *title, bool camera)
{
    lv_obj_set_flex_flow(parent,LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_all(parent,UI_SPACE_LG,0);
    lv_obj_set_style_pad_gap(parent,UI_SPACE_MD,0);
    if(camera) {
        lv_obj_set_style_bg_opa(lv_obj_get_parent(parent),LV_OPA_TRANSP,0);
        lv_obj_set_style_bg_opa(parent,LV_OPA_TRANSP,0);
    }
    lv_obj_t *header=ui_stack(parent,LV_FLEX_FLOW_ROW,UI_SPACE_MD);
    lv_obj_set_flex_align(header,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_CENTER,LV_FLEX_ALIGN_CENTER);
    if(camera) {
        lv_obj_set_style_bg_color(header,lv_color_hex(PANEL),0);
        lv_obj_set_style_bg_opa(header,LV_OPA_COVER,0);
        lv_obj_set_style_radius(header,UI_RADIUS_MD,0);
        lv_obj_set_style_pad_all(header,UI_SPACE_SM,0);
    }
    lv_obj_t *label=ui_emphasis(header,title,false);
    lv_obj_set_flex_grow(label,1);
    return header;
}
lv_obj_t *ui_panel(lv_obj_t *parent, int width)
{
    lv_obj_t *panel=ui_stack(parent,LV_FLEX_FLOW_COLUMN,UI_SPACE_SM);
    lv_obj_set_width(panel,width);
    lv_obj_set_style_pad_all(panel,UI_SPACE_MD,0);
    lv_obj_set_style_bg_color(panel,lv_color_hex(PANEL),0);
    lv_obj_set_style_bg_opa(panel,LV_OPA_COVER,0);
    lv_obj_set_style_radius(panel,UI_RADIUS_MD,0);
    return panel;
}
lv_obj_t *ui_data_table(lv_obj_t *parent, unsigned columns, unsigned rows)
{
    lv_obj_t *table=lv_table_create(parent);
    ui_widget_style(table);
    lv_obj_set_width(table,LV_PCT(100));
    lv_table_set_column_count(table,columns);
    lv_table_set_row_count(table,rows);
    lv_obj_set_style_text_font(table,&sim_font_16,LV_PART_ITEMS);
    lv_obj_set_style_pad_ver(table,8,LV_PART_ITEMS);
    return table;
}
lv_obj_t *ui_select(lv_obj_t *parent, const char *options)
{
    lv_obj_t *o=lv_dropdown_create(parent);
    ui_widget_style(o); lv_dropdown_set_options(o,options);
    lv_obj_set_width(o,LV_PCT(100)); ui_control(o);
    return o;
}
lv_obj_t *ui_live_badge(lv_obj_t *parent, const char *text, uint32_t color)
{
    lv_obj_t *o=ui_text_label(parent,text,&sim_font_20,PANEL);
    lv_obj_set_width(o,LV_PCT(100));
    lv_obj_set_style_bg_color(o,lv_color_hex(color),0);
    lv_obj_set_style_bg_opa(o,LV_OPA_COVER,0);
    lv_obj_set_style_pad_all(o,UI_SPACE_XS,0);
    lv_obj_set_style_radius(o,UI_RADIUS_SM,0);
    return o;
}
/* General page controls use base flex rows; lv_menu_cont requires a menu parent. */
static lv_obj_t *flex_row(lv_obj_t *parent, const char *text)
{
    lv_obj_t *o=ui_stack(parent,LV_FLEX_FLOW_ROW,UI_SPACE_SM);
    lv_obj_set_style_pad_all(o,UI_SPACE_SM,0);
    lv_obj_set_clickable(o,false);
    lv_obj_set_flex_align(o,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_CENTER,LV_FLEX_ALIGN_CENTER);
    lv_obj_t *label=ui_text_label(o,text,&sim_font_20,TEXT);
    lv_obj_set_flex_grow(label,1);
    return o;
}
lv_obj_t *ui_flex_switch(lv_obj_t *parent, const char *text, bool checked)
{
    lv_obj_t *o=lv_switch_create(flex_row(parent,text));
    ui_widget_style(o); lv_obj_set_size(o,56,30);
    if(checked) lv_obj_add_state(o,LV_STATE_CHECKED);
    ui_control(o);
    return o;
}
lv_obj_t *ui_flex_number(lv_obj_t *parent, const char *text, int value)
{
    lv_obj_t *container=flex_row(parent,text);
    lv_obj_t *minus=ui_action_button(container,"−",0);
    lv_obj_remove_event_cb(minus,action);
    lv_obj_t *spin=lv_spinbox_create(container); ui_widget_style(spin);
    lv_obj_set_size(spin,140,44); lv_spinbox_set_range(spin,-999,999);
    lv_spinbox_set_digit_format(spin,3,0); lv_spinbox_set_value(spin,value);
    lv_spinbox_set_step(spin,5); ui_control(spin);
    lv_obj_t *plus=ui_action_button(container,"+",0);
    lv_obj_remove_event_cb(plus,action);
    lv_obj_add_event_cb(minus,step,LV_EVENT_CLICKED,spin);
    lv_obj_add_event_cb(plus,step,LV_EVENT_CLICKED,spin);
    return spin;
}
