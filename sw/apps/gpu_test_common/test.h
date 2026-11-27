/* test.h — gpu-spec 2.1–2.10; shared GPU test scene/runtime contract.
 * CPU/host frame thread owns all buffers between synchronous submissions.
 */
#ifndef GPU_TEST_H
#define GPU_TEST_H
#include <stdint.h>
#include "gpu.h"
#include "plat.h"
#define TEST_OBJECT_MAX 100000u
#define TEST_TRI_MAX 60000u
#define TEST_QUAD_MAX 8192u
#define TEST_TEXTURE_BYTES 185792u
#define TEST_MIP_BASE 131072u
#define TEST_MIP_STRIDE 10944u
struct test_draw {
    unsigned kind;
    unsigned first;
    unsigned count;
    unsigned texture;
    unsigned blend;
    unsigned matrix;
};
struct test_state {
    unsigned game;
    unsigned mode;
    unsigned level;
    unsigned filter;
    unsigned weapon;
    unsigned checker;
    unsigned aa;
    unsigned cpu;
    unsigned frame;
    unsigned tick;
    unsigned score;
    unsigned health;
    unsigned objects_count;
    unsigned triangles;
    unsigned quads_count;
    unsigned draws_count;
    unsigned command_count;
    unsigned hit_count;
    unsigned free_count;
    unsigned alive_count;
    uint32_t cpu_us;
    uint32_t gpu_us;
    uint32_t fps10;
    uint32_t pixels;
    uint32_t previous_keys;
    int player_x;
    int player_y;
    struct gpu_quad *quads;
    struct gpu_vertex *vertices;
    struct gpu_object *objects;
    uint32_t *hits;
    uint32_t *released;
    int32_t *matrices;
    uint8_t *textures;
    uint32_t *palettes;
    uint16_t *surface[2];
    struct test_draw draws[128];
};
extern struct test_state test;
extern const int16_t test_sine[256];
void test_init(void);
void test_frame(void);
void test_select(unsigned game, unsigned mode, unsigned level, unsigned filter);
void test_draw(unsigned kind, unsigned first, unsigned count, unsigned texture,
               unsigned blend, unsigned matrix);
void test_quad(int x, int y, unsigned w, unsigned h, unsigned u, unsigned v,
               unsigned palette, unsigned alpha);
void test_rect(int x, int y, unsigned w, unsigned h, unsigned palette);
void test_panel(int x, int y, unsigned w, unsigned h, unsigned accent);
void test_text(int x, int y, const char *text, unsigned palette);
void test_sprite(int x, int y, int w, int h, unsigned u, unsigned v,
                 unsigned tw, unsigned th);
void test_scaled_text(int x, int y, const char *text, unsigned scale, unsigned color);
void test_vertex(int x, int y, int z, unsigned color, unsigned u, unsigned v, int ny);
unsigned test_color(unsigned r, unsigned g, unsigned b);
void test_sound(unsigned effect);
void test2d_init(void);
void test2d_update(uint32_t keys);
void test2d_scene(void);
void test2d_hud(void);
void test2d_results(void);
void test2d_capture(unsigned event);
void test3d_init(void);
void test3d_update(uint32_t keys);
void test3d_scene(void);
void test3d_hud(void);
void test3d_capture(unsigned event);
uint64_t test_clock_us(void);
uint32_t test_input_keys(void);
#endif
