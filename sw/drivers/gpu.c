/* File: gpu.c
 * Spec: gpu-spec 2-6; gpu-soc-spec 7; visual SoC 7.4.
 * Description: Exact 32-byte command construction, cache handoff and completion.
 * Clock domain: clk_sys CPU; GPU registers cross to clk_gpu.
 */
#include "gpu.h"
#include "mmio.h"
#include "cache.h"
#include "plic.h"

_Static_assert(sizeof(struct gpu_command) == 32u, "GPU command size");
static struct gpu_batch active;
static gpu_callback completion;
static void *completion_context;

void gpu_set_matrix(struct gpu_command *out, const struct gpu_set_matrix_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_SET_MATRIX_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_SET_MATRIX_OPCODE_OFFSET / 4u] = 1u;
    out->word[EDRV32_GPU_CMD_SET_MATRIX_ADDR_OFFSET / 4u] |=
        (args->addr) & EDRV32_GPU_CMD_SET_MATRIX_ADDR_MASK;
}

void gpu_set_light(struct gpu_command *out, const struct gpu_set_light_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_SET_LIGHT_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_SET_LIGHT_OPCODE_OFFSET / 4u] = 2u;
    out->word[EDRV32_GPU_CMD_SET_LIGHT_LX_OFFSET / 4u] |=
        (args->lx << EDRV32_GPU_CMD_SET_LIGHT_LX_POS) & EDRV32_GPU_CMD_SET_LIGHT_LX_MASK;
    out->word[EDRV32_GPU_CMD_SET_LIGHT_LY_OFFSET / 4u] |=
        (args->ly << EDRV32_GPU_CMD_SET_LIGHT_LY_POS) & EDRV32_GPU_CMD_SET_LIGHT_LY_MASK;
    out->word[EDRV32_GPU_CMD_SET_LIGHT_LZ_OFFSET / 4u] |=
        (args->lz << EDRV32_GPU_CMD_SET_LIGHT_LZ_POS) & EDRV32_GPU_CMD_SET_LIGHT_LZ_MASK;
    out->word[EDRV32_GPU_CMD_SET_LIGHT_DIR_RGB_OFFSET / 4u] |=
        (args->dir_rgb << EDRV32_GPU_CMD_SET_LIGHT_DIR_RGB_POS) &
        EDRV32_GPU_CMD_SET_LIGHT_DIR_RGB_MASK;
    out->word[EDRV32_GPU_CMD_SET_LIGHT_AMB_RGB_OFFSET / 4u] |=
        (args->amb_rgb << EDRV32_GPU_CMD_SET_LIGHT_AMB_RGB_POS) &
        EDRV32_GPU_CMD_SET_LIGHT_AMB_RGB_MASK;
}

void gpu_set_tex(struct gpu_command *out, const struct gpu_set_tex_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_SET_TEX_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_SET_TEX_OPCODE_OFFSET / 4u] = 3u;
    out->word[EDRV32_GPU_CMD_SET_TEX_OFFSET_OFFSET / 4u] |=
        (args->offset) & EDRV32_GPU_CMD_SET_TEX_OFFSET_MASK;
    out->word[EDRV32_GPU_CMD_SET_TEX_LOG2_W_OFFSET / 4u] |=
        (args->log2_w << EDRV32_GPU_CMD_SET_TEX_LOG2_W_POS) & EDRV32_GPU_CMD_SET_TEX_LOG2_W_MASK;
    out->word[EDRV32_GPU_CMD_SET_TEX_LOG2_H_OFFSET / 4u] |=
        (args->log2_h << EDRV32_GPU_CMD_SET_TEX_LOG2_H_POS) & EDRV32_GPU_CMD_SET_TEX_LOG2_H_MASK;
    out->word[EDRV32_GPU_CMD_SET_TEX_FORMAT_OFFSET / 4u] |=
        (args->format << EDRV32_GPU_CMD_SET_TEX_FORMAT_POS) & EDRV32_GPU_CMD_SET_TEX_FORMAT_MASK;
    out->word[EDRV32_GPU_CMD_SET_TEX_LEVELS_OFFSET / 4u] |=
        (args->levels << EDRV32_GPU_CMD_SET_TEX_LEVELS_POS) & EDRV32_GPU_CMD_SET_TEX_LEVELS_MASK;
    out->word[EDRV32_GPU_CMD_SET_TEX_PAL_GROUP_OFFSET / 4u] |=
        (args->pal_group << EDRV32_GPU_CMD_SET_TEX_PAL_GROUP_POS) &
        EDRV32_GPU_CMD_SET_TEX_PAL_GROUP_MASK;
    out->word[EDRV32_GPU_CMD_SET_TEX_SAMPLE_OFFSET / 4u] |=
        (args->sample << EDRV32_GPU_CMD_SET_TEX_SAMPLE_POS) & EDRV32_GPU_CMD_SET_TEX_SAMPLE_MASK;
    out->word[EDRV32_GPU_CMD_SET_TEX_LOD_BIAS_OFFSET / 4u] |=
        (args->lod_bias << EDRV32_GPU_CMD_SET_TEX_LOD_BIAS_POS) &
        EDRV32_GPU_CMD_SET_TEX_LOD_BIAS_MASK;
}

