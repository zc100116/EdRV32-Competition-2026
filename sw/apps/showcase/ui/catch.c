/* catch.c — T-GAMES-MORE; fruit crossing the basket rim scores once.
 * CPU domain; camera cursor owns x only, the basket remains at a fixed y.
 */
#include "catch.h"
#include <string.h>
void catch_init(catch_state_t *s, uint32_t seed)
{
    memset(s,0,sizeof *s);
    s->rng = seed | 1u;
    s->speed = GAME_SLOW;
    s->basket_x = s->target_x = 640*GAME_Q;
}
void catch_input(catch_state_t *s, int x, bool present)
{
    if (!present) return;
    if (x < GAME_SAFE_LEFT) x = GAME_SAFE_LEFT;
    if (x > GAME_SAFE_RIGHT) x = GAME_SAFE_RIGHT;
    s->target_x = x*GAME_Q;
}
void catch_step(catch_state_t *s)
{
    if (s->done) return;
    ++s->ticks;
    if (s->flash) --s->flash;
    int delta = s->target_x-s->basket_x;
    if (delta > CATCH_SPEED/2) delta = CATCH_SPEED/2;
    if (delta < -CATCH_SPEED/2) delta = -CATCH_SPEED/2;
    s->basket_x += delta;
    for (unsigned i = 0; i < CATCH_OBJECTS; ++i) {
        catch_fruit_t *f = &s->fruit[i];
        if (!f->active) continue;
        int old = f->y;
        f->y += f->vy/2;
        int dx = f->x-s->basket_x;
        int reach = (CATCH_WIDTH/2+CATCH_RADIUS)*GAME_Q;
        if (old < (CATCH_RIM-CATCH_RADIUS)*GAME_Q &&
            f->y >= (CATCH_RIM-CATCH_RADIUS)*GAME_Q && dx >= -reach && dx <= reach) {
            f->active = false;
            s->score += f->bomb ? CATCH_BOMB_SCORE : CATCH_FRUIT_SCORE;
            if (f->bomb) s->flash = CATCH_FLASH*GAME_SUBSTEPS;
        } else if (f->y > CATCH_EXIT_Y*GAME_Q) f->active = false;
    }
    if (s->ticks == CATCH_SECONDS*GAME_STEP_HZ) { s->done = true; return; }
    if (s->ticks % ((CATCH_SPAWN*4/s->speed)*GAME_SUBSTEPS) != 1) return;
    for (unsigned i = 0; i < CATCH_OBJECTS; ++i) if (!s->fruit[i].active) {
        catch_fruit_t *f = &s->fruit[i];
        f->active = true;
        f->x = (CATCH_SPAWN_X+(int)(game_random(&s->rng)%CATCH_SPAWN_RANGE))*GAME_Q;
        f->y = -CATCH_RADIUS*GAME_Q;
        f->vy = (CATCH_FALL_START+(int)(s->ticks/(CATCH_FALL_RAMP*GAME_SUBSTEPS)))*
                GAME_Q*(int)s->speed/4;
        f->kind = game_random(&s->rng)%CATCH_TYPES;
        f->bomb = game_random(&s->rng)%CATCH_BOMB_CHANCE == 0;
        break;
    }
}
