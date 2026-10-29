/* File: disp.h
 * Spec: disp-spec v0.3 2.4, 2.7, 4.2, 5.3.
 * Description: Independent Surface submission and release for two display layers.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_DISP_H
#define EDRV32_DISP_H
#include "engine.h"
enum disp_layer { DISP_L0, DISP_L1 };
/* Physical Surface base/stride; group shadow writes just after FRAME (5.3). */
void disp_submit(enum disp_layer layer, uint32_t base, uint32_t stride);
void disp_layer_enable(enum disp_layer layer, unsigned int enable);
void disp_l0_scroll(uint16_t x, uint16_t y);
void disp_l1_geometry(uint16_t x, uint16_t y, uint16_t width, uint16_t height, uint8_t opa);
/* Current/released physical bases; SWITCH is read without acknowledgement.
 * Release is valid only with this layer's captured SWITCH (or after stopped IDLE).
 * v0.3 does not report a release on the first enabled frame.
 */
uint32_t disp_current(enum disp_layer layer);
uint32_t disp_switched(enum disp_layer layer);
uint32_t disp_released(enum disp_layer layer);
#endif
