/* File: gpu.h
 * Spec: gpu-spec 2-6; gpu-soc-spec 7; visual SoC 7.4.
 * Description: Command/record encoding and explicit DMA ownership transfer.
 * Clock domain: clk_sys CPU; GPU registers cross to clk_gpu.
 */
#ifndef EDRV32_GPU_H
#define EDRV32_GPU_H
#include <stdint.h>
#include "gpu_soc_map.h"
#include "regs/gpu_regs.h"

struct gpu_command { uint32_t word[EDRV32_GPU_CMD_CLEAR_SIZE / 4u]; };
struct gpu_vertex { uint32_t word[EDRV32_GPU_VERTEX_SIZE / 4u]; };
struct gpu_quad { uint32_t word[EDRV32_GPU_QUAD_SIZE / 4u]; };
struct gpu_object { uint32_t word[EDRV32_GPU_OBJ_SIZE / 4u]; };
/* Fields use spec integer units, including byte addresses and signed fixed point bits.
 * The caller guarantees the specified alignment, ranges and buffer ownership. */

struct gpu_set_matrix_args {
    uint32_t addr;
};
void gpu_set_matrix(struct gpu_command *out, const struct gpu_set_matrix_args *args);

struct gpu_set_light_args {
    uint32_t lx;
    uint32_t ly;
    uint32_t lz;
    uint32_t dir_rgb;
    uint32_t amb_rgb;
};
void gpu_set_light(struct gpu_command *out, const struct gpu_set_light_args *args);

struct gpu_set_tex_args {
    uint32_t offset;
    uint32_t log2_w;
    uint32_t log2_h;
    uint32_t format;
    uint32_t levels;
    uint32_t pal_group;
    uint32_t sample;
    uint32_t lod_bias;
};
void gpu_set_tex(struct gpu_command *out, const struct gpu_set_tex_args *args);

struct gpu_set_pixel_args {
    uint32_t depth_func;
    uint32_t depth_write;
    uint32_t color_write;
    uint32_t cull;
    uint32_t st_func;
    uint32_t st_sfail;
    uint32_t st_zfail;
    uint32_t st_zpass;
    uint32_t st_ref;
    uint32_t st_rmask;
    uint32_t st_wmask;
    uint32_t bl_fs;
    uint32_t bl_fd;
    uint32_t bl_op;
    uint32_t bl_const_a;
};
void gpu_set_pixel(struct gpu_command *out, const struct gpu_set_pixel_args *args);

struct gpu_set_target_args {
    uint32_t tgt_x0;
    uint32_t tgt_y0;
    uint32_t sc_x0;
    uint32_t sc_y0;
    uint32_t sc_x1;
    uint32_t sc_y1;
    uint32_t vp_x0;
    uint32_t vp_y0;
    uint32_t vp_w;
    uint32_t vp_h;
};
void gpu_set_target(struct gpu_command *out, const struct gpu_set_target_args *args);

struct gpu_clear_args {
    uint32_t color;
    uint32_t depth;
    uint32_t stencil;
    uint32_t en_color;
    uint32_t en_depth;
    uint32_t en_stencil;
};
void gpu_clear(struct gpu_command *out, const struct gpu_clear_args *args);

struct gpu_draw_tri_args {
    uint32_t addr;
    uint32_t count;
};
void gpu_draw_tri(struct gpu_command *out, const struct gpu_draw_tri_args *args);

struct gpu_draw_quad_args {
    uint32_t addr;
    uint32_t count;
};
void gpu_draw_quad(struct gpu_command *out, const struct gpu_draw_quad_args *args);

struct gpu_obj_step_args {
    uint32_t step;
    uint32_t draw;
    uint32_t addr;
    uint32_t count;
};
void gpu_obj_step(struct gpu_command *out, const struct gpu_obj_step_args *args);

struct gpu_tex_load_args {
    uint32_t src;
    uint32_t dst;
    uint32_t bytes;
};
void gpu_tex_load(struct gpu_command *out, const struct gpu_tex_load_args *args);

