/* widgets.h — R4 design §5; thin LVGL style/layout components, GUI clock.
 * Cards and gradient badges are for static areas. Dynamic controls have no
 * shadows, blur or translucent layers and can be used over live camera video.
 */
#ifndef SHOWCASE_WIDGETS_H
#define SHOWCASE_WIDGETS_H
#include "theme.h"
void ui_widget_style(lv_obj_t *object);
lv_obj_t *ui_stack(lv_obj_t *parent, lv_flex_flow_t flow, int gap);
lv_obj_t *ui_text_label(lv_obj_t *parent, const char *text,
                        const lv_font_t *font, uint32_t color);
lv_obj_t *ui_action_button(lv_obj_t *parent, const char *text, unsigned action);
lv_obj_t *ui_app_card(lv_obj_t *parent, const lv_image_dsc_t *icon,
                      const char *name, const char *description,
                      unsigned required, unsigned action);
lv_obj_t *ui_scene_card(lv_obj_t *parent, const lv_image_dsc_t *art,
                        const char *title, const char *description,
                        unsigned required, unsigned action);
lv_obj_t *ui_segment(lv_obj_t *parent, const char *const *map, unsigned selected);
lv_obj_t *ui_switch_row(lv_obj_t *parent, const char *text, bool checked);
lv_obj_t *ui_number_row(lv_obj_t *parent, const char *text, int value);
lv_obj_t *ui_emphasis(lv_obj_t *parent, const char *text, bool large);
lv_obj_t *ui_badge(lv_obj_t *parent, const char *text);
lv_obj_t *ui_number(lv_obj_t *parent, const char *text, bool large);
lv_obj_t *ui_hold_arc(lv_obj_t *parent, unsigned maximum);
lv_obj_t *ui_page_layout(lv_obj_t *parent, const char *title, bool camera);
lv_obj_t *ui_panel(lv_obj_t *parent, int width);
lv_obj_t *ui_data_table(lv_obj_t *parent, unsigned columns, unsigned rows);
lv_obj_t *ui_select(lv_obj_t *parent, const char *options);
lv_obj_t *ui_live_badge(lv_obj_t *parent, const char *text, uint32_t color);
lv_obj_t *ui_flex_switch(lv_obj_t *parent, const char *text, bool checked);
lv_obj_t *ui_flex_number(lv_obj_t *parent, const char *text, int value);
lv_obj_t *ui_game_button(lv_obj_t *parent, const char *text,
                         int x, int y, int width, unsigned action);
void ui_game_instruction(lv_obj_t *parent, const lv_image_dsc_t *icon,
                         const char *text, int x, int y, int width);
lv_obj_t *ui_camera_layout(lv_obj_t *parent,const char *title);
lv_obj_t *ui_camera_metrics(lv_obj_t *header);
void ui_camera_metrics_update(lv_obj_t *label);
lv_obj_t *ui_camera_card(lv_obj_t *parent);
lv_obj_t *ui_camera_drawer(lv_obj_t *parent, lv_obj_t *header, const char *name);
bool ui_camera_drawer_close(void);
void ui_camera_drawer_toggle(void);
void ui_page_farm(lv_obj_t *parent);
void ui_farm_update(void);
void ui_farm_action(unsigned action);
extern bool ui_debug_overlay;
#endif
