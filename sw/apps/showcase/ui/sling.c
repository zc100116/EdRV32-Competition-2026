/* sling.c — T-GAME-SLING; 60 Hz ballistics, 30 Hz Q8 reference units, circle/AABB targets.
 * Application task; no floating point or runtime art transforms.
 */
#include "sling.h"
#include <string.h>
sling_state_t ui_sling;
static void ready(sling_state_t *s)
{
    s->ball = (sling_body_t){SLING_X * SLING_Q, SLING_Y * SLING_Q, 0, 0};
    s->phase = s->shots && s->remaining ? SLING_READY : SLING_DONE;
}
void sling_init(sling_state_t *s)
{
    memset(s, 0, sizeof *s);
    s->shots = SLING_SHOTS;
    s->remaining = SLING_TARGETS;
    s->cls = -1;
    s->cursor_x = 640;
    s->cursor_y = 360;
    for (unsigned i = 0; i < SLING_TARGETS; ++i) {
        bool balloon = i % 2;
        s->targets[i] = (sling_target_t){
            844 + (int)(i / 2) * 140 + (balloon ? 86 : 0),
            556 - (int)(i / 2) * 160 - (balloon ? 6 : 0),
            balloon ? 72 : 88, balloon ? 100 : 88, balloon, true};
    }
    ready(s);
}
/* Restoring square root keeps the circular pull limit integer-only. */
static unsigned root(unsigned n)
{
    unsigned r = 0;
    unsigned bit = 1u << 30;
    while (bit > n) bit >>= 2;
    while (bit) {
        if (n >= r + bit) { n -= r + bit; r = (r >> 1) + bit; }
        else r >>= 1;
        bit >>= 2;
    }
    return r;
}
static void aim(sling_state_t *s)
{
    int dx = s->cursor_x - SLING_X;
    int dy = s->cursor_y - SLING_Y;
    unsigned square = (unsigned)(dx * dx + dy * dy);
    if (square > SLING_PULL * SLING_PULL) {
        unsigned length = root(square);
        if (length * length < square) ++length;
        dx = dx * SLING_PULL / (int)length;
        dy = dy * SLING_PULL / (int)length;
    }
    if (SLING_X+dx < GAME_SAFE_LEFT) dx = GAME_SAFE_LEFT-SLING_X;
    if (SLING_X+dx > GAME_SAFE_RIGHT) dx = GAME_SAFE_RIGHT-SLING_X;
    if (SLING_Y+dy < GAME_SAFE_TOP) dy = GAME_SAFE_TOP-SLING_Y;
    if (SLING_Y+dy > GAME_SAFE_BOTTOM) dy = GAME_SAFE_BOTTOM-SLING_Y;
    s->ball.x = (SLING_X + dx) * SLING_Q;
    s->ball.y = (SLING_Y + dy) * SLING_Q;
}
void sling_launch_velocity(const sling_body_t *b, int32_t *vx, int32_t *vy)
{
    *vx = (SLING_X * SLING_Q - b->x) * SLING_K_NUM / SLING_K_DEN;
    *vy = (SLING_Y * SLING_Q - b->y) * SLING_K_NUM / SLING_K_DEN;
}
void sling_input(sling_state_t *s, int x, int y, bool closed, unsigned lost, int cls)
{
    bool previous = s->closed;
    s->lost = lost;
    s->present = !lost;
    s->cls = cls;
    if (lost) {
        if (lost >= SLING_LOST) {
            s->closed = false;
            if (s->phase == SLING_AIM) ready(s);
        }
        return;
    }
    s->cursor_x = x;
    s->cursor_y = y;
    s->closed = closed;
    if (s->phase == SLING_READY && closed && !previous) {
        int dx = x - SLING_X;
        int dy = y - SLING_Y;
        if (dx * dx + dy * dy <= SLING_REACH * SLING_REACH) s->phase = SLING_AIM;
    }
    if (s->phase == SLING_AIM) {
        aim(s);
        if (!closed && previous) {
            sling_launch_velocity(&s->ball, &s->ball.vx, &s->ball.vy);
            --s->shots;
            s->phase = SLING_FLY;
        }
    }
}
void sling_integrate(sling_body_t *b)
{
    b->x += b->vx/2;
    b->y += b->vy/2 + SLING_GRAVITY/8;
    b->vy += SLING_GRAVITY/2;
}
/* The view receives the aim curve as pixels, without advancing any rules. */
void sling_snapshot_copy(const sling_state_t *s, sling_state_t *destination)
{
    *destination = *s;
    if (s->phase != SLING_AIM) return;
    sling_body_t ball = s->ball;
    sling_launch_velocity(&ball,&ball.vx,&ball.vy);
    for (unsigned i = 0; i < SLING_PREVIEW; ++i) {
        sling_integrate(&ball);
        sling_integrate(&ball);
        destination->preview[i][0] = ball.x/SLING_Q;
        destination->preview[i][1] = ball.y/SLING_Q;
    }
}
static bool hit(const sling_body_t *b, const sling_target_t *t)
{
    int x = b->x / SLING_Q;
    int y = b->y / SLING_Q;
    int left = t->x - t->w / 2;
    int top = t->y - t->h / 2;
    int near_x = x < left ? left : x > left + t->w ? left + t->w : x;
    int near_y = y < top ? top : y > top + t->h ? top + t->h : y;
    int dx = x - near_x;
    int dy = y - near_y;
    return dx * dx + dy * dy <= SLING_RADIUS * SLING_RADIUS;
}
static void shatter(sling_state_t *s, unsigned target)
{
    sling_target_t *t = &s->targets[target];
    t->alive = false;
    --s->remaining;
    s->score += t->balloon ? SLING_BALLOON_SCORE : SLING_BOX_SCORE;
    for (unsigned i = 0; i < SLING_CHIPS; ++i) {
        sling_particle_t *p = &s->particles[target * SLING_CHIPS + i];
        p->body = (sling_body_t){t->x * SLING_Q, t->y * SLING_Q,
            ((int)i * 2 - 7) * 200, -(int)(4 + i % 3) * 400};
        p->life = SLING_FADE*GAME_SUBSTEPS;
        p->balloon = t->balloon;
    }
}
void sling_step(sling_state_t *s)
{
    for (unsigned i = 0; i < SLING_PARTICLES; ++i) {
        sling_particle_t *p = &s->particles[i];
        if (p->life) { sling_integrate(&p->body); --p->life; }
    }
    if (s->phase == SLING_DONE) {
        s->restart_ticks = s->present && s->cls == 1 &&
            s->cursor_x >= 420 && s->cursor_x <= 860 &&
            s->cursor_y >= 228 && s->cursor_y <= 478 ? s->restart_ticks + 1 : 0;
        if (s->restart_ticks == SLING_RESTART*GAME_SUBSTEPS) sling_init(s);
        return;
    }
    if (s->phase != SLING_FLY) return;
    sling_integrate(&s->ball);
    for (unsigned i = 0; i < SLING_TARGETS; ++i) {
        if (!s->targets[i].alive || !hit(&s->ball, &s->targets[i])) continue;
        shatter(s, i);
        if (!s->targets[i].balloon || !s->remaining) { ready(s); return; }
    }
    int x = s->ball.x / SLING_Q;
    int y = s->ball.y / SLING_Q;
    if (x < -SLING_RADIUS || x > 1280 + SLING_RADIUS || y > 720 + SLING_RADIUS)
        ready(s);
}
unsigned sling_stars(const sling_state_t *s)
{
    return s->score >= SLING_STAR_THREE ? 3 : s->score >= SLING_STAR_TWO ? 2 : 1;
}
