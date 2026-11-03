/* ch2.h — VIN spec 2.8; one row of RGB565 to letterboxed INT8_C4.
 * CPU task owns both buffers; no MMIO, clk_sys domain.
 */
#ifndef SHOWCASE_VISION_CH2_H
#define SHOWCASE_VISION_CH2_H
#include <stdint.h>
void vision_ch2_row(const uint8_t *rgb565, uint8_t *output, unsigned int y);
#endif
