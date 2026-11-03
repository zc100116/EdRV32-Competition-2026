/* game_pack.h — showcase design 4.5.5; little-endian EDGP v2 / EDG2 headers.
 * Offsets are relative to each record; ROM bytes remain borrowed DDR storage. */
#ifndef SHOWCASE_GAME_PACK_H
#define SHOWCASE_GAME_PACK_H
#include <stdint.h>
enum { GAME_PACK_VERSION=2, GAME_RECORD_VERSION=2 };
struct game_pack_header {
    char magic[4];
    uint16_t version;
    uint16_t count;
    /* Followed by count little-endian u32 record offsets. */
};
struct game_record_header {
    char magic[4];
    uint16_t version, reserved;
    uint32_t total;
    uint16_t name_w, name_h;
    uint32_t name_off;
    uint16_t cover_w, cover_h;
    uint32_t cover_off, rom_off, rom_len;
    char utf8_name[64];
};
_Static_assert(sizeof(struct game_pack_header)==8,"EDGP v2 header layout");
_Static_assert(sizeof(struct game_record_header)==100,"EDG2 header layout");
#endif
