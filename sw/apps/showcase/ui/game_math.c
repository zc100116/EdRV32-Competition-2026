/* game_math.c — T-GAMES-MORE; integer ballistic step and 32-bit Galois LFSR.
 * CPU domain; callers seed the LFSR from board mtime with its low bit set.
 */
#include "game_math.h"
uint32_t game_random(uint32_t *state)
{
    *state = (*state >> 1) ^ ((0u - (*state & 1u)) & 0x80200003u);
    return *state;
}
void game_integrate(game_body_t *b, int gravity)
{
    b->x += b->vx/2;
    b->y += b->vy/2 + gravity/8;
    b->vy += gravity/2;
}

void game_integrate_speed(game_body_t *b, int gravity, unsigned speed)
{
    b->x += b->vx*(int)speed/8;
    b->y += b->vy*(int)speed/8 + gravity*(int)(speed*speed)/128;
    b->vy += gravity*(int)speed/8;
}
