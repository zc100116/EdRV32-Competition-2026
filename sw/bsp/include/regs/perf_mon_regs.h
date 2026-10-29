/* File: perf_mon_regs.h
 * Spec: edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2
 * Description: Engine register offsets, fields and descriptor layouts.
 * Clock domain: none (constants).
 */
// 由 tools/gen/regs.py 从 rtl/include/regs/*.json 生成，不要手改。
#ifndef EDRV32_PERF_MON_REGS_H
#define EDRV32_PERF_MON_REGS_H

/* VALUE names unnamed ranges; common bit names include unused bits (SoC 7.1). */

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; RO; reset: 589825. */
#define EDRV32_PERF_MON_ID_OFFSET 0x00000000u
#define EDRV32_PERF_MON_ID_RESET 0x00090001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_ID_TYPE_POS 0x00000010u
#define EDRV32_PERF_MON_ID_TYPE_WIDTH 0x00000010u
#define EDRV32_PERF_MON_ID_TYPE_MASK 0xFFFF0000u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_ID_VERSION_POS 0x00000000u
#define EDRV32_PERF_MON_ID_VERSION_WIDTH 0x00000010u
#define EDRV32_PERF_MON_ID_VERSION_MASK 0x0000FFFFu

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; RW; reset: 0. */
#define EDRV32_PERF_MON_CTRL_OFFSET 0x00000004u
#define EDRV32_PERF_MON_CTRL_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_CTRL_ENABLE_POS 0x00000000u
#define EDRV32_PERF_MON_CTRL_ENABLE_WIDTH 0x00000001u
#define EDRV32_PERF_MON_CTRL_ENABLE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_CTRL_START_POS 0x00000001u
#define EDRV32_PERF_MON_CTRL_START_WIDTH 0x00000001u
#define EDRV32_PERF_MON_CTRL_START_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_CTRL_ABORT_POS 0x00000002u
#define EDRV32_PERF_MON_CTRL_ABORT_WIDTH 0x00000001u
#define EDRV32_PERF_MON_CTRL_ABORT_MASK 0x00000004u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_CTRL_SOFT_RST_POS 0x00000003u
#define EDRV32_PERF_MON_CTRL_SOFT_RST_WIDTH 0x00000001u
#define EDRV32_PERF_MON_CTRL_SOFT_RST_MASK 0x00000008u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; RO; reset: 2. */
#define EDRV32_PERF_MON_STATUS_OFFSET 0x00000008u
#define EDRV32_PERF_MON_STATUS_RESET 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_STATUS_BUSY_POS 0x00000000u
#define EDRV32_PERF_MON_STATUS_BUSY_WIDTH 0x00000001u
#define EDRV32_PERF_MON_STATUS_BUSY_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_STATUS_IDLE_POS 0x00000001u
#define EDRV32_PERF_MON_STATUS_IDLE_WIDTH 0x00000001u
#define EDRV32_PERF_MON_STATUS_IDLE_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_STATUS_ERROR_POS 0x00000002u
#define EDRV32_PERF_MON_STATUS_ERROR_WIDTH 0x00000001u
#define EDRV32_PERF_MON_STATUS_ERROR_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; RW; reset: 0. */
#define EDRV32_PERF_MON_IRQ_EN_OFFSET 0x0000000Cu
#define EDRV32_PERF_MON_IRQ_EN_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_IRQ_EN_DONE_POS 0x00000000u
#define EDRV32_PERF_MON_IRQ_EN_DONE_WIDTH 0x00000001u
#define EDRV32_PERF_MON_IRQ_EN_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_IRQ_EN_ERROR_POS 0x00000001u
#define EDRV32_PERF_MON_IRQ_EN_ERROR_WIDTH 0x00000001u
#define EDRV32_PERF_MON_IRQ_EN_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_IRQ_EN_FRAME_POS 0x00000002u
#define EDRV32_PERF_MON_IRQ_EN_FRAME_WIDTH 0x00000001u
#define EDRV32_PERF_MON_IRQ_EN_FRAME_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; RW1C; reset: 0. */
#define EDRV32_PERF_MON_IRQ_STAT_OFFSET 0x00000010u
#define EDRV32_PERF_MON_IRQ_STAT_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_IRQ_STAT_DONE_POS 0x00000000u
#define EDRV32_PERF_MON_IRQ_STAT_DONE_WIDTH 0x00000001u
#define EDRV32_PERF_MON_IRQ_STAT_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_IRQ_STAT_ERROR_POS 0x00000001u
#define EDRV32_PERF_MON_IRQ_STAT_ERROR_WIDTH 0x00000001u
#define EDRV32_PERF_MON_IRQ_STAT_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_IRQ_STAT_FRAME_POS 0x00000002u
#define EDRV32_PERF_MON_IRQ_STAT_FRAME_WIDTH 0x00000001u
#define EDRV32_PERF_MON_IRQ_STAT_FRAME_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_ERR_CODE_OFFSET 0x00000014u
#define EDRV32_PERF_MON_ERR_CODE_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; RW; reset: 0. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_PERF_MON_DESC_BASE_OFFSET 0x00000020u
#define EDRV32_PERF_MON_DESC_BASE_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; RW; reset: 0. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_PERF_MON_DESC_COUNT_OFFSET 0x00000024u
#define EDRV32_PERF_MON_DESC_COUNT_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; WO; reset: 0. */
/* WO; reads 0 (SoC 7.1). */
#define EDRV32_PERF_MON_DOORBELL_OFFSET 0x00000028u
#define EDRV32_PERF_MON_DOORBELL_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_DONE_COUNT_OFFSET 0x0000002Cu
#define EDRV32_PERF_MON_DONE_COUNT_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_PERF_N_COUNT 0x00000010u
#define EDRV32_PERF_MON_PERF_OFFSET(n) \
    (0x00000040u + 0x00000004u * (n))
