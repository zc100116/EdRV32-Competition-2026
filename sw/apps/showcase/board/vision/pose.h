/* pose.h — T-POSE-BOARD; retained-anchor keypoint decode, CPU domain. */
#ifndef SHOWCASE_POSE_H
#define SHOWCASE_POSE_H
#include "yolo_post.h"
struct pose_head { uint32_t offset; float scale; int zero_point; };
typedef struct { float x, y, visibility; } pose_point;
extern const yolo_head showcase_pose_heads[3];
extern const struct pose_head showcase_pose_keypoints[3];
extern const yolo_head showcase_gesture_heads[3];
extern const struct pose_head showcase_gesture_keypoints[3];
extern const yolo_head showcase_face_heads[3];
extern const struct pose_head showcase_face_keypoints[3];
extern const yolo_head showcase_doodle_heads[3];
extern const yolo_head showcase_helmet_heads[3];
void vision_keypoints_decode(const int8_t *output, uint16_t anchor,
    const yolo_head heads[3], const struct pose_head quantization[3],
    unsigned count, pose_point *points);
void vision_pose_decode(const int8_t *output, uint16_t anchor, pose_point points[17]);
#endif
