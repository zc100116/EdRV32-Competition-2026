/* preprocess.h — live demo L4/L5; integer Q8 gain and RGB565 grid luminance.
 * Pure CPU routines shared by the board and host acceptance tests.
 */
#ifndef SHOWCASE_PREPROCESS_H
#define SHOWCASE_PREPROCESS_H
#include <stdint.h>
enum { SHOWCASE_DEFAULT_PRESET = 1, SHOWCASE_TARGET_LUMA = 110 };
static inline unsigned preprocess_gain(unsigned gain, unsigned mean, unsigned target)
{
    if (mean+8 >= target && mean <= target+8) return gain;
    if (!mean) return 511;
    unsigned next = (gain*(mean+target)+mean)/(2*mean);
    return next < 256 ? 256 : next > 511 ? 511 : next;
}
static inline unsigned preprocess_luma(const uint16_t *pixels, unsigned stride)
{
    unsigned sum = 0;
    for (unsigned y = 0; y < 45; ++y)
        for (unsigned x = 0; x < 80; ++x) {
            unsigned c = pixels[(y*16)*stride+x*16];
            unsigned r = (c >> 11)&31;
            unsigned g = (c >> 5)&63;
            unsigned b = c&31;
            r = (r << 3)|(r >> 2);
            g = (g << 2)|(g >> 4);
            b = (b << 3)|(b >> 2);
            sum += (77*r+150*g+29*b) >> 8;
        }
    return (sum+1800)/3600;
}
#endif
