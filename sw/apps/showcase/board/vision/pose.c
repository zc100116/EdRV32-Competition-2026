/* pose.c — T-POSE-BOARD; matches pose_eval.int8/kpts_decode after NMS.
 * C16 planes, linear quantization, 640x384 letterbox to 1280x720; CPU domain.
 */
#include "pose.h"
#include <math.h>
static float display(float value, float padding, float limit)
{
    return fminf(limit, fmaxf(0, (value - padding) * 2));
}
void vision_pose_decode(const int8_t *output, uint16_t anchor, pose_point points[17])
{
    unsigned h = 0;
    unsigned cell = anchor;
    while (cell >= (unsigned)showcase_pose_heads[h].width * showcase_pose_heads[h].height) {
        cell -= (unsigned)showcase_pose_heads[h].width * showcase_pose_heads[h].height;
        ++h;
    }
    const yolo_head *head = &showcase_pose_heads[h];
    const struct pose_head *quant = &showcase_pose_keypoints[h];
    for (unsigned k = 0; k < 17; ++k) {
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
