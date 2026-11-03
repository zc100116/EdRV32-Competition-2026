/* geo_matrix.c — GEO 2.1 / PIX 2.3; parameter-to-matrix and gamma helpers.
 * CPU only; software floating point is used only when parameters change.
 */
#include "geo_matrix.h"
#include <math.h>
void geo_matrix(int32_t m[6], int angle, int scale_percent, int tx, int ty,
                int mirror_x, int mirror_y, unsigned width, unsigned height)
{
    double radians = angle * 0.017453292519943295;
    double scale = 100.0 / scale_percent;
    double a = cos(radians) * scale * (mirror_x ? -1 : 1);
    double b = sin(radians) * scale * (mirror_x ? -1 : 1);
    double c = -sin(radians) * scale * (mirror_y ? -1 : 1);
    double d = cos(radians) * scale * (mirror_y ? -1 : 1);
    double cx = (width - 1) * 0.5, cy = (height - 1) * 0.5;
    m[0] = (int32_t)lround(a * 65536);
    m[1] = (int32_t)lround(b * 65536);
    m[2] = (int32_t)lround((cx - a*(cx + tx) - b*(cy + ty)) * 65536);
    m[3] = (int32_t)lround(c * 65536);
    m[4] = (int32_t)lround(d * 65536);
    m[5] = (int32_t)lround((cy - c*(cx + tx) - d*(cy + ty)) * 65536);
}
uint8_t pix_gamma_value(unsigned input, unsigned gamma_tenths)
{
    return (uint8_t)lround(pow(input / 255.0, 10.0 / gamma_tenths) * 255);
}
void pix_gamma_table(uint8_t table[256], unsigned gamma_tenths)
{
    for (unsigned i = 0; i < 256; ++i)
        table[i] = pix_gamma_value(i, gamma_tenths);
}
