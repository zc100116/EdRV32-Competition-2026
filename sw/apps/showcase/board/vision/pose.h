/* pose.h — T-POSE-BOARD; retained-anchor keypoint decode, CPU domain. */
#ifndef SHOWCASE_POSE_H
#define SHOWCASE_POSE_H
#include "yolo_post.h"
struct pose_head { uint32_t offset; float scale; int zero_point; };
typedef struct { float x, y, visibility; } pose_point;
extern const yolo_head showcase_pose_heads[3];
extern const struct pose_head showcase_pose_keypoints[3];
void vision_pose_decode(const int8_t *output, uint16_t anchor, pose_point points[17]);
#endif
