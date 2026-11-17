/* grab.h — T-GRAB-TEST; geometry, hysteresis and falling objects.
 * Shared CPU/GUI state; coordinates are sensor-mirrored 1280x720 pixels.
 */
#ifndef SHOWCASE_GRAB_H
#define SHOWCASE_GRAB_H
#include "ui_data.h"
enum { GRAB_OBJECTS = 6, GRAB_RADIUS = 50, GRAB_GROUND = 520, GRAB_LOST_MS = 200 };
typedef struct { float x, y, velocity; bool falling; } grab_object_t;
typedef struct {
    grab_object_t objects[GRAB_OBJECTS];
    unsigned mode, pending_frames, lost, picks, drops;
    int held, event_object, cls, candidate_object;
    bool closed, smooth, mirror, keypoints;
    float x, y, offset_x, offset_y, d;
    float velocity_x, velocity_y, seen_x, seen_y;
    uint32_t seen_at;
    int thresholds[4]; /* hundredths for A/B, unused C, pixels for D */
} grab_state_t;
extern grab_state_t ui_grab;
void grab_init(grab_state_t *s);
void grab_reset_objects(grab_state_t *s);
/* cls is already debounced by the gesture page's three-frame filter. */
bool grab_frame(grab_state_t *s, const ui_pose_point_t *points, int cls, uint32_t stamp);
/* Raw rule result: caller owns transition timing and supplies D's current targets. */
int grab_rule(grab_state_t *s, const ui_pose_point_t *points, int cls,
              const grab_object_t *objects, unsigned count, float radius,
              bool smooth, bool *close, bool *release);
void grab_animate(grab_state_t *s, float seconds);
void grab_value(const grab_state_t *s, char *text, unsigned size);
void ui_data_grab_mirror(bool enabled);
void ui_data_grab_output(const char *text);
#endif
