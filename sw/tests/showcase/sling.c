/* sling.c — T-GAME-SLING host acceptance; integer reference trajectories and rules. */
#include "sling.h"
#include <assert.h>
#include <stdio.h>
static sling_state_t s;
static void input(int x, int y, bool closed)
{
    sling_input(&s, x, y, closed, 0, closed ? 1 : 0);
}
static void pull(void)
{
    sling_init(&s);
    input(SLING_X, SLING_Y, true);
    assert(s.phase == SLING_AIM);
    input(80, 470, true);
}
int main(void)
{
    sling_body_t b = {25600, 76800, 7000, -8000};
    for (int t = 1; t <= 60; ++t) {
        sling_integrate(&b);
        int x = 25600 + t * 7000;
        int y = 76800 - t * 8000 + SLING_GRAVITY * t * t / 2;
        assert(b.x == x && b.y == y); /* Exact analytic solution in Q8: 0 px error. */
    }
    sling_init(&s);
    input(351, 470, true);
    assert(s.phase == SLING_READY);
    input(260, 470, true);
    assert(s.phase == SLING_READY); /* Must enter grab near fork. */
    input(350, 470, false);
    input(350, 470, true);
    assert(s.phase == SLING_AIM); /* Inclusive 90 px boundary. */
    input(0, 0, true);
    int dx = s.ball.x / SLING_Q - SLING_X;
    int dy = s.ball.y / SLING_Q - SLING_Y;
    assert(dx * dx + dy * dy <= SLING_PULL * SLING_PULL);
    assert(dx * dx + dy * dy > 178 * 178);
    pull();
    input(80, 470, false);
    assert(s.phase == SLING_FLY && s.shots == 4);
    assert(s.ball.vx == 180 * SLING_Q * 3 / 10 && s.ball.vy == 0);
    pull();
    for (unsigned i = 1; i < SLING_LOST; ++i) {
        sling_input(&s, 0, 0, true, i, -1);
        assert(s.phase == SLING_AIM && s.shots == 5);
    }
    sling_input(&s, 0, 0, true, SLING_LOST, -1);
    assert(s.phase == SLING_READY && s.shots == 5 && s.ball.x == SLING_X * SLING_Q);
    sling_init(&s);
    s.phase = SLING_FLY;
    s.ball = (sling_body_t){s.targets[1].x * SLING_Q, s.targets[1].y * SLING_Q, 0, 0};
    sling_step(&s);
    assert(s.score == 50 && s.remaining == 5 && s.phase == SLING_FLY);
    assert(s.particles[SLING_CHIPS].life == SLING_FADE);
    s.ball = (sling_body_t){s.targets[0].x * SLING_Q, s.targets[0].y * SLING_Q, 0, 0};
    sling_step(&s);
    assert(s.score == 150 && s.phase == SLING_READY);
    for (unsigned i = 0; i < SLING_FADE; ++i) sling_step(&s);
    assert(!s.particles[0].life);
    s.phase = SLING_FLY;
    s.shots = 0;
    s.ball = (sling_body_t){1400 * SLING_Q, 0, 0, 0};
    sling_step(&s);
    assert(s.phase == SLING_DONE && sling_stars(&s) == 1);
    s.score = 200;
    assert(sling_stars(&s) == 2);
    s.score = 450;
    assert(sling_stars(&s) == 3);
    input(260, 470, true);
    for (unsigned i = 0; i < SLING_RESTART - 1; ++i) sling_step(&s);
    assert(s.phase == SLING_DONE);
    sling_step(&s);
    assert(s.phase == SLING_READY && s.shots == 5 && s.score == 0 && s.remaining == 6);
    s.remaining = 1;
    for (unsigned i = 0; i < SLING_TARGETS - 1; ++i) s.targets[i].alive = false;
    s.phase = SLING_FLY;
    s.ball = (sling_body_t){s.targets[5].x * SLING_Q, s.targets[5].y * SLING_Q, 0, 0};
    sling_step(&s);
    assert(s.phase == SLING_DONE && s.shots == 5);
    sling_init(&s); /* Same reset operation used by the button. */
    assert(s.phase == SLING_READY && s.targets[5].alive);
    puts("PASS sling: exact Q8 parabola, grab edge, circular pull, release, loss cancel, "
         "crate/balloon score, fragments, ammo/clear end, stars, fist/button restart");
}
