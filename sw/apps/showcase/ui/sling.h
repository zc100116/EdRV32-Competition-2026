/* sling.h — T-GAME-SLING; integer game rules and tunable prototype parameters.
 * Application task; Q8 velocities use 30 Hz reference units, integrated at 60 Hz.
 */
#ifndef SHOWCASE_SLING_H
#define SHOWCASE_SLING_H
#include "game_math.h"
#include <stdbool.h>
#include <stdint.h>
enum {
    SLING_Q = 256, SLING_HZ = 30, SLING_X = 400, SLING_Y = 470,
    SLING_REACH = 90, SLING_PULL = 180, SLING_RADIUS = 28,
    SLING_SHOTS = 5, SLING_TARGETS = 6, SLING_CHIPS = 8,
    SLING_PARTICLES = SLING_TARGETS * SLING_CHIPS,
    SLING_GRAVITY = 256, /* 900 px/s², per tick² in Q8 */
    SLING_K_NUM = 3, SLING_K_DEN = 10, /* 9 /s, per 30 Hz tick */
    SLING_LOST = 15, SLING_FADE = 24, SLING_PREVIEW = 18,
    SLING_RESTART = 30, SLING_BOX_SCORE = 100, SLING_BALLOON_SCORE = 50,
    SLING_STAR_TWO = 200, SLING_STAR_THREE = 400
};
typedef enum { SLING_READY, SLING_AIM, SLING_FLY, SLING_DONE } sling_phase_t;
typedef struct { int32_t x, y, vx, vy; } sling_body_t;
typedef struct { int x, y, w, h; bool balloon, alive; } sling_target_t;
typedef struct { sling_body_t body; unsigned life; bool balloon; } sling_particle_t;
typedef struct {
    sling_phase_t phase;
    sling_body_t ball;
    sling_target_t targets[SLING_TARGETS];
    sling_particle_t particles[SLING_PARTICLES];
    int preview[SLING_PREVIEW][2];
    int cursor_x, cursor_y, cls;
    bool closed, present;
    unsigned lost, shots, score, remaining, restart_ticks;
} sling_state_t;
extern sling_state_t ui_sling;
void sling_snapshot_copy(const sling_state_t *s, sling_state_t *destination);
void sling_init(sling_state_t *s);
void sling_input(sling_state_t *s, int x, int y, bool closed, unsigned lost, int cls);
void sling_step(sling_state_t *s);
void sling_integrate(sling_body_t *b);
void sling_launch_velocity(const sling_body_t *b, int32_t *vx, int32_t *vy);
unsigned sling_stars(const sling_state_t *s);
#endif
