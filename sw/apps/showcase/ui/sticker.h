/* sticker.h — T-SYNC-STICKER-R3: integer face tracking and AR placement.
 * Q8 pixel/degree pose; called once per inference frame in the GUI domain.
 */
#ifndef SHOWCASE_STICKER_H
#define SHOWCASE_STICKER_H
#include <stdint.h>
#include <stdbool.h>
enum { STICKER_FACES = 3, STICKER_SETS = 17, STICKER_Q = 256 };
enum { STICKER_HEAD, STICKER_EYES, STICKER_NOSE, STICKER_MOUTH, STICKER_CHEEKS,
       STICKER_PARTS };
typedef struct { int x, y; } sticker_point_t;
typedef struct { sticker_point_t points[5]; } sticker_detection_t;
typedef struct { int raw, value, derivative; } sticker_filter_t;
typedef struct {
    sticker_filter_t filter[14];
    int raw_x, raw_y, velocity_x, velocity_y;
    unsigned seen, lost, angle;
    bool active;
} sticker_track_t;
typedef struct { sticker_track_t tracks[STICKER_FACES]; } sticker_state_t;
typedef struct {
    const char *name;
    int offset_x, offset_y, width;
    unsigned part, pixels;
} sticker_style_t;
typedef struct { int x, y, width, anchor_x, anchor_y; } sticker_placement_t;
extern const sticker_style_t sticker_styles[STICKER_SETS];
extern unsigned sticker_revision;
void sticker_step(sticker_state_t *s, const sticker_detection_t *d, unsigned count,
                  unsigned milliseconds);
unsigned sticker_opacity(const sticker_track_t *t);
unsigned sticker_angle(unsigned current, int degrees_q8);
void sticker_place(const sticker_track_t *t, unsigned style, sticker_placement_t *p);
void sticker_place_part(const sticker_track_t *t, unsigned style, unsigned side,
                        sticker_placement_t *p);
int sticker_next(unsigned part, int current);
int sticker_distance(int x, int y);
int sticker_tilt(int x, int y);
#endif
