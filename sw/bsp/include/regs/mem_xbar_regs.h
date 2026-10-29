/* File: mem_xbar_regs.h
 * Spec: edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1
 * Description: Engine register offsets, fields and descriptor layouts.
 * Clock domain: none (constants).
 */
// 由 tools/gen/regs.py 从 rtl/include/regs/*.json 生成，不要手改。
#ifndef EDRV32_MEM_XBAR_REGS_H
#define EDRV32_MEM_XBAR_REGS_H

/* VALUE names unnamed ranges; common bit names include unused bits (SoC 7.1). */

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RO; reset: 524289. */
#define EDRV32_MEM_XBAR_ID_OFFSET 0x00000000u
#define EDRV32_MEM_XBAR_ID_RESET 0x00080001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_ID_VALUE_31_16_POS 0x00000010u
#define EDRV32_MEM_XBAR_ID_VALUE_31_16_WIDTH 0x00000010u
#define EDRV32_MEM_XBAR_ID_VALUE_31_16_MASK 0xFFFF0000u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_ID_VALUE_15_0_POS 0x00000000u
#define EDRV32_MEM_XBAR_ID_VALUE_15_0_WIDTH 0x00000010u
#define EDRV32_MEM_XBAR_ID_VALUE_15_0_MASK 0x0000FFFFu

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RW; reset: 0. */
#define EDRV32_MEM_XBAR_CTRL_OFFSET 0x00000004u
#define EDRV32_MEM_XBAR_CTRL_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_CTRL_ENABLE_POS 0x00000000u
#define EDRV32_MEM_XBAR_CTRL_ENABLE_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_CTRL_ENABLE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_CTRL_START_POS 0x00000001u
#define EDRV32_MEM_XBAR_CTRL_START_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_CTRL_START_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_CTRL_ABORT_POS 0x00000002u
#define EDRV32_MEM_XBAR_CTRL_ABORT_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_CTRL_ABORT_MASK 0x00000004u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_CTRL_SOFT_RST_POS 0x00000003u
#define EDRV32_MEM_XBAR_CTRL_SOFT_RST_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_CTRL_SOFT_RST_MASK 0x00000008u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RO; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_MEM_XBAR_STATUS_OFFSET 0x00000008u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_STATUS_BUSY_POS 0x00000000u
#define EDRV32_MEM_XBAR_STATUS_BUSY_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_STATUS_BUSY_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_STATUS_IDLE_POS 0x00000001u
#define EDRV32_MEM_XBAR_STATUS_IDLE_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_STATUS_IDLE_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_STATUS_ERROR_POS 0x00000002u
#define EDRV32_MEM_XBAR_STATUS_ERROR_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_STATUS_ERROR_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RW; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_MEM_XBAR_IRQ_EN_OFFSET 0x0000000Cu
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_IRQ_EN_DONE_POS 0x00000000u
#define EDRV32_MEM_XBAR_IRQ_EN_DONE_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_IRQ_EN_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_IRQ_EN_ERROR_POS 0x00000001u
#define EDRV32_MEM_XBAR_IRQ_EN_ERROR_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_IRQ_EN_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_IRQ_EN_FRAME_POS 0x00000002u
#define EDRV32_MEM_XBAR_IRQ_EN_FRAME_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_IRQ_EN_FRAME_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RW1C; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_MEM_XBAR_IRQ_STAT_OFFSET 0x00000010u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_IRQ_STAT_DONE_POS 0x00000000u
#define EDRV32_MEM_XBAR_IRQ_STAT_DONE_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_IRQ_STAT_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_IRQ_STAT_ERROR_POS 0x00000001u
#define EDRV32_MEM_XBAR_IRQ_STAT_ERROR_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_IRQ_STAT_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_IRQ_STAT_FRAME_POS 0x00000002u
#define EDRV32_MEM_XBAR_IRQ_STAT_FRAME_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_IRQ_STAT_FRAME_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RO; reset: null. */
/* Reset metadata: unspecified. */
#define EDRV32_MEM_XBAR_ERR_CODE_OFFSET 0x00000014u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RW; reset: 0. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_MEM_XBAR_DESC_BASE_OFFSET 0x00000020u
#define EDRV32_MEM_XBAR_DESC_BASE_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RW; reset: 0. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_MEM_XBAR_DESC_COUNT_OFFSET 0x00000024u
#define EDRV32_MEM_XBAR_DESC_COUNT_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; WO; reset: null. */
/* Reset metadata: not_applicable. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_MEM_XBAR_DOORBELL_OFFSET 0x00000028u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_DONE_COUNT_OFFSET 0x0000002Cu
#define EDRV32_MEM_XBAR_DONE_COUNT_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_PERF_N_COUNT 0x00000010u
#define EDRV32_MEM_XBAR_PERF_OFFSET(n) \
    (0x00000040u + 0x00000004u * (n))
#define EDRV32_MEM_XBAR_PERF_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RW; reset: 8. */
#define EDRV32_MEM_XBAR_OUTST_TOTAL_OFFSET 0x00000100u
#define EDRV32_MEM_XBAR_OUTST_TOTAL_RESET 0x00000008u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_OUTST_TOTAL_VALUE_POS 0x00000000u
#define EDRV32_MEM_XBAR_OUTST_TOTAL_VALUE_WIDTH 0x00000004u
#define EDRV32_MEM_XBAR_OUTST_TOTAL_VALUE_MASK 0x0000000Fu