void gpu_set_pixel(struct gpu_command *out, const struct gpu_set_pixel_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_SET_PIXEL_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_SET_PIXEL_OPCODE_OFFSET / 4u] = 4u;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_DEPTH_FUNC_OFFSET / 4u] |=
        (args->depth_func << EDRV32_GPU_CMD_SET_PIXEL_DEPTH_FUNC_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_DEPTH_FUNC_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_DEPTH_WRITE_OFFSET / 4u] |=
        (args->depth_write << EDRV32_GPU_CMD_SET_PIXEL_DEPTH_WRITE_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_DEPTH_WRITE_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_COLOR_WRITE_OFFSET / 4u] |=
        (args->color_write << EDRV32_GPU_CMD_SET_PIXEL_COLOR_WRITE_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_COLOR_WRITE_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_CULL_OFFSET / 4u] |=
        (args->cull << EDRV32_GPU_CMD_SET_PIXEL_CULL_POS) & EDRV32_GPU_CMD_SET_PIXEL_CULL_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_ST_FUNC_OFFSET / 4u] |=
        (args->st_func << EDRV32_GPU_CMD_SET_PIXEL_ST_FUNC_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_ST_FUNC_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_ST_SFAIL_OFFSET / 4u] |=
        (args->st_sfail << EDRV32_GPU_CMD_SET_PIXEL_ST_SFAIL_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_ST_SFAIL_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_ST_ZFAIL_OFFSET / 4u] |=
        (args->st_zfail << EDRV32_GPU_CMD_SET_PIXEL_ST_ZFAIL_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_ST_ZFAIL_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_ST_ZPASS_OFFSET / 4u] |=
        (args->st_zpass << EDRV32_GPU_CMD_SET_PIXEL_ST_ZPASS_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_ST_ZPASS_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_ST_REF_OFFSET / 4u] |=
        (args->st_ref << EDRV32_GPU_CMD_SET_PIXEL_ST_REF_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_ST_REF_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_ST_RMASK_OFFSET / 4u] |=
        (args->st_rmask << EDRV32_GPU_CMD_SET_PIXEL_ST_RMASK_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_ST_RMASK_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_ST_WMASK_OFFSET / 4u] |=
        (args->st_wmask << EDRV32_GPU_CMD_SET_PIXEL_ST_WMASK_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_ST_WMASK_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_BL_FS_OFFSET / 4u] |=
        (args->bl_fs << EDRV32_GPU_CMD_SET_PIXEL_BL_FS_POS) & EDRV32_GPU_CMD_SET_PIXEL_BL_FS_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_BL_FD_OFFSET / 4u] |=
        (args->bl_fd << EDRV32_GPU_CMD_SET_PIXEL_BL_FD_POS) & EDRV32_GPU_CMD_SET_PIXEL_BL_FD_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_BL_OP_OFFSET / 4u] |=
        (args->bl_op << EDRV32_GPU_CMD_SET_PIXEL_BL_OP_POS) & EDRV32_GPU_CMD_SET_PIXEL_BL_OP_MASK;
    out->word[EDRV32_GPU_CMD_SET_PIXEL_BL_CONST_A_OFFSET / 4u] |=
        (args->bl_const_a << EDRV32_GPU_CMD_SET_PIXEL_BL_CONST_A_POS) &
        EDRV32_GPU_CMD_SET_PIXEL_BL_CONST_A_MASK;
}

