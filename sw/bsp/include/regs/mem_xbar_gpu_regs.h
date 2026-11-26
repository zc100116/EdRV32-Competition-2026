/* File: mem_xbar_gpu_regs.h
 * Spec: gpu-soc-spec.md 8.3; edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1
 * Description: Engine register offsets, fields and descriptor layouts.
 * Clock domain: none (constants).
 */
// 由 tools/gen/regs.py 从 rtl/include/regs/*.json 生成，不要手改。
#ifndef EDRV32_MEM_XBAR_GPU_REGS_H
#define EDRV32_MEM_XBAR_GPU_REGS_H

/* gpu-soc-spec v0.3: removed register addresses read zero and ignore writes. */

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RO; reset: 524289. */
#define EDRV32_MEM_XBAR_GPU_ID_OFFSET 0x00000000u
#define EDRV32_MEM_XBAR_GPU_ID_RESET 0x00080001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_ID_TYPE_POS 0x00000010u
#define EDRV32_MEM_XBAR_GPU_ID_TYPE_WIDTH 0x00000010u
#define EDRV32_MEM_XBAR_GPU_ID_TYPE_MASK 0xFFFF0000u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_ID_VERSION_POS 0x00000000u
#define EDRV32_MEM_XBAR_GPU_ID_VERSION_WIDTH 0x00000010u
#define EDRV32_MEM_XBAR_GPU_ID_VERSION_MASK 0x0000FFFFu

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RW; reset: 0. */
#define EDRV32_MEM_XBAR_GPU_CTRL_OFFSET 0x00000004u
#define EDRV32_MEM_XBAR_GPU_CTRL_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_CTRL_ENABLE_POS 0x00000000u
#define EDRV32_MEM_XBAR_GPU_CTRL_ENABLE_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_CTRL_ENABLE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_CTRL_START_POS 0x00000001u
#define EDRV32_MEM_XBAR_GPU_CTRL_START_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_CTRL_START_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_CTRL_ABORT_POS 0x00000002u
#define EDRV32_MEM_XBAR_GPU_CTRL_ABORT_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_CTRL_ABORT_MASK 0x00000004u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_CTRL_SOFT_RST_POS 0x00000003u
#define EDRV32_MEM_XBAR_GPU_CTRL_SOFT_RST_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_CTRL_SOFT_RST_MASK 0x00000008u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RO; reset: 2. */
#define EDRV32_MEM_XBAR_GPU_STATUS_OFFSET 0x00000008u
#define EDRV32_MEM_XBAR_GPU_STATUS_RESET 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_STATUS_BUSY_POS 0x00000000u
#define EDRV32_MEM_XBAR_GPU_STATUS_BUSY_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_STATUS_BUSY_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_STATUS_IDLE_POS 0x00000001u
#define EDRV32_MEM_XBAR_GPU_STATUS_IDLE_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_STATUS_IDLE_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_STATUS_ERROR_POS 0x00000002u
#define EDRV32_MEM_XBAR_GPU_STATUS_ERROR_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_STATUS_ERROR_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RW; reset: 0. */
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_OFFSET 0x0000000Cu
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_DONE_POS 0x00000000u
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_DONE_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_ERROR_POS 0x00000001u
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_ERROR_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_FRAME_POS 0x00000002u
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_FRAME_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_IRQ_EN_FRAME_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RW1C; reset: 0. */
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_OFFSET 0x00000010u
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_RESET 0x00000000u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_DONE_POS 0x00000000u
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_DONE_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_DONE_MASK 0x00000001u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_ERROR_POS 0x00000001u
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_ERROR_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_ERROR_MASK 0x00000002u
/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_FRAME_POS 0x00000002u
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_FRAME_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_IRQ_STAT_FRAME_MASK 0x00000004u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_GPU_ERR_CODE_OFFSET 0x00000014u
#define EDRV32_MEM_XBAR_GPU_ERR_CODE_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RW; reset: 0. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_MEM_XBAR_GPU_DESC_BASE_OFFSET 0x00000020u
#define EDRV32_MEM_XBAR_GPU_DESC_BASE_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RW; reset: 0. */
/* Unused; reads zero and writes ignored. */
#define EDRV32_MEM_XBAR_GPU_DESC_COUNT_OFFSET 0x00000024u
#define EDRV32_MEM_XBAR_GPU_DESC_COUNT_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; WO; reset: 0. */
/* WO; reads 0 (SoC 7.1). */
#define EDRV32_MEM_XBAR_GPU_DOORBELL_OFFSET 0x00000028u
#define EDRV32_MEM_XBAR_GPU_DOORBELL_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_GPU_DONE_COUNT_OFFSET 0x0000002Cu
#define EDRV32_MEM_XBAR_GPU_DONE_COUNT_RESET 0x00000000u

/* edrv32-soc-spec.md 7.1; mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_GPU_PERF_N_COUNT 0x00000010u
#define EDRV32_MEM_XBAR_GPU_PERF_OFFSET(n) \
    (0x00000040u + 0x00000004u * (n))
#define EDRV32_MEM_XBAR_GPU_PERF_RESET 0x00000000u

/* gpu-soc-spec.md 6.2, 8.3; RO; reset: 0. */
#define EDRV32_MEM_XBAR_GPU_ERR_PORT_OFFSET 0x00000120u
#define EDRV32_MEM_XBAR_GPU_ERR_PORT_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_GPU_ERR_ADDR_OFFSET 0x00000124u
#define EDRV32_MEM_XBAR_GPU_ERR_ADDR_RESET 0x00000000u

/* mem-subsys-spec.md 4.1; RO; reset: 0. */
#define EDRV32_MEM_XBAR_GPU_ERR_TYPE_OFFSET 0x00000128u
#define EDRV32_MEM_XBAR_GPU_ERR_TYPE_RESET 0x00000000u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_ERR_TYPE_CROSS_4K_POS 0x00000000u
#define EDRV32_MEM_XBAR_GPU_ERR_TYPE_CROSS_4K_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_ERR_TYPE_CROSS_4K_MASK 0x00000001u
/* mem-subsys-spec.md 4.1 */
#define EDRV32_MEM_XBAR_GPU_ERR_TYPE_MISALIGN_POS 0x00000002u
#define EDRV32_MEM_XBAR_GPU_ERR_TYPE_MISALIGN_WIDTH 0x00000001u
#define EDRV32_MEM_XBAR_GPU_ERR_TYPE_MISALIGN_MASK 0x00000004u

#endif
