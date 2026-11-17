/* sprite_rot.c — showcase R4 §6.5, GEO §2.1–2.6; entry-time rotation atlas.
 * CPU splits premultiplied RGB565/alpha sources and restores straight ARGB8888.
 * clk_sys; GEO owns scratch outputs between prepare and finish.
 */
#include "sprite_rot.h"
#include "../board/ddr_map.h"
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
static unsigned align_page(unsigned bytes) { return (bytes+4095u)&~4095u; }
/* Nearest representable input; GEO itself truncates its interpolated RGB888 output. */
static uint16_t encode(unsigned r, unsigned g, unsigned b)
{
    return (uint16_t)(((r*31+127)/255)<<11 | ((g*63+127)/255)<<5 |
                      (b*31+127)/255);
}
static unsigned restore(unsigned c, uint32_t reciprocal)
{
    unsigned result = (c*reciprocal+32768)>>16;
    return result > 255 ? 255 : result;
}
void sprite_rot_begin(sprite_rot *a, const sprite_source sources[TOWER_KINDS],
                      uint64_t kinds, uint32_t *storage)
{
    memset(a,0,sizeof *a);
    memcpy(a->sources,sources,sizeof a->sources);
    a->kinds = kinds;
    a->storage = storage;
    for (unsigned i = 0; i < TOWER_KINDS; ++i)
        if (kinds & (UINT64_C(1)<<i)) {
            a->total += tower_frame_count(i%6);
            ++a->types;
        }
    /* Fold reciprocal multiplication/saturation into the RGB565 reconstruction tables.
     * Decode each GEO truncation bin at its midpoint; alpha uses the green channel.
     */
    for (unsigned alpha = 1; alpha < 64; ++alpha) {
        unsigned v = alpha*4+2;
        uint32_t reciprocal = (255u<<16)/v;
        for (unsigned c = 0; c < 32; ++c) {
            unsigned value = restore(c*8+4,reciprocal);
            a->red_blue[alpha*32+c] = (uint8_t)value;
        }
        for (unsigned c = 0; c < 64; ++c) {
            unsigned value = restore(c*4+2,reciprocal);
            a->alpha_green[alpha*64+c] = (v<<24)|(value<<8);
        }
    }
}
void sprite_rot_prepare(sprite_rot *a, void *scratch)
{
    while (!(a->kinds & (UINT64_C(1)<<a->kind))) ++a->kind;
    unsigned k = a->kind;
    sprite_source src = a->sources[k];
    unsigned stride = geo_surface_stride(src.width);
    unsigned source_bytes = align_page(stride*src.height);
    unsigned color_offset = 8192;
    unsigned alpha_offset = color_offset+source_bytes;
    unsigned offset = alpha_offset+source_bytes;
    uint16_t *color = (uint16_t *)((uint8_t *)scratch+color_offset);
    uint16_t *alpha = (uint16_t *)((uint8_t *)scratch+alpha_offset);
    for (unsigned y = 0; y < src.height; ++y)
        for (unsigned x = 0; x < src.width; ++x) {
            uint32_t c = src.pixels[y*src.width+x];
            unsigned v = c>>24;
            color[y*stride/2+x] = encode((((c>>16)&255)*v+127)/255,
                (((c>>8)&255)*v+127)/255,((c&255)*v+127)/255);
            alpha[y*stride/2+x] = encode(v,v,v);
        }
    phys_vec pivot = tower_pivot(k%6);
    for (unsigned f = 0; f < tower_frame_count(k%6); ++f) {
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
        a->bytes += out->width*out->height*4;
        /* GEO centers are integer coordinates. Keep the old half-pixel convention. */
        int dx = out->left*65536+32768;
        int dy = out->top*65536+32768;
        struct geo_config config = {
            .src_stride = stride, .src_width = src.width, .src_height = src.height,
            .dst_stride = geo_surface_stride(out->width),
            .rect_width = (out->width+1)&~1u, .rect_height = out->height,
            .matrix = {cs,sn,
                (int)(((int64_t)dx*cs+(int64_t)dy*sn)>>16)+pivot.x-32768,
                -sn,cs,(int)(((int64_t)dy*cs-(int64_t)dx*sn)>>16)+pivot.y-32768}
        };
        for (unsigned plane = 0; plane < 2; ++plane) {
            config.src_base = SHOWCASE_TOWER_GEO_BASE+
                (plane ? alpha_offset : color_offset);
            config.dst_base = SHOWCASE_TOWER_GEO_BASE+offset;
            a->configs[f*2+plane] = config;
            offset += align_page(config.dst_stride*out->height);
        }
    }
    a->scratch_bytes = offset;
    a->source_end = alpha_offset+source_bytes;
}
bool sprite_rot_finish(sprite_rot *a, const void *scratch)
{
    unsigned k = a->kind;
    for (unsigned f = 0; f < tower_frame_count(k%6); ++f) {
        const sprite_frame out = a->frames[k][f];
        const struct geo_config *config = &a->configs[f*2];
        const uint16_t *color = (const uint16_t *)((const uint8_t *)scratch+
            config[0].dst_base-SHOWCASE_TOWER_GEO_BASE);
        const uint16_t *alpha = (const uint16_t *)((const uint8_t *)scratch+
            config[1].dst_base-SHOWCASE_TOWER_GEO_BASE);
        const uint8_t *red_blue = a->red_blue;
        const uint32_t *alpha_green = a->alpha_green;
        unsigned stride = config->dst_stride/2;
        for (unsigned y = 0; y < out.height; ++y) {
            const uint16_t *color_row = color+y*stride;
            const uint16_t *alpha_row = alpha+y*stride;
            uint32_t *destination = out.pixels+y*out.width;
            for (unsigned x = 0; x < out.width; ++x) {
                /* Alpha already occupies bits 5..10: reuse them as the table row. */
                unsigned av = alpha_row[x]&0x7e0;
                unsigned c = color_row[x];
                destination[x] = ((uint32_t)red_blue[av|(c>>11)]<<16)|
                    alpha_green[(av<<1)|((c>>5)&63)]|red_blue[av|(c&31)];
            }
        }
        ++a->completed;
    }
    ++a->kind;
    return a->completed == a->total;
}