void gpu_set_target(struct gpu_command *out, const struct gpu_set_target_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_SET_TARGET_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_SET_TARGET_OPCODE_OFFSET / 4u] = 5u;
    out->word[EDRV32_GPU_CMD_SET_TARGET_TGT_X0_OFFSET / 4u] |=
        (args->tgt_x0 << EDRV32_GPU_CMD_SET_TARGET_TGT_X0_POS) &
        EDRV32_GPU_CMD_SET_TARGET_TGT_X0_MASK;
    out->word[EDRV32_GPU_CMD_SET_TARGET_TGT_Y0_OFFSET / 4u] |=
        (args->tgt_y0 << EDRV32_GPU_CMD_SET_TARGET_TGT_Y0_POS) &
        EDRV32_GPU_CMD_SET_TARGET_TGT_Y0_MASK;
    out->word[EDRV32_GPU_CMD_SET_TARGET_SC_X0_OFFSET / 4u] |=
        (args->sc_x0 << EDRV32_GPU_CMD_SET_TARGET_SC_X0_POS) & EDRV32_GPU_CMD_SET_TARGET_SC_X0_MASK;
    out->word[EDRV32_GPU_CMD_SET_TARGET_SC_Y0_OFFSET / 4u] |=
        (args->sc_y0 << EDRV32_GPU_CMD_SET_TARGET_SC_Y0_POS) & EDRV32_GPU_CMD_SET_TARGET_SC_Y0_MASK;
    out->word[EDRV32_GPU_CMD_SET_TARGET_SC_X1_OFFSET / 4u] |=
        (args->sc_x1 << EDRV32_GPU_CMD_SET_TARGET_SC_X1_POS) & EDRV32_GPU_CMD_SET_TARGET_SC_X1_MASK;
    out->word[EDRV32_GPU_CMD_SET_TARGET_SC_Y1_OFFSET / 4u] |=
        (args->sc_y1 << EDRV32_GPU_CMD_SET_TARGET_SC_Y1_POS) & EDRV32_GPU_CMD_SET_TARGET_SC_Y1_MASK;
    out->word[EDRV32_GPU_CMD_SET_TARGET_VP_X0_OFFSET / 4u] |=
        (args->vp_x0 << EDRV32_GPU_CMD_SET_TARGET_VP_X0_POS) & EDRV32_GPU_CMD_SET_TARGET_VP_X0_MASK;
    out->word[EDRV32_GPU_CMD_SET_TARGET_VP_Y0_OFFSET / 4u] |=
        (args->vp_y0 << EDRV32_GPU_CMD_SET_TARGET_VP_Y0_POS) & EDRV32_GPU_CMD_SET_TARGET_VP_Y0_MASK;
    out->word[EDRV32_GPU_CMD_SET_TARGET_VP_W_OFFSET / 4u] |=
        (args->vp_w << EDRV32_GPU_CMD_SET_TARGET_VP_W_POS) & EDRV32_GPU_CMD_SET_TARGET_VP_W_MASK;
    out->word[EDRV32_GPU_CMD_SET_TARGET_VP_H_OFFSET / 4u] |=
        (args->vp_h << EDRV32_GPU_CMD_SET_TARGET_VP_H_POS) & EDRV32_GPU_CMD_SET_TARGET_VP_H_MASK;
}

void gpu_clear(struct gpu_command *out, const struct gpu_clear_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_CLEAR_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_CLEAR_OPCODE_OFFSET / 4u] = 16u;
    out->word[EDRV32_GPU_CMD_CLEAR_COLOR_OFFSET / 4u] |=
        (args->color << EDRV32_GPU_CMD_CLEAR_COLOR_POS) & EDRV32_GPU_CMD_CLEAR_COLOR_MASK;
    out->word[EDRV32_GPU_CMD_CLEAR_DEPTH_OFFSET / 4u] |=
        (args->depth << EDRV32_GPU_CMD_CLEAR_DEPTH_POS) & EDRV32_GPU_CMD_CLEAR_DEPTH_MASK;
    out->word[EDRV32_GPU_CMD_CLEAR_STENCIL_OFFSET / 4u] |=
        (args->stencil << EDRV32_GPU_CMD_CLEAR_STENCIL_POS) & EDRV32_GPU_CMD_CLEAR_STENCIL_MASK;
    out->word[EDRV32_GPU_CMD_CLEAR_EN_COLOR_OFFSET / 4u] |=
        (args->en_color << EDRV32_GPU_CMD_CLEAR_EN_COLOR_POS) & EDRV32_GPU_CMD_CLEAR_EN_COLOR_MASK;
    out->word[EDRV32_GPU_CMD_CLEAR_EN_DEPTH_OFFSET / 4u] |=
        (args->en_depth << EDRV32_GPU_CMD_CLEAR_EN_DEPTH_POS) & EDRV32_GPU_CMD_CLEAR_EN_DEPTH_MASK;
    out->word[EDRV32_GPU_CMD_CLEAR_EN_STENCIL_OFFSET / 4u] |=
        (args->en_stencil << EDRV32_GPU_CMD_CLEAR_EN_STENCIL_POS) &
        EDRV32_GPU_CMD_CLEAR_EN_STENCIL_MASK;
}

