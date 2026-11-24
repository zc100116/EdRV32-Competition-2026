/* gpu_emu.c — gpu-spec 2–6: functional C reference implementation.
 * Integer geometry, planes, textures, pixels, objects and DMA; no clock domain.
 */
#include "gpu_emu.h"
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include <stdio.h>
#include "codec.h"

#ifndef GPU_EMU_THREADS
#define GPU_EMU_THREADS 3
#endif
#if GPU_EMU_THREADS > 1
#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif
#endif

typedef __int128 wide;
#define R(e, n) ((e)->regs[EDRV32_GPU_##n##_OFFSET / 4])
#define PERF(e, n) ((e)->regs[EDRV32_GPU_PERF_OFFSET(n) / 4])
#define RAM_BYTES (192 * 1024)
#define PIXELS 115200
struct gpu_emu {
    uint8_t *ddr;
    uint32_t ddr_bytes;
    uint32_t regs[128];
    uint16_t *color, *depth;
    uint8_t *stencil;
    struct rgba *texels;
    int texel_base[16], texel_group, texel_dirty;
    uint8_t ram[RAM_BYTES];
    uint32_t command_index;
    uint32_t palettes[16][256];
    int width, height;
    int32_t matrix[16];
    struct cmd_set_light light;
    struct cmd_set_tex texture;
    struct cmd_set_pixel pixel;
    struct cmd_set_target target;
    int mip_offset[16], mip_width[16], mip_height[16];
    jmp_buf fault;
};
struct rgba { int c[4]; };
struct vec { int64_t c[9]; };
struct number { int64_t m; int e; };
struct planes {
    wide coeff[7][3];
    int exp[7], x, y;
    struct number grad[2][3];
};
static wide absw(wide a) { return a < 0 ? -a : a; }
static wide div_round(wide a, wide b)
{
    if (b < 0) { a = -a; b = -b; }
    return a < 0 ? -((-a + b/2)/b) : (a + b/2)/b;
}
static wide shift(wide a, int bits)
{
    if (bits > 0) {
        if (bits >= 127) return 0;
        unsigned __int128 mag = (unsigned __int128)absw(a);
        wide rounded = (wide)((mag >> bits) + ((mag >> (bits-1)) & 1));
        return a < 0 ? -rounded : rounded;
    }
    return a * ((wide)1 << -bits);
}
static int bit_length(wide a)
{
    unsigned __int128 u = (unsigned __int128)absw(a);
    uint64_t high = (uint64_t)(u >> 64), low = (uint64_t)u;
    return high ? 128 - __builtin_clzll(high) : low ? 64 - __builtin_clzll(low) : 0;
}
static int64_t clamp(wide a, int64_t lo, int64_t hi)
{ return a < lo ? lo : a > hi ? hi : (int64_t)a; }
static int imin(int a, int b) { return a < b ? a : b; }
static int imax(int a, int b) { return a > b ? a : b; }
static int d(int a) { int t = a + 128; return (t + (t >> 8)) >> 8; }
static struct rgba expand(int a)
{
    int r = a >> 11, g = (a >> 5) & 63, b = a & 31;
    return (struct rgba){{(r<<3)|(r>>2), (g<<2)|(g>>4), (b<<3)|(b>>2), 255}};
}
static uint16_t p565(struct rgba a)
{ return (uint16_t)((a.c[0]>>3)<<11 | (a.c[1]>>2)<<5 | (a.c[2]>>3)); }
static int64_t reciprocal(int64_t value, int frac)
{
    int exp = bit_length(value) - 1;
    wide m = exp >= 30 ? value >> (exp-30) : (wide)value * ((wide)1 << (30-exp));
    wide index = (m - ((wide)1<<30)) >> 20;
    wide midpoint = ((wide)1<<30) + (index<<20) + (1<<19);
    wide seed = div_round((wide)1<<60, midpoint);
    wide product = shift(m*seed, 30);
    wide result = shift(seed*(((wide)2<<30)-product), 30);
    return (int64_t)shift(result, exp-frac);
}
/* The same integer ROM construction as arithmetic.logarithm_entry, generated below. */
#include "log_rom.h"
static int logarithm(wide value)
{
    int exp = bit_length(value)-1;
    int mantissa = (int)(exp >= 8 ? value >> (exp-8) : value * ((wide)1<<(8-exp)));
    return (exp-16)*256 + log_rom[mantissa-256];
}
/* gpu-spec 2.13.8–11: normalized products have at most 36 magnitude bits;
 * alignment uses 23 signed bits and Newton products at most 36. Only plane
 * accumulators (70 signed bits, 2.13.7) still need the wide normal(). */
