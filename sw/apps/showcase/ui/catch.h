/* catch.h — T-GAMES-MORE; capped horizontal basket motion and falling fruit.
 * CPU domain; 30 Hz Q8 motion, scores and flash duration are tunable constants.
 */
#ifndef SHOWCASE_CATCH_H
#define SHOWCASE_CATCH_H
#include "game_math.h"
enum { CATCH_OBJECTS = 6, CATCH_SECONDS = 60, CATCH_Y = 600, CATCH_WIDTH = 150,
       CATCH_RADIUS = 30, CATCH_RIM = 570, CATCH_SPEED = 30*GAME_Q,
       CATCH_SPAWN = 18, CATCH_FALL_START = 5, CATCH_FALL_RAMP = 180,
       CATCH_FRUIT_SCORE = 10, CATCH_BOMB_SCORE = -30, CATCH_FLASH = 12,
       CATCH_STAR_TWO = 100, CATCH_STAR_THREE = 250, CATCH_TYPES = 4,
       CATCH_BOMB_CHANCE = 8, CATCH_SPAWN_X = 100, CATCH_SPAWN_RANGE = 1080,
       CATCH_EXIT_Y = 760 };
typedef struct { int x, y, vy; unsigned kind; bool active, bomb; } catch_fruit_t;
typedef struct {
    catch_fruit_t fruit[CATCH_OBJECTS];
    int basket_x, target_x, score;
    unsigned ticks, flash;
    bool done;
    uint32_t rng;
} catch_state_t;
void catch_init(catch_state_t *s, uint32_t seed);
void catch_input(catch_state_t *s, int x, bool present);
void catch_step(catch_state_t *s);
#endif