void gpu_draw_tri(struct gpu_command *out, const struct gpu_draw_tri_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_DRAW_TRI_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_DRAW_TRI_OPCODE_OFFSET / 4u] = 32u;
    out->word[EDRV32_GPU_CMD_DRAW_TRI_ADDR_OFFSET / 4u] |=
        (args->addr) & EDRV32_GPU_CMD_DRAW_TRI_ADDR_MASK;
    out->word[EDRV32_GPU_CMD_DRAW_TRI_COUNT_OFFSET / 4u] |=
        (args->count << EDRV32_GPU_CMD_DRAW_TRI_COUNT_POS) & EDRV32_GPU_CMD_DRAW_TRI_COUNT_MASK;
}

void gpu_draw_quad(struct gpu_command *out, const struct gpu_draw_quad_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_DRAW_QUAD_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_DRAW_QUAD_OPCODE_OFFSET / 4u] = 33u;
    out->word[EDRV32_GPU_CMD_DRAW_QUAD_ADDR_OFFSET / 4u] |=
        (args->addr) & EDRV32_GPU_CMD_DRAW_QUAD_ADDR_MASK;
    out->word[EDRV32_GPU_CMD_DRAW_QUAD_COUNT_OFFSET / 4u] |=
        (args->count << EDRV32_GPU_CMD_DRAW_QUAD_COUNT_POS) & EDRV32_GPU_CMD_DRAW_QUAD_COUNT_MASK;
}

void gpu_obj_step(struct gpu_command *out, const struct gpu_obj_step_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_OBJ_STEP_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_OBJ_STEP_OPCODE_OFFSET / 4u] = 34u;
    out->word[EDRV32_GPU_CMD_OBJ_STEP_STEP_OFFSET / 4u] |=
        (args->step << EDRV32_GPU_CMD_OBJ_STEP_STEP_POS) & EDRV32_GPU_CMD_OBJ_STEP_STEP_MASK;
    out->word[EDRV32_GPU_CMD_OBJ_STEP_DRAW_OFFSET / 4u] |=
        (args->draw << EDRV32_GPU_CMD_OBJ_STEP_DRAW_POS) & EDRV32_GPU_CMD_OBJ_STEP_DRAW_MASK;
    out->word[EDRV32_GPU_CMD_OBJ_STEP_ADDR_OFFSET / 4u] |=
        (args->addr) & EDRV32_GPU_CMD_OBJ_STEP_ADDR_MASK;
    out->word[EDRV32_GPU_CMD_OBJ_STEP_COUNT_OFFSET / 4u] |=
        (args->count << EDRV32_GPU_CMD_OBJ_STEP_COUNT_POS) & EDRV32_GPU_CMD_OBJ_STEP_COUNT_MASK;
}

void gpu_tex_load(struct gpu_command *out, const struct gpu_tex_load_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_TEX_LOAD_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_TEX_LOAD_OPCODE_OFFSET / 4u] = 48u;
    out->word[EDRV32_GPU_CMD_TEX_LOAD_SRC_OFFSET / 4u] |=
        (args->src) & EDRV32_GPU_CMD_TEX_LOAD_SRC_MASK;
    out->word[EDRV32_GPU_CMD_TEX_LOAD_DST_OFFSET / 4u] |=
        (args->dst) & EDRV32_GPU_CMD_TEX_LOAD_DST_MASK;
    out->word[EDRV32_GPU_CMD_TEX_LOAD_BYTES_OFFSET / 4u] |=
        (args->bytes) & EDRV32_GPU_CMD_TEX_LOAD_BYTES_MASK;
}

void gpu_pal_load(struct gpu_command *out, const struct gpu_pal_load_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_PAL_LOAD_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_PAL_LOAD_OPCODE_OFFSET / 4u] = 49u;
    out->word[EDRV32_GPU_CMD_PAL_LOAD_GROUP_OFFSET / 4u] |=
        (args->group << EDRV32_GPU_CMD_PAL_LOAD_GROUP_POS) & EDRV32_GPU_CMD_PAL_LOAD_GROUP_MASK;
    out->word[EDRV32_GPU_CMD_PAL_LOAD_SRC_OFFSET / 4u] |=
        (args->src) & EDRV32_GPU_CMD_PAL_LOAD_SRC_MASK;
    out->word[EDRV32_GPU_CMD_PAL_LOAD_ENTRIES_OFFSET / 4u] |=
        (args->entries << EDRV32_GPU_CMD_PAL_LOAD_ENTRIES_POS) &
        EDRV32_GPU_CMD_PAL_LOAD_ENTRIES_MASK;
}

