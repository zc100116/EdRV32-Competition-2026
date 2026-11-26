/* runtime.c — gpu-spec 2.1–2.10; two stripes, GPU HUD and deterministic draw lists.
 * CPU frame thread; GPU owns submitted DDR ranges until gpu_wait returns.
 */
#include "test.h"
#include "aud.h"
#include "disp.h"
#include "cache.h"
#include "mmio.h"
#include "font8x16.h"
#include "regs/disp_gpu_regs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "assets.h"
struct test_state test;
static struct gpu_command *commands;
static struct aud_ring audio_ring;
static uint32_t sound_buffer[1024];
static unsigned oscillator;
static volatile unsigned sound_left;
static volatile unsigned sound_hz;
static unsigned menu_choice;
static unsigned hud_first;
static uint64_t previous_frame;
static uint64_t gpu_wait_elapsed;
static uint16_t *aa_buffer;
#define EMIT(name, ...) gpu_##name(&commands[n++], &(struct gpu_##name##_args){__VA_ARGS__})
unsigned test_color(unsigned r, unsigned g, unsigned b)
{
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
}
static void audio_fill(struct aud_ring *ring, const struct aud_event *event, void *context)
{
    (void)event;
    (void)context;
    unsigned count = aud_space(ring) / 4;
    if (count > 1024) count = 1024;
    count &= ~7u;
    for (unsigned i = 0; i < count; ++i) {
        int sample = 0;
        if (sound_left) {
            oscillator = (oscillator + sound_hz) % 48000;
            sample = (oscillator < 24000 ? 1 : -1) * (int)(sound_left / 2);
            --sound_left;
        }
        uint16_t value = (uint16_t)(int16_t)sample;
        sound_buffer[i] = value | (uint32_t)value << 16;
    }
    aud_write(ring, sound_buffer, count);
}
static void audio_irq(void *context)
{
    (void)context;
    struct aud_event event = aud_irq_handle(&audio_ring);
    if (event.error) {
        plat_printf("GPU test AUD error %u\n", event.error);
        abort();
    }
}
void test_sound(unsigned effect)
{
    static const unsigned hz[4] = {1200, 630, 110, 1800};
    sound_hz = hz[effect];
    sound_left = effect == 2 ? 3600 : effect == 3 ? 2400 : 800;
}
static unsigned texture_byte(unsigned x, unsigned y)
{
    unsigned bx = x / 2;
    unsigned address = 8 * ((y / 2) * 64 + bx / 2) + 2 * ((bx & 1) + 2 * (y & 1));
    return address + (x & 1);
}
void test_init(void)
{
    plat_init();
    commands = plat_dma_alloc(512 * sizeof(*commands), 64);
    test.quads = plat_dma_alloc(TEST_QUAD_MAX * sizeof(*test.quads), 32);
    test.vertices = plat_dma_alloc(TEST_TRI_MAX * 3 * sizeof(*test.vertices), 32);
    test.objects = plat_dma_alloc(TEST_OBJECT_MAX * sizeof(*test.objects), 32);
    test.hits = plat_dma_alloc(TEST_OBJECT_MAX * 4, 32);
    test.released = plat_dma_alloc(TEST_OBJECT_MAX * 4, 32);
    test.matrices = plat_dma_alloc(128, 32);
    test.textures = plat_dma_alloc(TEST_TEXTURE_BYTES, 32);
    test.palettes = plat_dma_alloc(16 * 1024, 32);
    for (unsigned i = 0; i < 2; ++i)
        test.surface[i] = plat_dma_alloc(640 * 360 * 2, 4096);
    aa_buffer = plat_dma_alloc(640 * 360 * 2, 32);
    memcpy(test.textures, test_asset_texture, TEST_TEXTURE_BYTES);
    memset(test.palettes, 0, 16 * 1024);
    static const uint16_t colors[16] = {
        0xffff, 0xffff, 0x3fff, 0xfc9f, 0xfd29, 0x0434, 0xbadf, 0xffa5,
        0x0865, 0x1b12, 0x2298, 0x447d, 0x6d5f, 0x977f, 0x27e9, 0xf986
    };
    for (unsigned p = 0; p < 16; ++p) {
        memcpy(test.palettes+p*256, test_asset_palette, sizeof(test_asset_palette));
        test.palettes[p*256+1] = 0xf0000 | colors[p];
        for (unsigned i = 16; i < 32; ++i)
            test.palettes[p*256+i] = ((i-16) << 16) | colors[p ? p : 1];
        if (p == 15)
            for (unsigned i = 1; i < 256; ++i)
                test.palettes[p*256+i] = (test.palettes[p*256+i] & 0xf0000) | 0xffff;
    }
    /* Existing public-domain font; 16 columns, six rows at atlas y=128. */
    for (unsigned g = 0; g < 95; ++g)
        for (unsigned y = 0; y < 16; ++y)
            for (unsigned x = 0; x < 8; ++x)
                test.textures[texture_byte((g % 16) * 8 + x, 128 + (g / 16) * 16 + y)] =
                    (font8x16[g][y] & (128u >> x)) ? 1 : 0;
    memset(test.matrices, 0, 128);
    test.matrices[0] = 205; /* pixel space -> clip; s15.16 */
    test.matrices[3] = -65536;
    test.matrices[5] = -364;
    test.matrices[7] = 65536;
    test.matrices[11] = 32768;
    test.matrices[15] = 65536;
    /* Perspective, camera looks along +Z, vertices use integer world units. */
    test.matrices[16] = 49152;
    test.matrices[21] = 87381;
    test.matrices[26] = 65500;
    test.matrices[27] = -65536;
    test.matrices[30] = 65536;
    aud_init(&audio_ring, plat_dma_alloc(32768, 512), 32768, 8192);
    for (unsigned i = 0; i < 8; ++i) audio_fill(&audio_ring, NULL, NULL);
    plat_irq_register(EDRV32_PLIC_SOURCE_AUD, audio_irq, NULL);
    aud_irq_register(1, audio_fill, NULL);
    aud_enable(1);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_LAYER_CTRL_OFFSET,
        EDRV32_DISP_GPU_LAYER_CTRL_L0_EN_MASK | EDRV32_DISP_GPU_LAYER_CTRL_L0_X2_MASK);
    unsigned n = 0;
    EMIT(tex_load, .src = gpu_physical(test.textures), .bytes = TEST_TEXTURE_BYTES);
    for (unsigned p = 0; p < 16; ++p)
        EMIT(pal_load, .group = p, .src = gpu_physical(test.palettes + p * 256), .entries = 256);
    const struct gpu_range sources[] = {
        {(uintptr_t)test.textures, TEST_TEXTURE_BYTES}, {(uintptr_t)test.palettes, 16384}
    };
    struct gpu_batch batch = {commands, n, sources, 2, NULL, 0};
    gpu_submit(&batch);
    struct gpu_event event = gpu_wait();
    if (event.error) { plat_printf("GPU asset load error %u\n", event.error); abort(); }
    test.aa = 1;
    previous_frame = test_clock_us();
}
void test_select(unsigned game, unsigned mode, unsigned level, unsigned filter)
{
    test.game = game;
    test.mode = mode;
    test.level = level;
    test.filter = filter;
    test.cpu = game == 1 && mode == 2;
    test.tick = 0;
    test.score = 0;
    test.health = 100;
    test.player_x = 320;
    test.player_y = game == 1 ? 290 : 0;
    if (game == 1) test2d_init();
    if (game == 2) test3d_init();
}
void test_draw(unsigned kind, unsigned first, unsigned count, unsigned texture,
               unsigned blend, unsigned matrix)
{
    test.draws[test.draws_count++] = (struct test_draw){kind, first, count, texture, blend, matrix};
    /* DRAW_QUAD.ADDR is 32-byte aligned; each quad occupies only 16 bytes.
     * Leave an unused slot after odd batches so the next batch starts aligned. */
    if (kind == 0) test.quads_count = (test.quads_count + 1) & ~1u;
}
void test_quad(int x, int y, unsigned w, unsigned h, unsigned u, unsigned v,
               unsigned palette, unsigned alpha)
{
    struct gpu_quad_args q = {.x = (uint32_t)x, .y = (uint32_t)y, .w = w, .h = h,
        .u0 = u, .v0 = v, .pal_group = palette, .alpha = alpha};
    gpu_quad(&test.quads[test.quads_count++], &q);
}
void test_rect(int x, int y, unsigned w, unsigned h, unsigned palette)
{
    /* 8x8 white area repeats through a palette filled with the same color. */
    for (unsigned j = 0; j < h; j += 8)
        for (unsigned i = 0; i < w; i += 8)
            test_quad(x + (int)i, y + (int)j, w-i < 8 ? w-i : 8,
                      h-j < 8 ? h-j : 8, 248, 248, palette, 255);
}
void test_text(int x, int y, const char *text, unsigned palette)
{
    while (*text) {
        unsigned c = (unsigned char)*text++;
        if (c < 128) {
            unsigned g = c-32;
            test_quad(x, y, 8, 16, (g%16)*8, 128+(g/16)*16, palette, 255);
            x += 8;
        } else {
            unsigned cp = (c & 15) << 12;
            cp |= ((unsigned char)*text++ & 63) << 6;
            cp |= (unsigned char)*text++ & 63;
            unsigned g = 0;
            /* The shipped BDF subset contains every compiled HUD string. */
            while (test_chinese[g] != cp) ++g;
            test_quad(x, y+2, 12, 12, 128+(g%10)*12, 128+(g/10)*12, palette, 255);
            x += 12;
        }
    }
}
void test_sprite(int x, int y, int w, int h, unsigned u, unsigned v,
                 unsigned tw, unsigned th)
{
    static const unsigned order[6] = {0,1,2,0,2,3};
    for (unsigned j = 0; j < 6; ++j) {
        unsigned k = order[j];
        unsigned right = k == 1 || k == 2;
        unsigned bottom = k > 1;
        test_vertex(x+(right ? w : 0), y+(bottom ? h : 0), 0, 0xffff,
                    (u+(right ? tw : 0))*256, (v+(bottom ? th : 0))*256, 0);
    }
}
void test_scaled_text(int x, int y, const char *text, unsigned scale, unsigned color)
{
    for (; *text; ++text, x += 8*(int)scale/256) {
        unsigned first = test.triangles;
        unsigned g = (unsigned char)*text-32;
        test_sprite(x, y, 8*(int)scale/256, 16*(int)scale/256,
                    (g%16)*8, 128+(g/16)*16, 8, 16);
        for (unsigned i = first; i < test.triangles; ++i)
            test.vertices[i].word[2] = (test.vertices[i].word[2] & 0xffff) | (color << 16);
    }
}
void test_vertex(int x, int y, int z, unsigned color, unsigned u, unsigned v, int ny)
{
    struct gpu_vertex_args args = {.x = (uint32_t)x, .y = (uint32_t)y,
        .z = (uint32_t)z, .ny = (uint32_t)ny, .nz = 100, .color = color, .u = u, .v = v};
    gpu_vertex(&test.vertices[test.triangles++], &args);
}
static struct gpu_event submit(unsigned n, int objects)
{
    struct gpu_range sources[] = {
        {(uintptr_t)test.quads, test.quads_count * sizeof(*test.quads)},
        {(uintptr_t)test.vertices, test.triangles * sizeof(*test.vertices)},
        {(uintptr_t)test.matrices, 128},
        {(uintptr_t)test.objects, test.objects_count * sizeof(*test.objects)}
    };
    struct gpu_range results[] = {
        {(uintptr_t)test.objects, test.objects_count * sizeof(*test.objects)},
        {(uintptr_t)test.hits, TEST_OBJECT_MAX * 4},
        {(uintptr_t)test.released, TEST_OBJECT_MAX * 4}
    };
    struct gpu_batch batch = {commands, n, sources, 4, results, objects ? 3u : 0u};
    uint64_t wait_start = test_clock_us();
    gpu_submit(&batch);
#ifndef GPU_TEST_PC
    /* Board submission is CPU/cache work; host submission executes the GPU model. */
    wait_start = test_clock_us();
#endif
    struct gpu_event event = gpu_wait();
    gpu_wait_elapsed += test_clock_us()-wait_start;
    if (event.error || event.object_status) {
        plat_printf("GPU test error %u, object status %u\n", event.error, event.object_status);
        abort();
    }
    test.command_count += n;
    return event;
}
static void render_gpu(void)
{
    for (unsigned stripe = 0; stripe < 2; ++stripe) {
        unsigned y = stripe * 180;
        unsigned n = 0;
        EMIT(set_target, .tgt_y0 = y, .sc_x1 = 640, .sc_y0 = y, .sc_y1 = y + 180,
             .vp_w = 640, .vp_h = 360);
        EMIT(clear, .color = 0x0865, .depth = 65535, .en_color = 1, .en_depth = 1,
             .en_stencil = 1);
        EMIT(set_light, .ly = 12000, .lz = 11000, .dir_rgb = 0x404040, .amb_rgb = 0xbfbfbf);
        for (unsigned i = test.cpu ? hud_first : 0; i < test.draws_count; ++i) {
            struct test_draw *d = &test.draws[i];
            EMIT(set_matrix, .addr = gpu_physical(test.matrices + d->matrix * 16));
            EMIT(set_pixel, .depth_func = d->matrix ? 0 : 1,
                 .depth_write = d->matrix && !d->blend ? 1 : 0, .color_write = 1, .st_func = 7,
                 .bl_fs = d->blend ? 2 : 1, .bl_fd = d->blend == 2 ? 1 : d->blend ? 3 : 0);
            if (d->texture && d->texture != 6)
                EMIT(set_tex, .offset = TEST_MIP_BASE+(d->texture-1)*TEST_MIP_STRIDE,
                     .log2_w = 6, .log2_h = 6,
                     .format = 2, .levels = 7, .sample = test.filter);
            else
                EMIT(set_tex, .offset = d->texture == 6 ? 65536 : 0,
                     .log2_w = 8, .log2_h = 8, .format = 1, .levels = 1);
            if (d->kind == 0) {
                EMIT(draw_quad, .addr = gpu_physical(test.quads + d->first), .count = d->count);
            } else if (d->kind == 1) {
                EMIT(draw_tri, .addr = gpu_physical(test.vertices + d->first), .count = d->count);
            } else {
                EMIT(obj_step, .draw = 1, .addr = gpu_physical(test.objects+d->first),
                     .count = d->count);
            }
        }
        unsigned low = test.cpu ? (stripe ? 336 : 0) : y;
        unsigned high = test.cpu ? (stripe ? 360 : 52) : y + 180;
        EMIT(resolve, .fxaa = test.aa, .fxaa_th = 32,
             .base = gpu_physical(test.surface[test.frame & 1]), .stride = 1280,
             .x1 = 640, .y0 = low, .y1 = high);
        submit(n, 0);
    }
}
static unsigned field(uint32_t word, uint32_t mask, unsigned shift)
{
    return (word & mask) >> shift;
}
#define QGET(q, f) field((q)->word[EDRV32_GPU_QUAD_##f##_OFFSET / 4], \
    EDRV32_GPU_QUAD_##f##_MASK, EDRV32_GPU_QUAD_##f##_POS)
