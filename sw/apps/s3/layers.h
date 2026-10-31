/* File: layers.h
 * Spec: DISP 4/5.3; DS-20; RN-30; SoC 7.3 R3/R4.
 * Description: Five board layer scenes and their host-observable register submissions.
 * Clock domain: clk_sys CPU.
 */
#ifndef S3_LAYERS_H
#define S3_LAYERS_H
#include <stdint.h>

enum { S3_LAYERS_WIDTH = 1536, S3_LAYERS_HEIGHT = 848 };
typedef void (*s3_layers_write)(uint32_t offset, uint32_t value, void *context);
/* scene=1..4; call while IDLE or immediately after FRAME, with immutable Surfaces. */
void s3_layers_frame(unsigned int scene, uint32_t milliseconds, uint32_t frame,
                     uint32_t l0, uint32_t l1, s3_layers_write write, void *context);
void s3_layers_run(void);
#endif
