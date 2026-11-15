/* hand_test.c — T-HAND-BOARD; npu_ref OUTPUT through board post and keypoints.
 * Checks anchor order, mapped boxes, confidence and all 21 points; host CPU.
 */
#include "post.h"
#include "pose.h"
#include "memory.h"
#include "ui/ui_data.h"
#include <assert.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static int8_t output[VISION_POSE_OUTPUT_BYTES];
static yolo_candidate workspace[YOLO_ANCHORS];
static yolo_detection detections[YOLO_MAX_DETECTIONS];
static void read_exact(void *data, size_t size, FILE *file)
{
    if (fread(data, size, 1, file) != 1) { perror("pose fixture read"); exit(1); }
}
static void rules(void)
{
    const unsigned masks[] = {0, 6, 31, 1};
    const unsigned expected[] = {1, 2, 3, 0};
    for (unsigned n = 0; n < 4; ++n) {
        ui_pose_point_t p[21] = {0};
        p[9].y = 100;
        p[17].x = 100;
        p[3].x = 110;
        p[4].x = masks[n] & 1 ? 120 : 105;
        for (unsigned f = 1; f < 5; ++f) {
            unsigned tip = 4 + f * 4;
            p[tip - 2] = (ui_pose_point_t){f * 10, 40, 0};
            p[tip] = (ui_pose_point_t){f * 10, masks[n] & (1u << f) ? 80 : 20, 0};
        }
        ui_hand_state_t state = {0};
        ui_hand_classify(p, &state);
        assert(state.fingers == masks[n] && state.rps == expected[n]);
    }
    ui_pose_point_t p[21] = {0};
    p[9].y = 100;
    ui_hand_state_t state = {0};
    const float separation[] = {20, 30, 40, 41, 30, 25, 24};
    const bool pinched[] = {true, true, true, false, false, false, true};
    for (unsigned i = 0; i < 7; ++i) {
        p[4].x = separation[i];
        ui_hand_classify(p, &state);
        assert(fabsf(state.d - separation[i] / 100) < 1e-6f);
        assert(state.pinch == pinched[i]);
    }
    char bits[6];
    ui_hand_bits(6, bits);
    assert(!strcmp(bits, "01100"));
    assert(!strcmp(ui_hand_rps(2), "scissors"));
    puts("PASS hand rules: rock/scissors/paper/none, five fingers, pinch hysteresis");
}
int main(int argc, char **argv)
{
    rules();
    if (argc != 3) { fprintf(stderr, "usage: hand_test OUTPUT expected\n"); return 1; }
    FILE *file = fopen(argv[1], "rb");
    if (!file) { perror(argv[1]); return 1; }
    read_exact(output, sizeof output, file);
    fclose(file);
    struct vision_post post;
    vision_post_begin(&post, output, workspace, detections);
    post.heads = showcase_hand_heads;
    while (!vision_post_step(&post)) {}
    file = fopen(argv[2], "rb");
    if (!file) { perror(argv[2]); return 1; }
    unsigned count;
    read_exact(&count, sizeof count, file);
    if (count != post.kept) {
        fprintf(stderr, "hands expected %u actual %u\n", count, post.kept); return 1;
    }
    float maximum = 0;
    for (unsigned i = 0; i < count; ++i) {
        uint16_t anchor;
        yolo_detection expected;
        float points[21][3];
        read_exact(&anchor, sizeof anchor, file);
        read_exact(&expected, sizeof expected, file);
        read_exact(points, sizeof points, file);
        const yolo_detection *actual = &detections[i];
        if (anchor != post.anchors[i] || expected.class_id != actual->class_id ||
            expected.score != actual->score || expected.x0 != actual->x0 ||
            expected.y0 != actual->y0 || expected.x1 != actual->x1 || expected.y1 != actual->y1) {
            fprintf(stderr, "hand %u box/score/anchor differs (anchor %u vs %u)\n",
                    i, anchor, post.anchors[i]); return 1;
        }
        pose_point decoded[21];
        vision_keypoints_decode(output, post.anchors[i], showcase_hand_heads,
                                showcase_hand_keypoints, 21, decoded);
        for (unsigned k = 0; k < 21; ++k) {
            float error = fmaxf(fabsf(decoded[k].x - points[k][0]),
                                fabsf(decoded[k].y - points[k][1]));
            maximum = fmaxf(maximum, error);
            if (error > .5f || fabsf(decoded[k].visibility - points[k][2]) > 1e-6f) {
                fprintf(stderr, "hand %u point %u error %f px\n", i, k, (double)error);
                return 1;
            }
        }
    }
    fclose(file);
    printf("PASS %s: %u hands, maximum coordinate error %.6f px\n",
           argv[1], count, (double)maximum);
    return 0;
}