#define EDRV32_PERF_MON_PERF_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RW; reset: 0. */
#define EDRV32_PERF_MON_MODE_OFFSET 0x00000100u
#define EDRV32_PERF_MON_MODE_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RW; reset: 0. */
#define EDRV32_PERF_MON_BASE_OFFSET 0x00000104u
#define EDRV32_PERF_MON_BASE_RESET 0x00000000u
/* mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_BASE_VALUE_POS 0x0000000Cu
#define EDRV32_PERF_MON_BASE_VALUE_WIDTH 0x00000012u
#define EDRV32_PERF_MON_BASE_VALUE_MASK 0x3FFFF000u

/* mem-subsys-spec.md 4.2; RW; reset: 4096. */
#define EDRV32_PERF_MON_SIZE_OFFSET 0x00000108u
#define EDRV32_PERF_MON_SIZE_RESET 0x00001000u
/* mem-subsys-spec.md 4.2 */
#define EDRV32_PERF_MON_SIZE_VALUE_POS 0x00000009u
#define EDRV32_PERF_MON_SIZE_VALUE_WIDTH 0x00000015u
#define EDRV32_PERF_MON_SIZE_VALUE_MASK 0x3FFFFE00u

/* mem-subsys-spec.md 4.2; RW; reset: 16. */
#define EDRV32_PERF_MON_BURST_LEN_OFFSET 0x0000010Cu
#define EDRV32_PERF_MON_BURST_LEN_RESET 0x00000010u

/* mem-subsys-spec.md 4.2; RW; reset: 0. */
#define EDRV32_PERF_MON_ADDR_MODE_OFFSET 0x00000110u
#define EDRV32_PERF_MON_ADDR_MODE_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RW; reset: 8. */
#define EDRV32_PERF_MON_RW_RATIO_OFFSET 0x00000114u
#define EDRV32_PERF_MON_RW_RATIO_RESET 0x00000008u

/* mem-subsys-spec.md 4.2; RW; reset: 0. */
#define EDRV32_PERF_MON_TXN_COUNT_OFFSET 0x00000118u
#define EDRV32_PERF_MON_TXN_COUNT_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RW; reset: 4. */
#define EDRV32_PERF_MON_OUTSTANDING_OFFSET 0x0000011Cu
#define EDRV32_PERF_MON_OUTSTANDING_RESET 0x00000004u

/* mem-subsys-spec.md 4.2; RW; reset: 0. */
#define EDRV32_PERF_MON_SEED_OFFSET 0x00000120u
#define EDRV32_PERF_MON_SEED_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RW; reset: 0. */
#define EDRV32_PERF_MON_CHECK_EN_OFFSET 0x00000124u
#define EDRV32_PERF_MON_CHECK_EN_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RW; reset: 16. */
#define EDRV32_PERF_MON_HIST_WIDTH_OFFSET 0x00000128u
#define EDRV32_PERF_MON_HIST_WIDTH_RESET 0x00000010u

/* mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_TXN_DONE_OFFSET 0x00000200u
#define EDRV32_PERF_MON_TXN_DONE_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_BEATS_OFFSET 0x00000204u
#define EDRV32_PERF_MON_BEATS_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_CYCLES_OFFSET 0x00000208u
#define EDRV32_PERF_MON_CYCLES_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RO; reset: 4294967295. */
#define EDRV32_PERF_MON_LAT_MIN_OFFSET 0x0000020Cu
#define EDRV32_PERF_MON_LAT_MIN_RESET 0xFFFFFFFFu

/* mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_LAT_MAX_OFFSET 0x00000210u
#define EDRV32_PERF_MON_LAT_MAX_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_LAT_SUM_OFFSET 0x00000214u
#define EDRV32_PERF_MON_LAT_SUM_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_READ_CNT_OFFSET 0x00000218u
#define EDRV32_PERF_MON_READ_CNT_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_ERR_BEATS_OFFSET 0x0000021Cu
#define EDRV32_PERF_MON_ERR_BEATS_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_FIRST_ERR_ADDR_OFFSET 0x00000220u
#define EDRV32_PERF_MON_FIRST_ERR_ADDR_RESET 0x00000000u

/* mem-subsys-spec.md 4.2; RO; reset: 0. */
#define EDRV32_PERF_MON_HIST_N_COUNT 0x00000010u
#define EDRV32_PERF_MON_HIST_OFFSET(n) \
    (0x00000300u + 0x00000004u * (n))
#define EDRV32_PERF_MON_HIST_RESET 0x00000000u

#endif
