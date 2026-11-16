/* tower_geo.c — GEO §2.1–2.2 bit-exact host model and R4 atlas quality acceptance.
 * Packed descriptors execute against DDR scratch; the old CPU sampler is test-only.
 * Native host, no SoC simulation.
 */
#include "sprite_rot.h"
#include "ddr_map.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint32_t cpu_sample(sprite_source source, int x_q8, int y_q8)
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
#include "geo_model.h"
static void model_vectors(uint8_t *scratch)
{
    struct geo_config cfg = {.src_base=SHOWCASE_TOWER_GEO_BASE+8192,
        .src_stride=32,.src_width=2,.src_height=2,
        .dst_base=SHOWCASE_TOWER_GEO_BASE+12288,.dst_stride=32,
        .rect_width=2,.rect_height=2,.matrix={65536,0,0,0,65536,0}};
    uint16_t *src = (void *)(scratch+8192), *dst = (void *)(scratch+12288);
    src[0]=0xf800; src[1]=0x07e0; src[16]=0x001f; src[17]=0xffff;
    geo_descriptor_pack((void *)scratch,&cfg);
    geo_model_execute(scratch,1);
    assert(dst[0]==src[0] && dst[1]==src[1] && dst[16]==src[16] && dst[17]==src[17]);
    cfg.matrix[2] = -32768;
    geo_descriptor_pack((void *)scratch,&cfg);
    geo_model_execute(scratch,1);
    assert(dst[0]==0x8000 && dst[1]==0x8400);
    cfg.matrix[2] = -65536*4;
    geo_descriptor_pack((void *)scratch,&cfg);
    geo_model_execute(scratch,1);
    assert(dst[0]==0 && dst[1]==0);
}
static unsigned distance(unsigned a, unsigned b) { return a > b ? a-b : b-a; }
static unsigned composite(unsigned color, unsigned alpha, unsigned background)
{
    return (color*alpha+background*(255-alpha)+127)/255;
}
static void transparent_edge(sprite_rot *a, uint8_t *scratch, uint32_t *pixels)
{
    uint32_t art[] = {0xffff0000,0x000000ff,0xffff0000,0x000000ff};
    sprite_source sources[TOWER_KINDS] = {{art,2,2}};
    sprite_rot_begin(a,sources,1,pixels);
    sprite_rot_prepare(a,scratch);
    const uint16_t *color = (const void *)(scratch+
        a->configs[0].src_base-SHOWCASE_TOWER_GEO_BASE);
    const uint16_t *alpha = (const void *)(scratch+
        a->configs[1].src_base-SHOWCASE_TOWER_GEO_BASE);
    assert(color[0] == 0xf800 && color[1] == 0);
    assert(alpha[0] == 0xffff && alpha[1] == 0);
    for (unsigned i = 0; i < 32; ++i)
        geo_descriptor_pack(&((struct geo_descriptor *)scratch)[i],&a->configs[i]);
    geo_model_execute(scratch,32);
    assert(sprite_rot_finish(a,scratch));
    for (unsigned f = 0; f < 16; ++f) {
        const sprite_frame *frame = &a->frames[0][f];
        for (unsigned i = 0; i < frame->width*frame->height; ++i) {
            uint32_t c = frame->pixels[i];
            unsigned alpha_value = c>>24;
            assert(composite(c&255,alpha_value,0) <= 4);
            assert(composite((c>>8)&255,alpha_value,0) <= 2);
            if (!alpha_value) assert(c == 0);
        }
    }
}
static unsigned percentile(const unsigned histogram[256], unsigned pixels)
{
    unsigned sum = 0;
    for (unsigned error = 0; error < 256; ++error) {
        sum += histogram[error];
        if ((uint64_t)sum*1000 >= (uint64_t)pixels*999) return error;
    }
    abort();
}
void tower_geo_test(const char *art_path)
{
    FILE *art = fopen(art_path,"rb");
    assert(art);
    sprite_source sources[TOWER_KINDS];
    for (unsigned k = 0; k < TOWER_KINDS; ++k) {
        uint32_t size[2];
        assert(fread(size,sizeof size,1,art)==1);
        uint32_t *pixels = malloc(size[0]*size[1]*4);
        assert(fread(pixels,4,size[0]*size[1],art)==size[0]*size[1]);
        sources[k] = (sprite_source){pixels,size[0],size[1]};
    }
    fclose(art);
    uint8_t *scratch = malloc(SHOWCASE_TOWER_GEO_BYTES);
    uint32_t *pixels = malloc(SHOWCASE_TOWER_ROT_BYTES);
    sprite_rot *a = malloc(sizeof *a);
    model_vectors(scratch);
    transparent_edge(a,scratch,pixels);
    for (unsigned mode = TOWER_TUTORIAL; mode <= TOWER_QUAKE; ++mode) {
        uint64_t kinds = tower_kinds((tower_mode)mode);
        sprite_rot_begin(a,sources,kinds,pixels);
        unsigned frames = 0, types = 0;
        for (unsigned k = 0; k < TOWER_KINDS; ++k)
            if (kinds & (UINT64_C(1)<<k)) { frames += tower_frame_count(k%6); ++types; }
        assert(a->total == frames && a->types == types);
    }
    sprite_rot_begin(a,sources,tower_kinds(TOWER_TUTORIAL),pixels);
    do {
        sprite_rot_prepare(a,scratch);
        unsigned k = a->kind;
        assert(k == 0 || k == 3);
        unsigned count = tower_frame_count(k%6)*2;
        for (unsigned i = 0; i < count; ++i)
            geo_descriptor_pack(&((struct geo_descriptor *)scratch)[i],&a->configs[i]);
        geo_model_execute(scratch,count);
    } while (!sprite_rot_finish(a,scratch));
    assert(a->completed == 80 && a->types == 2 && a->frames[1][0].pixels == NULL);
    sprite_rot_begin(a,sources,(UINT64_C(1)<<36)-1,pixels);
    unsigned max_rgb = 0, max_alpha = 0, max_straight = 0;
    unsigned rgb_histogram[256] = {0}, alpha_histogram[256] = {0};
    unsigned over8 = 0, geo_pixels = 0;
    unsigned alpha_low = 255, alpha_high = 0, max_scratch = 0;
    unsigned expected[] = {16,32,32,64,64,64};
    const unsigned backgrounds[][3] = {{0,0,0},{255,255,255},{37,113,201}};
    while (a->completed < a->total) {
        unsigned k = a->kind;
        sprite_rot_prepare(a,scratch);
        unsigned count = tower_frame_count(k%6)*2;
        assert(count==expected[k%6]*2);
        assert(a->scratch_bytes <= SHOWCASE_TOWER_GEO_BYTES);
        if (a->scratch_bytes > max_scratch) max_scratch = a->scratch_bytes;
        for (unsigned i = 0; i < count; ++i) {
            geo_descriptor_pack(&((struct geo_descriptor *)scratch)[i],&a->configs[i]);
            geo_pixels += a->configs[i].rect_width*a->configs[i].rect_height;
        }
        geo_model_execute(scratch,count);
        sprite_rot_finish(a,scratch);
        for (unsigned f = 0; f < count/2; ++f) {
            const sprite_frame *frame = &a->frames[k][f];
            const int32_t *m = a->configs[f*2].matrix;
            for (unsigned y = 0; y < frame->height; ++y)
                for (unsigned x = 0; x < frame->width; ++x) {
                    int sx = (int)((int64_t)m[0]*x+(int64_t)m[1]*y+m[2])>>8;
                    int sy = (int)((int64_t)m[3]*x+(int64_t)m[4]*y+m[5])>>8;
                    uint32_t old = cpu_sample(sources[k],sx,sy);
                    uint32_t now = frame->pixels[y*frame->width+x];
                    unsigned oa=old>>24, na=now>>24;
                    unsigned da=distance(oa,na);
                    unsigned pixel_error = 0;
                    ++alpha_histogram[da];
                    if (da > max_alpha) max_alpha=da;
                    for (unsigned c=0; c<3; ++c) {
                        unsigned oc=(old>>(16-c*8))&255, nc=(now>>(16-c*8))&255;
                        unsigned ds=distance(oc,nc);
                        if (ds > max_straight) {
                            max_straight=ds; alpha_low=alpha_high=oa;
                        } else if (ds == max_straight) {
                            if (oa < alpha_low) alpha_low=oa;
                            if (oa > alpha_high) alpha_high=oa;
                        }
                        for (unsigned bg=0; bg<3; ++bg) {
                            unsigned delta=distance(composite(oc,oa,backgrounds[bg][c]),
                                composite(nc,na,backgrounds[bg][c]));
                            if (delta > pixel_error) pixel_error = delta;
                            if (delta > max_rgb) {
                                max_rgb=delta;
                                if (delta > 12)
                                    fprintf(stderr,"quality kind=%u frame=%u x=%u y=%u "
                                    "old=%08x now=%08x bg=%u channel=%u delta=%u\n",
                                    k,f,x,y,old,now,bg,c,delta);
                            }
                        }
                    }
                    ++rgb_histogram[pixel_error];
                    if (pixel_error > 8) ++over8;
                    assert(da <= 8);
                }
        }
        assert(tower_frame(k%6,0)==0);
        assert(tower_frame(k%6,PHYS_PI/2)==16%expected[k%6]);
    }
    assert(a->completed==1632 && a->bytes==117165144);
    printf("GEO all 36 types frames=%u pixels=%u scratch=%u composite_rgb=%u "
        "alpha=%u straight_rgb=%u at_alpha=%u..%u\n",a->completed,a->bytes/4,max_scratch,
        max_rgb,max_alpha,max_straight,alpha_low,alpha_high);
    fflush(stdout);
    printf("GEO error p99.9_rgb=%u p99.9_alpha=%u over8=%u/%u (%.6f%%) geo_pixels=%u\n",
        percentile(rgb_histogram,a->bytes/4),percentile(alpha_histogram,a->bytes/4),
        over8,a->bytes/4,100.0*over8/(a->bytes/4),geo_pixels);
    assert(max_rgb <= 12 && max_alpha <= 8);
    free(a); free(pixels); free(scratch);
    for (unsigned k=0; k<TOWER_KINDS; ++k) free((void *)sources[k].pixels);
}
