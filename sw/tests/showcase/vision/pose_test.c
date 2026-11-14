/* pose_test.c — T-POSE-BOARD; npu_ref OUTPUT through board post and keypoints.
 * Checks anchor order, mapped boxes, confidence and all 17 points; host CPU.
 */
#include "post.h"
#include "pose.h"
#include "memory.h"
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
int main(int argc, char **argv)
{
    if (argc != 3) { fprintf(stderr, "usage: pose_test OUTPUT expected\n"); return 1; }
    FILE *file = fopen(argv[1], "rb");
    if (!file) { perror(argv[1]); return 1; }
    read_exact(output, sizeof output, file);
    fclose(file);
    struct vision_post post;
    vision_post_begin(&post, output, workspace, detections);
    post.heads = showcase_pose_heads;
    while (!vision_post_step(&post)) {}
    file = fopen(argv[2], "rb");
    if (!file) { perror(argv[2]); return 1; }
    unsigned count;
    read_exact(&count, sizeof count, file);
    if (count != post.kept) {
        fprintf(stderr, "persons expected %u actual %u\n", count, post.kept); return 1;
    }
    float maximum = 0;
    for (unsigned i = 0; i < count; ++i) {
        uint16_t anchor;
        yolo_detection expected;
        float points[17][3];
        read_exact(&anchor, sizeof anchor, file);
        read_exact(&expected, sizeof expected, file);
        read_exact(points, sizeof points, file);
        const yolo_detection *actual = &detections[i];
        if (anchor != post.anchors[i] || expected.class_id != actual->class_id ||
            expected.score != actual->score || expected.x0 != actual->x0 ||
            expected.y0 != actual->y0 || expected.x1 != actual->x1 || expected.y1 != actual->y1) {
            fprintf(stderr, "person %u box/score/anchor differs (anchor %u vs %u)\n",
                    i, anchor, post.anchors[i]); return 1;
        }
        pose_point decoded[17];
        vision_pose_decode(output, post.anchors[i], decoded);
        for (unsigned k = 0; k < 17; ++k) {
            float error = fmaxf(fabsf(decoded[k].x - points[k][0]),
                                fabsf(decoded[k].y - points[k][1]));
            maximum = fmaxf(maximum, error);
            if (error > .5f || fabsf(decoded[k].visibility - points[k][2]) > 1e-6f) {
                fprintf(stderr, "person %u point %u error %f px\n", i, k, (double)error);
                return 1;
            }
        }
    }
    fclose(file);
    printf("PASS %s: %u persons, maximum coordinate error %.6f px\n",
           argv[1], count, (double)maximum);
    return 0;
}