static int64_t shift64(int64_t value, int bits)
{
    uint64_t mag = (value < 0 ? -(uint64_t)value : (uint64_t)value);
    if (bits > 0) {
        if (bits >= 64) return bits == 64 ? (int64_t)(mag >> 63)*(value < 0 ? -1 : 1) : 0;
        mag = (mag + (UINT64_C(1) << (bits-1))) >> bits;
    } else mag <<= -bits;
    return value < 0 ? -(int64_t)mag : (int64_t)mag;
}
static inline struct number normal64(int64_t value, int exponent)
{
    if (!value) return (struct number){0,0};
    uint64_t mag = (value < 0 ? -(uint64_t)value : (uint64_t)value);
    int amount = 64-__builtin_clzll(mag)-18;
    int64_t mantissa = shift64(value,amount);
    if (llabs(mantissa) == (1<<18)) { mantissa = shift64(mantissa,1); ++amount; }
    return (struct number){mantissa,exponent+amount};
}
static struct number normal(wide value, int exponent)
{
    if (value >= INT64_MIN && value <= INT64_MAX)
        return normal64((int64_t)value,exponent);
    int amount = bit_length(value)-18;
    wide mantissa = shift(value, amount);
    if (absw(mantissa) == (1<<18)) { mantissa = shift(mantissa, 1); ++amount; }
    return (struct number){(int64_t)mantissa, exponent+amount};
}
static struct number multiply(struct number a, struct number b)
{ return normal64(a.m*b.m, a.e+b.e); }
static struct number subtract(struct number a, struct number b)
{
    if (!b.m) return a;
    if (!a.m) return (struct number){-b.m, b.e};
    int exp = imax(a.e, b.e)-3;
    return normal64(shift64(a.m, exp-a.e)-shift64(b.m, exp-b.e), exp);
}
static struct number inverse(struct number a)
{
    int64_t index = (a.m-(1<<17)) >> 7;
    int64_t midpoint = (1<<11)+2*index+1;
    int64_t seed = ((1<<28)+midpoint/2)/midpoint;
    int64_t product = shift64(a.m*seed, 17);
    int64_t result = shift64(seed*((2<<17)-product), 17);
    return normal64(result, -34-a.e);
}
static void fail(struct gpu_emu *e, int code) { longjmp(e->fault, code); }
static uint8_t *memory(struct gpu_emu *e, uint64_t addr, uint64_t bytes)
{
    if (addr + bytes > e->ddr_bytes) {
        fprintf(stderr,"GPU command %u: DDR address 0x%llx length %llu exceeds %u bytes\n",
                e->command_index,(unsigned long long)addr,(unsigned long long)bytes,
                e->ddr_bytes);
        abort();
    }
    return e->ddr + addr;
}
static void bounds(struct gpu_emu *e, int *x0, int *y0, int *x1, int *y1)
{
    struct cmd_set_target *t = &e->target;
    *x0 = imax(t->sc_x0, t->tgt_x0); *y0 = imax(t->sc_y0, t->tgt_y0);
    *x1 = imin(t->sc_x1, t->tgt_x0 + e->width);
    *y1 = imin(t->sc_y1, t->tgt_y0 + e->height);
}
static int address(const struct gpu_emu *e, int x, int y)
{ return (y-e->target.tgt_y0)*e->width + x-e->target.tgt_x0; }
static void stencil_op(struct gpu_emu *e, int i, int op)
{
    if (!op || !e->pixel.st_wmask) return;
    int old = e->stencil[i], value;
    switch (op) {
    case 1: value = 0; break;
    case 2: value = e->pixel.st_ref; break;
    case 3: value = imin(255,old+1); break;
    case 4: value = imax(0,old-1); break;
    default: value = old^255; break;
    }
    int mask = e->pixel.st_wmask;
    e->stencil[i] = (uint8_t)((old & (255^mask)) | (value & mask));
}
static int stencil_test(int func, int ref, int st)
{
    switch (func) {
    case 0: return 0;
    case 1: return ref < st;
    case 2: return ref == st;
    case 3: return ref <= st;
    case 4: return ref > st;
    case 5: return ref != st;
    case 6: return ref >= st;
    default: return 1;
    }
}
static int factor(int mode, int src, int dst, int alpha, int constant)
{
    switch (mode) {
    case 0: return 0;
    case 1: return 255;
    case 2: return alpha;
    case 3: return 255-alpha;
    case 4: return src;
    case 5: return 255-src;
    case 6: return dst;
    case 7: return 255-dst;
    case 8: return constant;
    default: return 255-constant;
    }
}
static void pixel_at(struct gpu_emu *e, int i, int depth, struct rgba rgba,
                     int transparent)
{
    if (transparent) return;
    struct cmd_set_pixel *s = &e->pixel;
    if (s->st_func != 7 && !stencil_test(s->st_func,s->st_ref & s->st_rmask,
                                        e->stencil[i] & s->st_rmask)) {
        stencil_op(e, i, s->st_sfail); return;
    }
    if (!s->depth_func && depth > e->depth[i]) {
        stencil_op(e, i, s->st_zfail); return;
    }
    ++PERF(e, 4);
    stencil_op(e, i, s->st_zpass);
    if (s->depth_write) e->depth[i] = (uint16_t)depth;
    if (!s->color_write) return;
    if (s->bl_fs == 1 && !s->bl_fd && !s->bl_op) {
        e->color[i] = p565(rgba);
        return;
    }
    struct rgba out = expand(e->color[i]);
    for (int c = 0; c < 3; ++c) {
        int src = rgba.c[c], dst = out.c[c], alpha = rgba.c[3];
        int a = d(src*factor(s->bl_fs,src,dst,alpha,s->bl_const_a));
        int b = d(dst*factor(s->bl_fd,src,dst,alpha,s->bl_const_a));
        int value;
        switch (s->bl_op) {
        case 0: value = a+b; break;
        case 1: value = a-b; break;
        case 2: value = b-a; break;
        case 3: value = imin(a,b); break;
        default: value = imax(a,b); break;
        }
        out.c[c] = clamp(value,0,255);
    }
    e->color[i] = p565(out);
}
static void pixel(struct gpu_emu *e, int x, int y, int depth, struct rgba rgba,
                  int transparent)
{
    pixel_at(e,address(e,x,y),depth,rgba,transparent);
}
static struct rgba raw_texel(struct gpu_emu *e, int64_t u, int64_t v, int level, int group)
{
    int w = e->mip_width[level], h = e->mip_height[level];
    int x = (int)(u & (w-1)), y = (int)(v & (h-1));
    int fmt = e->texture.format, bw = fmt < 2 ? 2 : 1;
    int bx = x >> (fmt < 2), by = y >> (fmt == 0);
    int blocks_x = (w+bw-1) >> (fmt < 2);
    int a = e->mip_offset[level] + 8*((by/2)*((blocks_x+1)/2)+bx/2)
          + 2*((bx&1)+2*(by&1));
    int word = e->ram[a] | (int)e->ram[a+1]<<8;
    if (fmt == 2) return expand(word);
    int bit = fmt == 0 ? 4*((x&1)+2*(y&1)) : 8*(x&1);
    int entry = (word>>bit) & (fmt == 0 ? 15 : 255);
    uint32_t color = e->palettes[group][entry];
    struct rgba result = expand(color & 65535);
    result.c[3] = ((color>>16)&15)*17;
    return result;
}
/* Decode tiled addressing and palette expansion once per texture/group change.
 * gpu-spec 2.6: at most 256^2 + 128^2 + ... + 1 = 87381 texels. */
