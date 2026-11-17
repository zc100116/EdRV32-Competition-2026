/* replay.c — T-DRAW-FIX3: original draw rules on recorded model keypoints.
 * Host clock uses video timestamps; no GUI, model approximation or raster allocation.
 */
#include "draw.h"
#include <stdio.h>
static unsigned emitted;
static int last_x;
static int last_y;
static void stamp(void *context, const draw_state_t *state, int x, int y)
{
    (void)context;
    (void)state;
    ++emitted;
    last_x = x;
    last_y = y;
}
int main(void)
{
    draw_state_t state;
    draw_init(&state);
    unsigned frame, now, count;
    puts("f,ms,hand,cls,geometry,pen,extrapolate,pause,x,y,strokes,emitted,"
         "out_x,out_y,why");
    while (scanf("%u %u %u", &frame, &now, &count) == 3) {
        draw_point_t selected[21] = {{0}};
        int cls = -1;
        int hand = -1;
        int area = -1;
        for (unsigned i = 0; i < count; ++i) {
            int x0, y0, x1, y1, candidate;
            if (scanf("%d %d %d %d %d", &x0, &y0, &x1, &y1, &candidate) != 5) return 1;
            draw_point_t points[21];
            for (unsigned k = 0; k < 21; ++k)
                if (scanf("%f %f", &points[k].x, &points[k].y) != 2) return 1;
            if ((x1-x0)*(y1-y0) > area) {
                area = (x1-x0)*(y1-y0);
                hand = (int)i;
                cls = candidate;
                for (unsigned k = 0; k < 21; ++k) selected[k] = points[k];
            }
        }
        int item = draw_hover(&state,count != 0,(int)selected[8].x,(int)selected[8].y,now);
        if (item >= 0) draw_select(&state,(unsigned)item);
        emitted = 0;
        draw_hand_step(&state,count != 0,cls,selected,now,stamp,NULL);
        const char *why = !count ? (state.down ? "missing_hold" : "lost") :
            state.negative_frames ? "release_wait" :
            cls == DRAW_POINT ? "class" : draw_pointing(selected) ? "geometry" :
            state.down ? "hold" : "up";
        printf("%u,%u,%d,%d,%d,%d,%d,%d,%.3f,%.3f,%u,%u,%d,%d,%s\n",
               frame,now,hand,cls,count ? draw_pointing(selected) : 0,state.down,
               state.extrapolating,state.tracking_paused,state.x,state.y,state.strokes,
               emitted,last_x,last_y,why);
    }
    return ferror(stdin) ? 1 : 0;
}
