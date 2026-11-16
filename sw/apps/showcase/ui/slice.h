/* slice.h — T-GAMES-MORE; Q8 thrown gems, frame-speed cuts and fading halves.
 * CPU domain; cursor filter uses 3/4 new input, independently of the grab filter.
 */
#ifndef SHOWCASE_SLICE_H
#define SHOWCASE_SLICE_H
#include "game_math.h"
enum { SLICE_OBJECTS = 9, SLICE_HALVES = 2*SLICE_OBJECTS, SLICE_RADIUS = 36,
       SLICE_TRAIL = 6, SLICE_SPEED = 800, SLICE_SMOOTH_NUM = 3, SLICE_SMOOTH_DEN = 4,
       SLICE_SECONDS = 60, SLICE_MISSES = 3, SLICE_SCORE = 10, SLICE_FADE = 24,
       SLICE_WAVE = 45, SLICE_GRAVITY = 128, SLICE_HALF_VX = 4*GAME_Q,
       SLICE_STAR_TWO = 100, SLICE_STAR_THREE = 250, SLICE_TYPES = 4,
       SLICE_WAVE_MAX = 3, SLICE_BOMB_CHANCE = 10, SLICE_FLASH = 9,
       SLICE_SPAWN_X = 200, SLICE_SPAWN_RANGE = 880, SLICE_SPAWN_Y = 740,
       SLICE_EXIT_Y = 760, SLICE_LAUNCH_VX = 3*GAME_Q,
       SLICE_LAUNCH_VY_MIN = 23, SLICE_LAUNCH_VY_RANGE = 5,
       SLICE_HALF_OFFSET = 18*GAME_Q, SLICE_HALF_VY = 2*GAME_Q };
typedef struct { game_body_t body; unsigned kind; bool active, bomb; } slice_object_t;
typedef struct { game_body_t body; unsigned kind, side, life; } slice_half_t;
typedef struct {
    slice_object_t objects[SLICE_OBJECTS];
    slice_half_t halves[SLICE_HALVES];
    unsigned ticks, misses, trail_count, flash;
    int score, cursor_x, cursor_y, trail[SLICE_TRAIL][2], flash_x, flash_y;
    uint32_t stamp, rng;
    bool cursor_valid, done;
} slice_state_t;
bool slice_intersects(int ax, int ay, int bx, int by, int cx, int cy, int radius);
bool slice_fast(int dx, int dy, unsigned ms);
void slice_init(slice_state_t *s, uint32_t seed);
void slice_input(slice_state_t *s, int x, int y, bool present, uint32_t stamp);
void slice_step(slice_state_t *s);
#endif
