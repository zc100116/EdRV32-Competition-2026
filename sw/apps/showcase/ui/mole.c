/* mole.c — T-GAMES-MORE; random visible targets, gold bonuses and bomb penalties.
 * CPU domain; only a valid open-to-grab input edge can consume a target.
 */
#include "mole.h"
#include <string.h>
void mole_center(unsigned hole, int *x, int *y)
{
    *x = MOLE_X + (int)(hole % MOLE_COLUMNS) * MOLE_COLUMN_STEP;
    *y = MOLE_Y + (int)(hole / MOLE_COLUMNS) * MOLE_ROW_STEP;
}
void mole_init(mole_state_t *s, uint32_t seed)
{
    memset(s,0,sizeof *s);
    s->rng = seed | 1u;
    s->speed = GAME_SLOW;
}
void mole_input(mole_state_t *s, int x, int y, bool closed, bool present)
{
    if (!present || s->done) return;
    bool edge = closed && !s->closed;
    s->closed = closed;
    if (!edge) return;
    for (unsigned i = 0; i < MOLE_HOLES; ++i) {
        int cx, cy;
        mole_center(i,&cx,&cy);
        int dx = x-cx;
        int dy = y-cy;
        mole_hole_t *h = &s->holes[i];
        if (h->life && dx*dx+dy*dy <= MOLE_RADIUS*MOLE_RADIUS) {
            s->score += h->kind == 2 ? MOLE_BOMB_SCORE :
                        h->kind == 1 ? MOLE_GOLD_SCORE : MOLE_NORMAL_SCORE;
            h->life = 0;
            h->flash = MOLE_FLASH;
            return;
        }
    }
}
void mole_step(mole_state_t *s)
{
    if (s->done) return;
    ++s->ticks;
    for (unsigned i = 0; i < MOLE_HOLES; ++i) {
        if (s->holes[i].life) --s->holes[i].life;
        if (s->holes[i].flash) --s->holes[i].flash;
    }
    if (s->ticks == MOLE_SECONDS*GAME_HZ) { s->done = true; return; }
    if (s->ticks % (MOLE_SPAWN*4/s->speed)) return;
    unsigned i = game_random(&s->rng) % MOLE_HOLES;
    mole_hole_t *h = &s->holes[i];
    if (h->life || h->flash) return; /* This random hole is already occupied. */
    unsigned span = MOLE_LIFE_MAX - s->ticks / MOLE_RAMP;
    if (span < MOLE_LIFE_MIN) span = MOLE_LIFE_MIN;
    h->life = (MOLE_LIFE_MIN + game_random(&s->rng) % (span-MOLE_LIFE_MIN+1))*4/s->speed;
    unsigned kind = game_random(&s->rng) % MOLE_CHANCES;
    h->kind = kind < MOLE_NORMAL_CHANCES ? 0 : kind == MOLE_NORMAL_CHANCES ? 1 : 2;
}
