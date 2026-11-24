/* File: gfx.c
 * Spec: ember_isles tech 1-5, E1/E2; GPU 2.1, 2.4, 2.6, 2.8-2.10.
 * Description: Night coast tiles, read-only simulation sprites, hardware particles
 * and two-stripe submission. prepare constructs CPU data; submit owns MMIO.
 * Clock domain: CPU frame; media clocks accessed only through drivers.
 */
#include "gfx2d/gfx.h"
#include "ui/ui.h"
#include "plat.h"
#include "disp.h"
#include "mmio.h"
#include "regs/disp_gpu_regs.h"
#include "atlas.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

enum { SCENE_QUADS = 512 + EMBER_ENEMIES * 3,
       EFFECT_VERTICES = (EMBER_SHOTS + EMBER_OBSTACLES) * 6,
       COMMANDS = 80 };
static struct gpu_command *commands;
static struct gpu_quad *scene;
static struct gpu_vertex *effects;
static struct gpu_object *particles;
static struct ember_ui_canvas canvas;
static uint8_t *texture;
static uint32_t *palettes;
static uint32_t *released;
static uint16_t *surface[2];
static int32_t *matrix;
static unsigned scene_count, vertex_count, particle_end, particle_next, command_count;
static unsigned resolve_command[2];
static unsigned last_frame, last_phase, have_frame, advance;
static int camera_x, camera_y, old_camera_x, old_camera_y, shake;
static uint32_t perf[16];

static int visible(int x, int y, int radius)
{
    return x + radius >= 0 && x - radius < 640 && y + radius >= 0 && y - radius < 360;
}

static void sprite(int x, int y, unsigned tile, unsigned flash, unsigned flip)
{
    if (!visible(x, y, 16)) return;
    gpu_quad(&scene[scene_count++], &(struct gpu_quad_args){
        .x = (uint32_t)(x - 16), .y = (uint32_t)(y - 16), .w = 32, .h = 32,
        .u0 = tile % 4 * 32, .v0 = tile / 4 * 32, .pal_group = flash,
        .alpha = 255, .flip_h = flip
    });
}

static void scaled_sprite(int x, int y, unsigned tile, int radius, unsigned color)
{
    if (!visible(x, y, radius)) return;
    static const unsigned order[6] = {0, 1, 2, 0, 2, 3};
    for (unsigned i = 0; i < 6; ++i) {
        unsigned p = order[i];
        int right = p == 1 || p == 2;
        int bottom = p >= 2;
        gpu_vertex(&effects[vertex_count++], &(struct gpu_vertex_args){
            .x = (uint32_t)(x + (right ? radius : -radius) - 320),
            .y = (uint32_t)(180 - y - (bottom ? radius : -radius)),
            .color = color, .nz = 127,
            .u = (tile % 4 * 32 + (right ? 32 : 0)) * 256,
            .v = (tile / 4 * 32 + (bottom ? 32 : 0)) * 256
        });
    }
}

static void particle(int x, int y, int vx, int vy, unsigned life,
                     unsigned u, unsigned v, unsigned size)
{
    gpu_object(&particles[particle_next], &(struct gpu_object_args){
        .alive = 1, .life = life, .px = (uint32_t)(x * 256), .py = (uint32_t)(y * 256),
        .vx = (uint32_t)vx, .vy = (uint32_t)vy, .ay = 48,
        .w = size, .h = size, .alpha = 255, .u0 = u, .v0 = v
    });
    ++particle_next;
    if (particle_next > particle_end) particle_end = particle_next;
    /* A fixed visual ring replaces the oldest emitted effect after 8000 entries. */
    if (particle_next == EMBER_PARTICLES) particle_next = 0;
}

static void burst(int x, int y, unsigned count, unsigned seed)
{
    static const int16_t velocity[16][2] = {
        {256,0},{237,98},{181,181},{98,237},{0,256},{-98,237},{-181,181},{-237,98},
        {-256,0},{-237,-98},{-181,-181},{-98,-237},{0,-256},{98,-237},{181,-181},{237,-98}
    };
    for (unsigned i = 0; i < count; ++i) {
        unsigned a = (i + seed) & 15;
        int speed = 1 + (int)((seed + i) % 3);
        particle(x, y, velocity[a][0] * speed, velocity[a][1] * speed - 128,
                 20 + (seed + i) % 22, 0, 192, 8);
    }
}

static void damage(int x, int y, unsigned value)
{
    char digits[8];
    (void)snprintf(digits, sizeof(digits), "%u", value);
    int left = x - (int)strlen(digits) * 3;
    for (unsigned i = 0; digits[i]; ++i) {
        unsigned code = (unsigned)digits[i] - 32;
        particle(left + (int)i * 6, y - 16, 0, -240, 38,
                 code % 16 * 8, 128 + code / 16 * 8, 8);
    }
}