static void prepare_texture(struct gpu_emu *e, int group)
{
    if (!e->texel_dirty && e->texel_group == group) return;
    int base = 0;
    for (int l = 0; l < e->texture.levels; ++l) {
        e->texel_base[l] = base;
        for (int y = 0; y < e->mip_height[l]; ++y)
            for (int x = 0; x < e->mip_width[l]; ++x)
                e->texels[base++] = raw_texel(e,x,y,l,group);
    }
    e->texel_group = group;
    e->texel_dirty = 0;
}
static struct rgba texel(struct gpu_emu *e, int64_t u, int64_t v, int level, int group)
{
    (void)group;
    int w = e->mip_width[level], h = e->mip_height[level];
    return e->texels[e->texel_base[level]+(v & (h-1))*w+(u & (w-1))];
}
static struct rgba bilinear(struct gpu_emu *e, int64_t u, int64_t v, int l, int g)
{
    u = (u>>l)-128; v = (v>>l)-128;
    int64_t x = u>>8, y = v>>8;
    int fx = u&255, fy = v&255;
    struct rgba samples[] = {texel(e,x,y,l,g), texel(e,x+1,y,l,g),
                             texel(e,x,y+1,l,g), texel(e,x+1,y+1,l,g)};
    int weights[] = {(256-fx)*(256-fy), fx*(256-fy), (256-fx)*fy, fx*fy};
    struct rgba out;
    for (int c = 0; c < 4; ++c) {
        int sum = 0;
        for (int k = 0; k < 4; ++k) sum += samples[k].c[c]*weights[k];
        out.c[c] = (sum+32768)>>16;
    }
    return out;
}
static struct rgba sample(struct gpu_emu *e, int64_t u, int64_t v, int lod,
                          int group, int nearest)
{
    if (nearest) return texel(e,u>>8,v>>8,0,group);
    struct cmd_set_tex *t = &e->texture;
    lod = clamp(lod+t->lod_bias*16, 0, (t->levels-1)*256);
    int l = lod>>8;
    if (!t->sample) return texel(e,u>>(8+l),v>>(8+l),l,group);
    struct rgba a = bilinear(e,u,v,l,group);
    if (t->sample == 1 || l == t->levels-1) return a;
    struct rgba b = bilinear(e,u,v,l+1,group);
    for (int c = 0; c < 4; ++c) a.c[c] = (a.c[c]*(256-(lod&255))+b.c[c]*(lod&255)+128)>>8;
    return a;
}
static void quad(struct gpu_emu *e, struct quad q)
{
    ++PERF(e,3);
    int x0, y0, x1, y1;
    bounds(e,&x0,&y0,&x1,&y1);
    x0 = imax(x0,q.x); x1 = imin(x1,q.x+q.w);
    y0 = imax(y0,q.y); y1 = imin(y1,q.y+q.h);
    if (x0 >= x1 || y0 >= y1) return;
    prepare_texture(e,q.pal_group);
    const struct cmd_set_pixel *state = &e->pixel;
    /* gpu-spec 2.7's opaque, stencil-KEEP, depth-ALWAYS combination needs
     * only the transparency discard, color store and passed-pixel counter. */
    if (state->st_func == 7 && state->depth_func && !state->depth_write
        && !state->st_zpass && state->color_write && state->bl_fs == 1
        && !state->bl_fd && !state->bl_op) {
        int w = e->mip_width[0], h = e->mip_height[0];
        int du = q.flip_h ? -1 : 1;
        int u0 = q.u0+(q.flip_h ? q.w-1-(x0-q.x) : x0-q.x);
        uint32_t passed = 0;
        for (int y = y0; y < y1; ++y) {
            int v = q.v0+(q.flip_v ? q.h-1-(y-q.y) : y-q.y);
            const struct rgba *row = e->texels+e->texel_base[0]+(v & (h-1))*w;
            uint16_t *out = e->color+address(e,x0,y);
            for (int x = x0, u = u0; x < x1; ++x, u += du, ++out) {
                struct rgba rgba = row[u & (w-1)];
                if (rgba.c[3]) { *out = p565(rgba); ++passed; }
            }
        }
        PERF(e,4) += passed;
        return;
    }
    for (int y = y0; y < y1; ++y) {
        int row = y-q.y;
        if (q.flip_v) row = q.h-1-row;
        int i = address(e,x0,y);
        for (int x = x0; x < x1; ++x, ++i) {
            int col = x-q.x;
            if (q.flip_h) col = q.w-1-col;
            struct rgba rgba = sample(e,(q.u0+col)*256,(q.v0+row)*256,0,q.pal_group,1);
            int transparent = !rgba.c[3];
            rgba.c[3] = d(rgba.c[3]*q.alpha);
            pixel_at(e,i,q.depth,rgba,transparent);
        }
    }
}
static int64_t edge(struct vec a, struct vec b, int64_t x, int64_t y)
{ return (b.c[0]-a.c[0])*(y-a.c[1]) - (b.c[1]-a.c[1])*(x-a.c[0]); }
static void setup(struct planes *p, struct vec *v, int64_t area)
{
    p->x = imin(v[0].c[0],imin(v[1].c[0],v[2].c[0])) >> 4;
    p->y = imin(v[0].c[1],imin(v[1].c[1],v[2].c[1])) >> 4;
    int64_t dx[3], dy[3];
    for (int i = 0; i < 3; ++i) {
        struct vec a = v[(i+1)%3], b = v[(i+2)%3];
        dx[i] = (a.c[1]-b.c[1])*16; dy[i] = (b.c[0]-a.c[0])*16;
    }
    int ae = bit_length(area)-1;
    int64_t inv = reciprocal(area,ae);
    const int fractions[] = {0,30,38,38,16,16,16};
    for (int c = 0; c < 7; ++c) {
        int64_t maximum = v[0].c[c+2];
        for (int i = 1; i < 3; ++i) if (v[i].c[c+2] > maximum) maximum = v[i].c[c+2];
        int bits = c >= 1 && c <= 3 ? bit_length(maximum) : c == 0 ? 16 : 24;
        int exp = bits-32;
        wide values[3], gx = 0, gy = 0;
        for (int i = 0; i < 3; ++i) {
            values[i] = shift(v[i].c[c+2],exp);
            gx += dx[i]*values[i]; gy += dy[i]*values[i];
        }
        gx = shift(gx*inv,30+ae); gy = shift(gy*inv,30+ae);
        p->coeff[c][0] = values[0]+shift((16*p->x+8-v[0].c[0])*gx
                                      +(16*p->y+8-v[0].c[1])*gy,4);
        p->coeff[c][1] = gx; p->coeff[c][2] = gy;
        p->exp[c] = exp-fractions[c];
    }
    for (int a = 0; a < 2; ++a) for (int c = 0; c < 3; ++c)
        p->grad[a][c] = normal(p->coeff[c+1][a+1],p->exp[c+1]);
}
static void triangle(struct gpu_emu *e, struct vec a, struct vec b, struct vec c)
{
    int64_t area = edge(a,b,c.c[0],c.c[1]);
    int cull = e->pixel.cull;
    if (!area || (cull == 1 && area > 0) || (cull == 2 && area < 0)) return;
    if (area < 0) { struct vec t = b; b = c; c = t; area = -area; }
    ++PERF(e,2);
    struct vec v[] = {a,b,c};
    int x0,y0,x1,y1;
    bounds(e,&x0,&y0,&x1,&y1);
    x0 = imax(x0,(imin(a.c[0],imin(b.c[0],c.c[0]))+7)>>4);
    y0 = imax(y0,(imin(a.c[1],imin(b.c[1],c.c[1]))+7)>>4);
    x1 = imin(x1,((imax(a.c[0],imax(b.c[0],c.c[0]))-8)>>4)+1);
    y1 = imin(y1,((imax(a.c[1],imax(b.c[1],c.c[1]))-8)>>4)+1);
    if (x0 >= x1 || y0 >= y1) return;
    prepare_texture(e,e->texture.pal_group);
    int inclusive[3];
    for (int i = 0; i < 3; ++i) {
        struct vec s = v[(i+1)%3], t = v[(i+2)%3];
        inclusive[i] = t.c[1] < s.c[1] || (t.c[1] == s.c[1] && t.c[0] > s.c[0]);
    }
    struct planes p;
    setup(&p,v,area);
    /* s12.4 endpoints differ by < 2^17; edge products and increments fit
     * signed 36 bits. Coverage stepping is exact in int64_t (spec 2.13.1). */
    int64_t edge_row[3], edge_dx[3], edge_dy[3];
    for (int i = 0; i < 3; ++i) {
        struct vec s = v[(i+1)%3], t = v[(i+2)%3];
        edge_row[i] = edge(s,t,16*x0+8,16*y0+8)-!inclusive[i];
        edge_dx[i] = -16*(t.c[1]-s.c[1]);
        edge_dy[i] = 16*(t.c[0]-s.c[0]);
    }
    int fixed[7], fixed_value[7];
    for (int k = 0; k < 7; ++k) {
        fixed[k] = !p.coeff[k][1] && !p.coeff[k][2];
        fixed_value[k] = 0;
        if (fixed[k] && (k == 0 || k >= 4))
            fixed_value[k] = clamp(shift(p.coeff[k][0],-p.exp[k]),0,k ? 255 : 65535);
    }
    int only_uv = fixed[0] && fixed[1] && fixed[4] && fixed[5] && fixed[6];
    struct number fixed_w = {0,0};
    if (fixed[1]) fixed_w = inverse(normal(p.coeff[1][0],p.exp[1]));
    wide row[7];
    for (int k = 0; k < 7; ++k)
        row[k] = p.coeff[k][0]+(x0-p.x)*p.coeff[k][1]+(y0-p.y)*p.coeff[k][2];
    for (int y = y0; y < y1; ++y) {
        wide attrs[7]; memcpy(attrs,row,sizeof attrs);
        int64_t weights[3]; memcpy(weights,edge_row,sizeof weights);
        for (int x = x0; x < x1; ++x) {
            int covered = (weights[0] | weights[1] | weights[2]) >= 0;
            for (int i = 0; i < 3; ++i) weights[i] += edge_dx[i];
            if (covered) {
                int depth = fixed[0] ? fixed_value[0] : clamp(shift(attrs[0],-p.exp[0]),0,65535);
                struct number w = fixed[1] ? fixed_w : inverse(normal(attrs[1],p.exp[1]));
                struct number uv[2];
                int64_t coords[2];
                for (int k = 0; k < 2; ++k) {
                    uv[k] = multiply(normal(attrs[k+2],p.exp[k+2]),w);
                    /* 2.13.12: coordinate outputs fit signed 32-bit Q8. */
                    coords[k] = shift64(uv[k].m,-uv[k].e-8);
                }
                wide span = 0;
                /* A single mip level makes LOD immaterial to all sampling modes. */
                if (e->texture.levels > 1)
                for (int axis = 0; axis < 2; ++axis) for (int k = 0; k < 2; ++k) {
                    struct number delta = subtract(p.grad[axis][k+1],
                                                   multiply(uv[k],p.grad[axis][0]));
                    struct number n = multiply(delta,w);
                    wide s = shift(absw(n.m),-n.e-16);
                    if (s > span) span = s;
                }
                struct rgba rgba = sample(e,coords[0],coords[1],span ? logarithm(span) : 0,
                                          e->texture.pal_group,0);
                int transparent = !rgba.c[3];
                for (int k = 0; k < 3; ++k)
                    rgba.c[k] = d(rgba.c[k]*(fixed[k+4] ? fixed_value[k+4]
                                          : clamp(shift(attrs[k+4],-p.exp[k+4]),0,255)));
                pixel(e,x,y,depth,rgba,transparent);
            }
            if (only_uv) {
                attrs[2] += p.coeff[2][1]; attrs[3] += p.coeff[3][1];
            } else for (int k = 0; k < 7; ++k) attrs[k] += p.coeff[k][1];
        }
        for (int k = 0; k < 7; ++k) row[k] += p.coeff[k][2];
        for (int i = 0; i < 3; ++i) edge_row[i] += edge_dy[i];
    }
}

