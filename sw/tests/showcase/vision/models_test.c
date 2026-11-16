/* models_test.c — T-DEMO-PAGES; board C post/decode against models_eval INT8.
 * Host CPU, one real evaluation image per model; three-frame gesture state.
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
    if (fread(data, size, 1, file) != 1) { perror("model fixture read"); exit(1); }
}
static void debounce(void)
{
    ui_hand_state_t s = {.cls = -1, .candidate = -1};
    assert(!ui_gesture_debounce(&s, 5) && s.cls == -1);
    assert(!ui_gesture_debounce(&s, 5) && s.cls == -1);
    assert(ui_gesture_debounce(&s, 5) && s.cls == 5);
    assert(!ui_gesture_debounce(&s, 2));
    assert(!ui_gesture_debounce(&s, 1));
    assert(!ui_gesture_debounce(&s, 2));
    assert(!ui_gesture_debounce(&s, 2) && s.cls == 5);
    assert(ui_gesture_debounce(&s, 2) && s.cls == 2);
    assert(!ui_gesture_debounce(&s, -1));
    assert(!ui_gesture_debounce(&s, 1));
    assert(!ui_gesture_debounce(&s, 1));
    assert(ui_gesture_debounce(&s, 1));
}
int main(int argc, char **argv)
{
    assert(argc == 4);
    debounce();
    struct model { const char *name; const yolo_head *heads;
        const struct pose_head *points; unsigned nc, nk, bytes; };
    static const struct model models[] = {
        {"gesture",showcase_gesture_heads,showcase_gesture_keypoints,14,21,1048320},
        {"face",showcase_face_heads,showcase_face_keypoints,1,5,806400},
        {"doodle",showcase_doodle_heads,NULL,20,0,725760},
        {"helmet",showcase_helmet_heads,NULL,2,0,725760}
    };
    const struct model *m = NULL;
    for (unsigned i = 0; i < 4; ++i) if (!strcmp(argv[1], models[i].name)) m = &models[i];
    assert(m);
    FILE *file = fopen(argv[2], "rb");
    if (!file) { perror(argv[2]); return 1; }
    read_exact(output, m->bytes, file); fclose(file);
    struct vision_post post;
    vision_post_begin(&post, output, workspace, detections);
    post.heads = m->heads; post.classes = m->nc;
    while (!vision_post_step(&post)) {}
    file = fopen(argv[3], "rb");
    if (!file) { perror(argv[3]); return 1; }
    unsigned count;
    read_exact(&count, sizeof count, file);
    assert(count > 0 && count == post.kept);
    float maximum = 0;
    for (unsigned i = 0; i < count; ++i) {
        uint16_t anchor;
        yolo_detection expected;
        float mapped[4], points[21][3];
        read_exact(&anchor, sizeof anchor, file);
        read_exact(&expected, sizeof expected, file);
        read_exact(mapped, sizeof mapped, file);
        if (m->nk) read_exact(points, m->nk * 3 * sizeof(float), file);
        const yolo_detection *actual = &detections[i];
        assert(anchor == post.anchors[i] && !memcmp(&expected, actual, sizeof expected));
        const int16_t coords[] = {actual->x0,actual->y0,actual->x1,actual->y1};
        for (unsigned k = 0; k < 4; ++k) {
            float error = fabsf(coords[k] - mapped[k]);
            maximum = fmaxf(maximum, error); assert(error <= .5f);
        }
        if (!m->nk) continue;
        pose_point decoded[21];
        vision_keypoints_decode(output, post.anchors[i], m->heads, m->points, m->nk, decoded);
        for (unsigned k = 0; k < m->nk; ++k) {
            float error = fmaxf(fabsf(decoded[k].x-points[k][0]),
                               fabsf(decoded[k].y-points[k][1]));
            maximum = fmaxf(maximum, error);
            assert(error <= .5f && fabsf(decoded[k].visibility-points[k][2]) < 1e-6f);
        }
    }
    fclose(file);
    printf("PASS %s: %u detections, maximum coordinate error %.6f px; debounce 3 frames\n",
           m->name, count, (double)maximum);
    return 0;
}
