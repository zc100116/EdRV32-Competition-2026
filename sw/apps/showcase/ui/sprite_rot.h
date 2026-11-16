/* sprite_rot.h — showcase R4 §6.5; CPU entry-time bilinear rotation atlas.
 * Caller supplies DDR storage and straight ARGB8888 art. No LVGL dependency.
 */
#ifndef SHOWCASE_SPRITE_ROT_H
#define SHOWCASE_SPRITE_ROT_H
#include "tower.h"
typedef struct { const uint32_t *pixels; unsigned width, height; } sprite_source;
typedef struct { uint32_t *pixels; unsigned width, height; int left, top; } sprite_frame;
typedef struct {
    sprite_source sources[TOWER_KINDS];
    sprite_frame frames[TOWER_KINDS][64];
    uint32_t *storage;
    uint64_t kinds;
    unsigned kind, frame, completed, total, bytes;
} sprite_rot;
void sprite_rot_begin(sprite_rot *atlas, const sprite_source sources[TOWER_KINDS],
                      uint64_t kinds, uint32_t *storage);
/* Generates one frame. Returns true after the last requested frame. */
bool sprite_rot_generate(sprite_rot *atlas);
uint32_t sprite_rot_sample(sprite_source source, int x_q8, int y_q8);
#endif