#define OGET(q, f) field((q)->word[EDRV32_GPU_OBJ_##f##_OFFSET / 4], \
    EDRV32_GPU_OBJ_##f##_MASK, EDRV32_GPU_OBJ_##f##_POS)
static int signed_bits(unsigned value, unsigned bits)
{
    return (int)(value ^ (1u << (bits-1))) - (int)(1u << (bits-1));
}
static unsigned software_texture;
static unsigned software_tint = 0xffff;
static void software_pixel(int x, int y, unsigned u, unsigned v, unsigned p,
                           unsigned alpha, unsigned blend)
{
    if (x < 0 || x >= 640 || y < 0 || y >= 360) return;
    unsigned index = test.textures[software_texture+texture_byte(u & 255, v & 255)];
    uint32_t rgba = test.palettes[p * 256 + index];
    if (!(rgba >> 16)) return;
    unsigned tint = software_tint;
    rgba = (rgba & 0xf0000) |
           (((((rgba >> 11)&31)*((tint >> 11)&31)+15)/31) << 11) |
           (((((rgba >> 5)&63)*((tint >> 5)&63)+31)/63) << 5) |
           (((rgba&31)*(tint&31)+15)/31);
    unsigned sa = (((rgba >> 16) * 17) * alpha + 127) / 255;
    uint16_t *dst = &test.surface[test.frame & 1][y * 640 + x];
    if (!blend) { *dst = (uint16_t)rgba; return; }
    unsigned sr = (rgba >> 11) & 31;
    unsigned sg = (rgba >> 5) & 63;
    unsigned sb = rgba & 31;
    unsigned dr = (*dst >> 11) & 31;
    unsigned dg = (*dst >> 5) & 63;
    unsigned db = *dst & 31;
    sr = (sr << 3) | (sr >> 2);
    sg = (sg << 2) | (sg >> 4);
    sb = (sb << 3) | (sb >> 2);
    dr = (dr << 3) | (dr >> 2);
    dg = (dg << 2) | (dg >> 4);
    db = (db << 3) | (db >> 2);
    unsigned fd = blend == 2 ? 255 : 255-sa;
    unsigned r = (sr * sa + 127) / 255 + (dr * fd + 127) / 255;
    unsigned g = (sg * sa + 127) / 255 + (dg * fd + 127) / 255;
    unsigned b = (sb * sa + 127) / 255 + (db * fd + 127) / 255;
    *dst = (uint16_t)test_color(r > 255 ? 255 : r, g > 255 ? 255 : g, b > 255 ? 255 : b);
}
static void software_quad(const struct gpu_quad *q, unsigned blend)
{
    int x0 = signed_bits(QGET(q, X), 12);
    int y0 = signed_bits(QGET(q, Y), 12);
    unsigned w = QGET(q, W);
    unsigned h = QGET(q, H);
    for (unsigned y = 0; y < h; ++y)
        for (unsigned x = 0; x < w; ++x)
            software_pixel(x0 + (int)x, y0 + (int)y, QGET(q, U0)+x, QGET(q, V0)+y,
                           QGET(q, PAL_GROUP), QGET(q, ALPHA), blend);
}
static int edge(int ax, int ay, int bx, int by, int x, int y)
{
    return (bx-ax)*(y-ay)-(by-ay)*(x-ax);
}
static void software_tri(unsigned first, unsigned count, unsigned blend)
{
    for (unsigned t = 0; t < count; ++t) {
        int x[3], y[3], u[3], v[3];
        for (unsigned i = 0; i < 3; ++i) {
            struct gpu_vertex *p = test.vertices + first + t*3+i;
            x[i] = (int16_t)(p->word[0] & 65535);
            y[i] = (int16_t)(p->word[0] >> 16);
            u[i] = p->word[3] & 65535;
            v[i] = p->word[3] >> 16;
        }
        software_tint = test.vertices[first+t*3].word[2] >> 16;
        int area = edge(x[0], y[0], x[1], y[1], x[2], y[2]);
        if (!area) continue;
        int xmin = x[0], xmax = x[0], ymin = y[0], ymax = y[0];
        for (unsigned i = 1; i < 3; ++i) {
            if (x[i] < xmin) xmin = x[i];
            if (x[i] > xmax) xmax = x[i];
            if (y[i] < ymin) ymin = y[i];
            if (y[i] > ymax) ymax = y[i];
        }
        if (xmin < 0) xmin = 0;
        if (xmax > 639) xmax = 639;
        if (ymin < 0) ymin = 0;
        if (ymax > 359) ymax = 359;
        for (int py = ymin; py <= ymax; ++py) for (int px = xmin; px <= xmax; ++px) {
            int a = edge(x[1]*2, y[1]*2, x[2]*2, y[2]*2, px*2+1, py*2+1);
            int b = edge(x[2]*2, y[2]*2, x[0]*2, y[0]*2, px*2+1, py*2+1);
            int c = area*4-a-b;
            if ((area > 0 && a >= 0 && b >= 0 && c >= 0) ||
                (area < 0 && a <= 0 && b <= 0 && c <= 0)) {
                unsigned tu = (unsigned)((a*u[0]+b*u[1]+c*u[2])/(area*4)) >> 8;
                unsigned tv = (unsigned)((a*v[0]+b*v[1]+c*v[2])/(area*4)) >> 8;
                software_pixel(px, py, tu, tv, 0, 255, blend);
            }
        }
    }
}
static void software_aa(void)
{
    uint16_t *surface = test.surface[test.frame & 1];
    memcpy(aa_buffer, surface, 640*360*2);
    for (int y = 0; y < 360; ++y) for (int x = 0; x < 640; ++x) {
        unsigned c[5] = {aa_buffer[y*640+x], aa_buffer[(y ? y-1 : y)*640+x],
            aa_buffer[(y < 359 ? y+1 : y)*640+x], aa_buffer[y*640+(x ? x-1 : x)],
            aa_buffer[y*640+(x < 639 ? x+1 : x)]};
        int rgb[5][3], lum[5], lo = 255, hi = 0;
        for (unsigned i = 0; i < 5; ++i) {
            rgb[i][0] = ((c[i] >> 11)*255+15)/31;
            rgb[i][1] = (((c[i] >> 5)&63)*255+31)/63;
            rgb[i][2] = ((c[i]&31)*255+15)/31;
            lum[i] = (rgb[i][0]+2*rgb[i][1]+rgb[i][2]) >> 2;
            if (lum[i] < lo) lo = lum[i];
            if (lum[i] > hi) hi = lum[i];
        }
        if (hi-lo < 32) continue;
        unsigned a = abs(lum[1]-lum[2]) >= abs(lum[3]-lum[4]) ? 1 : 3;
        surface[y*640+x] = (uint16_t)test_color((2*rgb[0][0]+rgb[a][0]+rgb[a+1][0])/4,
            (2*rgb[0][1]+rgb[a][1]+rgb[a+1][1])/4,
            (2*rgb[0][2]+rgb[a][2]+rgb[a+1][2])/4);
    }
}
static void render_software(void)
{
    uint16_t *surface = test.surface[test.frame & 1];
    for (unsigned i = 0; i < 640*360; ++i) surface[i] = 0x0865;
    for (unsigned i = 0; i < hud_first; ++i) {
        struct test_draw *d = &test.draws[i];
        software_texture = d->texture == 6 ? 65536 : 0;
        software_tint = 0xffff;
        if (d->kind == 0) {
            for (unsigned j = 0; j < d->count; ++j)
                software_quad(test.quads+d->first+j, d->blend);
        } else if (d->kind == 1) software_tri(d->first, d->count, d->blend);
        else for (unsigned j = 0; j < d->count; ++j) {
            struct gpu_object *o = test.objects+d->first+j;
            if (!OGET(o, ALIVE)) continue;
            unsigned w = OGET(o, W), h = OGET(o, H);
            int x0 = signed_bits(OGET(o, PX), 24)/256-(int)(w/2);
            int y0 = signed_bits(OGET(o, PY), 24)/256-(int)(h/2);
            for (unsigned y = 0; y < h; ++y) for (unsigned x = 0; x < w; ++x)
                software_pixel(x0+(int)x, y0+(int)y, OGET(o, U0)+x, OGET(o, V0)+y,
                               OGET(o, PAL_GROUP), OGET(o, ALPHA), d->blend);
        }
    }
    if (test.aa) software_aa();
    cache_clean((uintptr_t)surface, 640*360*2);
}
static void object_step(void)
{
    if (!test.cpu) {
        gpu_live_rect(-64, -64, 704, 424);
        gpu_object_lists(test.hits, TEST_OBJECT_MAX, test.released, TEST_OBJECT_MAX);
        unsigned n = 0;
        EMIT(obj_step, .step = 1, .addr = gpu_physical(test.objects), .count = test.objects_count);
        struct gpu_event event = submit(n, 1);
        test.hit_count = event.hit_count;
        test.free_count = event.free_count;
        test.alive_count = event.alive_count;
    }
    /* Software STEP is in the 2D module, sharing collision targets and respawn policy. */
    test2d_results();
}
static void hud(void)
{
    hud_first = test.draws_count;
    unsigned first = test.quads_count;
    test_rect(0, 0, 640, 48, 8);
    test_rect(0, 336, 640, 24, 8);
    char line[96];
    const char *name = test.game == 1 ? "PRISM PATROL" : "CANDY CANYON";
    const char *mode = test.mode == 0 ? "正常" : test.mode == 1 ? "压测" :
                       test.game == 1 ? "CPU 对比" : "纹理测试";
    snprintf(line, sizeof(line), "%s / %s / %s / AA %s", name, mode,
             test.cpu ? "CPU" : "GPU", test.aa ? "ON" : "OFF");
    test_text(8, 2, line, 1);
    unsigned count = test.game == 1 ? test.alive_count : test.triangles/3;
    snprintf(line, sizeof(line), "%s %u  FPS %u.%u  CPU %u.%03u ms",
             test.game == 1 ? "OBJ" : "TRI", count,
             (unsigned)test.fps10/10, (unsigned)test.fps10%10,
             (unsigned)test.cpu_us/1000, (unsigned)test.cpu_us%1000);
    test_text(8, 18, line, 2);
    if (test.gpu_us) snprintf(line, sizeof(line), "GPU %u us  得分 %u  血量 %u",
                              (unsigned)test.gpu_us, test.score, test.health);
    else snprintf(line, sizeof(line), "GPU n/a  得分 %u  血量 %u", test.score, test.health);
    test_text(8, 34, line, 7);
    test_rect(520, 34, test.health, 5, test.health > 30 ? 2 : 3);
    if (test.game == 2) test3d_hud();
    const char *help = "NEXT/PREV MOVE  ENTER: CONTROLS  ESC: MENU";
    test_text(8, 340, help, 1);
    test_draw(0, first, test.quads_count-first, 0, 1, 0);
}
void test_frame(void)
{
    uint64_t start = test_clock_us();
    gpu_wait_elapsed = 0;
    uint64_t elapsed = start-previous_frame;
    if (test.frame && elapsed) test.fps10 = (uint32_t)(10000000/elapsed);
    previous_frame = start;
    uint32_t keys = test_input_keys();
    uint32_t pressed = keys & ~test.previous_keys;
    test.previous_keys = keys;
    ++test.frame;
    test.triangles = 0;
    test.quads_count = 0;
    test.draws_count = 0;
    test.command_count = 0;
    uint32_t gpu_start = mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_PERF_OFFSET(0));
    uint32_t pixel_start = mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_PERF_OFFSET(4));
    if (pressed & (PLAT_START | PLAT_SELECT)) {
        test.game = 0; /* board fourth button is esc */
        menu_choice = 0;
    }
    if (!test.game) {
        if (pressed & (PLAT_LEFT | PLAT_RIGHT)) menu_choice ^= 1;
        if (pressed & PLAT_A) test_select(menu_choice+1, 0, 0, 2);
    } else if ((pressed & PLAT_A) && !(test.game & 4)) {
        /* Four physical buttons: enter opens a small control menu. */
        test.game |= 4;
        menu_choice = 0;
    }
    if (test.game & 4) {
        if (pressed & PLAT_RIGHT) menu_choice = (menu_choice+1)%6;
        if (pressed & PLAT_LEFT) menu_choice = (menu_choice+5)%6;
        if ((pressed & PLAT_A) && (test.tick & 0x80000000u)) {
            unsigned game = test.game & 3;
            if (menu_choice == 0) test_select(game, (test.mode+1)%3, 0, test.filter);
            if (menu_choice == 1) test_select(game, test.mode, (test.level+1)%7, test.filter);
            if (menu_choice == 2) test.aa ^= 1;
            if (menu_choice == 3) {
                if (game == 1) test.cpu ^= 1;
                else test.filter = (test.filter+1)%3;
            }
            if (menu_choice == 4) {
                if (game == 1) test.weapon = (test.weapon+1)%3;
                else test.checker ^= 1;
                test.game = game;
            }
            if (menu_choice == 5) test.game = game;
        }
        if (test.game & 4) test.tick |= 0x80000000u;
        test_text(100, 80, "TEST CONTROLS - NEXT/PREV SELECT, ENTER APPLY", 2);
        static const char *items[] = {"MODE: PLAY / STRESS / COMPARE-TEXTURE",
            "INCREASE LOAD LEVEL", "TOGGLE ANTI-ALIASING", "CPU-GPU / TEXTURE FILTER",
            "武器切换 / 棋盘切换", "继续"};
        for (unsigned i = 0; i < 6; ++i) {
            test_text(100, 110+(int)i*30, i == menu_choice ? ">" : " ", 7);
            test_text(124, 110+(int)i*30, items[i], i == menu_choice ? 1 : 9);
        }
        test_draw(0, 0, test.quads_count, 0, 1, 0);
        hud_first = 0;
    } else if (!test.game) {
        test_text(128, 90, "EDRV32 / GPU LAB", 2);
        test_text(128, 122, "TWO SMALL GAMES. ONE GPU.", 1);
        test_text(128, 180, menu_choice ? "  2D / PRISM PATROL" : "> 2D / PRISM PATROL", 7);
        test_text(128, 212, menu_choice ? "> 3D / CANDY CANYON" : "  3D / CANDY CANYON", 3);
        test_text(128, 280, "NEXT/PREV SELECT - ENTER PLAY", 1);
        test_draw(0, 0, test.quads_count, 0, 1, 0);
        hud_first = 0;
    } else {
        test.tick &= 0x7fffffffu;
        ++test.tick;
        if (test.game == 1) {
            test2d_update(keys);
            object_step();
            test2d_scene();
        } else {
            test3d_update(keys);
            test3d_scene();
        }
        hud();
    }
    unsigned cpu_mode = test.cpu;
    if (!test.game || (test.game & 4)) test.cpu = 0;
    if (test.cpu) render_software();
    render_gpu();
    test.cpu_us = (uint32_t)(test_clock_us()-start-gpu_wait_elapsed);
    test.cpu = cpu_mode;
    uint32_t cycles = mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_PERF_OFFSET(0))-gpu_start;
    test.gpu_us = cycles ? (cycles+179)/180 : 0; /* gpu-spec 7: initial clk_gpu 180 MHz */
    test.pixels = mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_PERF_OFFSET(4))-pixel_start;
    disp_submit(DISP_L0, gpu_physical(test.surface[test.frame & 1]), 1280);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_CTRL_OFFSET,
                 EDRV32_DISP_GPU_CTRL_ENABLE_MASK);
}
