/* File: png.c
 * Spec: S-0b headless frontend; PNG format with uncompressed DEFLATE blocks.
 * Description: Encode 1280x720 RGB pixels without third-party libraries.
 * Clock domain: host.
 */
#include "png.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void be32(uint8_t out[4], uint32_t value)
{
    out[0] = (uint8_t)(value >> 24); out[1] = (uint8_t)(value >> 16);
    out[2] = (uint8_t)(value >> 8); out[3] = (uint8_t)value;
}
static void chunk(FILE *file, const char *type, const uint8_t *bytes, uint32_t count)
{
    uint8_t word[4];
    be32(word, count);
    if (fwrite(word, 1, 4, file) != 4 || fwrite(type, 1, 4, file) != 4 ||
        fwrite(bytes, 1, count, file) != count) { perror("PNG chunk write"); exit(1); }
    uint32_t crc = UINT32_MAX;
    for (uint32_t i = 0; i < count + 4; ++i) {
        crc ^= i < 4 ? (uint8_t)type[i] : bytes[i - 4];
        for (unsigned b = 0; b < 8; ++b) crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1)));
    }
    be32(word, ~crc);
    if (fwrite(word, 1, 4, file) != 4) { perror("PNG CRC write"); exit(1); }
}
void pc_png_write(const char *path, const uint32_t *pixels)
{
    enum { ROW = 1280 * 3 + 1, SIZE = ROW * 720 };
    uint8_t *raw = malloc(SIZE);
    uint8_t *zlib = malloc(SIZE + SIZE / 65535 * 5 + 16);
    if (!raw || !zlib) { perror("PNG allocation"); exit(1); }
    for (unsigned y = 0; y < 720; ++y) {
        raw[y * ROW] = 0;
        for (unsigned x = 0; x < 1280; ++x) {
            uint32_t p = pixels[y * 1280 + x];
            for (unsigned c = 0; c < 3; ++c)
                raw[y * ROW + 1 + x * 3 + c] = (uint8_t)(p >> (16 - 8 * c));
        }
    }
    uint32_t a = 1, b = 0;
    for (unsigned i = 0; i < SIZE; ++i) { a = (a + raw[i]) % 65521; b = (b + a) % 65521; }
    size_t output = 2;
    zlib[0] = 0x78; zlib[1] = 0x01;
    for (unsigned start = 0; start < SIZE;) {
        unsigned count = SIZE - start;
        if (count > 65535) count = 65535;
        zlib[output++] = start + count == SIZE;
        zlib[output++] = (uint8_t)count; zlib[output++] = (uint8_t)(count >> 8);
        zlib[output++] = (uint8_t)~count; zlib[output++] = (uint8_t)(~count >> 8);
        memcpy(zlib + output, raw + start, count);
        output += count; start += count;
    }
    be32(zlib + output, b << 16 | a); output += 4;
    FILE *file = fopen(path, "wb");
    if (!file) { perror(path); exit(1); }
    const uint8_t signature[] = {137, 80, 78, 71, 13, 10, 26, 10};
    if (fwrite(signature, 1, 8, file) != 8) { perror(path); exit(1); }
    uint8_t header[13] = {0};
    be32(header, 1280); be32(header + 4, 720); header[8] = 8; header[9] = 2;
    chunk(file, "IHDR", header, 13);
    chunk(file, "IDAT", zlib, (uint32_t)output);
    chunk(file, "IEND", NULL, 0);
    if (fclose(file)) { perror(path); exit(1); }
    free(raw); free(zlib);
}
