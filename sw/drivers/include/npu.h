/* File: npu.h
 * Spec: npu-spec 2.4, 4
 * Description: B2 media engine software interface.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_NPU_H
#define EDRV32_NPU_H
#include "engine.h"
struct npu_config {
    uint32_t model;
    uint32_t work;
    uint32_t input;
    uint32_t output;
    uint32_t descriptors;
    uint32_t count;
};
/* NPU 2.4, 4: set all physical bases and descriptor count while idle. */
void npu_configure(const struct npu_config *config);
/* NPU 2.4: update INPUT/OUTPUT while idle and ring DOORBELL for one inference. */
void npu_start(uint32_t input, uint32_t output);
/* NPU 4: read current descriptor index for error reporting. */
uint32_t npu_current_descriptor(void);
/* npu-spec 2.6: normal mode EN=1, RAW_CLS_WRITE=0, thresholds 103/105/103, .25. */
void npu_post_configure(void);
/* SoC 7.4: release all dirty candidate lines, select POST_BASE, then ring DOORBELL. */
void npu_post_start(uint32_t input, uint32_t output, uint32_t post);
/* Call only after successful DONE; invalidate complete lines, then return POST_COUNT. */
uint32_t npu_post_acquire(uint32_t post);
uint32_t npu_post_count(void);
uint32_t npu_post_status(void);
#endif
