/* game_math.h — T-GAMES-MORE; shared integer units and deterministic random stream.
 * CPU domain; Q8 positions, 30 Hz fixed game steps, no accelerator ownership.
 */
#ifndef SHOWCASE_GAME_MATH_H
#define SHOWCASE_GAME_MATH_H
#include <stdbool.h>
#include <stdint.h>
enum { GAME_Q = 256, GAME_HZ = 30 };
typedef struct { int x, y, vx, vy; } game_body_t;
uint32_t game_random(uint32_t *state);
void game_integrate(game_body_t *body, int gravity);
#endif
