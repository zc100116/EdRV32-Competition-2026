/* page_image.c — showcase design §4.3; batch recognition view.
 * Shares detection canvas, but owns batch actions through ui_data.
 */
#include "theme.h"
void ui_page_image(lv_obj_t *p) { ui_vision_build(p, true); }
