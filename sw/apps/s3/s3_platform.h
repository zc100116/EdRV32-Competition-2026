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
/* Stop and await IDLE before changing ownership; NULL L1 keeps L1 disabled. */
void s3_display_begin(const void *l0, uint32_t l0_stride,
                      const void *l1, uint32_t l1_stride);
void s3_display_stop(void);
/* Submit together just after FRAME, then await each enabled layer's SWITCH.
 * NULL means leave that layer unchanged; initial setup uses display_begin.
 */
void s3_display_present(const void *l0, uint32_t l0_stride,
                        const void *l1, uint32_t l1_stride);
void s3_puts(const char *text);
void s3_put_u32(uint32_t value);
void s3_put_hex(uint32_t value);

#endif
