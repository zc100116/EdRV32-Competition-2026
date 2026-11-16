/* slice.c — T-GAMES-MORE; integer segment/circle cuts sampled per inference frame.
 * CPU domain; two pre-cropped halves separate without runtime rotation.
 */
#include "slice.h"
#include <string.h>
bool slice_intersects(int ax, int ay, int bx, int by, int cx, int cy, int radius)
{
    int64_t dx = bx-ax;
    int64_t dy = by-ay;
    int64_t px = cx-ax;
    int64_t py = cy-ay;
    int64_t length = dx*dx+dy*dy;
    int64_t projection = px*dx+py*dy;
    int64_t square = (int64_t)radius*radius;
    if (projection <= 0) return px*px+py*py <= square;
    if (projection >= length) {
        px = cx-bx;
        py = cy-by;
        return px*px+py*py <= square;
    }
    int64_t cross = px*dy-py*dx;
    return cross*cross <= square*length;
}
bool slice_fast(int dx, int dy, unsigned ms)
{
    return ((int64_t)dx*dx+(int64_t)dy*dy)*1000000 >
           (int64_t)SLICE_SPEED*SLICE_SPEED*ms*ms;
}
void slice_init(slice_state_t *s, uint32_t seed)
{
    memset(s,0,sizeof *s);
    s->rng = seed | 1u;
}
static void cut(slice_state_t *s, unsigned i)
{
    slice_object_t *o = &s->objects[i];
    o->active = false;
    s->flash = SLICE_FLASH;
    s->flash_x = o->body.x/GAME_Q;
    s->flash_y = o->body.y/GAME_Q;
    if (o->bomb) { s->done = true; return; }
    s->score += SLICE_SCORE;
    for (unsigned side = 0; side < 2; ++side) {
        slice_half_t *h = &s->halves[i*2+side];
        h->body = o->body;
        h->body.x += side ? SLICE_HALF_OFFSET : -SLICE_HALF_OFFSET;
        h->body.vx += side ? SLICE_HALF_VX : -SLICE_HALF_VX;
        h->body.vy -= SLICE_HALF_VY;
        h->kind = o->kind;
        h->side = side;
        h->life = SLICE_FADE;
    }
}
void slice_input(slice_state_t *s, int x, int y, bool present, uint32_t stamp)
{
    if (!present) { s->cursor_valid = false; s->trail_count = 0; return; }
    int ax = s->cursor_x;
    int ay = s->cursor_y;
    if (s->cursor_valid) {
        x = (ax*(SLICE_SMOOTH_DEN-SLICE_SMOOTH_NUM)+x*SLICE_SMOOTH_NUM)/SLICE_SMOOTH_DEN;
        y = (ay*(SLICE_SMOOTH_DEN-SLICE_SMOOTH_NUM)+y*SLICE_SMOOTH_NUM)/SLICE_SMOOTH_DEN;
        if (!s->done && slice_fast(x-ax,y-ay,stamp-s->stamp)) {
            for (unsigned i = 0; i < SLICE_OBJECTS; ++i) {
                slice_object_t *o = &s->objects[i];
                if (o->active && slice_intersects(ax,ay,x,y,o->body.x/GAME_Q,
                                                  o->body.y/GAME_Q,SLICE_RADIUS)) {
                    cut(s,i);
                    if (s->done) break;
                }
            }
        }
    }
    s->cursor_x = x;
    s->cursor_y = y;
    s->stamp = stamp;
    s->cursor_valid = true;
    for (unsigned i = SLICE_TRAIL-1; i; --i) {
        s->trail[i][0] = s->trail[i-1][0];
        s->trail[i][1] = s->trail[i-1][1];
    }
    s->trail[0][0] = x;
    s->trail[0][1] = y;
    if (s->trail_count < SLICE_TRAIL) ++s->trail_count;
}
static void wave(slice_state_t *s)
{
    unsigned count = 1 + game_random(&s->rng) % SLICE_WAVE_MAX;
    for (unsigned i = 0; i < SLICE_OBJECTS && count; ++i) {
        slice_object_t *o = &s->objects[i];
        if (o->active) continue;
        --count;
        o->active = true;
        o->kind = game_random(&s->rng) % SLICE_TYPES;
        o->bomb = game_random(&s->rng) % SLICE_BOMB_CHANCE == 0;
        int x = SLICE_SPAWN_X + (int)(game_random(&s->rng) % SLICE_SPAWN_RANGE);
        o->body = (game_body_t){x*GAME_Q,SLICE_SPAWN_Y*GAME_Q,
            x < 640 ? SLICE_LAUNCH_VX : -SLICE_LAUNCH_VX,
            -(SLICE_LAUNCH_VY_MIN+(int)(game_random(&s->rng)%SLICE_LAUNCH_VY_RANGE))*GAME_Q};
    }
}
void slice_step(slice_state_t *s)
{
    if (s->flash) --s->flash;
    for (unsigned i = 0; i < SLICE_HALVES; ++i) if (s->halves[i].life) {
        game_integrate(&s->halves[i].body,SLICE_GRAVITY);
        --s->halves[i].life;
    }
    if (s->done) return;
    ++s->ticks;
    for (unsigned i = 0; i < SLICE_OBJECTS; ++i) {
        slice_object_t *o = &s->objects[i];
        if (!o->active) continue;
        game_integrate(&o->body,SLICE_GRAVITY);
        if (o->body.y > SLICE_EXIT_Y*GAME_Q && o->body.vy > 0) {
            o->active = false;
            if (!o->bomb) ++s->misses;
        }
    }
    if (s->misses >= SLICE_MISSES || s->ticks == SLICE_SECONDS*GAME_HZ) s->done = true;
    if (!s->done && s->ticks % SLICE_WAVE == 1) wave(s);
}
