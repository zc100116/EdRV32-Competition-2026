/* sticker.c — T-FACE-STICKER-R2: One Euro tracking and AR anchor geometry.
 * Integer Q8 pose, Q16 filter alpha; GUI domain, no hardware dependencies.
 */
#include "sticker.h"
#include <string.h>
#include <stdlib.h>
unsigned sticker_revision;
/* Hz in Q8; beta = 0.003 Hz per unit/s (Q16). Derivative cutoff 1 Hz.
 * Low static cutoff suppresses ±3 px noise; beta opens bandwidth during motion.
 */
enum { MIN_CUTOFF = 26, BETA = 197, D_CUTOFF = 256 };
const sticker_style_t sticker_styles[STICKER_SETS] = {
    {"桃桃猫耳", 0, -256, 640}, {"软糖兔耳", 0, -320, 640},
    {"海盐墨镜", 0, 0, 640}, {"宝石皇冠", 0, -300, 563},
    {"彩带派对", 0, -384, 563}, {"心动发箍", 0, -307, 614}
};
int sticker_distance(int x, int y)
{
    uint32_t n = (uint32_t)(x*x + y*y), root = 0, bit = 1u << 30;
    while (bit > n) bit >>= 2;
    while (bit) {
        if (n >= root + bit) { n -= root + bit; root = (root >> 1) + bit; }
        else root >>= 1;
        bit >>= 2;
    }
    return (int)root;
}
/* CORDIC vectoring, Q8 degrees. Eye order is normalized to the right half plane. */
int sticker_tilt(int x, int y)
{
    static const int angles[] = {11520,6801,3593,1824,916,458,229,115,57,29,14};
    if (x < 0) { x = -x; y = -y; }
    x *= 256; y *= 256;
    int a = 0;
    for (unsigned i = 0; i < sizeof angles / sizeof angles[0]; ++i) {
        int old = x;
        if (y > 0) { x += y >> i; y -= old >> i; a += angles[i]; }
        else if (y < 0) { x -= y >> i; y += old >> i; a -= angles[i]; }
    }
    return a;
}
unsigned sticker_angle(unsigned current, int a)
{
    while (current < 4 && a > ((int)current*12 - 24 + 6 + 3)*256) ++current;
    while (current > 0 && a < ((int)current*12 - 24 - 6 - 3)*256) --current;
    return current;
}
static int alpha(int cutoff, unsigned ms)
{
    int k = (int)((int64_t)cutoff * 6283 * ms / 256000);
    return (int)((int64_t)k * 65536 / (1000 + k));
}
static int lowpass(int previous, int value, int a)
{
    return previous + (int)((int64_t)(value - previous)*a / 65536);
}
static int filter(sticker_filter_t *f, int value, unsigned ms)
{
    int speed = (int)((int64_t)(value-f->raw)*1000/ms);
    f->derivative = lowpass(f->derivative, speed, alpha(D_CUTOFF, ms));
    int cutoff = MIN_CUTOFF + (int)((int64_t)BETA*abs(f->derivative)/65536);
    f->value = lowpass(f->value, value, alpha(cutoff, ms));
    f->raw = value;
    return f->value;
}
unsigned sticker_opacity(const sticker_track_t *t)
{
    if (!t->active || t->seen < 2) return 0;
    return t->lost <= 6 ? 255 : (10-t->lost)*255/4;
}
void sticker_step(sticker_state_t *s, const sticker_detection_t *d, unsigned count,
                  unsigned ms)
{
    int cx[100], cy[100], distance[100], tilt[100];
    bool used[100] = {false}, matched[3] = {false};
    for (unsigned j = 0; j < count; ++j) {
        int dx = d[j].points[1].x-d[j].points[0].x;
        int dy = d[j].points[1].y-d[j].points[0].y;
        cx[j] = (d[j].points[0].x+d[j].points[1].x)*128;
        cy[j] = (d[j].points[0].y+d[j].points[1].y)*128;
        distance[j] = sticker_distance(dx,dy)*256;
        tilt[j] = sticker_tilt(dx,dy);
    }
    /* Globally nearest unclaimed pair. Predict center from the last raw motion
     * so opposite trajectories keep their identities through a crossing.
     */
    for (unsigned pair = 0; pair < STICKER_FACES; ++pair) {
        int best = 0x7fffffff, ti = -1, dj = -1;
        for (unsigned i = 0; i < STICKER_FACES; ++i) {
            sticker_track_t *t = &s->tracks[i];
            if (!t->active || matched[i]) continue;
            for (unsigned j = 0; j < count; ++j) {
                if (used[j]) continue;
                int x = (cx[j]-t->raw_x-t->velocity_x)/256;
                int y = (cy[j]-t->raw_y-t->velocity_y)/256;
                int cost = x*x+y*y;
                int gate = t->filter[2].value*4/(5*256);
                int raw_dx = (cx[j]-t->raw_x)/256;
                int raw_dy = (cy[j]-t->raw_y)/256;
                if (raw_dx*raw_dx+raw_dy*raw_dy > gate*gate) continue;
                if (cost <= gate*gate && cost < best) { best=cost; ti=(int)i; dj=(int)j; }
            }
        }
        if (ti < 0) break;
        sticker_track_t *t = &s->tracks[ti];
        matched[ti] = used[dj] = true;
        t->velocity_x = cx[dj]-t->raw_x; t->velocity_y = cy[dj]-t->raw_y;
        t->raw_x = cx[dj]; t->raw_y = cy[dj];
        t->lost = 0; ++t->seen;
        filter(&t->filter[0],cx[dj],ms); filter(&t->filter[1],cy[dj],ms);
        filter(&t->filter[2],distance[dj],ms); filter(&t->filter[3],tilt[dj],ms);
        t->angle = sticker_angle(t->angle,t->filter[3].value);
    }
    for (unsigned i = 0; i < STICKER_FACES; ++i) {
        sticker_track_t *t = &s->tracks[i];
        if (t->active && !matched[i]) {
            if (t->seen < 2 || ++t->lost >= 10) t->active = false;
        }
    }
    for (unsigned j = 0; j < count; ++j) if (!used[j]) {
        for (unsigned i = 0; i < STICKER_FACES; ++i) if (!s->tracks[i].active) {
            sticker_track_t *t = &s->tracks[i];
            memset(t,0,sizeof *t);
            int v[] = {cx[j],cy[j],distance[j],tilt[j]};
            for (unsigned k = 0; k < 4; ++k) t->filter[k].raw=t->filter[k].value=v[k];
            t->raw_x=cx[j]; t->raw_y=cy[j]; t->seen=1; t->active=true;
            int angle = (tilt[j]+30*256)/(12*256);
            t->angle = (unsigned)(angle < 0 ? 0 : angle > 4 ? 4 : angle);
            break;
        }
    }
}
/* Rotation of offsets uses the continuous filtered angle, not the selected art frame. */
void sticker_place(const sticker_track_t *t, unsigned style, sticker_placement_t *p)
{
    static const int atan_q8[] = {11520,6801,3593,1824,916,458,229,115,57,29,14};
    int c = 9949, sn = 0, z = t->filter[3].value;
    for (unsigned i = 0; i < sizeof atan_q8/sizeof atan_q8[0]; ++i) {
        int old = c;
        if (z >= 0) { c-=sn>>i; sn+=old>>i; z-=atan_q8[i]; }
        else { c+=sn>>i; sn-=old>>i; z+=atan_q8[i]; }
    }
    const sticker_style_t *a = &sticker_styles[style];
    int d = t->filter[2].value;
    int ox = a->offset_x*d/256, oy = a->offset_y*d/256;
    p->anchor_x=t->filter[0].value/256; p->anchor_y=t->filter[1].value/256;
    p->x=(t->filter[0].value+(int)((int64_t)ox*c/16384-(int64_t)oy*sn/16384))/256;
    p->y=(t->filter[1].value+(int)((int64_t)ox*sn/16384+(int64_t)oy*c/16384))/256;
    p->width=a->width*d/65536;
}
