/* game_view.c — T-GAMES-MORE; image-only sprites with explicit local dirty unions.
 * GUI domain; source, alpha and visibility only change when the image changes.
 */
#include "game_view.h"
#include "src/misc/lv_area_private.h"
void game_dirty(lv_obj_t *frame, int x, int y, int nx, int ny, int radius)
{
    lv_area_t old = {x-radius,y-radius,x+radius,y+radius};
    lv_area_t next = {nx-radius,ny-radius,nx+radius,ny+radius};
    lv_area_join(&old,&old,&next);
    lv_obj_invalidate_area(frame,&old);
}
lv_obj_t *game_sprite(lv_obj_t *p, const lv_image_dsc_t *src, int x, int y)
{
    lv_obj_t *o = lv_image_create(p);
    lv_image_set_src(o,src);
    lv_obj_set_pos(o,x-(int)src->header.w/2,y-(int)src->header.h/2);
    lv_obj_set_size(o,src->header.w,src->header.h);
    lv_obj_set_clickable(o,false);
    return o;
}
void game_image(lv_obj_t *o, const lv_image_dsc_t *src, int x, int y, bool show, unsigned opa)
{
    bool hidden = lv_obj_is_hidden(o);
    if (!show) { lv_obj_set_hidden(o,true); return; }
    if (lv_image_get_src(o) != src) {
        lv_image_set_src(o,src);
        lv_obj_set_size(o,src->header.w,src->header.h);
    }
    int nx = x-(int)src->header.w/2;
    int ny = y-(int)src->header.h/2;
    if (lv_obj_get_x(o) != nx || lv_obj_get_y(o) != ny) {
        /* A newly visible sprite has no old painted rectangle to erase. */
        if (!hidden) {
            lv_area_t old;
            lv_obj_get_coords(o,&old);
            lv_area_t next = {nx,ny,nx+(int)src->header.w-1,ny+(int)src->header.h-1};
            lv_area_join(&old,&old,&next);
            lv_obj_invalidate_area(lv_obj_get_parent(o),&old);
        }
        lv_obj_set_pos(o,nx,ny);
    }
    if (lv_obj_get_style_image_opa(o,0) != opa) lv_obj_set_style_image_opa(o,opa,0);
    lv_obj_set_hidden(o,false);
}
