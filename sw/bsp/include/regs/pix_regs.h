/* File: pix_regs.h
 * Spec: edrv32-soc-spec.md 7.1; pix-spec.md 4.1
 * Description: Engine register offsets, fields and descriptor layouts.
 * Clock domain: none (constants).
 */
// 由 tools/gen/regs.py 从 rtl/include/regs/*.json 生成，不要手改。
#ifndef EDRV32_PIX_REGS_H
#define EDRV32_PIX_REGS_H

/* VALUE names unnamed ranges; common bit names include unused bits (SoC 7.1). */

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; RO; reset: 131073. */
#define EDRV32_PIX_ID_OFFSET 0x00000000u
#define EDRV32_PIX_ID_RESET 0x00020001u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_ID_VALUE_31_16_POS 0x00000010u
#define EDRV32_PIX_ID_VALUE_31_16_WIDTH 0x00000010u
#define EDRV32_PIX_ID_VALUE_31_16_MASK 0xFFFF0000u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_ID_VALUE_15_0_POS 0x00000000u
#define EDRV32_PIX_ID_VALUE_15_0_WIDTH 0x00000010u
#define EDRV32_PIX_ID_VALUE_15_0_MASK 0x0000FFFFu

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; RW; reset: 0. */
#define EDRV32_PIX_CTRL_OFFSET 0x00000004u
#define EDRV32_PIX_CTRL_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_CTRL_ENABLE_POS 0x00000000u
#define EDRV32_PIX_CTRL_ENABLE_WIDTH 0x00000001u
#define EDRV32_PIX_CTRL_ENABLE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_CTRL_START_POS 0x00000001u
#define EDRV32_PIX_CTRL_START_WIDTH 0x00000001u
#define EDRV32_PIX_CTRL_START_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_CTRL_ABORT_POS 0x00000002u
#define EDRV32_PIX_CTRL_ABORT_WIDTH 0x00000001u
#define EDRV32_PIX_CTRL_ABORT_MASK 0x00000004u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_CTRL_SOFT_RST_POS 0x00000003u
#define EDRV32_PIX_CTRL_SOFT_RST_WIDTH 0x00000001u
#define EDRV32_PIX_CTRL_SOFT_RST_MASK 0x00000008u

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; RO; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_PIX_STATUS_OFFSET 0x00000008u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_STATUS_BUSY_POS 0x00000000u
#define EDRV32_PIX_STATUS_BUSY_WIDTH 0x00000001u
#define EDRV32_PIX_STATUS_BUSY_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_STATUS_IDLE_POS 0x00000001u
#define EDRV32_PIX_STATUS_IDLE_WIDTH 0x00000001u
#define EDRV32_PIX_STATUS_IDLE_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_STATUS_ERROR_POS 0x00000002u
#define EDRV32_PIX_STATUS_ERROR_WIDTH 0x00000001u
#define EDRV32_PIX_STATUS_ERROR_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; RW; reset: 0. */
#define EDRV32_PIX_IRQ_EN_OFFSET 0x0000000Cu
#define EDRV32_PIX_IRQ_EN_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_IRQ_EN_DONE_POS 0x00000000u
#define EDRV32_PIX_IRQ_EN_DONE_WIDTH 0x00000001u
#define EDRV32_PIX_IRQ_EN_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_IRQ_EN_ERROR_POS 0x00000001u
#define EDRV32_PIX_IRQ_EN_ERROR_WIDTH 0x00000001u
#define EDRV32_PIX_IRQ_EN_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_IRQ_EN_FRAME_POS 0x00000002u
#define EDRV32_PIX_IRQ_EN_FRAME_WIDTH 0x00000001u
#define EDRV32_PIX_IRQ_EN_FRAME_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; RW1C; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_PIX_IRQ_STAT_OFFSET 0x00000010u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_IRQ_STAT_DONE_POS 0x00000000u
#define EDRV32_PIX_IRQ_STAT_DONE_WIDTH 0x00000001u
#define EDRV32_PIX_IRQ_STAT_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_IRQ_STAT_ERROR_POS 0x00000001u
#define EDRV32_PIX_IRQ_STAT_ERROR_WIDTH 0x00000001u
#define EDRV32_PIX_IRQ_STAT_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1 */
#define EDRV32_PIX_IRQ_STAT_FRAME_POS 0x00000002u
#define EDRV32_PIX_IRQ_STAT_FRAME_WIDTH 0x00000001u
#define EDRV32_PIX_IRQ_STAT_FRAME_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; RO; reset: 0. */
#define EDRV32_PIX_ERR_CODE_OFFSET 0x00000014u
#define EDRV32_PIX_ERR_CODE_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; RW; reset: 0. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_PIX_DESC_BASE_OFFSET 0x00000020u
#define EDRV32_PIX_DESC_BASE_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; RW; reset: 0. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_PIX_DESC_COUNT_OFFSET 0x00000024u
#define EDRV32_PIX_DESC_COUNT_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; WO; reset: null. */
/* Reset metadata: not_applicable. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_PIX_DOORBELL_OFFSET 0x00000028u

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; RO; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_PIX_DONE_COUNT_OFFSET 0x0000002Cu

/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; pix-spec.md 4.3; RO; reset: 0. */
#define EDRV32_PIX_PERF_N_COUNT 0x00000010u
#define EDRV32_PIX_PERF_OFFSET(n) \
    (0x00000040u + 0x00000004u * (n))
