/* File: rnd.h
 * Spec: rnd-spec v0.5 2.1–2.6, 4–6; SoC 7.3–7.4.
 * Description: DDR command encoders and one in-flight rendering batch.
 * Clock domain: clk_sys CPU; RND registers in clk_mem.
 */
#ifndef EDRV32_RND_H
#define EDRV32_RND_H
#include <stddef.h>
#include <stdint.h>
#include "mmio.h"
#include "regs/rnd_regs.h"

enum rnd_format {
    RND_RGB565, RND_ARGB8888, RND_A8, RND_A4, RND_A2, RND_A1, RND_I8
};
enum rnd_flags {
    RND_GRAD = 1, RND_GRAD_V = 2, RND_HFLIP = 1, RND_VFLIP = 2,
    RND_COLORKEY = 4, RND_RECOLOR = 8, RND_NORMAL = 0
};
struct rnd_command { uint32_t word[16]; };
struct rnd_rect { int16_t x0, y0, x1, y1; };
struct rnd_common {
    uint32_t dst_base;               /* Physical DDR address. */
    uint16_t dst_stride;
    enum rnd_format dst_fmt;
    enum rnd_format src_fmt;
    uint16_t flags;
    struct rnd_rect clip;             /* Inclusive coordinates, as is rect. */
    struct rnd_rect rect;
    uint32_t color;                   /* RGB888; opa is separate. */
    uint8_t opa;
};
struct rnd_source {
    uint32_t base;
    uint16_t stride;
    uint16_t x;
    uint16_t y;
};
struct rnd_blit {
    struct rnd_source source;
    uint32_t scale_x;
    uint32_t scale_y;
    uint32_t palette;
    uint16_t key;
    uint32_t rc_color;
    uint8_t rc_opa;
};
/* rnd 2.5: caller supplies DDR storage with the list base aligned to 64 bytes.
 * Encoders write exactly one descriptor; all addresses inside descriptors are physical.
 * Caller guarantees format, bounds, alignment, overlap and Surface ownership contracts.
 */
void rnd_fill(struct rnd_command *out, const struct rnd_common *c, uint16_t radius,
              uint32_t grad_start, const int32_t steps[4]);
void rnd_border(struct rnd_command *out, const struct rnd_common *c,
                uint16_t radius, uint16_t width, uint8_t sides);
void rnd_glyph(struct rnd_command *out, const struct rnd_common *c,
               const struct rnd_source *source);
void rnd_blit(struct rnd_command *out, const struct rnd_common *c,
              const struct rnd_blit *blit);
void rnd_copy(struct rnd_command *out, const struct rnd_common *c,
              const struct rnd_source *source);
/* CPU address must be in either generated DDR alias; no validation is performed. */
uint32_t rnd_physical(const void *cpu_address);
struct rnd_range { const void *address; uint32_t bytes; };
struct rnd_batch {
    const struct rnd_command *commands;
    uint16_t count;
    const struct rnd_range *sources;
    size_t source_count;
    const struct rnd_range *targets;
    size_t target_count;
};
struct rnd_result { uint32_t irq; uint32_t error; uint32_t cur_desc; };
typedef void (*rnd_callback)(const struct rnd_result *result, void *context);
/* rnd 5.4 / SoC 7.4: clean cached commands and CPU-written sources, then ring DOORBELL.
 * Noncached DDR aliases skip maintenance for commands, sources and targets.
 * Single batch at a time; range arrays remain alive through completion/abort.
 * CPU-written destination pixels needed by read/modify/write must also be sources.
 */
void rnd_submit(const struct rnd_batch *batch);
/* Poll IRQ_STAT until DONE/ERROR, wait for bus drain, invalidate declared targets,
 * capture ERR_CODE/CUR_DESC before RW1C. Does not retry or recover errors.
 * Polling and IRQ completion are mutually exclusive for a given batch.
 */
struct rnd_result rnd_wait(void);
/* Enable DONE/ERROR and PLIC source 11. The application routes claimed source 11
 * to rnd_irq_handle(), then calls plic_complete(); callback may submit next batch.
 * Application owns mtvec, mie/mstatus and any interrupt serialization.
 */
void rnd_irq_register(unsigned int priority, rnd_callback callback, void *context);
void rnd_irq_handle(void);
/* rnd 5.3: request ABORT, wait IDLE, invalidate targets; return captured error detail. */
struct rnd_result rnd_abort(void);
/* rnd 4.3: caller serializes this six-register read with DOORBELL submission. */
void rnd_read_perf(uint32_t perf[6]);
/* CLINT ticks for the last batch: pre-submit clean, DOORBELL timestamp and
 * finish() MMIO/target invalidation. cache_ops counts clean + invalidate calls.
 */
struct rnd_timing {
    uint64_t clean_ticks;
    uint64_t doorbell_tick;
    uint64_t finish_ticks;
    uint32_t cache_ops;
};
const struct rnd_timing *rnd_last_timing(void);
#endif
