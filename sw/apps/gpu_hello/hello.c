/* File: hello.c
 * Spec: gpu 2.1-2.10; aud 2; S-0b example.
 * Description: Two-stripe textured cube, 100 GPU-stepped bouncing objects,
 * quad text and a controller-pitched stereo square wave, shared on all targets.
 * Clock domain: CPU or host; media clocks provided by platform.
 */
#include "hello.h"
#include "plat.h"
#include "gpu.h"
#include "aud.h"
#include "disp.h"
#include "mmio.h"
#include "plic.h"
#include "regs/disp_gpu_regs.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
static struct gpu_command *commands;
static struct gpu_vertex *vertices;
static struct gpu_quad *text;
static struct gpu_object *objects;
static uint32_t *hits, *released, *palette;
static uint32_t previous_hits;
static uint16_t *surface[2];
static int32_t *matrix;
static uint8_t *textures;
static struct aud_ring ring;
static unsigned phase;
static uint32_t sound[1024];
static void fill_sound(struct aud_ring *buffer, const struct aud_event *event, void *context)
{
    (void)event; (void)context;
    unsigned keys = plat_keys();
    unsigned hz = 220 + ((keys & PLAT_UP) ? 220 : 0) + ((keys & PLAT_RIGHT) ? 110 : 0);
    if (keys & PLAT_DOWN) hz /= 2;
    if (keys & PLAT_LEFT) hz = hz * 3 / 4;
    unsigned count = aud_space(buffer) / 4;
    if (count > 1024) count = 1024;
    count &= ~7u;
    for (unsigned i = 0; i < count; ++i) {
        phase = (phase + hz) % 48000;
        uint16_t value = (uint16_t)(int16_t)(phase < 24000 ? 3000 : -3000);
        sound[i] = value | (uint32_t)value << 16;
    }
    aud_write(buffer, sound, count);
}
static void audio_irq(void *context)
{
    (void)context;
    struct aud_event event = aud_irq_handle(&ring);
    if (event.error) { plat_printf("AUD error %u\n", event.error); abort(); }
}
static void texture_store(unsigned base, unsigned width, unsigned x, unsigned y,
                          unsigned format, uint16_t value)
{
    unsigned bx = format == 1 ? x / 2 : x;
    unsigned blocks = format == 1 ? width / 2 : width;
    unsigned address = base + 8 * ((y / 2) * ((blocks + 1) / 2) + bx / 2) +
                       2 * ((bx & 1) + 2 * (y & 1));
    if (format == 1) textures[address + (x & 1)] = (uint8_t)value;
    else memcpy(textures + address, &value, 2);
}
static void make_textures(void)
{
    unsigned base = 0;
    for (unsigned level = 0; level < 7; ++level) {
        unsigned width = 64u >> level;
        for (unsigned y = 0; y < width; ++y) for (unsigned x = 0; x < width; ++x) {
            unsigned checker = ((x >> (level < 3 ? 3 - level : 0)) ^
                                (y >> (level < 3 ? 3 - level : 0))) & 1;
            uint16_t color = checker ? 0xfd20 : 0x159f;
            texture_store(base, width, x, y, 2, color);
        }
        base += 8 * ((width + 1) / 2) * ((width + 1) / 2);
    }
    for (unsigned y = 0; y < 16; ++y) for (unsigned x = 0; x < 16; ++x) {
        int dx = (int)x - 7, dy = (int)y - 7;
        unsigned color = dx * dx + dy * dy < 56 ? (x < 5 || y < 5 ? 2 : 3) : 0;
        texture_store(16384, 16, x, y, 1, (uint16_t)color);
    }
    /* Five-bit rows: digits followed by F R A M E, read left-to-right. */
    static const uint8_t glyphs[15][7] = {
        {14,17,19,21,25,17,14}, {4,12,4,4,4,4,14}, {14,17,1,2,4,8,31},
        {30,1,1,14,1,1,30}, {2,6,10,18,31,2,2}, {31,16,16,30,1,1,30},
        {14,16,16,30,17,17,14}, {31,1,2,4,8,8,8}, {14,17,17,14,17,17,14},
        {14,17,17,15,1,1,14}, {31,16,16,30,16,16,16},
        {30,17,17,30,20,18,17}, {14,17,17,31,17,17,17},
        {17,27,21,21,17,17,17}, {31,16,16,30,16,16,31}
    };
    for (unsigned g = 0; g < 15; ++g) for (unsigned y = 0; y < 7; ++y)
        for (unsigned x = 0; x < 5; ++x)
            texture_store(32768, 128, g * 8 + x, y, 1,
                          (glyphs[g][y] & (16u >> x)) ? 1 : 0);
    palette[0] = 0;
    palette[1] = 0xfffffu;
    palette[2] = 0xfff60u;
    palette[3] = 0xf07ffu;
}
static void bounce_objects(void)
{
    for (unsigned i = 0; i < previous_hits; ++i) {
        unsigned object = gpu_hit_object(hits[i]);
        unsigned target = gpu_hit_target(hits[i]);
        uint32_t *word = &objects[object].word[EDRV32_GPU_OBJ_VX_OFFSET / 4];
        unsigned shift = target < 2 ? EDRV32_GPU_OBJ_VX_POS : EDRV32_GPU_OBJ_VY_POS;
        uint32_t mask = target < 2 ? EDRV32_GPU_OBJ_VX_MASK : EDRV32_GPU_OBJ_VY_MASK;
        int velocity = (int16_t)((*word & mask) >> shift);
        if ((target == 0 || target == 2) ? velocity < 0 : velocity > 0)
            *word = (*word & ~mask) | (((uint32_t)-velocity << shift) & mask);
    }
}
void hello_init(void)
{
    plat_init();
    commands = plat_dma_alloc(64 * sizeof(*commands), 64);
    vertices = plat_dma_alloc(36 * sizeof(*vertices), 32);
    matrix = plat_dma_alloc(64, 32);
    text = plat_dma_alloc(12 * sizeof(*text), 32);
    objects = plat_dma_alloc(100 * sizeof(*objects), 32);
    hits = plat_dma_alloc(400 * sizeof(*hits), 32);
    released = plat_dma_alloc(100 * sizeof(*released), 32);
    palette = plat_dma_alloc(256 * sizeof(*palette), 32);
    textures = plat_dma_alloc(33792, 32);
    surface[0] = plat_dma_alloc(640 * 360 * 2, 4096);
    surface[1] = plat_dma_alloc(640 * 360 * 2, 4096);
    make_textures();
    for (unsigned i = 0; i < 100; ++i) {
        struct gpu_object_args args = {
            .alive = 1, .tgt_mask = 15, .px = (24 + i % 10 * 64) * 256,
            .py = (28 + i / 10 * 32) * 256,
            .vx = (uint32_t)(int32_t)((i & 1 ? 1 : -1) * (180 + (int)(i % 3) * 90)),
            .vy = (uint32_t)(int32_t)((i & 2 ? 1 : -1) * (160 + (int)(i % 5) * 40)),
            .col_hw = 8, .col_hh = 8, .w = 16, .h = 16, .alpha = 255, .depth = 1000
        };
        gpu_object(&objects[i], &args);
    }
    aud_init(&ring, plat_dma_alloc(16384, 512), 16384, 4096);
    fill_sound(&ring, NULL, NULL);
    fill_sound(&ring, NULL, NULL);
    plat_irq_register(EDRV32_PLIC_SOURCE_AUD, audio_irq, NULL);
    aud_irq_register(1, fill_sound, NULL);
    aud_enable(1);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_LAYER_CTRL_OFFSET,
        EDRV32_DISP_GPU_LAYER_CTRL_L0_EN_MASK | EDRV32_DISP_GPU_LAYER_CTRL_L0_X2_MASK);
}
static void cube_matrix(unsigned frame)
{
    double angle = frame * 0.023;
    double c = cos(angle), s = sin(angle), ct = cos(angle * 0.7), st = sin(angle * 0.7);
    /* Object unit cube -> perspective with W = 4 + rotated Z, aspect 16:9. */
    double m[16] = {
        c * 1.2, s * st * 1.2, s * ct * 1.2, 0,
        0, ct * 2.1, -st * 2.1, 0,
        -s * 0.5, c * st * 0.5, c * ct * 0.5, 1.6,
        -s, c * st, c * ct, 4
    };
    for (unsigned i = 0; i < 16; ++i) matrix[i] = (int32_t)lround(m[i] * 65536);
}
static void cube_vertices(void)
{
    static const int8_t corners[8][3] = {
        {-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},
        {-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}
    };
    static const uint8_t faces[6][4] = {
        {0,1,2,3},{5,4,7,6},{4,0,3,7},{1,5,6,2},{3,2,6,7},{4,5,1,0}
    };
    static const unsigned colors[6] = {0xffff, 0xadff, 0xffe0, 0xfd7f, 0x87ff, 0xffff};
    static const unsigned order[6] = {0,1,2,0,2,3};
    static const unsigned uv[4][2] = {{0,0},{63,0},{63,63},{0,63}};
    for (unsigned f = 0; f < 6; ++f) for (unsigned v = 0; v < 6; ++v) {
        unsigned j = order[v];
        const int8_t *p = corners[faces[f][j]];
        struct gpu_vertex_args args = {
            .x = (uint32_t)(int32_t)p[0], .y = (uint32_t)(int32_t)p[1],
            .z = (uint32_t)(int32_t)p[2], .nz = 127,
            .color = colors[f], .u = uv[j][0] * 256, .v = uv[j][1] * 256
        };
        gpu_vertex(&vertices[f * 6 + v], &args);
    }
}
static void frame_text(unsigned frame)
{
    unsigned glyph[12] = {10,11,12,13,14,15,0,0,0,0,0,0};
    for (int i = 11; i >= 6; --i) { glyph[i] = frame % 10; frame /= 10; }
    for (unsigned i = 0; i < 12; ++i) {
        struct gpu_quad_args args = {
            .x = 16 + i * 8, .y = 16, .w = 8, .h = 8, .alpha = 255,
            .u0 = glyph[i] * 8, .v0 = 0, .depth = 0
        };
        gpu_quad(&text[i], &args);
    }
}
void hello_frame(unsigned frame)
{
    bounce_objects();
    cube_matrix(frame);
    cube_vertices();
    frame_text(frame);
    /* Each frame supplies complete GPU state and textures, including after reset.
     * This also makes the frame-150 DDR/register capture independently replayable. */
    unsigned n = 0;
#define EMIT(name, ...) gpu_##name(&commands[n++], &(struct gpu_##name##_args){__VA_ARGS__})
    EMIT(tex_load, .src = gpu_physical(textures), .dst = 0, .bytes = 33792);
    EMIT(pal_load, .group = 0, .src = gpu_physical(palette), .entries = 256);
    EMIT(set_matrix, .addr = gpu_physical(matrix));
    EMIT(set_light, .amb_rgb = 0xffffff);
    for (unsigned stripe = 0; stripe < 2; ++stripe) {
        unsigned y = stripe * 180;
        EMIT(set_target, .tgt_y0 = y, .sc_x1 = 640, .sc_y0 = y, .sc_y1 = y + 180,
             .vp_w = 640, .vp_h = 360);
        EMIT(clear, .color = 0x0863, .depth = 65535, .en_color = 1, .en_depth = 1,
             .en_stencil = 1);
        EMIT(set_pixel, .depth_write = 1, .color_write = 1, .st_func = 7,
             .st_rmask = 255, .st_wmask = 255, .bl_fs = 1);
        EMIT(set_tex, .log2_w = 6, .log2_h = 6, .format = 2, .levels = 7, .sample = 2);
        EMIT(draw_tri, .addr = gpu_physical(vertices), .count = 12);
        EMIT(set_pixel, .depth_func = 1, .color_write = 1, .st_func = 7,
             .st_rmask = 255, .st_wmask = 255, .bl_fs = 2, .bl_fd = 3);
        EMIT(set_tex, .offset = 16384, .log2_w = 4, .log2_h = 4, .format = 1, .levels = 1);
        EMIT(obj_step, .step = stripe == 0, .draw = 1,
             .addr = gpu_physical(objects), .count = 100);
        EMIT(set_tex, .offset = 32768, .log2_w = 7, .log2_h = 3, .format = 1, .levels = 1);
        EMIT(draw_quad, .addr = gpu_physical(text), .count = 12);
        EMIT(resolve, .base = gpu_physical(surface[frame & 1]), .stride = 1280,
             .x1 = 640, .y0 = y, .y1 = y + 180);
    }
#undef EMIT
    mmio_write32(EDRV32_GPU_BASE + EDRV32_GPU_CTRL_OFFSET, EDRV32_GPU_CTRL_SOFT_RST_MASK);
    gpu_live_rect(-32, -32, 672, 392);
    gpu_object_lists(hits, 400, released, 100);
    gpu_collision_target(0, -32, -32, 8, 392);
    gpu_collision_target(1, 632, -32, 672, 392);
    gpu_collision_target(2, -32, -32, 672, 8);
    gpu_collision_target(3, -32, 352, 672, 392);
    const struct gpu_range sources[] = {
        {(uintptr_t)vertices, 36 * sizeof(*vertices)}, {(uintptr_t)matrix, 64},
        {(uintptr_t)textures, 33792}, {(uintptr_t)palette, 1024},
        {(uintptr_t)objects, 100 * sizeof(*objects)}, {(uintptr_t)text, 12 * sizeof(*text)}
    };
    const struct gpu_range results[] = {
        {(uintptr_t)objects, 100 * sizeof(*objects)}, {(uintptr_t)hits, 1600}
    };
    /* Split submission at first OBJ_STEP so software retains its hit count before
     * the second stripe's STEP=0 clears the specified per-command counters. */
    const unsigned first = 4 + 8;
    struct gpu_batch batch = {commands, first, sources, 6, results, 2};
    gpu_submit(&batch);
    struct gpu_event event = gpu_wait();
    if (event.error) { plat_printf("GPU error %u\n", event.error); abort(); }
    previous_hits = event.hit_count;
    batch.commands = commands + first;
    batch.count = n - first;
    gpu_submit(&batch);
    event = gpu_wait();
    if (event.error) { plat_printf("GPU error %u\n", event.error); abort(); }
    disp_submit(DISP_L0, gpu_physical(surface[frame & 1]), 1280);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_CTRL_OFFSET,
                 EDRV32_DISP_GPU_CTRL_ENABLE_MASK);
}
