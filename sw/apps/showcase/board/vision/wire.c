/* wire.c — showcase design 4.5.4; EDNM validation and EDDT wire encoding.
 * Little endian wire boundary, compatible with debug_tool/core/yolo.py; CPU domain.
 */
#include "wire.h"
#include "memory.h"
#include <stddef.h>
static void put16(uint8_t *out, uint16_t value)
{
    out[0] = (uint8_t)value;
    out[1] = (uint8_t)(value >> 8);
}

static void put32(uint8_t *out, uint32_t value)
{
    put16(out, (uint16_t)value);
    put16(out + 2, (uint16_t)(value >> 16));
}

uint32_t vision_read32(const uint8_t *bytes)
{
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

size_t vision_detection_pack(uint8_t *out, const yolo_detection *boxes,
                           unsigned int count, uint32_t frame_id)
{
    out[0] = 'E'; out[1] = 'D'; out[2] = 'D'; out[3] = 'T';
    put16(out + 4, 1);
    put16(out + 6, (uint16_t)count);
    put32(out + 8, frame_id);
    put32(out + 12, 0);
    for (unsigned int i = 0; i < count; ++i) {
        uint8_t *b = out + 16 + i * 12;
        put16(b, (uint16_t)boxes[i].x0);
        put16(b + 2, (uint16_t)boxes[i].y0);
        put16(b + 4, (uint16_t)boxes[i].x1);
        put16(b + 6, (uint16_t)boxes[i].y1);
        put16(b + 8, boxes[i].class_id);
        put16(b + 10, boxes[i].score);
    }
    return 16u + count * 12u;
}

const char *vision_model_header(const uint8_t *h, uint32_t received_bytes)
{
    if (h[0] != 'E' || h[1] != 'D' || h[2] != 'N' || h[3] != 'M' ||
        vision_read32(h + 4) != 1u) {
        return "EDNM magic/version";
    }
    uint32_t descriptors = vision_read32(h + 8);
    uint32_t descriptor_bytes = vision_read32(h + 12);
    uint32_t model_bytes = vision_read32(h + 16);
    if (descriptors == 0u || descriptors > VISION_DESC_SIZE / 64u ||
        descriptor_bytes != descriptors * 64u || model_bytes > VISION_MODEL_SIZE) {
        return "EDNM descriptor/model length";
    }
    if (vision_read32(h + 20) != VISION_WORK_BASE ||
        vision_read32(h + 24) != VISION_INPUT_BASE ||
        vision_read32(h + 28) != VISION_OUTPUT_BASE) {
        return "EDNM base layout";
    }
    if (received_bytes != 0x100000u + model_bytes) {
        return "Model bytes";
    }
    return NULL;
}