static unsigned update_particles(const struct ember_sim *sim)
{
    unsigned alive = 0;
    int dx = (old_camera_x - camera_x) * 256;
    int dy = (old_camera_y - camera_y) * 256;
    for (unsigned i = 0; i < particle_end; ++i) {
        uint32_t *word = particles[i].word;
        if (!(word[0] & EDRV32_GPU_OBJ_ALIVE_MASK)) continue;
        ++alive;
        unsigned px = EDRV32_GPU_OBJ_PX_OFFSET / 4;
        unsigned py = EDRV32_GPU_OBJ_PY_OFFSET / 4;
        word[px] = (word[px] & ~EDRV32_GPU_OBJ_PX_MASK) |
                   ((word[px] + (uint32_t)dx) & EDRV32_GPU_OBJ_PX_MASK);
        word[py] = (word[py] & ~EDRV32_GPU_OBJ_PY_MASK) |
                   ((word[py] + (uint32_t)dy) & EDRV32_GPU_OBJ_PY_MASK);
    }
    if (advance) {
        for (unsigned i = 0; i < sim->events.count; ++i) {
            const struct ember_event *e = &sim->events.item[i];
            int x = e->x / EMBER_Q - camera_x;
            int y = e->y / EMBER_Q - camera_y;
            if (!visible(x, y, 32)) continue;
            if (e->kind == 1) damage(x, y, e->value);
            if (e->kind == 2 || e->kind == 3 || e->kind == 4)
                burst(x, y, e->kind == 2 ? 12 : 8, i + sim->frame);
            if (e->kind == 5 || e->kind == 6 || e->kind == 9)
                burst(x, y, 48, i + sim->frame);
            if (e->kind == 8 || e->kind == 5) shake = 9;
        }
        if ((sim->frame & 3) == 0) {
            /* Campfire embers have no simulation owner and never affect combat. */
            int x = sim->world_width / EMBER_Q / 2 - camera_x;
            int y = sim->world_height / EMBER_Q / 2 + 64 - camera_y;
            if (visible(x, y, 16)) burst(x, y - 6, 2, sim->frame);
        }
    }
    old_camera_x = camera_x;
    old_camera_y = camera_y;
    return alive;
}

static void coast(const struct ember_sim *sim)
{
    /* Tile choice is a pure world-coordinate pattern, independent of simulation RNG. */
    int width = sim->world_width / EMBER_Q;
    int height = sim->world_height / EMBER_Q;
    int start_x = (camera_x - 31) / 32 * 32;
    int start_y = (camera_y - 31) / 32 * 32;
    for (int y = start_y; y < camera_y + 392; y += 32) {
        for (int x = start_x; x < camera_x + 672; x += 32) {
            unsigned tile = 1;
            if (x < 32 || y < 32 || x >= width - 32 || y >= height - 32 ||
                x + 16 < sim->safe_left / EMBER_Q || y + 16 < sim->safe_top / EMBER_Q ||
                x + 16 > sim->safe_right / EMBER_Q || y + 16 > sim->safe_bottom / EMBER_Q)
                tile = 0;
            else if (x < 64 || y < 64 || x >= width - 64 || y >= height - 64) tile = 2;
            else if ((x >= width / 2 - 32 && x <= width / 2 + 32) ||
                     (y >= height / 2 - 16 && y <= height / 2 + 16)) tile = 3;
            sprite(x + 16 - camera_x, y + 16 - camera_y, tile, 10, 0);
        }
    }
    sprite(width / 2 - camera_x, height / 2 + 64 - camera_y, 12, 0, 0);
    sprite(width / 2 - camera_x, height / 2 - 88 - camera_y, 13, 0, 0);
    for (unsigned i = 0; i < sim->obstacle_count; ++i) {
        const struct ember_obstacle *o = &sim->obstacles[i];
        scaled_sprite(o->x / EMBER_Q - camera_x, o->y / EMBER_Q - camera_y,
                      20, o->radius, 0xffff);
    }
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        if (sim->pickups[i].alive)
            sprite(sim->pickups[i].x / EMBER_Q - camera_x,
                   sim->pickups[i].y / EMBER_Q - camera_y, 14, 0, 0);
    }
}

