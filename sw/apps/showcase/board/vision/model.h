/* model.h — P5b 9.1; immutable compiler model embedded in the ELF; clk_sys. */
#ifndef SHOWCASE_MODEL_H
#define SHOWCASE_MODEL_H
#include <stdint.h>
extern const uint32_t showcase_model_count;
extern const uint32_t showcase_model_desc_bytes;
extern const uint32_t showcase_model_weights_bytes;
extern const uint8_t showcase_model_desc[];
extern const uint8_t showcase_model_weights[];
extern const uint32_t showcase_pose_count;
extern const uint32_t showcase_pose_desc_bytes;
extern const uint32_t showcase_pose_weights_bytes;
extern const uint8_t showcase_pose_desc[];
extern const uint8_t showcase_pose_weights[];
extern const uint32_t showcase_gesture_count;
extern const uint32_t showcase_gesture_desc_bytes;
extern const uint32_t showcase_gesture_weights_bytes;
extern const uint8_t showcase_gesture_desc[];
extern const uint8_t showcase_gesture_weights[];
extern const uint32_t showcase_face_count;
extern const uint32_t showcase_face_desc_bytes;
extern const uint32_t showcase_face_weights_bytes;
extern const uint8_t showcase_face_desc[];
extern const uint8_t showcase_face_weights[];
extern const uint32_t showcase_helmet_count;
extern const uint32_t showcase_helmet_desc_bytes;
extern const uint32_t showcase_helmet_weights_bytes;
extern const uint8_t showcase_helmet_desc[];
extern const uint8_t showcase_helmet_weights[];
#endif
