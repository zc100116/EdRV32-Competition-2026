/* motion.h — T-GAMES-MORE; one persistent hand session for a five-game arcade.
 * CPU/GUI cooperative domain; the lobby and restart timers use 30 Hz steps.
 */
#ifndef SHOWCASE_MOTION_H
#define SHOWCASE_MOTION_H
#include "game_math.h"
#include "rps.h"
#include "mole.h"
#include "slice.h"
#include "catch.h"
enum { MOTION_PAGE = 15, MOTION_GAMES = 5, MOTION_HOLD = GAME_HZ,
       MOTION_CARD_W = 280, MOTION_CARD_H = 170 };
typedef enum { MOTION_HALL, MOTION_SLING, MOTION_RPS, MOTION_MOLE,
               MOTION_SLICE, MOTION_CATCH } motion_game_t;
typedef struct {
    int x, y, cls;
    bool closed, present;
    unsigned lost;
} motion_hand_t;
typedef struct {
    motion_game_t game;
    motion_hand_t hand;
    int hovered;
    unsigned hold, restart, speed, duration;
    bool waiting, running;
    uint32_t rng, revision, sample;
    rps_state_t rps;
    mole_state_t mole;
    slice_state_t slice;
    catch_state_t basket;
} motion_state_t;
extern motion_state_t ui_motion;
void motion_init(void);
void motion_seed(uint32_t mtime);
void motion_select(motion_game_t game);
void motion_card(unsigned card, int *x, int *y);
int motion_hover(int x, int y);
void motion_input(int x, int y, int raw_x, int raw_y, bool closed,
                  unsigned lost, int cls, uint32_t stamp);
void motion_step(void);
void motion_start(void);
void motion_speed(unsigned speed);
void motion_finish(void);
int motion_setup_hover(int x, int y);
const char *motion_name(void);
const char *motion_speed_name(void);
bool motion_done(void);
int motion_score(void);
unsigned motion_stars(void);
#endif
