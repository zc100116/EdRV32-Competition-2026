/* File: logic.c
 * Spec: design 2026-10-29-b2-software 3.3–3.5a.
 * Description: Explicit little-endian wire formats and exact UART menu parser.
 * Clock domain: none (pure software).
 */
#include "demo.h"

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

static void put64(uint8_t *out, uint64_t value)
{
    put32(out, (uint32_t)value);
    put32(out + 4, (uint32_t)(value >> 32));
}

uint32_t demo_read32(const uint8_t *bytes)
{
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static int equal(const char *a, const char *b)
{
    while (*a && *a == *b) {
        ++a;
        ++b;
    }
    return *a == *b;
}

static int prefix(const char *line, const char *key)
{
    while (*key) {
        if (*line++ != *key++) {
            return 0;
        }
    }
    return 1;
}

int demo_parse(const char *line, struct demo_command *command)
{
    static const struct {
        const char *text;
        enum demo_command_kind kind;
        unsigned int value;
    } choices[] = {
        {"help", DEMO_HELP, 0}, {"status", DEMO_STATUS, 0},
        {"s1", DEMO_SCENE, 1}, {"s2", DEMO_SCENE, 2},
        {"pix bypass", DEMO_PIX, 0}, {"pix brightness", DEMO_PIX, 1},
        {"pix gamma", DEMO_PIX, 2}, {"pix gaussian", DEMO_PIX, 3},
        {"pix sobel", DEMO_PIX, 4}, {"geo off", DEMO_GEO, 0},
        {"geo rotate", DEMO_GEO, 1}, {"geo scale", DEMO_GEO, 2},
        {"output hdmi", DEMO_OUTPUT, DEMO_HDMI},
        {"output eth", DEMO_OUTPUT, DEMO_ETHERNET},
        {"output both", DEMO_OUTPUT, DEMO_BOTH}
    };
    for (unsigned int i = 0; i < sizeof choices / sizeof choices[0]; ++i) {
        if (equal(line, choices[i].text)) {
            *command = (struct demo_command){choices[i].kind, choices[i].value};
            return 0;
        }
    }
    unsigned int minimum;
    unsigned int maximum;
    const char *digits;
    if (prefix(line, "fps ")) {
        command->kind = DEMO_FPS;
        minimum = 1;
        maximum = 60;
        digits = line + 4;
    } else if (prefix(line, "sample ")) {
        command->kind = DEMO_SAMPLE;
        minimum = 10;
        maximum = 1000;
        digits = line + 7;
    } else {
        return -1;
    }
    unsigned int value = 0;
    if (*digits == 0) {
        return -1;
    }
    while (*digits) {
        if (*digits < '0' || *digits > '9') {
            return -1;
        }
        value = value * 10u + (unsigned int)(*digits++ - '0');
        if (value > maximum) {
            return -1;
        }
    }
    command->value = value;
    return value >= minimum ? 0 : -1;
}

unsigned int demo_frame_divisor(unsigned int source_fps, unsigned int requested_fps)
{
    return requested_fps >= source_fps ? 1u :
           (source_fps + requested_fps - 1u) / requested_fps;
}

int demo_frame_due(uint32_t frame_id, unsigned int divisor)
{
    return frame_id % divisor == 0u;
}

void demo_video_pack(uint8_t out[DEMO_VIDEO_BYTES], uint32_t frame_id,
                     uint64_t time, uint32_t scene)
{
    out[0] = 'E'; out[1] = 'D'; out[2] = 'V'; out[3] = 'F';
    put16(out + 4, 1);
    put16(out + 6, 1);
    put16(out + 8, DEMO_WIDTH);
    put16(out + 10, DEMO_HEIGHT);
    put32(out + 12, DEMO_STRIDE);
    put32(out + 16, frame_id);
    put64(out + 20, time);
    put32(out + 28, scene);
}

size_t demo_detection_pack(uint8_t *out, const yolo_detection *boxes,
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

const char *demo_model_header(const uint8_t *h, uint32_t received_bytes)
{
    if (h[0] != 'E' || h[1] != 'D' || h[2] != 'N' || h[3] != 'M' ||
        demo_read32(h + 4) != 1u) {
        return "EDNM magic/version";
    }
    uint32_t descriptors = demo_read32(h + 8);
    uint32_t descriptor_bytes = demo_read32(h + 12);
    uint32_t model_bytes = demo_read32(h + 16);
    if (descriptors == 0u || descriptors > DEMO_DESC_SIZE / 64u ||
        descriptor_bytes != descriptors * 64u || model_bytes > DEMO_MODEL_SIZE) {
        return "EDNM descriptor/model length";
    }
    if (demo_read32(h + 20) != DEMO_WORK_BASE ||
        demo_read32(h + 24) != DEMO_INPUT_BASE ||
        demo_read32(h + 28) != DEMO_OUTPUT_BASE) {
        return "EDNM base layout";
    }
    if (received_bytes != 32u + descriptor_bytes + model_bytes) {
        return "WIN2_BYTES";
    }
    return NULL;
}
