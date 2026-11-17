/* draw.c — T-DRAW / R5-5; One Euro filtering and causal 3 px resampling.
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
    s->why = "idle";
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
    s->finger_count = 0;
    s->finger_next = 0;
    s->extrapolating = false;
    s->tracking_paused = false;
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
int draw_choose_hand(draw_state_t *s, const draw_point_t *anchors,
                     const float *areas, unsigned count, uint32_t now)
{
    int chosen = -1;
    float best = s->down ? 120*120 : 0;
    for (unsigned i = 0; i < count; ++i) {
        float value = s->down ? distance2(anchors[i],s->hand_anchor) : areas[i];
        if (s->down ? value < best : chosen < 0 || value > best) {
            best = value;
            chosen = (int)i;
        }
    }
    /* Expiration is handled by draw_hand_step, without acquiring another hand
     * in the same frame that finishes the lost stroke. */
    if (chosen >= 0 && (!s->down || now-s->seen_at <= DRAW_LOST_MS))
        s->hand_anchor = anchors[chosen];
    else chosen = -1;
    return chosen;
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
static void finish(draw_state_t *s)
{
    s->down = false;
    s->positive_frames = 0;
    s->negative_frames = 0;
    s->finger_count = 0;
    s->finger_next = 0;
    s->extrapolating = false;
    s->tracking_paused = false;
    s->confirming = false;
}
static float alpha(float cutoff, float dt)
{
    float r = 6.2831853f*cutoff*dt;
    return r/(1+r);
}
static float median3(float a, float b, float c)
{
    return fmaxf(fminf(a,b),fminf(fmaxf(a,b),c));
}
static void position_step(draw_state_t *s, bool present, int cls, bool geometry,
                          bool release, float x, float y, uint32_t now,
                          draw_stamp_fn stamp, void *context)
{
    s->cls = present ? cls : -1;
    s->why = cls == DRAW_POINT ? "class" : geometry ? "geometry" : "hold";
    if (now-s->seen_at > DRAW_LOST_MS) {
        finish(s);
        s->visible = false;
    }
    if (!present) {
        s->positive_frames = 0;
        s->negative_frames = 0;
        s->why = s->down ? "missing_hold" : "lost";
        return;
    }
    s->seen_at = now;
    s->visible = true;
    if (toolbar(x,y)) {
        s->why = "toolbar";
        finish(s);
        s->x = x;
        s->y = y;
        return;
    }
    bool pointing = (cls == DRAW_POINT && !release) || geometry;
    if (pointing) {
        ++s->positive_frames;
        s->negative_frames = 0;
    } else if (release) {
        s->positive_frames = 0;
        if (!s->negative_frames) s->release_at = now;
        ++s->negative_frames;
        s->why = "release_wait";
    } else {
        s->positive_frames = 0;
        s->negative_frames = 0;
    }
    if (!s->down) {
        s->x = x;
        s->y = y;
        if (s->positive_frames < 2) return;
        s->down = true;
        s->previous_raw = (draw_point_t){x,y};
        s->confirming = false;
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
        if (s->tool == DRAW_ERASER) commit(s,stamp,context);
        return;
    }
    if (s->negative_frames && now-s->release_at >= DRAW_RELEASE_MS) {
        finish(s);
        s->why = "release";
        s->x = x;
        s->y = y;
        return;
    }
    if (s->tracking_paused) return;
    /* Centered three-frame position median rejects isolated velocity spikes
     * before One Euro, with exactly one added frame of delay. */
    draw_point_t current = {x,y};
    if (!s->confirming) {
        s->confirmation = current;
        s->confirmation_at = now;
        s->confirming = true;
        return;
    }
    draw_point_t accepted = {
        median3(s->previous_raw.x,s->confirmation.x,x),
        median3(s->previous_raw.y,s->confirmation.y,y)
    };
    uint32_t accepted_at = s->confirmation_at;
    s->previous_raw = s->confirmation;
    s->confirmation = current;
    s->confirmation_at = now;
    x = accepted.x;
    y = accepted.y;
    now = accepted_at;
    float dt = (now-s->filter_at)*.001f;
    float derivative_alpha = alpha(1,dt);
    s->velocity_x += derivative_alpha*((x-s->raw_x)/dt-s->velocity_x);
    s->velocity_y += derivative_alpha*((y-s->raw_y)/dt-s->velocity_y);
    float speed = sqrtf(s->velocity_x*s->velocity_x+s->velocity_y*s->velocity_y);
    float a = alpha(2.5f+.012f*speed,dt);
    draw_point_t next = {s->x+a*(x-s->x),s->y+a*(y-s->y)};
    s->filter_at = now;
    s->raw_x = x;
    s->raw_y = y;
    /* Emit through the current filtered point. The former delayed spline added
     * a full frame after position confirmation; direct arc-length sampling
     * retains the same filtered trajectory without that display delay. */
    segment(s,(draw_point_t){s->x,s->y},next,stamp,context);
    s->x = next.x;
    s->y = next.y;
}
void draw_step(draw_state_t *s, bool present, int cls, bool geometry, float x, float y,
               uint32_t now, draw_stamp_fn stamp, void *context)
{
    position_step(s,present,cls,geometry,cls == 0 || cls == 1 || cls == 5,
                  x,y,now,stamp,context);
}
static float median(const float values[5], unsigned count)
{
    float sorted[5];
    memcpy(sorted,values,count*sizeof sorted[0]);
    for (unsigned i = 1; i < count; ++i) {
        float value = sorted[i];
        unsigned j = i;
        while (j && sorted[j-1] > value) {
            sorted[j] = sorted[j-1];
            --j;
        }
        sorted[j] = value;
    }
    return sorted[count/2];
}
void draw_hand_step(draw_state_t *s, bool present, int cls, const draw_point_t p[21],
                    uint32_t now, draw_stamp_fn stamp, void *context)
{
    if (!present) {
        draw_step(s,false,cls,false,s->x,s->y,now,stamp,context);
        return;
    }
    bool resumed = false;
    draw_point_t points[21];
    memcpy(points,p,sizeof points);
    float length = sqrtf(distance2(p[8],p[5]));
    float distal = sqrtf(distance2(p[8],p[7]));
    float dx = p[7].x-p[6].x;
    float dy = p[7].y-p[6].y;
    float direction2 = dx*dx+dy*dy;
    float dot = dx*(p[8].x-p[7].x)+dy*(p[8].y-p[7].y);
    bool unreliable = s->down && s->finger_count &&
        (length < .7f*median(s->finger_lengths,s->finger_count) ||
         dot <= 0 || dot*dot < .5f*direction2*distal*distal);
    if (unreliable) {
        if (!s->extrapolating) s->extrapolate_at = now;
        s->extrapolating = true;
        if (now-s->extrapolate_at > 300) {
            s->tracking_paused = true;
        }
        /* Recorded face overlap folds PIP/DIP as well as the tip. Their current
         * axis points downward, so translate the last observed MCP-relative tip
         * with the palm instead of projecting along that corrupted axis. */
        points[8] = (draw_point_t){p[5].x+s->finger_offset.x,
                                 p[5].y+s->finger_offset.y};
    } else {
        s->extrapolating = false;
        if (s->tracking_paused) {
            /* Resume at the recovered tip without painting the paused interval. */
            s->x = s->raw_x = p[8].x;
            s->y = s->raw_y = p[8].y;
            s->velocity_x = s->velocity_y = 0;
            s->filter_at = now;
            s->previous_raw = p[8];
            s->confirming = false;
            resumed = true;
        }
    }
    bool geometry = draw_pointing(p);
    if (!unreliable && (s->down || cls == DRAW_POINT || geometry)) {
        s->finger_offset = (draw_point_t){p[8].x-p[5].x,p[8].y-p[5].y};
        s->finger_lengths[s->finger_next] = length;
        s->finger_next = (s->finger_next+1)%5;
        if (s->finger_count < 5) ++s->finger_count;
    }
    bool release = cls == 0 || cls == 1 || cls == 5 ||
        distance2(p[8],p[0]) <= distance2(p[6],p[0]);
    position_step(s,true,cls,geometry,release,points[8].x,points[8].y,now,stamp,context);
    if (resumed) s->tracking_paused = false;
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
