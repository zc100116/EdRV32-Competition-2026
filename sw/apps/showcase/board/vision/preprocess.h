/* preprocess.h — live demo L9/L13; grid histogram, percentile levels and gamma.
 * Pure CPU calculations shared by board and host tests; clk_sys.
 */
#ifndef SHOWCASE_PREPROCESS_H
#define SHOWCASE_PREPROCESS_H
#include <stdint.h>
#include <math.h>
enum { SHOWCASE_DEFAULT_PRESET = 1, SHOWCASE_TARGET_LUMA = 110,
       SHOWCASE_DEFAULT_EXPOSURE = 44 };
struct preprocess_stats { unsigned mean, lo, hi; };
static inline struct preprocess_stats preprocess_measure(const uint16_t *pixels, unsigned stride)
{
    unsigned histogram[256] = {0}, sum = 0;
    for (unsigned y = 0; y < 45; ++y)
        for (unsigned x = 0; x < 80; ++x) {
            unsigned c = pixels[y*16*stride+x*16];
            unsigned r = (c >> 11)&31, g = (c >> 5)&63, b = c&31;
            r = (r << 3)|(r >> 2);
            g = (g << 2)|(g >> 4);
            b = (b << 3)|(b >> 2);
            unsigned luma = (77*r+150*g+29*b) >> 8;
            ++histogram[luma]; sum += luma;
        }
    unsigned count = 0, lo = 0, hi = 0;
    for (unsigned i = 0; i < 256; ++i) {
        unsigned previous = count; count += histogram[i];
        if (previous < 72 && count >= 72) lo = i;
        if (previous < 3528 && count >= 3528) hi = i;
    }
    return (struct preprocess_stats){(sum+1800)/3600,lo,hi};
}
static inline void preprocess_levels(unsigned lo, unsigned hi, int *contrast, int *brightness)
{
    unsigned span = hi-lo < 32 ? 32 : hi-lo;
    int c = (256*224+span/2)/span;
    if (c > 511) c = 511;
    /* PIX 2.2 arithmetic shift: choose B so lo maps exactly to 16. */
    int b = 16-128-(((int)lo-128)*c >> 8);
    *contrast = c;
    *brightness = b < -256 ? -256 : b > 255 ? 255 : b;
}
static inline unsigned preprocess_bc(unsigned mean, int contrast, int brightness)
{
    int value = (((int)mean-128)*contrast >> 8)+128+brightness;
    return value < 0 ? 0 : value > 255 ? 255 : (unsigned)value;
}
static inline unsigned preprocess_gamma(unsigned mean, unsigned current)
{
    double gamma = mean == 0 ? 0.4 : mean == 255 ? 1.0 :
        log(SHOWCASE_TARGET_LUMA/255.0)/log(mean/255.0);
    if (gamma < 0.4) gamma = 0.4;
    if (gamma > 1.0) gamma = 1.0;
    if (fabs(gamma-current/10.0) < 0.1) return current;
    return (unsigned)(gamma*10+0.5);
}
static inline uint8_t preprocess_gamma_value(unsigned value, unsigned tenths)
{ return (uint8_t)(255*pow(value/255.0,tenths/10.0)+0.5); }
/* L13.1: lower-bound inverse of the monotonic, currently applied point transform. */
static inline unsigned preprocess_input(unsigned output, int contrast, int brightness,
                                        const uint8_t *gamma)
{
    unsigned low = 0, high = 255;
    while (low < high) {
        unsigned middle = (low+high)/2;
        unsigned value = preprocess_bc(middle,contrast,brightness);
        if (gamma) value = gamma[value];
        if (value >= output) high = middle;
        else low = middle+1;
    }
    return low;
}
static inline struct preprocess_stats preprocess_input_stats(struct preprocess_stats output,
                                                             int contrast, int brightness,
                                                             const uint8_t *gamma)
{
    return (struct preprocess_stats){
        preprocess_input(output.mean,contrast,brightness,gamma),
        preprocess_input(output.lo,contrast,brightness,gamma),
        preprocess_input(output.hi,contrast,brightness,gamma)};
}
static inline void preprocess_levels_update(unsigned lo, unsigned hi,
                                             int *contrast, int *brightness)
{
    int c, b;
    preprocess_levels(lo,hi,&c,&b);
    c = (*contrast+c)/2;
    b = (*brightness+b)/2;
    if (c >= *contrast+16 || c <= *contrast-16) *contrast = c;
    if (b >= *brightness+8 || b <= *brightness-8) *brightness = b;
}

#endif
