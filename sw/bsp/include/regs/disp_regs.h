/* File: disp_regs.h
 * Spec: edrv32-soc-spec.md 7.1; disp-spec.md 4.1
 * Description: Engine register offsets, fields and descriptor layouts.
 * Clock domain: none (constants).
 */
// 由 tools/gen/regs.py 从 rtl/include/regs/*.json 生成，不要手改。
#ifndef EDRV32_DISP_REGS_H
#define EDRV32_DISP_REGS_H

/* VALUE names unnamed ranges; common bit names include unused bits (SoC 7.1). */

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; RO; reset: 327681. */
#define EDRV32_DISP_ID_OFFSET 0x00000000u
#define EDRV32_DISP_ID_RESET 0x00050001u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_ID_TYPE_POS 0x00000010u
#define EDRV32_DISP_ID_TYPE_WIDTH 0x00000010u
#define EDRV32_DISP_ID_TYPE_MASK 0xFFFF0000u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_ID_VERSION_POS 0x00000000u
#define EDRV32_DISP_ID_VERSION_WIDTH 0x00000010u
#define EDRV32_DISP_ID_VERSION_MASK 0x0000FFFFu

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; RW; reset: 0. */
#define EDRV32_DISP_CTRL_OFFSET 0x00000004u
#define EDRV32_DISP_CTRL_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_CTRL_ENABLE_POS 0x00000000u
#define EDRV32_DISP_CTRL_ENABLE_WIDTH 0x00000001u
#define EDRV32_DISP_CTRL_ENABLE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_CTRL_START_POS 0x00000001u
#define EDRV32_DISP_CTRL_START_WIDTH 0x00000001u
#define EDRV32_DISP_CTRL_START_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_CTRL_ABORT_POS 0x00000002u
#define EDRV32_DISP_CTRL_ABORT_WIDTH 0x00000001u
#define EDRV32_DISP_CTRL_ABORT_MASK 0x00000004u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_CTRL_SOFT_RST_POS 0x00000003u
#define EDRV32_DISP_CTRL_SOFT_RST_WIDTH 0x00000001u
#define EDRV32_DISP_CTRL_SOFT_RST_MASK 0x00000008u

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; RO; reset: 2. */
#define EDRV32_DISP_STATUS_OFFSET 0x00000008u
#define EDRV32_DISP_STATUS_RESET 0x00000002u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_STATUS_BUSY_POS 0x00000000u
#define EDRV32_DISP_STATUS_BUSY_WIDTH 0x00000001u
#define EDRV32_DISP_STATUS_BUSY_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_STATUS_IDLE_POS 0x00000001u
#define EDRV32_DISP_STATUS_IDLE_WIDTH 0x00000001u
#define EDRV32_DISP_STATUS_IDLE_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_STATUS_ERROR_POS 0x00000002u
#define EDRV32_DISP_STATUS_ERROR_WIDTH 0x00000001u
#define EDRV32_DISP_STATUS_ERROR_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; RW; reset: 0. */
#define EDRV32_DISP_IRQ_EN_OFFSET 0x0000000Cu
#define EDRV32_DISP_IRQ_EN_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_IRQ_EN_DONE_POS 0x00000000u
#define EDRV32_DISP_IRQ_EN_DONE_WIDTH 0x00000001u
#define EDRV32_DISP_IRQ_EN_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_IRQ_EN_ERROR_POS 0x00000001u
#define EDRV32_DISP_IRQ_EN_ERROR_WIDTH 0x00000001u
#define EDRV32_DISP_IRQ_EN_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_IRQ_EN_FRAME_POS 0x00000002u
#define EDRV32_DISP_IRQ_EN_FRAME_WIDTH 0x00000001u
#define EDRV32_DISP_IRQ_EN_FRAME_MASK 0x00000004u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_IRQ_EN_SWITCH_POS 0x00000008u
#define EDRV32_DISP_IRQ_EN_SWITCH_WIDTH 0x00000001u
#define EDRV32_DISP_IRQ_EN_SWITCH_MASK 0x00000100u

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; RW1C; reset: 0. */
#define EDRV32_DISP_IRQ_STAT_OFFSET 0x00000010u
#define EDRV32_DISP_IRQ_STAT_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_IRQ_STAT_DONE_POS 0x00000000u
#define EDRV32_DISP_IRQ_STAT_DONE_WIDTH 0x00000001u
#define EDRV32_DISP_IRQ_STAT_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_IRQ_STAT_ERROR_POS 0x00000001u
#define EDRV32_DISP_IRQ_STAT_ERROR_WIDTH 0x00000001u
#define EDRV32_DISP_IRQ_STAT_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_IRQ_STAT_FRAME_POS 0x00000002u
#define EDRV32_DISP_IRQ_STAT_FRAME_WIDTH 0x00000001u
#define EDRV32_DISP_IRQ_STAT_FRAME_MASK 0x00000004u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1 */
#define EDRV32_DISP_IRQ_STAT_SWITCH_POS 0x00000008u
#define EDRV32_DISP_IRQ_STAT_SWITCH_WIDTH 0x00000001u
#define EDRV32_DISP_IRQ_STAT_SWITCH_MASK 0x00000100u

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; RO; reset: 0. */
#define EDRV32_DISP_ERR_CODE_OFFSET 0x00000014u
#define EDRV32_DISP_ERR_CODE_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; RW; reset: 0. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_DISP_DESC_BASE_OFFSET 0x00000020u
#define EDRV32_DISP_DESC_BASE_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; RW; reset: 0. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_DISP_DESC_COUNT_OFFSET 0x00000024u
#define EDRV32_DISP_DESC_COUNT_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; WO; reset: 0. */
/* WO; reads 0 (SoC 7.1). */
#define EDRV32_DISP_DOORBELL_OFFSET 0x00000028u
#define EDRV32_DISP_DOORBELL_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; RO; reset: 0. */
#define EDRV32_DISP_DONE_COUNT_OFFSET 0x0000002Cu
#define EDRV32_DISP_DONE_COUNT_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; disp-spec.md 4.3; RO; reset: 0. */
#define EDRV32_DISP_PERF_N_COUNT 0x00000010u
#define EDRV32_DISP_PERF_OFFSET(n) \
    (0x00000040u + 0x00000004u * (n))
