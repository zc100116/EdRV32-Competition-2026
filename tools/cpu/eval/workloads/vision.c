/* vision.c — cpu-spec 4.1–4.4 evaluation; showcase postprocessing.
 * Fixed sparse INT8 tensor, using the repository post_test.c fixture recipe.
 * CPU/Spike domain; initialization is outside the measured window.
 */
#include "post.h"
#include <string.h>

extern void start_time(void);
extern void stop_time(void);
static int8_t output[YOLO_OUTPUT_BYTES];
static yolo_candidate workspace[YOLO_ANCHORS];
static yolo_detection detections[YOLO_MAX_DETECTIONS];
static struct vision_post post;
volatile unsigned result;

int main(void)
{
    memset(output, 0x80, sizeof output);
    for (unsigned head = 0; head < 3; ++head) {
        const yolo_head *h = &yolo_default_heads[head];
        for (unsigned cell = 0; cell < (unsigned)h->width * h->height; ++cell) {
            for (unsigned side = 0; side < 4; ++side) {
                for (unsigned bin = 0; bin < 16; ++bin) {
                    output[h->box_offset + side * h->plane_stride + cell * 16 + bin] =
                        (int8_t)(bin == 3 ? 32 : -32);
                }
            }
        }
        for (unsigned n = 0; n < 75; ++n) {
            unsigned cell = (n * 37) % (h->width * h->height);
            unsigned category = n % 5;
            output[h->class_offset + (category / 16) * h->plane_stride +
                   cell * 16 + category % 16] = (int8_t)(h->class_threshold + n % 16);
        }
    }
    start_time();
    vision_post_begin(&post, output, workspace, detections);
    while (!vision_post_step(&post)) { }
    result = post.kept;
    stop_time();
    return 0;
}
