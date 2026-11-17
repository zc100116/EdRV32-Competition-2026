/* draw.c — T-DRAW / R5-5; One Euro filtering, Catmull-Rom and 3 px resampling.
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
    s->positive_frames = 0;
    s->negative_frames = 0;
    if (item < 8) s->color = item;
    else if (item < 11) s->size = item-8;
    else if (item < 13) s->tool = item == 11 ? DRAW_PEN : DRAW_ERASER;
}
static void emit(draw_state_t *s, draw_stamp_fn stamp, void *context, float x, float y)
{
    ++s->points;
    stamp(context,s,(int)lroundf(x),(int)lroundf(y));
}
static float distance2(draw_point_t a, draw_point_t b)
{
    float dx = a.x-b.x;
    float dy = a.y-b.y;
    return dx*dx+dy*dy;
}
bool draw_pointing(const draw_point_t p[21])
{
    float index = distance2(p[8],p[0]);
    if (index <= 1.44f*distance2(p[6],p[0])) return false;
    if (index <= 1.69f*distance2(p[12],p[0]) ||
        index <= 1.69f*distance2(p[16],p[0])) return false;
    for (unsigned tip = 12; tip <= 20; tip += 4)
        if (distance2(p[tip],p[0]) >= distance2(p[tip-2],p[0])) return false;
    return distance2(p[4],p[0]) < .5625f*index;
}
static void commit(draw_state_t *s, draw_stamp_fn stamp, void *context)
{
    s->committed = true;
    ++s->strokes;
    for (unsigned i = 0; i < s->pending_count; ++i)
        emit(s,stamp,context,s->pending[i].x,s->pending[i].y);
    s->pending_count = 0;
}
static void segment(draw_state_t *s, draw_point_t a, draw_point_t b,
                    draw_stamp_fn stamp, void *context)
{
    float dx = b.x-a.x;
    float dy = b.y-a.y;
    float length = sqrtf(dx*dx+dy*dy);
    s->length += length;
    if (!s->committed && s->length >= 10) commit(s,stamp,context);
    for (float d = 3-s->carry; d <= length; d += 3) {
        draw_point_t p = {a.x+dx*d/length,a.y+dy*d/length};
        if (s->committed) emit(s,stamp,context,p.x,p.y);
        else s->pending[s->pending_count++] = p;
    }
    s->carry = fmodf(s->carry+length,3);
}
static draw_point_t catmull(const draw_point_t p[4], float t)
{
    float t2 = t*t;
    float t3 = t2*t;
    float w0 = .5f*(-t+2*t2-t3);
    float w1 = .5f*(2-5*t2+3*t3);
    float w2 = .5f*(t+4*t2-3*t3);
    float w3 = .5f*(-t2+t3);
    return (draw_point_t){w0*p[0].x+w1*p[1].x+w2*p[2].x+w3*p[3].x,
                          w0*p[0].y+w1*p[1].y+w2*p[2].y+w3*p[3].y};
}
static void curve_segment(draw_state_t *s, draw_stamp_fn stamp, void *context)
{
    /* One-pixel subdivisions before the shared 3 px arc-length sampler. */
    float length = 0;
    for (unsigned i = 1; i < 4; ++i)
        length += sqrtf(distance2(s->curve[i-1],s->curve[i]));
    unsigned steps = (unsigned)ceilf(length)+1;
    draw_point_t previous = s->curve[1];
    for (unsigned i = 1; i <= steps; ++i) {
        draw_point_t next = catmull(s->curve,(float)i/steps);
        segment(s,previous,next,stamp,context);
        previous = next;
    }
}
static void finish(draw_state_t *s, draw_stamp_fn stamp, void *context)
{
    if (s->down && s->curve_count == 3) {
        s->curve[3] = s->curve[2];
        curve_segment(s,stamp,context);
    }
    s->down = false;
    s->positive_frames = 0;
    s->negative_frames = 0;
    s->curve_count = 0;
}
static float alpha(float cutoff, float dt)
{
    float r = 6.2831853f*cutoff*dt;
    return r/(1+r);
}
void draw_step(draw_state_t *s, bool present, int cls, bool geometry, float x, float y,
               uint32_t now, draw_stamp_fn stamp, void *context)
{
    s->cls = present ? cls : -1;
    if (now-s->seen_at > 200) {
        finish(s,stamp,context);
        s->visible = false;
    }
    if (!present) {
        s->positive_frames = 0;
        s->gap = true;
        return;
    }
    s->seen_at = now;
    s->visible = true;
    if (toolbar(x,y)) {
        finish(s,stamp,context);
        s->x = x;
        s->y = y;
        return;
    }
    bool pointing = cls == DRAW_POINT || geometry;
    if (pointing) {
        ++s->positive_frames;
        s->negative_frames = 0;
    } else {
        s->positive_frames = 0;
        ++s->negative_frames;
    }
    if (!s->down) {
        s->x = x;
        s->y = y;
        if (s->positive_frames < 2) return;
        s->down = true;
        s->raw_x = x;
        s->raw_y = y;
        s->velocity_x = 0;
        s->velocity_y = 0;
        s->filter_at = now;
        s->length = 0;
        s->carry = 0;
        s->pending_count = 1;
        s->pending[0] = (draw_point_t){x,y};
        s->committed = false;
        s->gap = false;
        s->curve[0] = s->curve[1] = (draw_point_t){x,y};
        s->curve_count = 2;
        if (s->tool == DRAW_ERASER) commit(s,stamp,context);
        return;
    }
    if (s->negative_frames >= 4) {
        finish(s,stamp,context);
        s->x = x;
        s->y = y;
        return;
    }
    float dt = (now-s->filter_at)*.001f;
    float derivative_alpha = alpha(1,dt);
    s->velocity_x += derivative_alpha*((x-s->raw_x)/dt-s->velocity_x);
    s->velocity_y += derivative_alpha*((y-s->raw_y)/dt-s->velocity_y);
    float speed = sqrtf(s->velocity_x*s->velocity_x+s->velocity_y*s->velocity_y);
    float a = alpha(.35f+.012f*speed,dt);
    draw_point_t next = {s->x+a*(x-s->x),s->y+a*(y-s->y)};
    s->filter_at = now;
    s->raw_x = x;
    s->raw_y = y;
    if (s->tool == DRAW_ERASER) {
        segment(s,(draw_point_t){s->x,s->y},next,stamp,context);
        s->gap = false;
    } else if (s->gap) {
        /* Finish the delayed spline endpoint, then bridge missing observations linearly. */
        if (s->curve_count == 3) {
            s->curve[3] = s->curve[2];
            curve_segment(s,stamp,context);
        }
        segment(s,(draw_point_t){s->x,s->y},next,stamp,context);
        s->curve[0] = s->curve[1] = next;
        s->curve_count = 2;
        s->gap = false;
    } else {
        s->curve[s->curve_count++] = next;
        if (s->curve_count == 4) {
            curve_segment(s,stamp,context);
            memmove(s->curve,s->curve+1,3*sizeof s->curve[0]);
            s->curve_count = 3;
        }
    }
    s->x = next.x;
    s->y = next.y;
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