/* mem-subsys-spec.md 4.1; RW; reset: 8. */
#define EDRV32_MEM_XBAR_URG_MAX_OFFSET 0x00000104u
#define EDRV32_MEM_XBAR_URG_MAX_RESET 0x00000008u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_URG_MAX_VALUE_POS 0x00000000u
#define EDRV32_MEM_XBAR_URG_MAX_VALUE_WIDTH 0x00000008u
#define EDRV32_MEM_XBAR_URG_MAX_VALUE_MASK 0x000000FFu

/* mem-subsys-spec.md 4.1; RW; reset: 256. */
#define EDRV32_MEM_XBAR_STARVE_CYC_OFFSET 0x00000108u
#define EDRV32_MEM_XBAR_STARVE_CYC_RESET 0x00000100u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_STARVE_CYC_VALUE_POS 0x00000000u
#define EDRV32_MEM_XBAR_STARVE_CYC_VALUE_WIDTH 0x00000010u
#define EDRV32_MEM_XBAR_STARVE_CYC_VALUE_MASK 0x0000FFFFu

/* mem-subsys-spec.md 4.1; RW; reset: 4. */
#define EDRV32_MEM_XBAR_DIR_BATCH_OFFSET 0x0000010Cu
#define EDRV32_MEM_XBAR_DIR_BATCH_RESET 0x00000004u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_DIR_BATCH_VALUE_POS 0x00000000u
#define EDRV32_MEM_XBAR_DIR_BATCH_VALUE_WIDTH 0x00000008u
#define EDRV32_MEM_XBAR_DIR_BATCH_VALUE_MASK 0x000000FFu

/* mem-subsys-spec.md 4.1; WO; reset: null. */
/* Reset metadata: not_applicable. */
#define EDRV32_MEM_XBAR_STAT_CTRL_OFFSET 0x00000110u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_STAT_CTRL_SNAPSHOT_POS 0x00000000u
#define EDRV32_MEM_XBAR_STAT_CTRL_SNAPSHOT_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_STAT_CTRL_SNAPSHOT_MASK 0x00000001u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_STAT_CTRL_CLEAR_POS 0x00000001u
#define EDRV32_MEM_XBAR_STAT_CTRL_CLEAR_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_STAT_CTRL_CLEAR_MASK 0x00000002u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_ERR_PORT_OFFSET 0x00000120u
#define EDRV32_MEM_XBAR_ERR_PORT_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_ERR_ADDR_OFFSET 0x00000124u
#define EDRV32_MEM_XBAR_ERR_ADDR_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_ERR_TYPE_OFFSET 0x00000128u
#define EDRV32_MEM_XBAR_ERR_TYPE_RESET 0x00000000u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_ERR_TYPE_VALUE_0_POS 0x00000000u
#define EDRV32_MEM_XBAR_ERR_TYPE_VALUE_0_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_ERR_TYPE_VALUE_0_MASK 0x00000001u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_ERR_TYPE_VALUE_2_POS 0x00000002u
#define EDRV32_MEM_XBAR_ERR_TYPE_VALUE_2_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_ERR_TYPE_VALUE_2_MASK 0x00000004u

