/* File: geo_regs.h
 * Spec: edrv32-soc-spec.md 7.1; geo-spec.md 4.1
 * Description: Engine register offsets, fields and descriptor layouts.
 * Clock domain: none (constants).
 */
// 由 tools/gen/regs.py 从 rtl/include/regs/*.json 生成，不要手改。
#ifndef EDRV32_GEO_REGS_H
#define EDRV32_GEO_REGS_H

/* VALUE names unnamed ranges; common bit names include unused bits (SoC 7.1). */

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; RO; reset: 196609. */
#define EDRV32_GEO_ID_OFFSET 0x00000000u
#define EDRV32_GEO_ID_RESET 0x00030001u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_ID_VALUE_31_16_POS 0x00000010u
#define EDRV32_GEO_ID_VALUE_31_16_WIDTH 0x00000010u
#define EDRV32_GEO_ID_VALUE_31_16_MASK 0xFFFF0000u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_ID_VALUE_15_0_POS 0x00000000u
#define EDRV32_GEO_ID_VALUE_15_0_WIDTH 0x00000010u
#define EDRV32_GEO_ID_VALUE_15_0_MASK 0x0000FFFFu

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; RW; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_GEO_CTRL_OFFSET 0x00000004u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_CTRL_ENABLE_POS 0x00000000u
#define EDRV32_GEO_CTRL_ENABLE_WIDTH 0x00000001u
#define EDRV32_GEO_CTRL_ENABLE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_CTRL_START_POS 0x00000001u
#define EDRV32_GEO_CTRL_START_WIDTH 0x00000001u
#define EDRV32_GEO_CTRL_START_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_CTRL_ABORT_POS 0x00000002u
#define EDRV32_GEO_CTRL_ABORT_WIDTH 0x00000001u
#define EDRV32_GEO_CTRL_ABORT_MASK 0x00000004u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_CTRL_SOFT_RST_POS 0x00000003u
#define EDRV32_GEO_CTRL_SOFT_RST_WIDTH 0x00000001u
#define EDRV32_GEO_CTRL_SOFT_RST_MASK 0x00000008u

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; RO; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_GEO_STATUS_OFFSET 0x00000008u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_STATUS_BUSY_POS 0x00000000u
#define EDRV32_GEO_STATUS_BUSY_WIDTH 0x00000001u
#define EDRV32_GEO_STATUS_BUSY_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_STATUS_IDLE_POS 0x00000001u
#define EDRV32_GEO_STATUS_IDLE_WIDTH 0x00000001u
#define EDRV32_GEO_STATUS_IDLE_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_STATUS_ERROR_POS 0x00000002u
#define EDRV32_GEO_STATUS_ERROR_WIDTH 0x00000001u
#define EDRV32_GEO_STATUS_ERROR_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; RW; reset: 0. */
#define EDRV32_GEO_IRQ_EN_OFFSET 0x0000000Cu
#define EDRV32_GEO_IRQ_EN_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_IRQ_EN_DONE_POS 0x00000000u
#define EDRV32_GEO_IRQ_EN_DONE_WIDTH 0x00000001u
#define EDRV32_GEO_IRQ_EN_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_IRQ_EN_ERROR_POS 0x00000001u
#define EDRV32_GEO_IRQ_EN_ERROR_WIDTH 0x00000001u
#define EDRV32_GEO_IRQ_EN_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_IRQ_EN_FRAME_POS 0x00000002u
#define EDRV32_GEO_IRQ_EN_FRAME_WIDTH 0x00000001u
#define EDRV32_GEO_IRQ_EN_FRAME_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; RW1C; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_GEO_IRQ_STAT_OFFSET 0x00000010u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_IRQ_STAT_DONE_POS 0x00000000u
#define EDRV32_GEO_IRQ_STAT_DONE_WIDTH 0x00000001u
#define EDRV32_GEO_IRQ_STAT_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_IRQ_STAT_ERROR_POS 0x00000001u
#define EDRV32_GEO_IRQ_STAT_ERROR_WIDTH 0x00000001u
#define EDRV32_GEO_IRQ_STAT_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_IRQ_STAT_FRAME_POS 0x00000002u
#define EDRV32_GEO_IRQ_STAT_FRAME_WIDTH 0x00000001u
#define EDRV32_GEO_IRQ_STAT_FRAME_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; RO; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_GEO_ERR_CODE_OFFSET 0x00000014u

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; RW; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_GEO_DESC_BASE_OFFSET 0x00000020u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_DESC_BASE_VALUE_POS 0x00000005u
#define EDRV32_GEO_DESC_BASE_VALUE_WIDTH 0x0000001Bu
#define EDRV32_GEO_DESC_BASE_VALUE_MASK 0xFFFFFFE0u

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; RW; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_GEO_DESC_COUNT_OFFSET 0x00000024u
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1 */
#define EDRV32_GEO_DESC_COUNT_VALUE_POS 0x00000000u
#define EDRV32_GEO_DESC_COUNT_VALUE_WIDTH 0x00000010u
#define EDRV32_GEO_DESC_COUNT_VALUE_MASK 0x0000FFFFu

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; WO; reset: null. */
/* Reset metadata: not_applicable. */
#define EDRV32_GEO_DOORBELL_OFFSET 0x00000028u

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; RO; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_GEO_DONE_COUNT_OFFSET 0x0000002Cu

/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; geo-spec.md 4.3; RO; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_GEO_PERF_N_COUNT 0x00000010u
#define EDRV32_GEO_PERF_OFFSET(n) \
    (0x00000040u + 0x00000004u * (n))
/* edrv32-soc-spec.md 7.1; geo-spec.md 4.1; geo-spec.md 4.3 */
#define EDRV32_GEO_PERF_VALUE_POS 0x00000000u
#define EDRV32_GEO_PERF_VALUE_WIDTH 0x00000020u
#define EDRV32_GEO_PERF_VALUE_MASK 0xFFFFFFFFu

/* geo-spec.md 4.2; RO; reset: 0. */
#define EDRV32_GEO_CUR_DESC_OFFSET 0x00000100u
#define EDRV32_GEO_CUR_DESC_RESET 0x00000000u

#endif
