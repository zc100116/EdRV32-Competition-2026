/* geo_model.h — GEO §2.1–2.2; packed-descriptor RGB565 reference execution.
 * Host-only hardware replacement shared by tower acceptance and native screenshots.
 */
#ifndef SHOWCASE_GEO_MODEL_H
#define SHOWCASE_GEO_MODEL_H
#include "geo.h"
#include "../../apps/showcase/board/ddr_map.h"
#include <assert.h>
static unsigned expand(unsigned pixel, unsigned channel)
{
    unsigned c = channel == 0 ? pixel>>11 : channel == 1 ? (pixel>>5)&63 : pixel&31;
    return channel == 1 ? (c<<2)|(c>>4) : (c<<3)|(c>>2);
}
static uint16_t model_sample(const uint8_t *scratch, const uint32_t *d, int xq, int yq)
{
    int x = xq>>16;
    int y = yq>>16;
    unsigned fx = ((unsigned)xq>>8)&255;
    unsigned fy = ((unsigned)yq>>8)&255;
    unsigned weights[] = {(256-fx)*(256-fy),fx*(256-fy),(256-fx)*fy,fx*fy};
    unsigned sums[3] = {32768,32768,32768};
    unsigned width = d[2]&4095, height = (d[2]>>16)&4095;
    for (unsigned i = 0; i < 4; ++i) {
        int sx = x+(int)(i&1), sy = y+(int)(i>>1);
        uint16_t pixel = (uint16_t)d[7];
        if (sx >= 0 && sy >= 0 && sx < (int)width && sy < (int)height) {
            const uint16_t *row = (const uint16_t *)(scratch+
                (d[0]&0xfffff000u)-SHOWCASE_TOWER_GEO_BASE+(unsigned)sy*(d[1]&0xffe0));
            pixel = row[sx];
        }
        for (unsigned c = 0; c < 3; ++c) sums[c] += expand(pixel,c)*weights[i];
    }
    return (uint16_t)(((sums[0]>>19)<<11)|((sums[1]>>18)<<5)|(sums[2]>>19));
}
static void geo_model_execute(uint8_t *scratch, unsigned count)
{
    const struct geo_descriptor *descriptors = (const void *)scratch;
    for (unsigned i = 0; i < count; ++i) {
        const uint32_t *d = descriptors[i].word;
        unsigned width = d[6]&4094, height = (d[6]>>16)&4095;
        assert((d[0]&4095) == 0 && (d[3]&4095) == 0);
        assert((d[1]&31) == 0 && (d[4]&31) == 0);
        for (unsigned v = 0; v < height; ++v) {
            uint16_t *row = (uint16_t *)(scratch+(d[3]&0xfffff000u)-
                SHOWCASE_TOWER_GEO_BASE+((d[5]>>16)+v)*(d[4]&0xffe0));
            for (unsigned u = 0; u < width; ++u) {
                int x = (int)((int64_t)(int32_t)d[8]*u+(int64_t)(int32_t)d[9]*v+
                              (int32_t)d[10]);
                int y = (int)((int64_t)(int32_t)d[11]*u+(int64_t)(int32_t)d[12]*v+
                              (int32_t)d[13]);
                row[(d[5]&4080)+u] = model_sample(scratch,d,x,y);
            }
        }
    }
}
#endif
