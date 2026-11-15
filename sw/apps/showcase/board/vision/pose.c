/* pose.c — T-POSE-BOARD; matches pose_eval.int8/kpts_decode after NMS.
 * C16 planes, linear quantization, 640x384 letterbox to 1280x720; CPU domain.
 */
#include "pose.h"
#include <math.h>
static float display(float value, float padding, float limit)
{
    return fminf(limit, fmaxf(0, (value - padding) * 2));
}
void vision_keypoints_decode(const int8_t *output, uint16_t anchor,
    const yolo_head heads[3], const struct pose_head quantization[3],
    unsigned count, pose_point *points)
{
    unsigned h = 0;
    unsigned cell = anchor;
    while (cell >= (unsigned)heads[h].width * heads[h].height) {
        cell -= (unsigned)heads[h].width * heads[h].height;
        ++h;
    }
    const yolo_head *head = &heads[h];
    const struct pose_head *quant = &quantization[h];
    for (unsigned k = 0; k < count; ++k) {
        float values[3];
        for (unsigned axis = 0; axis < 3; ++axis) {
            unsigned channel = k * 3 + axis;
            int raw = output[quant->offset + channel / 16 * head->plane_stride +
                             cell * 16 + channel % 16];
            values[axis] = (raw - quant->zero_point) * quant->scale;
        }
        points[k].x = display((values[0] * 2 + cell % head->width) * head->stride, 0, 1280);
        points[k].y = display((values[1] * 2 + cell / head->width) * head->stride, 12, 720);
        points[k].visibility = 1 / (1 + expf(-values[2]));
    }
}

void vision_pose_decode(const int8_t *output, uint16_t anchor, pose_point points[17])
{
    vision_keypoints_decode(output, anchor, showcase_pose_heads, showcase_pose_keypoints,
                            17, points);
}
