/* kernels.c — C2-F matrix/graphics/physics evaluation; clock: target CPU.
 * Design: 2026-11-27-cpu-v2-fpu, performance workloads. No SoC dependencies.
 */
#include "real.h"
volatile real_t sink;
real_t matrix[16][16];
real_t other[16][16];
real_t result[16][16];
real_t vertices[64][4];
real_t normals[64][3];
real_t velocity[64][3];
real_t output[64][4];

static void initialize(void)
{
    for (int i = 0; i < 16; ++i) {
        for (int j = 0; j < 16; ++j) {
            matrix[i][j] = (real_t)((i + j) % 7 + 1) * R(0.125);
            other[i][j] = (real_t)((i * 3 + j) % 11 - 5) * R(0.0625);
        }
    }
    for (int i = 0; i < 64; ++i) {
        for (int j = 0; j < 4; ++j) {
            vertices[i][j] = (real_t)(i + j + 1) * R(0.03125);
        }
        for (int j = 0; j < 3; ++j) {
            normals[i][j] = (real_t)((i+j)%5+1) * R(0.25);
            velocity[i][j] = R(0.125);
        }
    }
}

int main(void)
{
    initialize();
    start_time();
#if WORKLOAD == 0
    for (int i = 0; i < 16; ++i) {
        for (int j = 0; j < 16; ++j) {
            real_t sum = R(0.0);
            for (int k = 0; k < 16; ++k) {
                sum += matrix[i][k] * other[k][j];
            }
            result[i][j] = sum;
        }
    }
    sink = result[15][15];
#elif WORKLOAD == 1
    for (int i = 0; i < 64; ++i) {
        for (int j = 0; j < 4; ++j) {
            real_t sum = R(0.0);
            for (int k = 0; k < 4; ++k) {
                sum += matrix[j][k] * vertices[i][k];
            }
            output[i][j] = sum;
        }
        real_t x = normals[i][0];
        real_t y = normals[i][1];
        real_t z = normals[i][2];
        real_t inverse = R(1.0) / rsqrt(x*x + y*y + z*z);
        real_t light = (x*R(0.25) + y*R(0.5) + z*R(0.75)) * inverse;
        output[i][3] = light > R(0.0) ? light : R(0.0);
    }
    sink = output[63][3];
#elif WORKLOAD == 2
    for (int step = 0; step < 16; ++step) {
        for (int i = 0; i < 64; ++i) {
            for (int j = 0; j < 3; ++j) {
                real_t acceleration = -R(0.125) * vertices[i][j] - R(0.03125)*velocity[i][j];
                velocity[i][j] += acceleration * R(0.016);
                vertices[i][j] += velocity[i][j] * R(0.016);
            }
        }
    }
    sink = vertices[63][2];
#endif
    stop_time();
    return 0;
}
