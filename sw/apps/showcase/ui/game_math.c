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
    b->x += b->vx;
    b->y += b->vy + gravity / 2;
    b->vy += gravity;
}