static struct vec transform(struct gpu_emu *e, struct vertex v)
{
    struct vec out;
    int64_t pos[] = {v.x,v.y,v.z,1};
    for (int r = 0; r < 4; ++r) {
        wide sum = 0;
        for (int c = 0; c < 4; ++c) sum += (wide)e->matrix[4*r+c]*pos[c];
        out.c[r] = clamp(sum,-(INT64_C(1)<<39),(INT64_C(1)<<39)-1);
    }
    int64_t dot = v.nx*e->light.lx + v.ny*e->light.ly + v.nz*e->light.lz;
    if (dot < 0) dot = 0;
    struct rgba color = expand(v.color);
    out.c[4] = v.u; out.c[5] = v.v;
    for (int c = 0; c < 3; ++c) {
        int bit = 16-8*c;
        int amb = (e->light.amb_rgb>>bit)&255, dir = (e->light.dir_rgb>>bit)&255;
        wide illumination = ((wide)amb<<21) + dot*dir;
        out.c[c+6] = clamp(div_round(color.c[c]*illumination,255<<21),0,255)*65536;
    }
    return out;
}
static int64_t distance(struct vec v, int plane)
{
    switch (plane) {
    case 0: return v.c[3]-(1<<12);
    case 1: return 4*v.c[3]+v.c[0];
    case 2: return 4*v.c[3]-v.c[0];
    case 3: return 4*v.c[3]+v.c[1];
    default: return 4*v.c[3]-v.c[1];
    }
}
static struct vec project(struct gpu_emu *e, struct vec v)
{
    int64_t q = reciprocal(v.c[3],16);
    wide scale = (wide)1<<46;
    struct cmd_set_target *t = &e->target;
    struct vec out;
    out.c[0] = clamp(t->vp_x0*16 + div_round(((wide)v.c[0]*q+scale)*t->vp_w*8,
                                           scale),-65536,65535);
    out.c[1] = clamp(t->vp_y0*16 + div_round((scale-(wide)v.c[1]*q)*t->vp_h*8,
                                           scale),-65536,65535);
    out.c[2] = clamp(div_round((wide)v.c[2]*q*65535,scale),0,65535);
    out.c[3] = q; out.c[4] = v.c[4]*q; out.c[5] = v.c[5]*q;
    for (int i = 6; i < 9; ++i) out.c[i] = v.c[i];
    return out;
}
static int clip(struct vec *polygon, int count)
{
    struct vec result[16];
    for (int plane = 0; plane < 5 && count; ++plane) {
        int n = 0;
        struct vec prev = polygon[count-1];
        int64_t dp = distance(prev,plane);
        for (int i = 0; i < count; ++i) {
            struct vec cur = polygon[i];
            int64_t dc = distance(cur,plane);
            if ((dp >= 0) != (dc >= 0)) {
                for (int k = 0; k < 9; ++k)
                    result[n].c[k] = (int64_t)div_round((wide)prev.c[k]*dc
                                                        -(wide)cur.c[k]*dp,dc-dp);
                ++n;
            }
            if (dc >= 0) result[n++] = cur;
            prev = cur; dp = dc;
        }
        count = n; memcpy(polygon,result,(size_t)n*sizeof *polygon);
    }
    return count;
}
static void draw_triangle(struct gpu_emu *e, const uint8_t *data)
{
    PERF(e,1) += 3;
    struct vec polygon[16];
    for (int i = 0; i < 3; ++i) polygon[i] = transform(e,decode_vertex(data+16*i));
    int count = clip(polygon,3);
    for (int i = 0; i < count; ++i) polygon[i] = project(e,polygon[i]);
    for (int i = 1; i < count-1; ++i) triangle(e,polygon[0],polygon[i],polygon[i+1]);
}
static void object_quad(struct gpu_emu *e, struct obj o)
{
    struct quad q = {0};
    q.x = (o.px>>8)-o.w/2; q.y = (o.py>>8)-o.h/2;
    q.w = o.w; q.h = o.h; q.u0 = o.u0; q.v0 = o.v0;
    q.flip_h = o.flip_h; q.flip_v = o.flip_v;
    q.pal_group = o.pal_group; q.alpha = o.alpha; q.depth = o.depth;
    quad(e,q);
}
static void append_list(struct gpu_emu *e, int hit, uint32_t index, uint32_t value)
{
    uint32_t max = hit ? R(e,OBJ_HIT_MAX) : R(e,OBJ_FREE_MAX);
    uint32_t base = hit ? R(e,OBJ_HIT_BASE) : R(e,OBJ_FREE_BASE);
    if (index < max) store32(memory(e,(uint64_t)base+4*(uint64_t)index,4),value);
    else R(e,OBJ_STAT) |= hit ? 1 : 2;
}
static void rect(uint32_t a, uint32_t b, int *r)
{
    r[0] = sign_bits(a,16); r[1] = sign_bits(a>>16,16);
    r[2] = sign_bits(b,16); r[3] = sign_bits(b>>16,16);
}
static void objects(struct gpu_emu *e, struct cmd_obj_step f)
{
    uint32_t hit = 0, free_count = 0, alive = 0;
    int live[4], targets[8][4];
    R(e,OBJ_STAT) = 0;
    rect(R(e,OBJ_LIVE_RECT0),R(e,OBJ_LIVE_RECT1),live);
    for (int i = 0; i < 8; ++i)
        rect(e->regs[EDRV32_GPU_OBJ_TGT0_OFFSET(i)/4],
             e->regs[EDRV32_GPU_OBJ_TGT1_OFFSET(i)/4],targets[i]);
    for (uint32_t i = 0; i < f.count; ++i) {
        uint8_t *p = memory(e,f.addr+32*(uint64_t)i,32);
        uint8_t original[32];
        memcpy(original,p,sizeof original);
        struct obj o = decode_obj(original);
        if (!o.alive) continue;
        if (!f.step) {
            ++alive;
            if (f.draw) object_quad(e,o);
            continue;
        }
        o.vx = sign_bits((uint32_t)(o.vx+shift(o.ax,4)),16);
        o.vy = sign_bits((uint32_t)(o.vy+shift(o.ay,4)),16);
        o.px = sign_bits((uint32_t)(o.px+o.vx),24);
        o.py = sign_bits((uint32_t)(o.py+o.vy),24);
        if (o.life && !--o.life) o.alive = 0;
        if (!(live[0]*256 <= o.px && o.px < live[2]*256
              && live[1]*256 <= o.py && o.py < live[3]*256)) o.alive = 0;
        if (o.alive) {
            ++alive;
            int x = o.px>>8, y = o.py>>8;
            for (int t = 0; t < 8; ++t) {
                int *r = targets[t];
                if ((o.tgt_mask & (1<<t)) && x+o.col_hw > r[0] && x-o.col_hw < r[2]
                    && y+o.col_hh > r[1] && y-o.col_hh < r[3]) {
                    append_list(e,1,hit,i | (uint32_t)t<<24); ++hit;
                }
            }
        } else { append_list(e,0,free_count,i); ++free_count; }
        update_obj(original,o);
        memcpy(p,original,sizeof original);
        if (f.draw && o.alive) object_quad(e,o);
    }
    R(e,OBJ_HIT_COUNT) = hit & 0xffffff;
    R(e,OBJ_FREE_COUNT) = free_count & 0xffffff;
    R(e,OBJ_ALIVE_COUNT) = alive & 0xffffff;
}
static void resolve(struct gpu_emu *e, struct cmd_resolve f)
{
    for (int y = f.y0; y < f.y1; ++y) {
        uint8_t *out = memory(e,f.base+y*(uint64_t)f.stride+f.x0*2,2*(f.x1-f.x0));
        for (int x = f.x0; x < f.x1; ++x) {
            uint16_t color = e->color[address(e,x,y)];
            if (f.fxaa) {
                int xs[] = {x,x,x,imax(f.x0,x-1),imin(f.x1-1,x+1)};
                int ys[] = {y,imax(f.y0,y-1),imin(f.y1-1,y+1),y,y};
                struct rgba samples[5]; int lum[5], lo = 255, hi = 0;
                for (int k = 0; k < 5; ++k) {
                    samples[k] = expand(e->color[address(e,xs[k],ys[k])]);
                    lum[k] = (samples[k].c[0]+2*samples[k].c[1]+samples[k].c[2])>>2;
                    lo = imin(lo,lum[k]); hi = imax(hi,lum[k]);
                }
                if (hi-lo >= f.fxaa_th) {
                    int left = abs(lum[1]-lum[2]) >= abs(lum[3]-lum[4]) ? 1 : 3;
                    struct rgba a = {{0,0,0,255}};
                    for (int k = 0; k < 3; ++k)
                        a.c[k] = (2*samples[0].c[k]+samples[left].c[k]
                                  +samples[left+1].c[k])>>2;
                    color = p565(a);
                }
            }
            out[2*(x-f.x0)] = (uint8_t)color;
            out[2*(x-f.x0)+1] = (uint8_t)(color>>8);
        }
    }
}
/* A draw batch only reads DDR/texture state. Each horizontal section owns
 * disjoint target rows and executes every primitive in the original order.
 * Geometry/primitive PERF totals are identical in every section; pixels sum. */
