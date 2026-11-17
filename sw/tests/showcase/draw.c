/* draw.c — T-DRAW host acceptance; gesture, smoothing, jumps and tool isolation.
 * Deterministic millisecond input; no LVGL or vision dependency.
 */
#include "draw.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static uint32_t pixels[DRAW_WIDTH*DRAW_HEIGHT];
static draw_point_t points[256];
static unsigned count;
static void stamp(void *context, const draw_state_t *s, int x, int y)
{
    (void)context;
    points[count++] = (draw_point_t){x,y};
    draw_raster(pixels,s,x,y);
}
int main(void)
{
    draw_state_t s;
    draw_init(&s);
    draw_step(&s,true,DRAW_POINT,300,300,0,stamp,NULL);
    assert(s.down && s.strokes == 1 && count == 1);
    draw_step(&s,true,DRAW_POINT,320,300,40,stamp,NULL);
    assert(s.x == 310 && count == 4); /* alpha=.5; stamps at 303,306,309 */
    assert(points[1].x == 303 && points[3].x == 309);
    draw_step(&s,true,DRAW_POINT,330,300,80,stamp,NULL);
    assert(s.x == 320 && points[4].x == 312); /* preserves fractional spacing */
    unsigned before = count;
    draw_step(&s,true,0,330,300,120,stamp,NULL);
    assert(!s.down && count == before);
    draw_step(&s,true,DRAW_POINT,350,300,160,stamp,NULL);
    assert(s.down && s.strokes == 2);
    draw_step(&s,false,-1,0,0,360,stamp,NULL);
    assert(s.down); /* exactly 200 ms is still held */
    draw_step(&s,false,-1,0,0,361,stamp,NULL);
    assert(!s.down && !s.visible);
    draw_step(&s,true,DRAW_POINT,400,300,400,stamp,NULL);
    before = count;
    draw_step(&s,true,DRAW_POINT,600,300,440,stamp,NULL);
    assert(s.strokes == 4 && count == before+1 && points[count-1].x == 600);
    assert(pixels[300*DRAW_WIDTH+500] == 0); /* jump never connected */
    assert(pixels[300*DRAW_WIDTH+600] != 0);
    draw_select(&s,2); /* color selection never enables eraser */
    draw_step(&s,true,DRAW_POINT,600,300,480,stamp,NULL);
    assert(pixels[300*DRAW_WIDTH+600] == (0xff000000u|draw_colors[2]));
    draw_select(&s,12);
    draw_step(&s,true,0,600,300,520,stamp,NULL);
    assert(pixels[300*DRAW_WIDTH+600] != 0); /* palm never erases */
    draw_step(&s,true,DRAW_POINT,600,300,560,stamp,NULL);
    assert(pixels[300*DRAW_WIDTH+600] == 0);
    draw_select(&s,11);
    draw_step(&s,true,DRAW_POINT,600,300,600,stamp,NULL);
    assert(pixels[300*DRAW_WIDTH+600] != 0);
    before = count;
    draw_step(&s,true,DRAW_POINT,200,100,640,stamp,NULL);
    assert(!s.down && count == before);
    assert(draw_hover(&s,true,200,100,640) == -1);
    assert(draw_hover(&s,true,200,100,1239) == -1);
    assert(draw_hover(&s,true,200,100,1240) == 0);
    assert(draw_hover(&s,true,200,100,1300) == -1); /* once per hover */
    assert(draw_hover(&s,false,200,100,1340) == -1 && s.hold == 0);
    for (unsigned i = 0; i < 3; ++i) {
        draw_select(&s,8+i);
        assert(draw_sizes[s.size] == (6u << i));
    }
    puts("PASS draw: down/up, 200 ms loss, smoothing, 3 px resampling, jump, tools, toolbar");
    return 0;
}
