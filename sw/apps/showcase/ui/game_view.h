/* game_view.h — T-GAMES-MORE; shared ARGB sprite rendering and arcade views.
 * GUI domain; movement invalidates the union of the old and new image bounds.
 */
#ifndef SHOWCASE_GAME_VIEW_H
#define SHOWCASE_GAME_VIEW_H
#include "theme.h"
#include "motion.h"
lv_obj_t *game_sprite(lv_obj_t *parent, const lv_image_dsc_t *src, int x, int y);
void game_image(lv_obj_t *o, const lv_image_dsc_t *src, int x, int y, bool show, unsigned opa);
void game_dirty(lv_obj_t *frame, int x, int y, int nx, int ny, int radius);
void ui_page_motion(lv_obj_t *p);
void ui_motion_action(unsigned action);
bool ui_motion_back(void);
void ui_sling_build(lv_obj_t *parent);
void ui_sling_sync(void);
void ui_sling_draw(lv_layer_t *layer);
void ui_arcade_build(lv_obj_t *parent, lv_obj_t *labels);
void ui_arcade_sync(void);
void ui_arcade_draw(lv_layer_t *layer);
#endif
