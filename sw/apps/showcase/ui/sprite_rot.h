/* sprite_rot.h — showcase R4 §6.5; GEO entry-time bilinear rotation atlas.
 * Caller supplies DDR storage and straight ARGB8888 art. No LVGL dependency.
 */
#ifndef SHOWCASE_SPRITE_ROT_H
#define SHOWCASE_SPRITE_ROT_H
#include "tower.h"
#include "geo.h"
typedef struct { const uint32_t *pixels; unsigned width, height; } sprite_source;
typedef struct { uint32_t *pixels; unsigned width, height; int left, top; } sprite_frame;
typedef struct {
    sprite_source sources[TOWER_KINDS];
    sprite_frame frames[TOWER_KINDS][64];
    uint32_t *storage;
    uint64_t kinds;
    unsigned kind, completed, total, bytes, types;
    unsigned scratch_bytes, source_end;
    uint8_t red_blue[64*32];
    uint32_t alpha_green[64*64];
    struct geo_config configs[128];
} sprite_rot;
void sprite_rot_begin(sprite_rot *atlas, const sprite_source sources[TOWER_KINDS],
                      uint64_t kinds, uint32_t *storage);
/* Prepare both planes and all angle descriptors for one kind in DDR scratch. */
void sprite_rot_prepare(sprite_rot *atlas, void *scratch);
/* After GEO completion/cache invalidation, restore one kind; true when all done. */
bool sprite_rot_finish(sprite_rot *atlas, const void *scratch);
#endif