void gpu_resolve(struct gpu_command *out, const struct gpu_resolve_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_CMD_RESOLVE_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_CMD_RESOLVE_OPCODE_OFFSET / 4u] = 64u;
    out->word[EDRV32_GPU_CMD_RESOLVE_FXAA_OFFSET / 4u] |=
        (args->fxaa << EDRV32_GPU_CMD_RESOLVE_FXAA_POS) & EDRV32_GPU_CMD_RESOLVE_FXAA_MASK;
    out->word[EDRV32_GPU_CMD_RESOLVE_FXAA_TH_OFFSET / 4u] |=
        (args->fxaa_th << EDRV32_GPU_CMD_RESOLVE_FXAA_TH_POS) & EDRV32_GPU_CMD_RESOLVE_FXAA_TH_MASK;
    out->word[EDRV32_GPU_CMD_RESOLVE_BASE_OFFSET / 4u] |=
        (args->base) & EDRV32_GPU_CMD_RESOLVE_BASE_MASK;
    out->word[EDRV32_GPU_CMD_RESOLVE_STRIDE_OFFSET / 4u] |=
        (args->stride) & EDRV32_GPU_CMD_RESOLVE_STRIDE_MASK;
    out->word[EDRV32_GPU_CMD_RESOLVE_X0_OFFSET / 4u] |=
        (args->x0 << EDRV32_GPU_CMD_RESOLVE_X0_POS) & EDRV32_GPU_CMD_RESOLVE_X0_MASK;
    out->word[EDRV32_GPU_CMD_RESOLVE_Y0_OFFSET / 4u] |=
        (args->y0 << EDRV32_GPU_CMD_RESOLVE_Y0_POS) & EDRV32_GPU_CMD_RESOLVE_Y0_MASK;
    out->word[EDRV32_GPU_CMD_RESOLVE_X1_OFFSET / 4u] |=
        (args->x1 << EDRV32_GPU_CMD_RESOLVE_X1_POS) & EDRV32_GPU_CMD_RESOLVE_X1_MASK;
    out->word[EDRV32_GPU_CMD_RESOLVE_Y1_OFFSET / 4u] |=
        (args->y1 << EDRV32_GPU_CMD_RESOLVE_Y1_POS) & EDRV32_GPU_CMD_RESOLVE_Y1_MASK;
}

void gpu_vertex(struct gpu_vertex *out, const struct gpu_vertex_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_VERTEX_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_VERTEX_X_OFFSET / 4u] |=
        (args->x << EDRV32_GPU_VERTEX_X_POS) & EDRV32_GPU_VERTEX_X_MASK;
    out->word[EDRV32_GPU_VERTEX_Y_OFFSET / 4u] |=
        (args->y << EDRV32_GPU_VERTEX_Y_POS) & EDRV32_GPU_VERTEX_Y_MASK;
    out->word[EDRV32_GPU_VERTEX_Z_OFFSET / 4u] |=
        (args->z << EDRV32_GPU_VERTEX_Z_POS) & EDRV32_GPU_VERTEX_Z_MASK;
    out->word[EDRV32_GPU_VERTEX_NX_OFFSET / 4u] |=
        (args->nx << EDRV32_GPU_VERTEX_NX_POS) & EDRV32_GPU_VERTEX_NX_MASK;
    out->word[EDRV32_GPU_VERTEX_NY_OFFSET / 4u] |=
        (args->ny << EDRV32_GPU_VERTEX_NY_POS) & EDRV32_GPU_VERTEX_NY_MASK;
    out->word[EDRV32_GPU_VERTEX_NZ_OFFSET / 4u] |=
        (args->nz << EDRV32_GPU_VERTEX_NZ_POS) & EDRV32_GPU_VERTEX_NZ_MASK;
    out->word[EDRV32_GPU_VERTEX_COLOR_OFFSET / 4u] |=
        (args->color << EDRV32_GPU_VERTEX_COLOR_POS) & EDRV32_GPU_VERTEX_COLOR_MASK;
    out->word[EDRV32_GPU_VERTEX_U_OFFSET / 4u] |=
        (args->u << EDRV32_GPU_VERTEX_U_POS) & EDRV32_GPU_VERTEX_U_MASK;
    out->word[EDRV32_GPU_VERTEX_V_OFFSET / 4u] |=
        (args->v << EDRV32_GPU_VERTEX_V_POS) & EDRV32_GPU_VERTEX_V_MASK;
}

