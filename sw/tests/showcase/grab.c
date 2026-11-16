/* grab.c — T-GRAB-TEST acceptance; deterministic geometry/state/physics, host domain. */
#include "grab.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static ui_pose_point_t p[21];
static grab_state_t s;
static void hand(float x, float y, float gap)
{
    for (unsigned i = 0; i < 21; ++i) p[i] = (ui_pose_point_t){x,y,1};
    p[0].y = y + 100;
    p[9].y = y;
    p[4].x = x - gap/2;
    p[8].x = x + gap/2;
}
static bool frame(void) { return grab_frame(&s,p,0); }
int main(void)
{
    grab_init(&s);
    hand(140,600,20);
    assert(!frame() && !s.closed);
    assert(frame() && s.closed && s.held == 0 && s.picks == 1);
    hand(240,400,30); /* Hysteresis band preserves grab; cursor is smoothed. */
    assert(!frame() && s.closed);
    assert(s.x == 190 && s.y == 500);
    assert(s.objects[0].x == 190 && s.objects[0].y == 500);
    hand(240,400,50);
    assert(!frame() && s.closed);
    assert(frame() && !s.closed && s.held == -1 && s.drops == 1);
    float start = s.objects[0].y;
    grab_animate(&s,.1f);
    assert(fabsf(s.objects[0].y - start - 15) < .01f);
    assert(s.objects[0].velocity == 300);
    for (unsigned i = 0; i < 30; ++i) grab_animate(&s,1/30.f);
    assert(s.objects[0].y == 600 && !s.objects[0].falling);
    hand(240,400,30);
    assert(!frame() && !s.closed); /* The same band also preserves open. */
    hand(140,600,20);
    assert(!frame());
    p[4].visibility = .49f;
    assert(!frame() && !s.closed);
    p[4].visibility = .5f;
    assert(!frame()); /* Invisible frame broke the consecutive sequence. */
    assert(frame() && s.closed);
    p[8].visibility = 0;
    hand(140,600,60);
    p[8].visibility = 0;
    assert(!frame() && s.closed);
    grab_init(&s);
    s.objects[0].x = 100;
    s.objects[1].x = 150;
    hand(140,600,20);
    frame(); frame();
    assert(s.held == 1); /* Both in range: choose nearest. */
    for (unsigned i = 0; i < 9; ++i) assert(!grab_frame(&s,NULL,-1) && s.held == 1);
    assert(grab_frame(&s,NULL,-1) && s.held == -1 && !s.closed && s.drops == 1);
    grab_init(&s);
    hand(640,300,20);
    frame(); frame();
    assert(s.closed && s.held == -1 && s.picks == 0); /* Empty grab. */
    grab_init(&s);
    s.mode = 1;
    hand(140,600,20);
    p[12].x = p[16].x = p[20].x = 150;
    assert(!frame()); assert(frame() && s.closed && fabsf(s.d - .2f) < .001f);
    p[12].x = p[16].x = p[20].x = 200;
    assert(!frame() && s.closed); /* Mean .575, release above .55. */
    assert(frame() && !s.closed);
    grab_init(&s);
    s.mode = 3;
    hand(140,600,100);
    assert(!frame()); assert(frame() && s.held == 0);
    hand(140,600,190);
    assert(!frame() && s.closed); /* Exactly release threshold: preserve. */
    hand(140,600,200);
    assert(!frame()); assert(frame() && !s.closed);
    grab_init(&s); s.mode = 3;
    hand(140,600,100);
    p[4].x = 150; p[8].x = 170;
    frame(); frame(); assert(!s.closed); /* Same side cannot enclose center. */
    hand(140,600,160);
    frame(); frame(); assert(!s.closed); /* Beyond r+m. */
    hand(140,600,150);
    frame(); frame(); assert(s.closed && s.held == 0); /* Inclusive edge. */
    grab_init(&s); s.mode = 3;
    s.objects[0].y = 300; s.objects[0].falling = true;
    hand(140,300,100); frame(); frame();
    assert(s.held == 0 && !s.objects[0].falling); /* Regrab while falling. */
    for (int cls = 0; cls < 14; ++cls) {
        grab_init(&s); s.mode = 2;
        hand(140,600,20);
        bool closed = cls == 1 || cls == 4 || cls == 5;
        grab_frame(&s,p,cls);
        assert(s.closed == closed);
        s.closed = true;
        grab_frame(&s,p,cls);
        assert(s.closed == (closed || cls == 13));
    }
    ui_hand_state_t debounce = {.cls=-1,.candidate=-1};
    grab_init(&s); s.mode = 2;
    for (unsigned i = 0; i < 3; ++i) {
        ui_gesture_debounce(&debounce,5);
        grab_frame(&s,p,debounce.cls);
        assert(s.closed == (i == 2));
    }
    puts("PASS grab A hysteresis/debounce, B/D geometry, C classes/3-frame debounce, "
         "visibility, nearest pick, smooth follow, gravity, regrab and 10-frame hand loss");
}
