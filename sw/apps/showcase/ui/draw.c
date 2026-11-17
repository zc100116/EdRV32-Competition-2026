/* draw.c — T-DRAW / R5-5; low-pass smoothing and 3 px arc-length resampling.
 * Caller clock in milliseconds; only explicitly selected eraser clears alpha.
 */
#include "draw.h"
#include <math.h>
#include <string.h>
const uint32_t draw_colors[DRAW_COLORS] = {
    0xffffff,0x152b45,0xff595e,0xffa62b,0xffdf45,0x39dc97,0x45b7ff,0xc18aff
};
const unsigned draw_sizes[3] = {6,12,24};
void draw_init(draw_state_t *s)
{
    memset(s,0,sizeof *s);
    s->size = 1;
    s->hover = -1;
    s->cls = -1;
}
static bool toolbar(float x, float y)
{
    return x >= 180 && x < 1100 && y >= 72 && y < 144;
}
int draw_hover(draw_state_t *s, bool present, int x, int y, uint32_t now)
{
    int item = -1;
    if (present && x >= 192 && y >= 80 && y < 136) {
        int index = (x-192)/64;
        if (index < DRAW_ITEMS && (x-192)%64 < 56) item = index;
    }
    if (item != s->hover) {
        s->hover = item;
        s->hover_at = now;
        s->selected = false;
    }
    s->hold = item < 0 ? 0 : now-s->hover_at;
    if (s->hold > DRAW_HOLD_MS) s->hold = DRAW_HOLD_MS;
    if (item < 0 || s->hold < DRAW_HOLD_MS || s->selected) return -1;
    s->selected = true;
    return item;
}
void draw_select(draw_state_t *s, unsigned item)
{
    s->down = false;
    if (item < 8) s->color = item;
    else if (item < 11) s->size = item-8;
    else if (item < 13) s->tool = item == 11 ? DRAW_PEN : DRAW_ERASER;
}
static void emit(draw_state_t *s, draw_stamp_fn stamp, void *context, float x, float y)
{
    ++s->points;
    stamp(context,s,(int)lroundf(x),(int)lroundf(y));
}
void draw_step(draw_state_t *s, bool present, int cls, float x, float y,
               uint32_t now, draw_stamp_fn stamp, void *context)
{
    s->cls = present ? cls : -1;
    if (now-s->seen_at > 200) {
        s->down = false;
        s->visible = false;
    }
    if (!present) return;
    float dx = x-s->raw_x;
    float dy = y-s->raw_y;
    bool jump = dx*dx+dy*dy > 120*120;
    s->raw_x = x;
    s->raw_y = y;
    s->seen_at = now;
    s->visible = true;
    if (cls != DRAW_POINT || toolbar(x,y)) {
        s->down = false;
        s->x = x;
        s->y = y;
        return;
    }
    if (!s->down || jump) {
        s->x = x;
        s->y = y;
        s->carry = 0;
        s->down = true;
        ++s->strokes;
        emit(s,stamp,context,x,y);
        return;
    }
    float nx = s->x+(x-s->x)*.5f;
    float ny = s->y+(y-s->y)*.5f;
    dx = nx-s->x;
    dy = ny-s->y;
    float length = sqrtf(dx*dx+dy*dy);
    for (float distance = 3-s->carry; distance <= length; distance += 3)
        emit(s,stamp,context,s->x+dx*distance/length,s->y+dy*distance/length);
    s->carry = fmodf(s->carry+length,3);
    s->x = nx;
    s->y = ny;
}
void draw_raster(uint32_t *pixels, const draw_state_t *s, int x, int y)
{
    int size = (int)draw_sizes[s->size];
    int radius = size/2;
    for (int py = y-radius; py < y+radius; ++py) {
        if (py < 0 || py >= DRAW_HEIGHT) continue;
        for (int px = x-radius; px < x+radius; ++px) {
            if (px < 0 || px >= DRAW_WIDTH) continue;
            int dx = 2*(px-x)+1;
            int dy = 2*(py-y)+1;
            if (s->tool == DRAW_PEN && dx*dx+dy*dy > size*size) continue;
            pixels[py*DRAW_WIDTH+px] = s->tool == DRAW_ERASER ? 0 :
                0xff000000u | draw_colors[s->color];
        }
    }
}