#define EDRV32_DISP_PERF_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; disp-spec.md 4.1; disp-spec.md 4.3 */
#define EDRV32_DISP_PERF_VALUE_POS 0x00000000u
#define EDRV32_DISP_PERF_VALUE_WIDTH 0x00000020u
#define EDRV32_DISP_PERF_VALUE_MASK 0xFFFFFFFFu

/* disp-spec.md 4.2; RW; reset: 0. */
#define EDRV32_DISP_NEXT_BASE_OFFSET 0x00000100u
#define EDRV32_DISP_NEXT_BASE_RESET 0x00000000u
/* disp-spec.md 4.2 */
#define EDRV32_DISP_NEXT_BASE_VALUE_POS 0x0000000Cu
#define EDRV32_DISP_NEXT_BASE_VALUE_WIDTH 0x00000014u
#define EDRV32_DISP_NEXT_BASE_VALUE_MASK 0xFFFFF000u

/* disp-spec.md 4.2; RW; reset: 2560. */
#define EDRV32_DISP_STRIDE_OFFSET 0x00000104u
#define EDRV32_DISP_STRIDE_RESET 0x00000A00u
/* disp-spec.md 4.2 */
#define EDRV32_DISP_STRIDE_VALUE_POS 0x00000005u
#define EDRV32_DISP_STRIDE_VALUE_WIDTH 0x0000000Bu
#define EDRV32_DISP_STRIDE_VALUE_MASK 0x0000FFE0u

/* disp-spec.md 4.2; RO; reset: 0. */
#define EDRV32_DISP_CUR_BASE_OFFSET 0x00000108u
#define EDRV32_DISP_CUR_BASE_RESET 0x00000000u

/* disp-spec.md 4.2; RO; reset: 0. */
#define EDRV32_DISP_REL_BASE_OFFSET 0x0000010Cu
#define EDRV32_DISP_REL_BASE_RESET 0x00000000u

/* disp-spec.md 4.2; RO; reset: 0. */
#define EDRV32_DISP_FRAME_CNT_OFFSET 0x00000110u
#define EDRV32_DISP_FRAME_CNT_RESET 0x00000000u
/* disp-spec.md 4.2 */
#define EDRV32_DISP_FRAME_CNT_VALUE_POS 0x00000000u
#define EDRV32_DISP_FRAME_CNT_VALUE_WIDTH 0x00000020u
#define EDRV32_DISP_FRAME_CNT_VALUE_MASK 0xFFFFFFFFu

#endif