/* mem-subsys-spec.md 4.1; edrv32-soc-spec.md 6.4.5; RW; reset: [4, 2, 1, 4, 2, 2, 2]. */
/* Reset sources are cited in spec; WEIGHT P2 unused; RATE only P2/P6. */
#define EDRV32_MEM_XBAR_OUTST_RD_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_OUTST_RD_OFFSET(p) \
    (0x00000200u + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_OUTST_RD_RESET_0 0x00000004u
#define EDRV32_MEM_XBAR_OUTST_RD_RESET_1 0x00000002u
#define EDRV32_MEM_XBAR_OUTST_RD_RESET_2 0x00000001u
#define EDRV32_MEM_XBAR_OUTST_RD_RESET_3 0x00000004u
#define EDRV32_MEM_XBAR_OUTST_RD_RESET_4 0x00000002u
#define EDRV32_MEM_XBAR_OUTST_RD_RESET_5 0x00000002u
#define EDRV32_MEM_XBAR_OUTST_RD_RESET_6 0x00000002u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_OUTST_RD_VALUE_POS 0x00000000u
#define EDRV32_MEM_XBAR_OUTST_RD_VALUE_WIDTH 0x00000004u
#define EDRV32_MEM_XBAR_OUTST_RD_VALUE_MASK 0x0000000Fu

/* mem-subsys-spec.md 4.1; edrv32-soc-spec.md 6.4.5; RW; reset: [0, 4, 1, 2, 2, 2, 2]. */
/* Reset sources are cited in spec; WEIGHT P2 unused; RATE only P2/P6. */
#define EDRV32_MEM_XBAR_OUTST_WR_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_OUTST_WR_OFFSET(p) \
    (0x00000204u + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_OUTST_WR_RESET_0 0x00000000u
#define EDRV32_MEM_XBAR_OUTST_WR_RESET_1 0x00000004u
#define EDRV32_MEM_XBAR_OUTST_WR_RESET_2 0x00000001u
#define EDRV32_MEM_XBAR_OUTST_WR_RESET_3 0x00000002u
#define EDRV32_MEM_XBAR_OUTST_WR_RESET_4 0x00000002u
#define EDRV32_MEM_XBAR_OUTST_WR_RESET_5 0x00000002u
#define EDRV32_MEM_XBAR_OUTST_WR_RESET_6 0x00000002u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_OUTST_WR_VALUE_POS 0x00000000u
#define EDRV32_MEM_XBAR_OUTST_WR_VALUE_WIDTH 0x00000004u
#define EDRV32_MEM_XBAR_OUTST_WR_VALUE_MASK 0x0000000Fu

/* mem-subsys-spec.md 4.1; edrv32-soc-spec.md 6.4.5; RW; reset: [4, 4, null, 3, 2, 2, 1]. */
/* Reset metadata: null entries are unspecified or unused in the cited table. */
/* Reset sources are cited in spec; WEIGHT P2 unused; RATE only P2/P6. */
#define EDRV32_MEM_XBAR_WEIGHT_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_WEIGHT_OFFSET(p) \
    (0x00000208u + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_WEIGHT_RESET_0 0x00000004u
#define EDRV32_MEM_XBAR_WEIGHT_RESET_1 0x00000004u
#define EDRV32_MEM_XBAR_WEIGHT_RESET_3 0x00000003u
#define EDRV32_MEM_XBAR_WEIGHT_RESET_4 0x00000002u
#define EDRV32_MEM_XBAR_WEIGHT_RESET_5 0x00000002u
#define EDRV32_MEM_XBAR_WEIGHT_RESET_6 0x00000001u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_WEIGHT_VALUE_POS 0x00000000u
#define EDRV32_MEM_XBAR_WEIGHT_VALUE_WIDTH 0x00000004u
#define EDRV32_MEM_XBAR_WEIGHT_VALUE_MASK 0x0000000Fu

/* mem-subsys-spec.md 4.1; edrv32-soc-spec.md 6.4.5; RW; reset: [null, null, 26, null, null, null, 13]. */
/* Reset metadata: null entries are unspecified or unused in the cited table. */
/* Reset sources are cited in spec; WEIGHT P2 unused; RATE only P2/P6. */
#define EDRV32_MEM_XBAR_RATE_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_RATE_OFFSET(p) \
    (0x0000020Cu + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_RATE_RESET_2 0x0000001Au
#define EDRV32_MEM_XBAR_RATE_RESET_6 0x0000000Du
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_RATE_VALUE_POS 0x00000000u
#define EDRV32_MEM_XBAR_RATE_VALUE_WIDTH 0x00000009u
#define EDRV32_MEM_XBAR_RATE_VALUE_MASK 0x000001FFu

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_RD_TXN_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_RD_TXN_OFFSET(p) \
    (0x00000400u + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_RD_TXN_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_RD_BEAT_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_RD_BEAT_OFFSET(p) \
    (0x00000404u + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_RD_BEAT_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_WAIT_MAX_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_WAIT_MAX_OFFSET(p) \
    (0x00000408u + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_WAIT_MAX_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_WAIT_SUM_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_WAIT_SUM_OFFSET(p) \
    (0x0000040Cu + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_WAIT_SUM_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_URG_CNT_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_URG_CNT_OFFSET(p) \
    (0x00000410u + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_URG_CNT_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_WR_TXN_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_WR_TXN_OFFSET(p) \
    (0x00000414u + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_WR_TXN_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_WR_BEAT_P_COUNT 0x00000007u
#define EDRV32_MEM_XBAR_WR_BEAT_OFFSET(p) \
    (0x00000418u + 0x00000020u * (p))
#define EDRV32_MEM_XBAR_WR_BEAT_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_DIR_SWITCH_OFFSET 0x00000500u
#define EDRV32_MEM_XBAR_DIR_SWITCH_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_DS_BUSY_OFFSET 0x00000504u
#define EDRV32_MEM_XBAR_DS_BUSY_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_WINDOW_CYC_OFFSET 0x00000508u
#define EDRV32_MEM_XBAR_WINDOW_CYC_RESET 0x00000000u

#endif
