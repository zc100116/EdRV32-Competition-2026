/* File: es8156.h
 * Spec: aud-spec 1, 9 A-3; ES8156 datasheet rev 5 registers 02, 08, 11.
 * Description: Configure PMOD ES8156 on I2C0 port 0 for 48 kHz, 16-bit I2S slave.
 * Clock domain: clk_sys software; codec MCLK 12.288 MHz.
 */
#ifndef EDRV32_ES8156_H
#define EDRV32_ES8156_H
#include <stdint.h>
/* Returns -1 immediately on NACK; no retries or recovery. */
int es8156_init(void);
#endif
