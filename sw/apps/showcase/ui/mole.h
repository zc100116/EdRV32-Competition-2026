/* mole.h — T-GAMES-MORE; six-hole gesture-edge hit game and tunable constants.
 * CPU domain; lifetime and hit animation advance at 30 Hz.
 */
#ifndef SHOWCASE_MOLE_H
#define SHOWCASE_MOLE_H
#include "game_math.h"
enum { MOLE_HOLES = 6, MOLE_RADIUS = 70, MOLE_SECONDS = 45,
       MOLE_LIFE_MIN = 27, MOLE_LIFE_MAX = 42, MOLE_FLASH = 9,
       MOLE_SPAWN = 15, MOLE_NORMAL_SCORE = 10, MOLE_GOLD_SCORE = 30,
       MOLE_BOMB_SCORE = -20, MOLE_STAR_TWO = 100, MOLE_STAR_THREE = 250,
       MOLE_X = 360, MOLE_Y = 330, MOLE_COLUMNS = 3,
       MOLE_COLUMN_STEP = 280, MOLE_ROW_STEP = 170, MOLE_RAMP = 3*GAME_HZ,
       MOLE_CHANCES = 10, MOLE_NORMAL_CHANCES = 8 };
typedef struct { unsigned life, flash, kind; } mole_hole_t;
typedef struct {
    mole_hole_t holes[MOLE_HOLES];
    unsigned ticks;
    int score;
    bool closed, done;
    unsigned speed;
    uint32_t rng;
} mole_state_t;
void mole_center(unsigned hole, int *x, int *y);
void mole_init(mole_state_t *s, uint32_t seed);
void mole_input(mole_state_t *s, int x, int y, bool closed, bool present);
void mole_step(mole_state_t *s);
#endif