struct gpu_pal_load_args {
    uint32_t group;
    uint32_t src;
    uint32_t entries;
};
void gpu_pal_load(struct gpu_command *out, const struct gpu_pal_load_args *args);

struct gpu_resolve_args {
    uint32_t fxaa;
    uint32_t fxaa_th;
    uint32_t base;
    uint32_t stride;
    uint32_t x0;
    uint32_t y0;
    uint32_t x1;
    uint32_t y1;
};
void gpu_resolve(struct gpu_command *out, const struct gpu_resolve_args *args);

struct gpu_vertex_args {
    uint32_t x;
    uint32_t y;
    uint32_t z;
    uint32_t nx;
    uint32_t ny;
    uint32_t nz;
    uint32_t color;
    uint32_t u;
    uint32_t v;
};
void gpu_vertex(struct gpu_vertex *out, const struct gpu_vertex_args *args);

struct gpu_quad_args {
    uint32_t x;
    uint32_t y;
    uint32_t pal_group;
    uint32_t flip_h;
    uint32_t flip_v;
    uint32_t w;
    uint32_t h;
    uint32_t alpha;
    uint32_t u0;
    uint32_t v0;
    uint32_t depth;
};
void gpu_quad(struct gpu_quad *out, const struct gpu_quad_args *args);

struct gpu_object_args {
    uint32_t alive;
    uint32_t tgt_mask;
    uint32_t life;
    uint32_t px;
    uint32_t py;
    uint32_t vx;
    uint32_t vy;
    uint32_t ax;
    uint32_t ay;
    uint32_t col_hw;
    uint32_t col_hh;
    uint32_t w;
    uint32_t h;
    uint32_t pal_group;
    uint32_t flip_h;
    uint32_t flip_v;
    uint32_t alpha;
    uint32_t u0;
    uint32_t v0;
    uint32_t depth;
};
void gpu_object(struct gpu_object *out, const struct gpu_object_args *args);

struct gpu_range { uintptr_t address; uint32_t bytes; };
struct gpu_batch {
    const struct gpu_command *commands; /* DDR CPU address, list 64 B aligned. */
    uint32_t count;
    const struct gpu_range *sources; /* CPU modifications consumed by GPU. */
    uint32_t source_count;
    const struct gpu_range *results; /* Object table, lists and CPU-read Surfaces. */
    uint32_t result_count;
};
enum gpu_error {
    GPU_OK = 0,
    GPU_ERROR_OPCODE = 1,
    GPU_ERROR_AXI = 2,
    GPU_ERROR_TEXTURE_DESCRIPTOR = 3,
    GPU_ERROR_TEXTURE_LOAD = 4
};
struct gpu_event {
    uint32_t irq;
    uint32_t error; /* gpu-spec 6: 1 opcode, 2 AXI, 3 descriptor, 4 load bounds. */
    uint32_t done_count;
    uint32_t hit_count;
    uint32_t free_count;
    uint32_t alive_count;
    uint32_t object_status;
};
typedef void (*gpu_callback)(const struct gpu_event *event, void *context);
uint32_t gpu_physical(const void *address);
/* Single in-flight batch; ranges and command storage live until completion.
 * Cache operations are skipped for uncached DDR aliases. Output ranges include
 * full object/list allocations; CPU must not access them while GPU owns them. */
void gpu_submit(const struct gpu_batch *batch);
struct gpu_event gpu_wait(void);
void gpu_irq_register(unsigned int priority, gpu_callback callback, void *context);
/* Application claims/completes PLIC source 13; poll and IRQ consumers are exclusive. */
void gpu_irq_handle(void);
void gpu_object_lists(void *hits, uint32_t hit_capacity, void *released,
                      uint32_t free_capacity);
void gpu_live_rect(int16_t x0, int16_t y0, int16_t x1, int16_t y1);
void gpu_collision_target(unsigned int target, int16_t x0, int16_t y0,
                          int16_t x1, int16_t y1);
uint32_t gpu_hit_object(uint32_t entry);
uint32_t gpu_hit_target(uint32_t entry);
uint32_t gpu_free_object(uint32_t entry);
#endif
