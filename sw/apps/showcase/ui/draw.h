/* draw.h — T-DRAW / R5-5; air drawing rules and incremental raster stamps.
 * No LVGL dependency; caller supplies millisecond time and the ARGB8888 layer.
 */
#ifndef SHOWCASE_DRAW_H
#define SHOWCASE_DRAW_H
#include <stdbool.h>
#include <stdint.h>
enum { DRAW_WIDTH = 1280, DRAW_HEIGHT = 720, DRAW_COLORS = 8, DRAW_ITEMS = 14,
       DRAW_PAGE = 20, DRAW_POINT = 3, DRAW_HOLD_MS = 600 };
typedef enum { DRAW_PEN, DRAW_ERASER } draw_tool_t;
typedef struct {
    float x;
    float y;
} draw_point_t;
typedef struct {
    draw_tool_t tool;
    unsigned color;
    unsigned size;
    bool down;
    bool visible;
    float x;
    float y;
    float raw_x;
    float raw_y;
    float carry;
    float velocity_x;
    float velocity_y;
    float length;
    float finger_lengths[5];
    float distal_lengths[5];
    unsigned finger_count;
    unsigned finger_next;
    uint32_t extrapolate_at;
    bool extrapolating;
    bool tracking_paused;
    draw_point_t confirmation;
    draw_point_t previous_raw;
    uint32_t confirmation_at;
    bool confirming;
    draw_point_t curve[4];
    draw_point_t pending[4];
    unsigned curve_count;
    unsigned pending_count;
    unsigned positive_frames;
    unsigned negative_frames;
    uint32_t filter_at;
    bool committed;
    bool gap;
    uint32_t seen_at;
    unsigned strokes;
    unsigned points;
    int hover;
    uint32_t hover_at;
    unsigned hold;
    bool selected;
    int cls;
} draw_state_t;
typedef void (*draw_stamp_fn)(void *context, const draw_state_t *state, int x, int y);
extern const uint32_t draw_colors[DRAW_COLORS];
extern const unsigned draw_sizes[3];
void draw_init(draw_state_t *state);
/* Returns the selected toolbar item once per uninterrupted 600 ms hover. */
int draw_hover(draw_state_t *state, bool present, int x, int y, uint32_t now);
void draw_select(draw_state_t *state, unsigned item);
bool draw_pointing(const draw_point_t points[21]);
void draw_step(draw_state_t *state, bool present, int cls, bool geometry, float x, float y,
               uint32_t now, draw_stamp_fn stamp, void *context);
/* Keypoint consistency and the shared pen/eraser position confirmation. */
void draw_hand_step(draw_state_t *state, bool present, int cls,
                    const draw_point_t points[21], uint32_t now,
                    draw_stamp_fn stamp, void *context);
/* Clips each circular pen / square eraser stamp to the 1280x720 layer. */
void draw_raster(uint32_t *pixels, const draw_state_t *state, int x, int y);
#endif
