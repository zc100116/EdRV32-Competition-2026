/* vision_profile.c — npu-spec 2.2; Spike RV32 instruction profiling, no MMIO.
 * Clock domain: Spike instruction counter; not an EdRV32 cycle simulation.
 */
#include <stdint.h>
#include "post.h"
volatile uint64_t tohost __attribute__((section(".tohost"), aligned(64)));
volatile uint64_t fromhost __attribute__((section(".tohost"), aligned(64)));
static uint32_t scans, dfl;
static inline uint32_t instructions(void)
{
    uint32_t value;
    __asm__ volatile ("csrr %0, minstret" : "=r"(value) :: "memory");
    return value;
}
static int scan(const int8_t *classes, const yolo_head *head, uint16_t *id)
{
    uint32_t start = instructions();
    int best = -129;
#ifdef PACKED_FILTER
    uint32_t hit = 0;
    uint32_t bias = (128u - (unsigned)head->class_threshold) * 0x01010101u;
    for (unsigned plane = 0; plane < 5; ++plane) {
        const uint32_t *words = (const uint32_t *)(classes + plane * head->plane_stride);
        for (unsigned word = 0; word < 4; ++word) {
            uint32_t x = words[word];
            hit |= ((x & 0x7f7f7f7fu) + bias) & ~x & 0x80808080u;
        }
    }
    if (!hit) {
        scans += instructions() - start;
        return best;
    }
#endif
    for (unsigned plane = 0; plane < 5; ++plane) {
        for (unsigned lane = 0; lane < 16; ++lane) {
            int value = classes[plane * head->plane_stride + lane];
            if (value > best) {
                best = value;
                *id = (uint16_t)(plane * 16 + lane);
            }
        }
    }
    scans += instructions() - start;
    return best;
}
#include "post_profile.inc"
extern const int8_t frame[];
static yolo_candidate workspace[YOLO_ANCHORS];
static yolo_detection detections[YOLO_MAX_DETECTIONS];
static struct vision_post post;
static void print_number(uint32_t value)
{
    char text[16];
    unsigned n = 0;
    do { text[n++] = (char)('0' + value % 10); value /= 10; } while (value);
    for (unsigned i = 0; i < n / 2; ++i) {
        char c = text[i]; text[i] = text[n - i - 1]; text[n - i - 1] = c;
    }
    text[n++] = '\n';
    volatile uint64_t args[8] __attribute__((aligned(64))) =
        {64, 1, (uintptr_t)text, n, 0, 0, 0, 0};
    __asm__ volatile ("fence rw, rw" ::: "memory");
    tohost = (uintptr_t)args;
    while (!fromhost) {}
    fromhost = 0;
}
void run(void)
{
    uint32_t phases[3] = {0};
    uint32_t calls[3] = {0};
    vision_post_begin(&post, frame, workspace, detections);
    int done = 0;
    while (!done) {
        unsigned phase = post.phase == 0 ? 0 : post.phase < 3 ? 1 : 2;
        uint32_t start = instructions();
        done = vision_post_step(&post);
        phases[phase] += instructions() - start;
        ++calls[phase];
    }
    for (unsigned i = 0; i < 3; ++i) { print_number(phases[i]); print_number(calls[i]); }
    print_number(scans); print_number(dfl); print_number(post.count); print_number(post.kept);
    print_number(post.stats.sort_comparisons); print_number(post.stats.iou_comparisons);
    for (unsigned i = 0; i < post.kept; ++i) {
        const uint16_t *row = (const uint16_t *)&detections[i];
        for (unsigned j = 0; j < 6; ++j) print_number(row[j]);
    }
    tohost = 1;
    for (;;) {}
}
