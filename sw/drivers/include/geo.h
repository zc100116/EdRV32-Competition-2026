/* File: geo.h
 * Spec: geo-spec 2.1, 2.6, 4.1
 * Description: B2 media engine software interface.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_GEO_H
#define EDRV32_GEO_H
#include "engine.h"
struct geo_config {
    uint32_t src_base;
    uint32_t src_stride;
    unsigned int src_width;
    unsigned int src_height;
    uint32_t dst_base;
    uint32_t dst_stride;
    unsigned int rect_x;
    unsigned int rect_y;
    unsigned int rect_width;
    unsigned int rect_height;
    uint16_t background;
    int32_t matrix[6]; /* A, B, TX, C, D, TY: signed Q16.16. */
};
struct geo_descriptor { uint32_t word[16]; };
/* GEO 2.1: convert an exact rational to Q16.16, truncating toward zero. */
int32_t geo_q16(int32_t numerator, int32_t denominator);
/* GEO 2.6: pack one 64-byte little-endian descriptor, zeroing reserved words. */
void geo_descriptor_pack(struct geo_descriptor *descriptor, const struct geo_config *config);
/* GEO 4.1: submit an already coherent, 32-byte-aligned physical descriptor list. */
void geo_submit(uint32_t descriptors, uint32_t count);
#endif