void gpu_quad(struct gpu_quad *out, const struct gpu_quad_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_QUAD_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_QUAD_X_OFFSET / 4u] |=
        (args->x << EDRV32_GPU_QUAD_X_POS) & EDRV32_GPU_QUAD_X_MASK;
    out->word[EDRV32_GPU_QUAD_Y_OFFSET / 4u] |=
        (args->y << EDRV32_GPU_QUAD_Y_POS) & EDRV32_GPU_QUAD_Y_MASK;
    out->word[EDRV32_GPU_QUAD_PAL_GROUP_OFFSET / 4u] |=
        (args->pal_group << EDRV32_GPU_QUAD_PAL_GROUP_POS) & EDRV32_GPU_QUAD_PAL_GROUP_MASK;
    out->word[EDRV32_GPU_QUAD_FLIP_H_OFFSET / 4u] |=
        (args->flip_h << EDRV32_GPU_QUAD_FLIP_H_POS) & EDRV32_GPU_QUAD_FLIP_H_MASK;
    out->word[EDRV32_GPU_QUAD_FLIP_V_OFFSET / 4u] |=
        (args->flip_v << EDRV32_GPU_QUAD_FLIP_V_POS) & EDRV32_GPU_QUAD_FLIP_V_MASK;
    out->word[EDRV32_GPU_QUAD_W_OFFSET / 4u] |=
        (args->w << EDRV32_GPU_QUAD_W_POS) & EDRV32_GPU_QUAD_W_MASK;
    out->word[EDRV32_GPU_QUAD_H_OFFSET / 4u] |=
        (args->h << EDRV32_GPU_QUAD_H_POS) & EDRV32_GPU_QUAD_H_MASK;
    out->word[EDRV32_GPU_QUAD_ALPHA_OFFSET / 4u] |=
        (args->alpha << EDRV32_GPU_QUAD_ALPHA_POS) & EDRV32_GPU_QUAD_ALPHA_MASK;
    out->word[EDRV32_GPU_QUAD_U0_OFFSET / 4u] |=
        (args->u0 << EDRV32_GPU_QUAD_U0_POS) & EDRV32_GPU_QUAD_U0_MASK;
    out->word[EDRV32_GPU_QUAD_V0_OFFSET / 4u] |=
        (args->v0 << EDRV32_GPU_QUAD_V0_POS) & EDRV32_GPU_QUAD_V0_MASK;
    out->word[EDRV32_GPU_QUAD_DEPTH_OFFSET / 4u] |=
        (args->depth << EDRV32_GPU_QUAD_DEPTH_POS) & EDRV32_GPU_QUAD_DEPTH_MASK;
}

