/* slice.c — T-GAMES-MORE acceptance; swept cuts, speed, halves and finish conditions. */
#include "slice.h"
#include <assert.h>
#include <stdio.h>
int main(void)
{
    assert(slice_intersects(0,0,200,0,100,35,36));
    assert(!slice_intersects(0,0,200,0,100,37,36));
    assert(slice_intersects(0,0,200,0,236,0,36));
    assert(!slice_intersects(0,0,200,0,237,0,36));
    assert(slice_intersects(100,100,100,100,100,100,36));
    assert(slice_intersects(0,0,200,200,100,100,36));
    assert(!slice_fast(80,0,100)); /* Exactly 800 px/s is not enough. */
    assert(slice_fast(81,0,100));
    slice_state_t s;
    slice_init(&s,123);
    s.objects[0] = (slice_object_t){{200*GAME_Q,300*GAME_Q,0,0},2,true,false};
    slice_input(&s,100,300,true,1000);
    slice_input(&s,300,300,true,1100); /* Filtered endpoint 250; sweep crosses 200. */
    assert(s.score == 10 && !s.objects[0].active && s.halves[0].life == SLICE_FADE);
    assert(s.halves[1].life == SLICE_FADE && s.halves[0].body.vx < 0);
    assert(s.halves[1].body.vx > 0 && s.halves[0].kind == 2 && s.halves[1].side == 1);
    assert(s.trail_count == 2 && s.cursor_x == 250);
    for (unsigned i = 0; i < SLICE_FADE; ++i) slice_step(&s);
    assert(!s.halves[0].life && !s.halves[1].life);
    slice_init(&s,123);
    s.objects[0] = (slice_object_t){{200*GAME_Q,300*GAME_Q,0,0},0,true,true};
    slice_input(&s,100,300,true,1000);
    slice_input(&s,300,300,true,1100);
    assert(s.done && s.score == 0);
    slice_init(&s,123);
    for (unsigned i = 0; i < 3; ++i)
        s.objects[i] = (slice_object_t){{200*GAME_Q,761*GAME_Q,0,1},0,true,false};
    slice_step(&s);
    assert(s.done && s.misses == 3);
    slice_init(&s,123);
    s.ticks = SLICE_SECONDS*GAME_HZ-1;
    slice_step(&s);
    assert(s.done);
    slice_init(&s,123);
    slice_input(&s,100,300,true,1000);
    slice_input(&s,0,0,false,1100);
    assert(!s.cursor_valid && !s.trail_count);
    s.objects[0] = (slice_object_t){{200*GAME_Q,300*GAME_Q,0,0},0,true,false};
    slice_input(&s,300,300,true,1200);
    assert(s.objects[0].active); /* Reappearing hand cannot cut across the missing interval. */
    puts("PASS slice: tangent/end/zero-length/diagonal segments, strict 800 px/s, "
         "light smoothing, two separating halves/fade, bomb/3-miss/time end and trail break");
}
