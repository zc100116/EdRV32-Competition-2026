/* theme.h — showcase design §3/4.1; shared B palette and static styles.
 * All objects belong to the UI thread and use the LVGL tick clock.
 */
#ifndef UI_THEME_H
#define UI_THEME_H
#include "lvgl.h"
#include "ui_data.h"
#define BG 0xeff3f8
#define PANEL 0xffffff
#define SELECTED 0xeaf2ff
#define LINE 0xd6e0ec
#define TEXT 0x152b45
#define MUTED 0x61748b
#define ACCENT 0x2563EB
#define TEAL 0x0D9488
#define DISABLED 0xe4e9f0
LV_FONT_DECLARE(sim_font_14);
LV_FONT_DECLARE(sim_font_16);
LV_FONT_DECLARE(sim_font_20);
LV_FONT_DECLARE(sim_font_28);
LV_FONT_DECLARE(sim_font_40);
LV_FONT_DECLARE(sim_digits_40);
void theme_init(void);
lv_obj_t *ui_box(lv_obj_t *p, int x, int y, int w, int h, uint32_t color);
lv_obj_t *ui_label(lv_obj_t *p, const char *s, int x, int y,
                   const lv_font_t *font, uint32_t color);
void ui_text(lv_obj_t *label, const char *text);
void ui_bar(lv_obj_t *p, int x, int y, int w, int value, uint32_t color);
void ui_picture(lv_obj_t *p, const lv_image_dsc_t *src, int x, int y, int w, int h);
void ui_title(lv_obj_t *p, const char *title);
void ui_video_surface(lv_obj_t *p);
void ui_start(void);
void ui_suspend(bool paused);
void ui_open(unsigned page);
void ui_key(uint32_t key);
void ui_back(void);
void ui_monitor_init(void);
void ui_monitor_controls(void);
void ui_monitor_toggle(void);
void ui_monitor_suppress(bool hide);
void ui_hide_interface(void);
bool ui_restore_interface(void);
bool ui_interface_hidden(void);
void ui_monitor_corner(void);
bool ui_monitor_visible(void);
void ui_monitor_parent(lv_obj_t *parent, bool compact);
void ui_monitor_position(int *x, int *y);
void ui_process_action(unsigned action);
void ui_refresh(void);
void ui_process_update(void);
void ui_button(lv_obj_t *p, const char *s, int x, int y, int w, unsigned action);
void ui_hint(const char *s);
void ui_page_home(lv_obj_t *p);
void ui_page_vision(lv_obj_t *p);
void ui_page_image(lv_obj_t *p);
void ui_page_process(lv_obj_t *p);
void ui_page_graphics(lv_obj_t *p);
void ui_page_games(lv_obj_t *p);
void ui_page_chip(lv_obj_t *p);
void ui_page_debug(lv_obj_t *p);
void ui_vision_update(bool batch);
void ui_vision_frame(bool batch);
void ui_monitor_update(void);
void ui_chip_update(void);
void ui_graphics_update(void);
void ui_benchmark_controls(bool show);
void ui_debug_update(void);
void ui_vision_build(lv_obj_t *p, bool batch);
extern unsigned ui_page;
extern unsigned ui_tab;
extern unsigned ui_mode;
bool ui_game_active(void);
void ui_control(lv_obj_t *obj);
void ui_control_style(lv_obj_t *obj);
lv_obj_t *ui_switch(lv_obj_t *p, int x, int y);
lv_obj_t *ui_dropdown(lv_obj_t *p, int x, int y, int w, const char *options);
lv_obj_t *ui_slider(lv_obj_t *p, int x, int y, int w, int low, int high);
extern bool ui_detection_settings;
#endif
