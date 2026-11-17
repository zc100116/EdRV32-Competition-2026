/* draw.c — T-DRAW-FIX host acceptance; deterministic geometry and noisy trajectories.
 * Gaussian sigma=6 px, classifier interruptions and 40..200 ms missing hands.
 */
#include "draw.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static uint32_t pixels[DRAW_WIDTH*DRAW_HEIGHT];
static unsigned count;
static uint32_t random_state = 42653887;
static float uniform(void)
{
    random_state = random_state*1664525u+1013904223u;
    return ((random_state>>8)+1.0f)/16777217.0f;
}
static float noise(void)
{
    return 6*sqrtf(-2*logf(uniform()))*cosf(6.2831853f*uniform());
}
static void stamp(void *context, const draw_state_t *s, int x, int y)
{
    (void)context;
    assert(s->tool == DRAW_ERASER || s->length >= 10);
    ++count;
    draw_raster(pixels,s,x,y);
}
static void step(draw_state_t *s, bool present, int cls, bool geometry,
                 float x, float y, uint32_t now)
{
    draw_step(s,present,cls,geometry,x,y,now,stamp,NULL);
}
static void geometry_test(void)
{
    draw_point_t p[21] = {{0}};
    p[0] = (draw_point_t){100,400};
    p[4] = (draw_point_t){120,370};
    p[6] = (draw_point_t){100,310};
    p[8] = (draw_point_t){100,250};
    for (unsigned tip = 12; tip <= 20; tip += 4) {
        p[tip-2] = (draw_point_t){100,330};
        p[tip] = (draw_point_t){100,370};
    }
    assert(draw_pointing(p));
    p[12] = (draw_point_t){110,245};
    assert(!draw_pointing(p)); /* two extended fingers */
    p[12] = (draw_point_t){100,370};
    p[8] = (draw_point_t){100,375};
    assert(!draw_pointing(p)); /* fist */
}
static void transitions(void)
{
    draw_state_t s;
    draw_init(&s);
    step(&s,true,0,true,300,300,0);
    assert(!s.down);
    step(&s,true,0,true,300,300,40);
    assert(s.down && !count);
    for (unsigned i = 1; i <= 20; ++i)
        step(&s,true,0,true,300+4*i,300,40+40*i);
    assert(s.strokes == 1 && count);
    for (unsigned i = 1; i <= 3; ++i) {
        step(&s,true,0,false,380,300,840+40*i);
        assert(s.down);
    }
    step(&s,true,DRAW_POINT,false,380,300,1000);
    assert(s.down && s.strokes == 1);
    for (unsigned i = 1; i <= 4; ++i) {
        step(&s,true,0,false,380,300,1000+40*i);
        assert(s.down == (i < 4));
    }
    unsigned before = count;
    step(&s,true,DRAW_POINT,false,600,300,1200);
    step(&s,true,DRAW_POINT,false,600,300,1240);
    for (unsigned i = 1; i <= 10; ++i)
        step(&s,true,DRAW_POINT,false,600+0.2f*i,300,1240+40*i);
    for (unsigned i = 1; i <= 4; ++i)
        step(&s,true,0,false,602,300,1640+40*i);
    assert(s.strokes == 1 && count == before); /* <10 px produces no dot */
    step(&s,true,DRAW_POINT,false,650,350,1840);
    step(&s,true,DRAW_POINT,false,650,350,1880);
    step(&s,false,-1,false,0,0,2080);
    assert(s.down);
    step(&s,true,DRAW_POINT,false,680,350,2080); /* exact 200 ms recovery */
    assert(s.down);
    step(&s,false,-1,false,0,0,2281);
    assert(!s.down && !s.visible);
    draw_select(&s,2);
    assert(s.color == 2 && s.tool == DRAW_PEN);
    draw_select(&s,12);
    assert(s.tool == DRAW_ERASER);
    unsigned old = count;
    step(&s,true,0,false,700,300,2320);
    assert(count == old);
    step(&s,true,DRAW_POINT,false,700,300,2360);
    step(&s,true,DRAW_POINT,false,700,300,2400);
    assert(count == old+1 && pixels[300*DRAW_WIDTH+700] == 0);
    step(&s,true,DRAW_POINT,false,200,100,2440);
    assert(!s.down);
    assert(draw_hover(&s,true,200,100,2440) == -1);
    assert(draw_hover(&s,true,200,100,3039) == -1);
    assert(draw_hover(&s,true,200,100,3040) == 0);
    assert(draw_hover(&s,true,200,100,3080) == -1);
    for (unsigned i = 0; i < 3; ++i) {
        draw_select(&s,8+i);
        assert(draw_sizes[s.size] == (6u << i));
    }
}
static void synthetic(void)
{
    draw_state_t s;
    draw_init(&s);
    double input = 0;
    double output = 0;
    double error = 0;
    unsigned samples = 0;
    unsigned dropped = 0;
    unsigned missing = 0;
    unsigned frames = 0;
    uint32_t now = 0;
    for (unsigned stroke = 0; stroke < 3; ++stroke) {
        float previous_ix = 0;
        float previous_iy = 0;
        float previous_ox = 0;
        float previous_oy = 0;
        bool previous = false;
        for (unsigned i = 0; i < 300; ++i, now += 40) {
            /* Slow and fast horizontal writing at 12.5, 50 and 75 px/s. */
            float truth_x = 180+i*(stroke == 0 ? .5f : stroke == 1 ? 2 : 3);
            float truth_y = 260+150*stroke;
            float nx = noise();
            float ny = noise();
            bool present = !(i >= 80 && i < 81+(stroke == 2 ? 3 : stroke));
            bool interrupted = i%10 == 5; /* exactly 10% classification interruption */
            ++frames;
            dropped += interrupted;
            missing += !present;
            step(&s,present,interrupted ? 0 : DRAW_POINT,false,
                 truth_x+nx,truth_y+ny,now);
            /* RMS frame-to-frame change in error relative to truth measures jitter;
             * constant filter lag contributes no high-frequency jitter. */
            float ox = s.x-truth_x;
            float oy = s.y-truth_y;
            if (i > 40 && present && previous) {
                input += (nx-previous_ix)*(nx-previous_ix)+(ny-previous_iy)*(ny-previous_iy);
                output += (ox-previous_ox)*(ox-previous_ox)+(oy-previous_oy)*(oy-previous_oy);
                error += ox*ox+oy*oy;
                ++samples;
            }
            previous_ix = nx;
            previous_iy = ny;
            previous_ox = ox;
            previous_oy = oy;
            previous = present;
        }
        for (unsigned i = 0; i < 4; ++i, now += 40)
            step(&s,true,0,false,s.raw_x,s.raw_y,now);
        assert(!s.down && s.strokes == stroke+1);
    }
    double in = sqrt(input/samples);
    double out = sqrt(output/samples);
    printf("synthetic: strokes=%u expected=3, cls=%u/%u, missing=%u, "
           "jitter RMS input=%.3f output=%.3f reduction=%.2f%%, position RMSE=%.3f px\n",
           s.strokes,dropped,frames,missing,in,out,100*(1-out/in),sqrt(error/samples));
    assert(out <= .3*in);
    assert(s.strokes == 3 && s.pending_count == 0);
}
int main(void)
{
    geometry_test();
    transitions();
    synthetic();
    puts("PASS draw: geometry OR class, 2/4 frames, <=200 ms bridge, no dots, tools, >=70% jitter");
    return 0;
}