void gpu_object(struct gpu_object *out, const struct gpu_object_args *args)
{
    for (unsigned int i = 0; i < EDRV32_GPU_OBJ_SIZE / 4u; ++i) {
        out->word[i] = 0u;
    }
    out->word[EDRV32_GPU_OBJ_ALIVE_OFFSET / 4u] |=
        (args->alive << EDRV32_GPU_OBJ_ALIVE_POS) & EDRV32_GPU_OBJ_ALIVE_MASK;
    out->word[EDRV32_GPU_OBJ_TGT_MASK_OFFSET / 4u] |=
        (args->tgt_mask << EDRV32_GPU_OBJ_TGT_MASK_POS) & EDRV32_GPU_OBJ_TGT_MASK_MASK;
    out->word[EDRV32_GPU_OBJ_LIFE_OFFSET / 4u] |=
        (args->life << EDRV32_GPU_OBJ_LIFE_POS) & EDRV32_GPU_OBJ_LIFE_MASK;
    out->word[EDRV32_GPU_OBJ_PX_OFFSET / 4u] |=
        (args->px << EDRV32_GPU_OBJ_PX_POS) & EDRV32_GPU_OBJ_PX_MASK;
    out->word[EDRV32_GPU_OBJ_PY_OFFSET / 4u] |=
        (args->py << EDRV32_GPU_OBJ_PY_POS) & EDRV32_GPU_OBJ_PY_MASK;
    out->word[EDRV32_GPU_OBJ_VX_OFFSET / 4u] |=
        (args->vx << EDRV32_GPU_OBJ_VX_POS) & EDRV32_GPU_OBJ_VX_MASK;
    out->word[EDRV32_GPU_OBJ_VY_OFFSET / 4u] |=
        (args->vy << EDRV32_GPU_OBJ_VY_POS) & EDRV32_GPU_OBJ_VY_MASK;
    out->word[EDRV32_GPU_OBJ_AX_OFFSET / 4u] |=
        (args->ax << EDRV32_GPU_OBJ_AX_POS) & EDRV32_GPU_OBJ_AX_MASK;
    out->word[EDRV32_GPU_OBJ_AY_OFFSET / 4u] |=
        (args->ay << EDRV32_GPU_OBJ_AY_POS) & EDRV32_GPU_OBJ_AY_MASK;
    out->word[EDRV32_GPU_OBJ_COL_HW_OFFSET / 4u] |=
        (args->col_hw << EDRV32_GPU_OBJ_COL_HW_POS) & EDRV32_GPU_OBJ_COL_HW_MASK;
    out->word[EDRV32_GPU_OBJ_COL_HH_OFFSET / 4u] |=
        (args->col_hh << EDRV32_GPU_OBJ_COL_HH_POS) & EDRV32_GPU_OBJ_COL_HH_MASK;
    out->word[EDRV32_GPU_OBJ_W_OFFSET / 4u] |=
        (args->w << EDRV32_GPU_OBJ_W_POS) & EDRV32_GPU_OBJ_W_MASK;
    out->word[EDRV32_GPU_OBJ_H_OFFSET / 4u] |=
        (args->h << EDRV32_GPU_OBJ_H_POS) & EDRV32_GPU_OBJ_H_MASK;
    out->word[EDRV32_GPU_OBJ_PAL_GROUP_OFFSET / 4u] |=
        (args->pal_group << EDRV32_GPU_OBJ_PAL_GROUP_POS) & EDRV32_GPU_OBJ_PAL_GROUP_MASK;
    out->word[EDRV32_GPU_OBJ_FLIP_H_OFFSET / 4u] |=
        (args->flip_h << EDRV32_GPU_OBJ_FLIP_H_POS) & EDRV32_GPU_OBJ_FLIP_H_MASK;
    out->word[EDRV32_GPU_OBJ_FLIP_V_OFFSET / 4u] |=
        (args->flip_v << EDRV32_GPU_OBJ_FLIP_V_POS) & EDRV32_GPU_OBJ_FLIP_V_MASK;
    out->word[EDRV32_GPU_OBJ_ALPHA_OFFSET / 4u] |=
        (args->alpha << EDRV32_GPU_OBJ_ALPHA_POS) & EDRV32_GPU_OBJ_ALPHA_MASK;
    out->word[EDRV32_GPU_OBJ_U0_OFFSET / 4u] |=
        (args->u0 << EDRV32_GPU_OBJ_U0_POS) & EDRV32_GPU_OBJ_U0_MASK;
    out->word[EDRV32_GPU_OBJ_V0_OFFSET / 4u] |=
        (args->v0 << EDRV32_GPU_OBJ_V0_POS) & EDRV32_GPU_OBJ_V0_MASK;
    out->word[EDRV32_GPU_OBJ_DEPTH_OFFSET / 4u] |=
        (args->depth << EDRV32_GPU_OBJ_DEPTH_POS) & EDRV32_GPU_OBJ_DEPTH_MASK;
}

static uint32_t read_reg(uint32_t offset)
{
    return mmio_read32(EDRV32_GPU_BASE + offset);
}

static void write_reg(uint32_t offset, uint32_t value)
{
    mmio_write32(EDRV32_GPU_BASE + offset, value);
}

uint32_t gpu_physical(const void *address)
{
    return ddr_physical(address);
}

void gpu_submit(const struct gpu_batch *batch)
{
    active = *batch;
    if ((uintptr_t)batch->commands < EDRV32_DDR_UNCACHED_BASE) {
        cache_clean((uintptr_t)batch->commands, batch->count * sizeof(struct gpu_command));
    }
    for (uint32_t i = 0; i < batch->source_count; ++i) {
        if (batch->sources[i].address < EDRV32_DDR_UNCACHED_BASE) {
            cache_clean(batch->sources[i].address, batch->sources[i].bytes);
        }
    }
    write_reg(EDRV32_GPU_CTRL_OFFSET, EDRV32_GPU_CTRL_ENABLE_MASK);
    write_reg(EDRV32_GPU_DESC_BASE_OFFSET, gpu_physical(batch->commands));
    write_reg(EDRV32_GPU_DESC_COUNT_OFFSET, batch->count);
    write_reg(EDRV32_GPU_DOORBELL_OFFSET, 1u);
}

static struct gpu_event finish(void)
{
    uint32_t irq = read_reg(EDRV32_GPU_IRQ_STAT_OFFSET);
    /* DONE already guarantees completed writes. ERROR may precede AXI drain (GPU 6). */
    if ((irq & EDRV32_GPU_IRQ_STAT_ERROR_MASK) != 0u) {
        while ((read_reg(EDRV32_GPU_STATUS_OFFSET) & EDRV32_GPU_STATUS_IDLE_MASK) == 0u) {
        }
    }
    struct gpu_event event = {
        irq, read_reg(EDRV32_GPU_ERR_CODE_OFFSET),
        read_reg(EDRV32_GPU_DONE_COUNT_OFFSET), read_reg(EDRV32_GPU_OBJ_HIT_COUNT_OFFSET),
        read_reg(EDRV32_GPU_OBJ_FREE_COUNT_OFFSET),
        read_reg(EDRV32_GPU_OBJ_ALIVE_COUNT_OFFSET), read_reg(EDRV32_GPU_OBJ_STAT_OFFSET)
    };
    for (uint32_t i = 0; i < active.result_count; ++i) {
        if (active.results[i].address < EDRV32_DDR_UNCACHED_BASE) {
            cache_invalidate(active.results[i].address, active.results[i].bytes);
        }
    }
    write_reg(EDRV32_GPU_IRQ_STAT_OFFSET, event.irq);
    return event;
}

