/* File: ov5640.h
 * Spec: SoC 3.5; design 2026-10-29-b2-software 3.2
 * Description: B2 media engine software interface.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_OV5640_H
#define EDRV32_OV5640_H
#include <stdint.h>
#include <stddef.h>
struct ov5640_register {
    uint16_t address;
    uint8_t value;
};
/* Design 3.2: vendor 720p RGB565 DVP table, stored locally rather than legacy dependency. */
const struct ov5640_register *ov5640_table(size_t *count);
/* SoC 3.5: power/reset and configure camera 0/1 over corresponding I2C0 port; NACK = -1. */
int ov5640_init(unsigned int camera, uint32_t clock_hz);
/* Design 3.2: select camera port and read 0x300a/0x300b; NACK = -1, no retry. */
int ov5640_chip_id(unsigned int camera, uint32_t clock_hz, uint16_t *chip_id);
#endif