#define EDRV32_PIX_PERF_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; pix-spec.md 4.1; pix-spec.md 4.3 */
#define EDRV32_PIX_PERF_VALUE_POS 0x00000000u
#define EDRV32_PIX_PERF_VALUE_WIDTH 0x00000020u
#define EDRV32_PIX_PERF_VALUE_MASK 0xFFFFFFFFu

/* pix-spec.md 4.2; RW; reset: 0. */
#define EDRV32_PIX_CFG_OFFSET 0x00000100u
#define EDRV32_PIX_CFG_RESET 0x00000000u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_CFG_BC_EN_POS 0x00000000u
#define EDRV32_PIX_CFG_BC_EN_WIDTH 0x00000001u
#define EDRV32_PIX_CFG_BC_EN_MASK 0x00000001u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_CFG_GAMMA_EN_POS 0x00000001u
#define EDRV32_PIX_CFG_GAMMA_EN_WIDTH 0x00000001u
#define EDRV32_PIX_CFG_GAMMA_EN_MASK 0x00000002u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_CFG_GAMMA_BANK_POS 0x00000002u
#define EDRV32_PIX_CFG_GAMMA_BANK_WIDTH 0x00000001u
#define EDRV32_PIX_CFG_GAMMA_BANK_MASK 0x00000004u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_CFG_S1_OP_POS 0x00000004u
#define EDRV32_PIX_CFG_S1_OP_WIDTH 0x00000003u
#define EDRV32_PIX_CFG_S1_OP_MASK 0x00000070u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_CFG_S2_OP_POS 0x00000008u
#define EDRV32_PIX_CFG_S2_OP_WIDTH 0x00000003u
#define EDRV32_PIX_CFG_S2_OP_MASK 0x00000700u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_CFG_GRAY_EN_POS 0x00000010u
#define EDRV32_PIX_CFG_GRAY_EN_WIDTH 0x00000001u
#define EDRV32_PIX_CFG_GRAY_EN_MASK 0x00010000u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_CFG_BIN_EN_POS 0x00000011u
#define EDRV32_PIX_CFG_BIN_EN_WIDTH 0x00000001u
#define EDRV32_PIX_CFG_BIN_EN_MASK 0x00020000u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_CFG_INV_EN_POS 0x00000012u
#define EDRV32_PIX_CFG_INV_EN_WIDTH 0x00000001u
#define EDRV32_PIX_CFG_INV_EN_MASK 0x00040000u

/* pix-spec.md 4.2; RW; reset: 256. */
#define EDRV32_PIX_BC_OFFSET 0x00000104u
#define EDRV32_PIX_BC_RESET 0x00000100u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_BC_CONTRAST_POS 0x00000000u
#define EDRV32_PIX_BC_CONTRAST_WIDTH 0x00000009u
#define EDRV32_PIX_BC_CONTRAST_MASK 0x000001FFu
/* pix-spec.md 4.2 */
#define EDRV32_PIX_BC_BRIGHTNESS_POS 0x00000010u
#define EDRV32_PIX_BC_BRIGHTNESS_WIDTH 0x00000009u
#define EDRV32_PIX_BC_BRIGHTNESS_MASK 0x01FF0000u

/* pix-spec.md 4.2; RW; reset: 128. */
#define EDRV32_PIX_THRESH_OFFSET 0x00000108u
#define EDRV32_PIX_THRESH_RESET 0x00000080u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_THRESH_VALUE_POS 0x00000000u
#define EDRV32_PIX_THRESH_VALUE_WIDTH 0x00000008u
#define EDRV32_PIX_THRESH_VALUE_MASK 0x000000FFu

/* pix-spec.md 4.2; WO; reset: null. */
/* Reset metadata: not_applicable. */
#define EDRV32_PIX_GAMMA_WR_OFFSET 0x0000010Cu
/* pix-spec.md 4.2 */
#define EDRV32_PIX_GAMMA_WR_VALUE_POS 0x00000010u
#define EDRV32_PIX_GAMMA_WR_VALUE_WIDTH 0x00000008u
#define EDRV32_PIX_GAMMA_WR_VALUE_MASK 0x00FF0000u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_GAMMA_WR_BANK_POS 0x00000008u
#define EDRV32_PIX_GAMMA_WR_BANK_WIDTH 0x00000001u
#define EDRV32_PIX_GAMMA_WR_BANK_MASK 0x00000100u
/* pix-spec.md 4.2 */
#define EDRV32_PIX_GAMMA_WR_INDEX_POS 0x00000000u
#define EDRV32_PIX_GAMMA_WR_INDEX_WIDTH 0x00000008u
#define EDRV32_PIX_GAMMA_WR_INDEX_MASK 0x000000FFu

#endif
