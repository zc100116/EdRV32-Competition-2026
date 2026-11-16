/* sprite_rot.c — showcase R4 §6.5; inverse rotation with premultiplied filtering.
 * Entry-time CPU work; atlas output is straight-alpha for RND alpha copy.
 */
#include "sprite_rot.h"
#include <string.h>
static const int sine[64] = {
    0,6424,12785,19024,25080,30893,36410,41576,
    46341,50660,54491,57798,60547,62714,64277,65220,
    65536,65220,64277,62714,60547,57798,54491,50660,
    46341,41576,36410,30893,25080,19024,12785,6424,
    0,-6424,-12785,-19024,-25080,-30893,-36410,-41576,
    -46341,-50660,-54491,-57798,-60547,-62714,-64277,-65220,
    -65536,-65220,-64277,-62714,-60547,-57798,-54491,-50660,
    -46341,-41576,-36410,-30893,-25080,-19024,-12785,-6424
};
uint32_t sprite_rot_sample(sprite_source source, int x_q8, int y_q8)
{
    int x = x_q8 >> 8;
    int y = y_q8 >> 8;
    unsigned fx = (unsigned)x_q8 & 255;
    unsigned fy = (unsigned)y_q8 & 255;
    unsigned weights[] = {(256-fx)*(256-fy),fx*(256-fy),(256-fx)*fy,fx*fy};
    /* Sum(weights)=65536, so 255*255*65536 fits in a uint32_t. */
    uint32_t alpha = 0, red = 0, green = 0, blue = 0;
    for (unsigned i = 0; i < 4; ++i) {
        int sx = x+(int)(i&1);
        int sy = y+(int)(i>>1);
        if (sx < 0 || sy < 0 || sx >= (int)source.width || sy >= (int)source.height)
            continue; /* The rotated image exterior is transparent. */
        uint32_t c = source.pixels[(unsigned)sy*source.width+(unsigned)sx];
        uint32_t a = (c>>24)*weights[i];
        alpha += a;
        red += ((c>>16)&255)*a;
        green += ((c>>8)&255)*a;
        blue += (c&255)*a;
    }
    unsigned a = (unsigned)((alpha+32768)>>16);
    if (!a) return 0;
    return (a<<24)|((uint32_t)((red+alpha/2)/alpha)<<16)|
        ((uint32_t)((green+alpha/2)/alpha)<<8)|(uint32_t)((blue+alpha/2)/alpha);
}
void sprite_rot_begin(sprite_rot *a, const sprite_source sources[TOWER_KINDS],
                      uint64_t kinds, uint32_t *storage)
{
    memset(a,0,sizeof *a);
    memcpy(a->sources,sources,sizeof a->sources);
    a->kinds = kinds;
    a->storage = storage;
    for (unsigned i = 0; i < TOWER_KINDS; ++i)
        if (kinds & (UINT64_C(1)<<i)) a->total += tower_frame_count(i%6);
}
bool sprite_rot_generate(sprite_rot *a)
{
    while (!(a->kinds & (UINT64_C(1)<<a->kind))) ++a->kind;
    unsigned k = a->kind;
    unsigned f = a->frame;
    sprite_source src = a->sources[k];
    phys_vec pivot = tower_pivot(k%6);
    int sn = sine[f];
    int cs = sine[(f+16)%64];
    int min_x = 1000, min_y = 1000, max_x = -1000, max_y = -1000;
    for (unsigned i = 0; i < 4; ++i) {
        int x = (i&1 ? (int)src.width : 0)*65536-pivot.x;
        int y = (i&2 ? (int)src.height : 0)*65536-pivot.y;
        int rx = (int)(((int64_t)x*cs-(int64_t)y*sn)>>32);
        int ry = (int)(((int64_t)x*sn+(int64_t)y*cs)>>32);
        if (rx < min_x) min_x = rx;
        if (ry < min_y) min_y = ry;
        if (rx > max_x) max_x = rx;
        if (ry > max_y) max_y = ry;
    }
    sprite_frame *out = &a->frames[k][f];
    out->left = min_x-1;
    out->top = min_y-1;
    out->width = (unsigned)(max_x-min_x+3);
    out->height = (unsigned)(max_y-min_y+3);
    out->pixels = a->storage+a->bytes/4;
    for (unsigned y = 0; y < out->height; ++y)
        for (unsigned x = 0; x < out->width; ++x) {
            int dx = (out->left+(int)x)*256+128;
            int dy = (out->top+(int)y)*256+128;
            int sx = (int)(((int64_t)dx*cs+(int64_t)dy*sn)>>16)+(pivot.x>>8)-128;
            int sy = (int)(((int64_t)dy*cs-(int64_t)dx*sn)>>16)+(pivot.y>>8)-128;
            out->pixels[y*out->width+x] = sprite_rot_sample(src,sx,sy);
        }
    a->bytes += out->width*out->height*4;
    ++a->completed;
    if (++a->frame == tower_frame_count(k%6)) { ++a->kind; a->frame = 0; }
    return a->completed == a->total;
}
