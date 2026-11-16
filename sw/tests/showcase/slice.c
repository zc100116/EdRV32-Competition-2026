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
    assert(!slice_fast(35,0,100)); /* Exactly 350 px/s is not enough. */
    assert(slice_fast(36,0,100));
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
    assert(s.cursor_valid && s.trail_count == 1);
    s.objects[0] = (slice_object_t){{200*GAME_Q,300*GAME_Q,0,0},0,true,false};
    s.previous[0][0] = 200;
    s.previous[0][1] = 300;
    slice_input(&s,0,0,false,1150);
    slice_input(&s,300,300,true,1200);
    assert(s.score == 10); /* Two missing samples still connect. */
    slice_init(&s,123);
    slice_input(&s,100,300,true,1000);
    for (unsigned i = 0; i < 3; ++i) slice_input(&s,0,0,false,1050+i*50);
    assert(!s.cursor_valid && !s.trail_count);
    s.objects[0] = (slice_object_t){{200*GAME_Q,300*GAME_Q,0,0},0,true,false};
    slice_input(&s,300,300,true,1200);
    assert(s.objects[0].active);
    /* Moving circle crosses the blade between samples, but ends far away. */
    slice_init(&s,123);
    s.objects[0] = (slice_object_t){{200*GAME_Q,200*GAME_Q,0,0},0,true,false};
    slice_input(&s,100,300,true,1000);
    s.objects[0].body.y = 400*GAME_Q;
    slice_input(&s,366,300,true,1100);
    assert(s.score == 10 && s.hits == 1 && s.segments == 1 && s.fast_segments == 1);
    /* Finger allowance hits at 60 px; nearby misses include slow sweeps. */
    slice_init(&s,123);
    s.objects[0] = (slice_object_t){{200*GAME_Q,360*GAME_Q,0,0},0,true,false};
    slice_input(&s,100,300,true,1000);
    slice_input(&s,366,300,true,1100);
    assert(s.score == 10);
    slice_init(&s,123);
    s.objects[0] = (slice_object_t){{200*GAME_Q,361*GAME_Q,0,0},0,true,false};
    slice_input(&s,100,300,true,1000);
    slice_input(&s,366,300,true,1100);
    assert(s.score == 0 && s.near_misses == 1);
    slice_init(&s,123);
    s.objects[0] = (slice_object_t){{200*GAME_Q,300*GAME_Q,0,0},0,true,false};
    slice_input(&s,200,300,true,1000);
    slice_input(&s,210,300,true,1100);
    assert(s.score == 0 && !s.fast_segments && s.near_misses == 1);
    for (unsigned speed = GAME_SLOW; speed <= GAME_FAST; ++speed) {
        slice_init(&s,123);
        s.speed = speed;
        s.ticks = 1;
        s.objects[0] = (slice_object_t){{640*GAME_Q,400*GAME_Q,4*GAME_Q,-8*GAME_Q},
                                     0,true,false};
        slice_step(&s);
        assert(s.objects[0].body.x == 640*GAME_Q+GAME_Q*(int)speed);
        assert(s.objects[0].body.vy == -8*GAME_Q+SLICE_GRAVITY*(int)speed/4);
        assert(s.objects[0].body.y == 400*GAME_Q-2*GAME_Q*(int)speed+
               SLICE_GRAVITY*(int)(speed*speed)/32);
    }
    puts("PASS slice: 350 px/s, finger allowance, moving circles, two-frame loss bridge, "
         "three-frame break, segment/fast/hit/near counters, halves and finish");
}
