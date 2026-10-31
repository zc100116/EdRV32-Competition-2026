/* File: s3_platform.h
 * Spec: SoC 3.5/7.3/7.4; RND 5.4; DISP 5.3; Task B3-3b.
 * Description: Shared input, rendering completion and display ownership interface.
 * Clock domain: clk_sys CPU, media interrupts from clk_mem.
 */
#ifndef S3_PLATFORM_H
#define S3_PLATFORM_H

#include <stdint.h>
#include "rnd.h"
#include "disp.h"

enum s3_key {
    S3_KEY_LEFT = 1,
    S3_KEY_RIGHT = 2,
    S3_KEY_JUMP = 4,
    S3_KEY_PAUSE = 8
};

/* DDR storage: discard the cached alias before transferring to this alias. */
void *s3_uncached(void *storage);
void s3_platform_init(void);
uint64_t s3_ticks(void);
uint32_t s3_clock_hz(void);
uint32_t s3_milliseconds(void);
uint32_t s3_input(void); /* GPIO held bits; UART a/d/w/p supplies the same bits. */
uint32_t s3_frame_count(void);
void s3_wait_frame(void);
/* One synchronous batch, completed through the one shared RND IRQ callback.
 * On ERROR print ERR_CODE/CUR_DESC and stop. No polling completion or fallback.
 */
void s3_rnd_run(const struct rnd_batch *batch);
/* Last synchronous run, including submit/cache maintenance and DONE IRQ service. */
uint64_t s3_rnd_elapsed_ticks(void);
struct s3_rnd_timing {
    uint64_t clean_ticks;
    uint64_t wait_ticks;
    uint64_t finish_ticks;
    uint32_t cache_ops;
};
struct s3_rnd_timing s3_rnd_last_timing(void);
/* cpu-spec 5/7.1: cycle, instret and events 9--16 in one scene window. */
struct s3_cpu_counters {
    uint64_t cycles;
    uint64_t instructions;
    uint64_t events[8];
};
void s3_cpu_begin(void);
void s3_cpu_end(struct s3_cpu_counters *counters);
_Noreturn void s3_stop(void);
/* Stop and await IDLE before changing ownership; NULL L1 keeps L1 disabled. */
void s3_display_begin(const void *l0, uint32_t l0_stride,
                      const void *l1, uint32_t l1_stride);
void s3_display_stop(void);
/* Stage scroll for the same submission window as the next Surface flip. */
void s3_display_scroll(uint16_t x, uint16_t y);
/* Submit together in the current FRAME window, then await each layer's SWITCH.
 * NULL means leave that layer unchanged; initial setup uses display_begin.
 * Return is already in the next FRAME: no extra wait_frame in the app loop.
 */
void s3_display_present(const void *l0, uint32_t l0_stride,
                        const void *l1, uint32_t l1_stride);
void s3_puts(const char *text);
void s3_put_u32(uint32_t value);
void s3_put_hex(uint32_t value);

#endif
