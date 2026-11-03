/* post_test.c — showcase 4.5.2; sliced/reference equivalence including operation counts.
 * Fixed-seed NPU OUTPUT, dense and empty frames; host CPU domain.
 */
#include "post.h"
#include "wire.h"
#include "memory.h"
#include "ch2.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static int8_t output[YOLO_OUTPUT_BYTES];
static yolo_candidate reference_workspace[YOLO_ANCHORS];
static yolo_candidate sliced_workspace[YOLO_ANCHORS];
static yolo_detection expected[YOLO_MAX_DETECTIONS];
static yolo_detection actual[YOLO_MAX_DETECTIONS];
static uint32_t random_state = 0x20261103;
static uint32_t random32(void)
{
    random_state ^= random_state << 13;
    random_state ^= random_state >> 17;
    random_state ^= random_state << 5;
    return random_state;
}
static void compare(const char *name)
{
    yolo_post_stats stats;
    uint32_t count = yolo_post_process(output, yolo_default_heads, reference_workspace,
                                     expected, &stats);
    struct vision_post post;
    vision_post_begin(&post, output, sliced_workspace, actual);
    unsigned slices = 1;
    while (!vision_post_step(&post)) ++slices;
    assert(post.kept == count);
    assert(memcmp(expected, actual, count * sizeof(*actual)) == 0);
    assert(memcmp(&stats, &post.stats, sizeof stats) == 0);
    assert(memcmp(reference_workspace, sliced_workspace,
                  stats.decoded_anchors * sizeof(*sliced_workspace)) == 0);
    printf("PASS %s: %u detections, %u slices, identical results/workspace/stats\n",
           name, count, slices);
}
static void put32(uint8_t *out, uint32_t value)
{
    for (unsigned i = 0; i < 4; ++i) out[i] = (uint8_t)(value >> (8*i));
}
static void wire_test(void)
{
    uint8_t header[32] = {'E','D','N','M'};
    put32(header+4, 1);
    put32(header+8, 68);
    put32(header+12, 68*64);
    put32(header+16, 32);
    put32(header+20, VISION_WORK_BASE);
    put32(header+24, VISION_INPUT_BASE);
    put32(header+28, VISION_OUTPUT_BASE);
    assert(vision_model_header(header, 0x100020) == NULL);
    assert(strcmp(vision_model_header(header, 32+68*64+32), "Model bytes") == 0);
    header[0] = 0;
    assert(strcmp(vision_model_header(header, 0x100020), "EDNM magic/version") == 0);
    const yolo_detection d = {1, 2, 1279, 719, 79, 875};
    uint8_t bytes[28];
    assert(vision_detection_pack(bytes, &d, 1, 123) == 28);
    const uint8_t exact[] = {'E','D','D','T',1,0,1,0,123,0,0,0,0,0,0,0,
                            1,0,2,0,255,4,207,2,79,0,107,3};
    assert(memcmp(bytes, exact, sizeof exact) == 0);
    puts("PASS sparse EDNM boundary and exact yolo.py EDDT encoding");
}
static void ch2_test(void)
{
    static uint8_t rgb[VISION_IMAGE_BYTES];
    static uint8_t tensor[VISION_INPUT_BYTES];
    memset(rgb, 0xff, sizeof rgb);
    memset(tensor, 0xaa, sizeof tensor);
    for (unsigned y = 0; y < 384; ++y) {
        vision_ch2_row(rgb, tensor, y);
        for (unsigned x = 0; x < 640; ++x) {
            const uint8_t *pixel = tensor + y*2560 + x*4;
            unsigned value = y < 12 || y >= 372 ? 57 : 127;
            assert(pixel[0] == value && pixel[1] == value && pixel[2] == value);
            assert(pixel[3] == 0);
        }
    }
    puts("PASS sliced CPU CH2: 384 rows, letterbox and C4 padding");
}
int main(void)
{
    memset(output, 0x80, sizeof output);
    compare("empty");
    memset(output, 0x7f, sizeof output);
    compare("dense ties / maximum cap");
    for (unsigned frame = 0; frame < 5; ++frame) {
        for (unsigned i = 0; i < sizeof output; ++i) output[i] = (int8_t)random32();
        compare("seeded OUTPUT");
        /* Sparse classes exercise all heads, threshold ties and head boundaries. */
        for (unsigned head = 0; head < 3; ++head) {
            const yolo_head *h = &yolo_default_heads[head];
            memset(output + h->class_offset, 0x80, 5*h->plane_stride);
            for (unsigned n = 0; n < 75; ++n) {
                unsigned cell = random32() % (h->width*h->height);
                unsigned category = random32() % 80;
                output[h->class_offset + (category/16)*h->plane_stride +
                       cell*16 + category%16] = (int8_t)(h->class_threshold +
                                      random32() % (128-h->class_threshold));
            }
        }
        compare("sparse OUTPUT");
    }
    wire_test();
    ch2_test();
    return 0;
}
