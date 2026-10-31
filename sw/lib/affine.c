/* File: affine.c
 * Spec: geo-spec 2.1, 2.4, 5.2.
 * Description: Invert rotation, independent scale, translation and mirrors about center.
 * Clock domain: none (pure software).
 */
#include "affine.h"
#include <limits.h>

const char *affine_inverse(int32_t matrix[6], int angle_tenths, int scale_x,
                           int scale_y, int translate_x, int translate_y,
                           int mirror_x, int mirror_y, int width, int height)
{
    if (scale_x <= 0 || scale_y <= 0) {
        return "GEO scale must be positive (per mille)";
    }
    double angle = (angle_tenths % 3600) * (3.14159265358979323846 / 1800.0);
    if (angle > 3.14159265358979323846) {
        angle -= 6.28318530717958647692;
    } else if (angle < -3.14159265358979323846) {
        angle += 6.28318530717958647692;
    }
    /* Taylor recurrence on [-pi, pi], error below 2e-15 after 13 terms. */
    double sine = angle;
    double cosine = 1;
    double sine_term = angle;
    double cosine_term = 1;
    for (int n = 1; n <= 13; ++n) {
        sine_term *= -angle * angle / ((2 * n) * (2 * n + 1));
        cosine_term *= -angle * angle / ((2 * n - 1) * (2 * n));
        sine += sine_term;
        cosine += cosine_term;
    }
    double x = (mirror_x ? -1000.0 : 1000.0) / scale_x;
    double y = (mirror_y ? -1000.0 : 1000.0) / scale_y;
    double cx = (width - 1) / 2.0;
    double cy = (height - 1) / 2.0;
    double m[6] = {x * cosine, x * sine, 0, -y * sine, y * cosine, 0};
    m[2] = cx - m[0] * (cx + translate_x) - m[1] * (cy + translate_y);
    m[5] = cy - m[3] * (cx + translate_x) - m[4] * (cy + translate_y);
    for (unsigned int i = 0; i < 6; ++i) {
        double q = m[i] * 65536.0;
        if (q < INT32_MIN || q > INT32_MAX) {
            return "GEO matrix exceeds signed Q16.16 range";
        }
        matrix[i] = (int32_t)(q < 0 ? q - 0.5 : q + 0.5);
    }
    /* 5.2: BW=32, BH=16, PW=PH=80; test the actual quantized descriptor. */
    for (unsigned int row = 0; row < 2; ++row) {
        int64_t a = matrix[row * 3];
        int64_t b = matrix[row * 3 + 1];
        if ((a < 0 ? -a : a) * 31 + (b < 0 ? -b : b) * 15 > 78 * 65536) {
            return "GEO transform exceeds geo-spec 2.4 source tile coverage";
        }
    }
    return 0;
}