static void entities(const struct ember_sim *sim)
{
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        const struct ember_enemy *e = &sim->enemies[i];
        if (!e->alive) continue;
        int x = e->x / EMBER_Q - camera_x;
        int y = e->y / EMBER_Q - camera_y;
        sprite(x, y, 5 + e->kind, e->flash != 0, e->vx < 0);
        if (e->burn && visible(x, y, 16)) sprite(x, y + 6, 15, 0, 0);
    }
    int px = sim->player.x / EMBER_Q - camera_x;
    int py = sim->player.y / EMBER_Q - camera_y;
    if (sim->phase != EMBER_MENU)
        sprite(px, py - (sim->player.dash ? 2 : 0), 4,
               sim->player.flash != 0, sim->player.facing == 2);
    for (unsigned i = 0; i < EMBER_SHOTS; ++i) {
        const struct ember_shot *s = &sim->shots[i];
        if (!s->alive) continue;
        int x = s->x / EMBER_Q - camera_x;
        int y = (s->y - s->z) / EMBER_Q - camera_y;
        unsigned tile;
        unsigned color = 0xffff;
        int radius = s->radius;
        switch (s->kind) {
        case 0: tile = 8; radius = 9; break;
        case 1: tile = 9; break;
        case 2: tile = 10; break;
        case 3: tile = 11; radius = 12; break;
        case 4: tile = 11; radius = 12; break;
        case 5: tile = 9; break;
        default: tile = 14; radius = 7; color = 0x65df; break;
        }
        scaled_sprite(x, y, tile, radius, color);
    }
}

void ember_gfx_init(void)
{
    commands = plat_dma_alloc(COMMANDS * sizeof(*commands), 64);
    scene = plat_dma_alloc(SCENE_QUADS * sizeof(*scene), 32);
    effects = plat_dma_alloc(EFFECT_VERTICES * sizeof(*effects), 32);
    particles = plat_dma_alloc(EMBER_PARTICLES * sizeof(*particles), 32);
    released = plat_dma_alloc(EMBER_PARTICLES * sizeof(*released), 32);
    canvas.rects = plat_dma_alloc(EMBER_UI_RECTS * sizeof(*canvas.rects), 32);
    canvas.glyphs = plat_dma_alloc(EMBER_UI_GLYPHS * sizeof(*canvas.glyphs), 32);
    matrix = plat_dma_alloc(64, 32);
    texture = plat_dma_alloc(EMBER_ATLAS_BYTES, 32);
    palettes = plat_dma_alloc(sizeof(ember_palette), 32);
    surface[0] = plat_dma_alloc(640 * 360 * 2, 4096);
    surface[1] = plat_dma_alloc(640 * 360 * 2, 4096);
    memcpy(texture, ember_atlas, EMBER_ATLAS_BYTES);
    memcpy(palettes, ember_palette, sizeof(ember_palette));
    memset(particles, 0, EMBER_PARTICLES * sizeof(*particles));
    memset(matrix, 0, 64);
    matrix[0] = 205;
    matrix[5] = 364;
    matrix[10] = 65536;
    matrix[15] = 65536;
    particle_end = 0;
    particle_next = 0;
    have_frame = 0;
    shake = 0;
    old_camera_x = old_camera_y = 0;
    memset(perf, 0, sizeof(perf));
}

