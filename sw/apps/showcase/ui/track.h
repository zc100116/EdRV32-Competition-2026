/* track.h — T-HELMET-STABLE: helmet tracks and warning dwell times.
 * One tracking step per inference result; warning uses GUI milliseconds.
 */
#ifndef SHOWCASE_TRACK_H
#define SHOWCASE_TRACK_H
#include "ui_data.h"
enum { HELMET_TRACKS = 100, HELMET_HISTORY = 5 };
typedef struct {
    ui_detection_t box;
    unsigned seen, lost, history, samples;
    bool active, visible;
} helmet_track_t;
typedef struct {
    helmet_track_t tracks[HELMET_TRACKS];
    unsigned helmet, head, warning_since;
    bool warning, has_head;
} helmet_state_t;
extern unsigned helmet_revision;
extern helmet_state_t helmet_stable;
void helmet_step(helmet_state_t *s, const ui_detection_t *boxes, unsigned count);
bool helmet_warning(helmet_state_t *s, unsigned now);
#endif