static void draw_batch(struct gpu_emu *e, uint32_t addr, int count, int triangles)
{
    for (int i = 0; i < count; ++i) {
        if (triangles) draw_triangle(e,memory(e,addr+48*(uint64_t)i,48));
        else quad(e,decode_quad(memory(e,addr+16*(uint64_t)i,16)));
    }
}
#if GPU_EMU_THREADS > 1
struct draw_job {
    struct gpu_emu local;
    uint32_t addr;
    int count, triangles;
#ifdef _WIN32
    HANDLE thread;
#else
    pthread_t thread;
#endif
};
#ifdef _WIN32
static DWORD WINAPI draw_worker(void *arg)
#else
static void *draw_worker(void *arg)
#endif
{
    struct draw_job *job = arg;
    draw_batch(&job->local,job->addr,job->count,job->triangles);
    return 0;
}
static void parallel_draw(struct gpu_emu *e, uint32_t addr, int count, int triangles)
{
    /* Small batches cost less than creating host threads and copying state. */
    if (count < 128) { draw_batch(e,addr,count,triangles); return; }
    struct draw_job *jobs = malloc(GPU_EMU_THREADS*sizeof *jobs);
    if (!jobs) { fputs("GPU draw jobs allocation failed\n",stderr); abort(); }
    int x0,y0,x1,y1;
    bounds(e,&x0,&y0,&x1,&y1);
    int rows = imax(0,y1-y0);
    for (int i = 0; i < GPU_EMU_THREADS; ++i) {
        struct draw_job *j = &jobs[i];
        memcpy(&j->local,e,sizeof *e);
        j->local.texels = malloc(87392*sizeof *e->texels);
        if (!j->local.texels) { fputs("GPU texture allocation failed\n",stderr); abort(); }
        j->local.texel_dirty = 1;
        j->local.target.sc_y0 = y0+rows*i/GPU_EMU_THREADS;
        j->local.target.sc_y1 = y0+rows*(i+1)/GPU_EMU_THREADS;
        j->addr = addr; j->count = count; j->triangles = triangles;
        if (i == GPU_EMU_THREADS-1) {
            draw_worker(j);
            continue;
        }
#ifdef _WIN32
        j->thread = CreateThread(NULL,0,draw_worker,j,0,NULL);
        if (!j->thread) { fputs("GPU CreateThread failed\n",stderr); abort(); }
#else
        int error = pthread_create(&j->thread,NULL,draw_worker,j);
        if (error) { fprintf(stderr,"GPU pthread_create: %s\n",strerror(error)); abort(); }
#endif
    }
    uint32_t pixels = 0;
    for (int i = 0; i < GPU_EMU_THREADS; ++i) {
        struct draw_job *j = &jobs[i];
        if (i != GPU_EMU_THREADS-1) {
#ifdef _WIN32
            if (WaitForSingleObject(j->thread,INFINITE) != WAIT_OBJECT_0) {
                fputs("GPU thread wait failed\n",stderr); abort();
            }
            if (!CloseHandle(j->thread)) { fputs("GPU CloseHandle failed\n",stderr); abort(); }
#else
            int error = pthread_join(j->thread,NULL);
            if (error) { fprintf(stderr,"GPU pthread_join: %s\n",strerror(error)); abort(); }
#endif
        }
        pixels += PERF(&j->local,4)-PERF(e,4);
        free(j->local.texels);
    }
    for (int i = 1; i <= 3; ++i) PERF(e,i) = PERF(&jobs[0].local,i);
    PERF(e,4) += pixels;
    free(jobs);
}
#else
#define parallel_draw draw_batch
#endif
static void command(struct gpu_emu *e, const uint8_t *data)
{
    switch (data[0]) {
    case 1: {
        struct cmd_set_matrix f = decode_cmd_set_matrix(data);
        const uint8_t *p = memory(e,f.addr,64);
        for (int i = 0; i < 16; ++i) e->matrix[i] = (int32_t)load32(p+4*i);
        break;
    }
    case 2: e->light = decode_cmd_set_light(data); break;
    case 3: {
        struct cmd_set_tex t = decode_cmd_set_tex(data);
        int offsets[16], widths[16], heights[16];
        int offset = t.offset, bw = t.format < 2 ? 2 : 1, bh = t.format == 0 ? 2 : 1;
        for (int i = 0; i < t.levels; ++i) {
            int w = imax(1,(1<<t.log2_w)>>i), h = imax(1,(1<<t.log2_h)>>i);
            offsets[i] = offset; widths[i] = w; heights[i] = h;
            int bx = (w+bw-1)/bw, by = (h+bh-1)/bh;
            offset += 8*((bx+1)/2)*((by+1)/2);
        }
        if (offset > RAM_BYTES) fail(e,3);
        e->texture = t;
        e->texel_dirty = 1;
        for (int i = 0; i < t.levels; ++i) {
            e->mip_offset[i] = offsets[i];
            e->mip_width[i] = widths[i]; e->mip_height[i] = heights[i];
        }
        break;
    }
    case 4: e->pixel = decode_cmd_set_pixel(data); break;
    case 5: e->target = decode_cmd_set_target(data); break;
    case 16: {
        struct cmd_clear f = decode_cmd_clear(data);
        int x0,y0,x1,y1; bounds(e,&x0,&y0,&x1,&y1);
        for (int y = y0; y < y1; ++y) for (int x = x0; x < x1; ++x) {
            int i = address(e,x,y);
            if (f.en_color) e->color[i] = f.color;
            if (f.en_depth) e->depth[i] = f.depth;
            if (f.en_stencil) e->stencil[i] = f.stencil;
        }
        break;
    }
    case 32: {
        struct cmd_draw_tri f = decode_cmd_draw_tri(data);
        parallel_draw(e,f.addr,f.count,1);
        break;
    }
    case 33: {
        struct cmd_draw_quad f = decode_cmd_draw_quad(data);
        parallel_draw(e,f.addr,f.count,0);
        break;
    }
    case 34: objects(e,decode_cmd_obj_step(data)); break;
    case 48: {
        struct cmd_tex_load f = decode_cmd_tex_load(data);
        if (f.dst+f.bytes > RAM_BYTES) fail(e,4);
        e->texel_dirty = 1;
        memcpy(e->ram+f.dst,memory(e,f.src,f.bytes),(size_t)f.bytes);
        break;
    }
    case 49: {
        struct cmd_pal_load f = decode_cmd_pal_load(data);
        e->texel_dirty = 1;
        for (int i = 0; i < f.entries; ++i)
            e->palettes[f.group][i] = load32(memory(e,f.src+4*(uint64_t)i,4));
        break;
    }
    case 64: resolve(e,decode_cmd_resolve(data)); break;
    default: fail(e,1);
    }
}
static void reset(struct gpu_emu *e)
{
    uint8_t *ddr = e->ddr; uint32_t bytes = e->ddr_bytes;
    uint16_t *color = e->color, *depth = e->depth; uint8_t *stencil = e->stencil;
    struct rgba *texels = e->texels;
    memset(e,0,sizeof *e); e->ddr = ddr; e->ddr_bytes = bytes;
    e->texels = texels; e->texel_dirty = 1;
    e->color = color; e->depth = depth; e->stencil = stencil;
    memset(color,0,PIXELS*sizeof *color); memset(depth,0,PIXELS*sizeof *depth);
    memset(stencil,0,PIXELS);
    e->width = 640; e->height = 180;
    for (size_t i = 0; i < sizeof register_descs/sizeof *register_descs; ++i)
        e->regs[register_descs[i].offset/4] = register_descs[i].reset;
}
struct gpu_emu *gpu_emu_create(uint8_t *ddr, uint32_t ddr_bytes)
{
    struct gpu_emu *e = malloc(sizeof *e);
    if (!e) return NULL;
    e->color = malloc(PIXELS*sizeof *e->color);
    e->depth = malloc(PIXELS*sizeof *e->depth);
    e->stencil = malloc(PIXELS);
    e->texels = malloc(87392*sizeof *e->texels);
    if (!e->color || !e->depth || !e->stencil || !e->texels) { gpu_emu_destroy(e); return NULL; }
    e->ddr = ddr; e->ddr_bytes = ddr_bytes; reset(e);
    return e;
}
void gpu_emu_destroy(struct gpu_emu *e)
{
    if (e) { free(e->color); free(e->depth); free(e->stencil); free(e->texels); free(e); }
}
uint32_t gpu_emu_read(struct gpu_emu *e, uint32_t offset)
{
    for (size_t i = 0; i < sizeof register_descs/sizeof *register_descs; ++i)
        if (offset == register_descs[i].offset) return e->regs[offset/4];
    return 0;
}
int gpu_emu_irq(const struct gpu_emu *e) { return !!(R(e,IRQ_STAT) & R(e,IRQ_EN)); }
static void run(struct gpu_emu *e)
{
    R(e,STATUS) = 1;
    int error = setjmp(e->fault);
    if (error) {
        R(e,STATUS) = 6; R(e,ERR_CODE) = error; R(e,IRQ_STAT) |= 2;
        return;
    }
    for (uint32_t i = 0; i < R(e,DESC_COUNT); ++i) {
        e->command_index = i;
        command(e,memory(e,(uint64_t)R(e,DESC_BASE)+32*(uint64_t)i,32));
    }
    R(e,STATUS) = 2; ++R(e,DONE_COUNT); R(e,IRQ_STAT) |= 1;
}
void gpu_emu_write(struct gpu_emu *e, uint32_t offset, uint32_t value)
{
    for (size_t i = 0; i < sizeof register_descs/sizeof *register_descs; ++i) {
        const struct register_desc *r = &register_descs[i];
        if (offset != r->offset) continue;
        value &= r->mask;
        if (!r->access) return;
        if (r->access == 2) e->regs[offset/4] &= ~value;
        else if (offset == EDRV32_GPU_DOORBELL_OFFSET) run(e);
        else if (offset == EDRV32_GPU_CTRL_OFFSET) {
            R(e,CTRL) = value & EDRV32_GPU_CTRL_ENABLE_MASK;
            if (value & EDRV32_GPU_CTRL_SOFT_RST_MASK) reset(e);
        } else {
            e->regs[offset/4] = value;
            if (offset == EDRV32_GPU_TGT_CFG_OFFSET) {
                e->width = value & 1 ? 1280 : 640;
                e->height = value & 1 ? 90 : 180;
            }
        }
        return;
    }
}
