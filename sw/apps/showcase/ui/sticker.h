/* sticker.h — T-FACE-STICKER-R2: integer face tracking and AR placement.
 * Q8 pixel/degree pose; called once per inference frame in the GUI domain.
 */
#ifndef SHOWCASE_STICKER_H
#define SHOWCASE_STICKER_H
#include <stdint.h>
#include <stdbool.h>
enum { STICKER_FACES = 3, STICKER_SETS = 6, STICKER_Q = 256 };
typedef struct { int x, y; } sticker_point_t;
typedef struct { sticker_point_t points[5]; } sticker_detection_t;
typedef struct { int raw, value, derivative; } sticker_filter_t;
typedef struct {
    sticker_filter_t filter[4];
    int raw_x, raw_y, velocity_x, velocity_y;
    unsigned seen, lost, angle;
    bool active;
} sticker_track_t;
typedef struct { sticker_track_t tracks[STICKER_FACES]; } sticker_state_t;
typedef struct { const char *name; int offset_x, offset_y, width; } sticker_style_t;
typedef struct { int x, y, width, anchor_x, anchor_y; } sticker_placement_t;
extern const sticker_style_t sticker_styles[STICKER_SETS];
extern unsigned sticker_revision;
void sticker_step(sticker_state_t *s, const sticker_detection_t *d, unsigned count,
                  unsigned milliseconds);
unsigned sticker_opacity(const sticker_track_t *t);
unsigned sticker_angle(unsigned current, int degrees_q8);
void sticker_place(const sticker_track_t *t, unsigned style, sticker_placement_t *p);
int sticker_distance(int x, int y);
int sticker_tilt(int x, int y);
#endif
