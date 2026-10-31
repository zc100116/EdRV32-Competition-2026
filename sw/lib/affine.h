/* File: affine.h
 * Spec: geo-spec 2.1, 2.4, 5.2.
 * Description: Centered forward transform to inverse Q16.16 coefficients.
 * Clock domain: none (pure software).
 */
#ifndef EDRV32_AFFINE_H
#define EDRV32_AFFINE_H
#include <stdint.h>
const char *affine_inverse(int32_t matrix[6], int angle_tenths, int scale_x,
                           int scale_y, int translate_x, int translate_y,
                           int mirror_x, int mirror_y, int width, int height);
#endif
