/* File: ch2.c
 * Spec: vin-spec 2.8; Task T-UI1.
 * Description: Byte-exact CPU equivalent of VIN RGB565 to INT8_C4 adaptation.
 * Clock domain: clk_sys; input/output are caller-owned CPU buffers.
 */
#include "demo.h"

static unsigned int channel(uint16_t pixel, unsigned int c)
{
    unsigned int value = c == 0 ? pixel >> 11 : c == 1 ? (pixel >> 5) & 63u : pixel & 31u;
    return c == 1 ? (value << 2) | (value >> 4) : (value << 3) | (value >> 2);
}

void demo_ch2(const uint8_t *rgb565, uint8_t *output)
{
    for (unsigned int y = 0; y < 384; ++y) {
        for (unsigned int x = 0; x < 640; ++x) {
            for (unsigned int c = 0; c < 3; ++c) {
                unsigned int value = 114;
                if (y >= 12 && y < 372) {
                    unsigned int sum = 0;
                    for (unsigned int dy = 0; dy < 2; ++dy) {
                        for (unsigned int dx = 0; dx < 2; ++dx) {
                            unsigned int offset = ((y - 12) * 2 + dy) * DEMO_STRIDE +
                                                  (x * 2 + dx) * 2;
                            uint16_t pixel = (uint16_t)(rgb565[offset] |
                                                       (rgb565[offset + 1] << 8));
                            sum += channel(pixel, c);
                        }
                    }
                    value = (sum + 2) >> 2;
                }
                *output++ = (uint8_t)((254 * value + 255) / 510);
            }
            *output++ = 0;
        }
    }
}
