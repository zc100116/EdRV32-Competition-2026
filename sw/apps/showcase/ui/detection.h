/* detection.h — showcase 4.5.10; shared display filter and COCO labels. */
#ifndef SHOWCASE_DETECTION_H
#define SHOWCASE_DETECTION_H
#include "ui_data.h"
extern const char *const ui_coco_names[80];
void ui_detection_filter(ui_vision_t *out,const ui_detection_t *raw,unsigned count);
void ui_page_detection_settings(lv_obj_t *parent);
void ui_detection_settings_action(unsigned action);
#endif