struct gpu_event gpu_wait(void)
{
    while ((read_reg(EDRV32_GPU_IRQ_STAT_OFFSET) &
            (EDRV32_GPU_IRQ_STAT_DONE_MASK | EDRV32_GPU_IRQ_STAT_ERROR_MASK)) == 0u) {
    }
    return finish();
}

void gpu_irq_register(unsigned int priority, gpu_callback callback, void *context)
{
    completion = callback;
    completion_context = context;
    write_reg(EDRV32_GPU_IRQ_EN_OFFSET,
              EDRV32_GPU_IRQ_EN_DONE_MASK | EDRV32_GPU_IRQ_EN_ERROR_MASK);
    plic_set_priority(EDRV32_PLIC_SOURCE_GPU, priority);
    plic_set_enable(mmio_read32(EDRV32_PLIC_BASE + PLIC_ENABLE) |
                    (1u << EDRV32_PLIC_SOURCE_GPU));
}

void gpu_irq_handle(void)
{
    struct gpu_event event = finish();
    completion(&event, completion_context);
}

void gpu_object_lists(void *hits, uint32_t hit_capacity, void *released,
                      uint32_t free_capacity)
{
    write_reg(EDRV32_GPU_OBJ_HIT_BASE_OFFSET, gpu_physical(hits));
    write_reg(EDRV32_GPU_OBJ_HIT_MAX_OFFSET, hit_capacity);
    write_reg(EDRV32_GPU_OBJ_FREE_BASE_OFFSET, gpu_physical(released));
    write_reg(EDRV32_GPU_OBJ_FREE_MAX_OFFSET, free_capacity);
}

void gpu_live_rect(int16_t x0, int16_t y0, int16_t x1, int16_t y1)
{
    write_reg(EDRV32_GPU_OBJ_LIVE_RECT0_OFFSET,
              ((uint32_t)(uint16_t)x0 << EDRV32_GPU_OBJ_LIVE_RECT0_X0_POS) |
              ((uint32_t)(uint16_t)y0 << EDRV32_GPU_OBJ_LIVE_RECT0_Y0_POS));
    write_reg(EDRV32_GPU_OBJ_LIVE_RECT1_OFFSET,
              ((uint32_t)(uint16_t)x1 << EDRV32_GPU_OBJ_LIVE_RECT1_X1_POS) |
              ((uint32_t)(uint16_t)y1 << EDRV32_GPU_OBJ_LIVE_RECT1_Y1_POS));
}

void gpu_collision_target(unsigned int target, int16_t x0, int16_t y0,
                          int16_t x1, int16_t y1)
{
    write_reg(EDRV32_GPU_OBJ_TGT0_OFFSET(target),
              ((uint32_t)(uint16_t)x0 << EDRV32_GPU_OBJ_TGT0_X0_POS) |
              ((uint32_t)(uint16_t)y0 << EDRV32_GPU_OBJ_TGT0_Y0_POS));
    write_reg(EDRV32_GPU_OBJ_TGT1_OFFSET(target),
              ((uint32_t)(uint16_t)x1 << EDRV32_GPU_OBJ_TGT1_X1_POS) |
              ((uint32_t)(uint16_t)y1 << EDRV32_GPU_OBJ_TGT1_Y1_POS));
}

uint32_t gpu_hit_object(uint32_t entry)
{
    return (entry & EDRV32_GPU_HIT_ENTRY_OBJ_MASK) >> EDRV32_GPU_HIT_ENTRY_OBJ_POS;
}

uint32_t gpu_hit_target(uint32_t entry)
{
    return (entry & EDRV32_GPU_HIT_ENTRY_TGT_MASK) >> EDRV32_GPU_HIT_ENTRY_TGT_POS;
}

uint32_t gpu_free_object(uint32_t entry)
{
    return (entry & EDRV32_GPU_FREE_ENTRY_OBJ_MASK) >> EDRV32_GPU_FREE_ENTRY_OBJ_POS;
}
