/* game_math.h — T-GAMES-MORE; shared integer units and deterministic random stream.
 * CPU domain; Q8 positions, 30 Hz reference units, 60 Hz fixed steps, no accelerator ownership.
 */
#ifndef SHOWCASE_GAME_MATH_H
#define SHOWCASE_GAME_MATH_H
#include <stdbool.h>
#include <stdint.h>
enum { GAME_Q = 256, GAME_HZ = 30, GAME_STEP_HZ = 60,
       GAME_SUBSTEPS = GAME_STEP_HZ/GAME_HZ,
       GAME_SAFE_LEFT = 200, GAME_SAFE_RIGHT = 1080,
       GAME_SAFE_TOP = 120, GAME_SAFE_BOTTOM = 600 };
typedef enum { GAME_SLOW = 2, GAME_MEDIUM = 3, GAME_FAST = 4 } game_speed_t;
typedef struct { int x, y, vx, vy; } game_body_t;
uint32_t game_random(uint32_t *state);
void game_integrate(game_body_t *body, int gravity);
void game_integrate_speed(game_body_t *body, int gravity, unsigned speed);
#endif
