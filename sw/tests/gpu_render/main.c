/* File: main.c
 * Spec: gpu-soc-testplan ST-10; gpu-spec 2.1-2.10; gpu-soc 8.2.
 * Description: Render one triangle, a quad and an object in two 640x180 stripes.
 * Clock domain: clk_sys software; GPU clk_gpu; DISP clk_mem/clk_pix.
 */
#include "../gpu_drivers/test.h"
#include "regs/disp_gpu_regs.h"

int main(void)
{
    test_init();
    struct gpu_command *commands = (void *)(uintptr_t)(EDRV32_DDR_BASE + 0x20000u);
    int32_t *matrix = (void *)(uintptr_t)(EDRV32_DDR_BASE + 0x10000u);
    uint16_t *texture = (void *)(uintptr_t)(EDRV32_DDR_BASE + 0x10100u);
    struct gpu_vertex *vertices = (void *)(uintptr_t)(EDRV32_DDR_BASE + 0x10200u);
    struct gpu_quad *quads = (void *)(uintptr_t)(EDRV32_DDR_BASE + 0x10300u);
    struct gpu_object *objects = (void *)(uintptr_t)(EDRV32_DDR_BASE + 0x10400u);
    for (uint32_t i = 0; i < 16u; ++i) {
        matrix[i] = 0;
    }
    matrix[0] = 655;
    matrix[5] = 655;
    matrix[10] = 328;
    matrix[15] = 65536;
    for (uint32_t i = 0; i < 64u; ++i) {
        texture[i] = 0xffffu;
    }
    gpu_vertex(&vertices[0], &(struct gpu_vertex_args){
        .x = (uint32_t)-80, .y = (uint32_t)-60, .z = 100u, .color = 0xf800u
    });
    gpu_vertex(&vertices[1], &(struct gpu_vertex_args){
        .x = 80u, .y = (uint32_t)-60, .z = 100u, .color = 0x07e0u
    });
    gpu_vertex(&vertices[2], &(struct gpu_vertex_args){
        .x = 0u, .y = 60u, .z = 100u, .color = 0x001fu
    });
    gpu_quad(quads, &(struct gpu_quad_args){
        .x = 20u, .y = 20u, .w = 40u, .h = 24u, .alpha = 255u
    });
    gpu_object(objects, &(struct gpu_object_args){
        .alive = 1u, .px = 500u * 256u, .py = 280u * 256u, .vx = 256u,
        .w = 20u, .h = 20u, .alpha = 255u
    });
    gpu_live_rect(0, 0, 640, 360);
    struct gpu_range source = {(uintptr_t)matrix, 0x420u};
    for (uint32_t stripe = 0; stripe < 2u; ++stripe) {
        uint32_t y = stripe * 180u;
        uint32_t count = 0u;
        gpu_set_target(&commands[count++], &(struct gpu_set_target_args){
            .tgt_y0 = y, .sc_y0 = y, .sc_x1 = 640u, .sc_y1 = y + 180u,
            .vp_w = 640u, .vp_h = 360u
        });
        gpu_clear(&commands[count++], &(struct gpu_clear_args){
            .color = 0x0841u, .depth = 65535u, .en_color = 1u,
            .en_depth = 1u, .en_stencil = 1u
        });
        gpu_set_matrix(&commands[count++], &(struct gpu_set_matrix_args){
            .addr = gpu_physical(matrix)
        });
        gpu_set_light(&commands[count++], &(struct gpu_set_light_args){.amb_rgb = 0xffffffu});
        gpu_tex_load(&commands[count++], &(struct gpu_tex_load_args){
            .src = gpu_physical(texture), .bytes = 128u
        });
        gpu_set_tex(&commands[count++], &(struct gpu_set_tex_args){
            .log2_w = 3u, .log2_h = 3u, .format = 2u, .levels = 1u
        });
        gpu_set_pixel(&commands[count++], &(struct gpu_set_pixel_args){
            .depth_func = 1u, .color_write = 1u, .st_func = 7u,
            .st_rmask = 255u, .st_wmask = 255u, .bl_fs = 1u
        });
        gpu_draw_tri(&commands[count++], &(struct gpu_draw_tri_args){
            .addr = gpu_physical(vertices), .count = 1u
        });
        gpu_draw_quad(&commands[count++], &(struct gpu_draw_quad_args){
            .addr = gpu_physical(quads), .count = 1u
        });
        gpu_obj_step(&commands[count++], &(struct gpu_obj_step_args){
            .addr = gpu_physical(objects), .count = 1u, .step = stripe == 0u, .draw = 1u
        });
        gpu_resolve(&commands[count++], &(struct gpu_resolve_args){
            .base = 0x100000u, .stride = 1280u, .y0 = y, .x1 = 640u, .y1 = y + 180u
        });
        /* Only first stripe hands CPU modifications to GPU; second reads GPU writeback. */
        struct gpu_batch batch = {commands, count, &source, stripe == 0u, 0, 0u};
        gpu_submit(&batch);
        struct gpu_event event = gpu_wait();
        test_equal("render error", 0u, event.error);
        test_equal("render DONE count", stripe + 1u, event.done_count);
    }
    /* Both stripes complete: FILLING -> READY -> DISP IN_USE; never write while scanned. */
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_NEXT_BASE_OFFSET, 0x100000u);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_STRIDE_OFFSET, 1280u);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_LAYER_CTRL_OFFSET,
                 EDRV32_DISP_GPU_LAYER_CTRL_L0_EN_MASK | EDRV32_DISP_GPU_LAYER_CTRL_L0_X2_MASK);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_CTRL_OFFSET, EDRV32_DISP_GPU_CTRL_ENABLE_MASK);
    test_external(10u);
    uart_puts("PASS ST-10 render HDMI\r\n");
    test_finish(0u);
}
