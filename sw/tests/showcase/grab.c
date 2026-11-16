/* grab.c — T-GRAB-TEST/R2 acceptance; geometry/state/physics, host domain. */
#include "grab.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static ui_pose_point_t p[21];
static grab_state_t s;
static uint32_t stamp;
static void hand(float x, float y, float gap)
{
    for (unsigned i = 0; i < 21; ++i) p[i] = (ui_pose_point_t){x,y,1};
    p[0].y = y + 100;
    p[4].x = x - gap/2;
    p[8].x = x + gap/2;
}
static bool frame(void) { return grab_frame(&s,p,0,stamp+=40); }
static void test_a(void)
{
    grab_init(&s);
    for (unsigned i = 0; i < GRAB_OBJECTS; ++i) {
        assert(s.objects[i].x == 290 + 140 * i);
        assert(s.objects[i].y == 470);
    }
    hand(290,470,20);
    assert(!frame() && !s.closed);
    assert(frame() && s.closed && s.held == 0 && s.picks == 1);
    hand(390,400,30); /* Smoothed d=.25 preserves grab. */
    assert(!frame() && s.closed && fabsf(s.d - .25f) < .001f);
    assert(s.x == 340 && s.y == 435);
    assert(s.objects[0].x == 340 && s.objects[0].y == 435);
    hand(390,400,80);
    for (unsigned i = 0; i < 3; ++i) assert(!frame() && s.closed);
    hand(390,400,0); /* Break the release sequence with smoothed d < .40. */
    assert(!frame() && s.closed && s.pending_frames == 0);
    hand(390,400,80);
    for (unsigned i = 0; i < 3; ++i) assert(!frame() && s.closed);
    assert(frame() && !s.closed && s.held == -1 && s.drops == 1);
    float start = s.objects[0].y;
    grab_animate(&s,.1f);
    assert(fabsf(s.objects[0].y - start - 15) < .01f);
    assert(s.objects[0].velocity == 300);
    for (unsigned i = 0; i < 30; ++i) grab_animate(&s,1/30.f);
    assert(s.objects[0].y == 470 && !s.objects[0].falling);

    grab_init(&s);
    hand(290,470,30);
    assert(!frame() && !s.closed); /* Hysteresis band also preserves open. */
    hand(290,470,10);
    assert(!frame());
    p[4].visibility = .49f;
    assert(!frame() && !s.closed);
    p[4].visibility = .5f;
    assert(!frame()); /* Invisible frame broke the consecutive sequence. */
    assert(frame() && s.closed);
    hand(290,470,80);
    p[8].visibility = 0;
    assert(!frame() && s.closed);

    grab_init(&s);
    s.objects[0].x = 250;
    s.objects[1].x = 300;
    hand(290,470,20);
    frame(); frame();
    assert(s.held == 1); /* Both in range: choose nearest. */
    for (unsigned i = 0; i < 10; ++i) assert(!grab_frame(&s,NULL,-1,stamp+=10) && s.held == 1);
    assert(!frame() && s.held == 1 && s.lost == 0);
    float seen_x = s.x;
    float speed = s.velocity_x;
    assert(!grab_frame(&s,NULL,-1,s.seen_at+200) && s.held == 1 && s.closed);
    assert(fabsf(s.x-seen_x-speed*200) < .01f);
    assert(grab_frame(&s,NULL,-1,s.seen_at+201) && s.held == -1 && !s.closed);
    grab_init(&s);
    hand(640,300,20);
    frame(); frame();
    assert(s.closed && s.held == -1 && s.picks == 0); /* Empty grab. */
}
static void test_scale(void)
{
    for (unsigned mode = 0; mode < 2; ++mode) {
        grab_init(&s);
        s.mode = mode;
        hand(290,470,20);
        /* L=(100+0+200+100)/4=100 even when P9 coincides with P0. */
        p[9] = p[0];
        p[13].y = p[0].y - 200;
        p[12].x = p[16].x = p[20].x = 300;
        assert(!frame() && fabsf(s.d - .2f) < .001f);
        assert(frame() && s.closed && s.held == 0);
        /* Different root lengths: L=(100+0+200+300)/4=150. */
        p[17].y = p[0].y - 300;
        assert(!frame() && fabsf(s.d - (1.f/6)) < .001f);
    }
}
static void test_b(void)
{
    grab_init(&s);
    s.mode = 1;
    hand(290,470,20);
    p[12].x = p[16].x = p[20].x = 300;
    assert(!frame()); assert(frame() && s.closed && fabsf(s.d - .2f) < .001f);
    p[12].x = p[16].x = p[20].x = 400; /* Raw mean .95, smoothed .575. */
    assert(!frame() && s.closed && fabsf(s.d - .575f) < .001f);
    for (unsigned i = 0; i < 2; ++i) assert(!frame() && s.closed);
    assert(frame() && !s.closed);
}
static void test_d(void)
{
    grab_init(&s);
    s.mode = 3;
    hand(290,470,100);
    assert(!frame()); assert(frame() && s.held == 0);
    hand(290,470,190);
    assert(!frame() && s.closed && s.d == 145);
    hand(290,470,240);
    assert(!frame() && s.closed && s.d == 192.5f);
    for (unsigned i = 0; i < 2; ++i) assert(!frame() && s.closed);
    assert(frame() && !s.closed);
    grab_init(&s); s.mode = 3;
    hand(290,470,100);
    p[4].x = 300; p[8].x = 320;
    frame(); frame(); assert(!s.closed); /* Same side cannot enclose center. */
    hand(290,470,160);
    frame(); frame(); assert(!s.closed); /* Beyond r+m. */
    hand(290,470,150);
    frame(); frame(); assert(s.closed && s.held == 0); /* Inclusive edge. */
    grab_init(&s); s.mode = 3;
    s.objects[0].y = 300; s.objects[0].falling = true;
    hand(290,300,100); frame(); frame();
    assert(s.held == 0 && !s.objects[0].falling); /* Regrab while falling. */
}
static void test_c(void)
{
    for (int cls = -1; cls < 14; ++cls) {
        grab_init(&s); s.mode = 2;
        hand(290,470,20);
        bool close = cls == 1 || cls == 5;
        bool release = cls == 0 || cls == 11;
        grab_frame(&s,p,cls,stamp+=40);
        assert(s.closed == close);
        s.closed = true;
        s.held = 0;
        grab_frame(&s,p,cls,stamp+=40);
        assert(s.closed == !release);
        assert(s.held == (release ? -1 : 0));
    }
    ui_hand_state_t debounce = {.cls=-1,.candidate=-1};
    grab_init(&s); s.mode = 2;
    for (unsigned i = 0; i < 3; ++i) {
        ui_gesture_debounce(&debounce,5);
        grab_frame(&s,p,debounce.cls,stamp+=40);
        assert(s.closed == (i == 2));
    }
    for (unsigned i = 0; i < 3; ++i) {
        ui_gesture_debounce(&debounce,0);
        grab_frame(&s,p,debounce.cls,stamp+=40);
        assert(s.closed == (i != 2));
    }
}
int main(void)
{
    test_a();
    grab_init(&s);
    hand(290,470,20); frame(); frame();
    hand(390,430,20); frame();
    uint32_t seen_at = s.seen_at;
    assert(!grab_frame(&s,NULL,-1,seen_at+100) && s.closed && s.held == 0);
    assert(fabsf(s.x-465) < .01f && fabsf(s.y-400) < .01f);
    assert(s.objects[0].x == s.x && s.objects[0].y == s.y);
    assert(grab_frame(&s,NULL,-1,seen_at+201) && s.held == -1);
    test_scale();
    test_b();
    test_d();
    test_c();
    puts("PASS grab R2 layout, A/B four-root scale, A/B/D value smoothing, "
         "2-frame grab/4-frame release, C hold classes/3-frame debounce, "
         "visibility, nearest pick, smooth follow, gravity, regrab and "
         "200 ms hand loss hold/release/extrapolation");
}
