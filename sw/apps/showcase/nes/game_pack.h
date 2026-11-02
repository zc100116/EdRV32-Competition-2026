/* game_pack.h: showcase design 4.5; little-endian EDGP view. CPU clk_sys. */
#ifndef SHOWCASE_GAME_PACK_H
#define SHOWCASE_GAME_PACK_H
#include <stdint.h>
enum { GAME_PACK_VERSION = 1, GAME_PACK_ARGB8888 = 1 };
struct game_pack_header {
    char magic[4];
    uint16_t version;
    uint16_t count;
};
struct game_pack_entry {
    char name[64];
    uint32_t rom_offset;
    uint32_t rom_length;
    uint32_t icon_offset;
    uint16_t icon_width;
    uint16_t icon_height;
    uint32_t icon_format;
};
_Static_assert(sizeof(struct game_pack_header) == 8, "EDGP header layout");
_Static_assert(sizeof(struct game_pack_entry) == 84, "EDGP entry layout");
#endif
