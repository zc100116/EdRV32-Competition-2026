/* live_demo.h — live demo L1–L3; shared scene navigation, GUI task clock. */
#ifndef SHOWCASE_LIVE_DEMO_H
#define SHOWCASE_LIVE_DEMO_H
#include "widgets.h"
enum { LIVE_DEMO_PAGE = 21, LIVE_DEMO_DIRECTORY = 255 };
unsigned ui_live_scene(void);
void ui_live_exit(void);
void ui_live_command(unsigned action, unsigned arg);
void ui_live_directory(lv_obj_t *parent);
void ui_live_refresh(void);
void ui_live_banner(lv_obj_t *parent);
bool ui_live_back(void);
void ui_preset_controls(lv_obj_t *parent);
void ui_preprocess_tag(lv_obj_t *parent);
void ui_preprocess_refresh(void);
void ui_preprocess_reset(void);
void ui_preprocess_advanced(lv_obj_t *parent);
#endif