void ember_gfx_prepare(const struct ember_sim *sim, unsigned fps, const struct ember_ui_state *ui)
{
    advance = (!have_frame || sim->frame != last_frame) && !sim->paused &&
              sim->phase != EMBER_UPGRADE;
    if (have_frame && (sim->frame < last_frame ||
        (sim->phase == EMBER_MENU && last_phase != EMBER_MENU))) {
        memset(particles, 0, EMBER_PARTICLES * sizeof(*particles));
        particle_end = particle_next = 0;
        shake = 0;
    }
    camera_x = sim->player.x / EMBER_Q - 320;
    camera_y = sim->player.y / EMBER_Q - 180;
    if (sim->phase == EMBER_MENU) {
        camera_x = sim->world_width / EMBER_Q / 2 - 320;
        camera_y = sim->world_height / EMBER_Q / 2 - 180;
    }
    if (camera_x < 0) camera_x = 0;
    if (camera_y < 0) camera_y = 0;
    if (camera_x > sim->world_width / EMBER_Q - 640)
        camera_x = sim->world_width / EMBER_Q - 640;
    if (camera_y > sim->world_height / EMBER_Q - 360)
        camera_y = sim->world_height / EMBER_Q - 360;
    if (advance && shake) --shake;
    if (shake) {
        camera_x += ((int)(sim->frame % 3) - 1) * shake / 3;
        camera_y += ((int)(sim->frame % 5) - 2) * shake / 4;
    }
    unsigned alive = update_particles(sim);
    scene_count = vertex_count = 0;
    coast(sim);
    entities(sim);
    ember_ui_build(&canvas, sim, ui, fps, perf, alive);
    last_frame = sim->frame;
    last_phase = sim->phase;
    have_frame = 1;
    unsigned n = 0;
#define EMIT(name, ...) gpu_##name(&commands[n++], &(struct gpu_##name##_args){__VA_ARGS__})
    EMIT(tex_load, .src = gpu_physical(texture), .bytes = EMBER_ATLAS_BYTES);
    for (unsigned i = 0; i < EMBER_PALETTE_GROUPS; ++i)
        EMIT(pal_load, .group = i, .src = gpu_physical(palettes + i * 256), .entries = 256);
    EMIT(set_matrix, .addr = gpu_physical(matrix));
    EMIT(set_light, .amb_rgb = 0xffffff);
    for (unsigned stripe = 0; stripe < 2; ++stripe) {
        unsigned y = stripe * 180;
        EMIT(set_target, .tgt_y0 = y, .sc_x1 = 640, .sc_y0 = y, .sc_y1 = y + 180,
             .vp_w = 640, .vp_h = 360);
        EMIT(clear, .color = 0x0843, .depth = 65535, .en_color = 1, .en_depth = 1,
             .en_stencil = 1);
        EMIT(set_pixel, .depth_func = 1, .color_write = 1, .st_func = 7,
             .bl_fs = 2, .bl_fd = 3);
        EMIT(set_tex, .log2_w = 8, .log2_h = 8, .format = 1, .levels = 1);
        EMIT(draw_quad, .addr = gpu_physical(scene), .count = scene_count);
        EMIT(draw_tri, .addr = gpu_physical(effects), .count = vertex_count / 3);
        EMIT(obj_step, .step = stripe == 0 && advance, .draw = 1,
             .addr = gpu_physical(particles), .count = particle_end);
        EMIT(set_tex, .offset = 65536, .log2_w = 3, .log2_h = 3, .format = 1, .levels = 1);
        EMIT(draw_quad, .addr = gpu_physical(canvas.rects), .count = canvas.rect_count);
        EMIT(set_tex, .log2_w = 8, .log2_h = 8, .format = 1, .levels = 1);
        EMIT(draw_quad, .addr = gpu_physical(canvas.glyphs), .count = canvas.glyph_count);
        resolve_command[stripe] = n;
        EMIT(resolve, .stride = 1280, .x1 = 640, .y0 = y, .y1 = y + 180);
    }
#undef EMIT
    command_count = n;
}

void ember_gfx_submit(unsigned frame)
{
    for (unsigned stripe = 0; stripe < 2; ++stripe)
        gpu_resolve(&commands[resolve_command[stripe]], &(struct gpu_resolve_args){
            .base = gpu_physical(surface[frame & 1]), .stride = 1280,
            .x1 = 640, .y0 = stripe * 180, .y1 = stripe * 180 + 180
        });
    const struct gpu_range sources[] = {
        {(uintptr_t)texture, EMBER_ATLAS_BYTES}, {(uintptr_t)palettes, sizeof(ember_palette)},
        {(uintptr_t)matrix, 64}, {(uintptr_t)scene, scene_count * sizeof(*scene)},
        {(uintptr_t)effects, vertex_count * sizeof(*effects)},
        {(uintptr_t)particles, particle_end * sizeof(*particles)},
        {(uintptr_t)canvas.rects, canvas.rect_count * sizeof(*canvas.rects)},
        {(uintptr_t)canvas.glyphs, canvas.glyph_count * sizeof(*canvas.glyphs)}
    };
    const struct gpu_range results[] = {
        {(uintptr_t)particles, EMBER_PARTICLES * sizeof(*particles)},
        {(uintptr_t)released, EMBER_PARTICLES * sizeof(*released)}
    };
    mmio_write32(EDRV32_GPU_BASE + EDRV32_GPU_CTRL_OFFSET, EDRV32_GPU_CTRL_SOFT_RST_MASK);
    gpu_live_rect(-32, -32, 672, 392);
    gpu_object_lists(released, 0, released, EMBER_PARTICLES);
    struct gpu_batch batch = {commands, command_count, sources, 8, results, 2};
    gpu_submit(&batch);
    struct gpu_event event = gpu_wait();
    if (event.error) { plat_printf("Ember Isles GPU error %u\n", event.error); abort(); }
    for (unsigned i = 0; i < 16; ++i)
        perf[i] = mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_PERF_OFFSET(i));
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_LAYER_CTRL_OFFSET,
                EDRV32_DISP_GPU_LAYER_CTRL_L0_EN_MASK | EDRV32_DISP_GPU_LAYER_CTRL_L0_X2_MASK);
    disp_submit(DISP_L0, gpu_physical(surface[frame & 1]), 1280);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_CTRL_OFFSET,
                EDRV32_DISP_GPU_CTRL_ENABLE_MASK);
}
