/* geo_matrix.h — GEO 2.1; center-based inverse affine matrix helper.
 * CPU configuration only, Q16.16 output ordered A, B, TX, C, D, TY.
 */
#ifndef GEO_MATRIX_H
#define GEO_MATRIX_H
#include <stdint.h>
void geo_matrix(int32_t matrix[6], int angle, int scale_percent, int tx, int ty,
                int mirror_x, int mirror_y, unsigned width, unsigned height);
void pix_gamma_table(uint8_t table[256], unsigned gamma_tenths);
#endif
