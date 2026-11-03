/* records.h — showcase design 4.5.5: little-endian EDG2/EDGP wire views.
 * Parsed pointers borrow the immutable record storage; clk_sys or host tests. */
#ifndef SHOWCASE_RECORDS_H
#define SHOWCASE_RECORDS_H
#include <stdint.h>
struct game_record {
    const uint8_t *base, *name, *cover, *rom;
    const char *text;
    uint32_t total, rom_len;
    uint16_t name_w, name_h, cover_w, cover_h;
};
uint16_t record_u16(const uint8_t *p);
uint32_t record_u32(const uint8_t *p);
void record_put32(uint8_t *p, uint32_t value);
int game_record_parse(struct game_record *out, const uint8_t *data, uint32_t bytes);
int game_pack_count(const uint8_t *data, uint32_t bytes, unsigned *count);
int game_pack_record(struct game_record *out, const uint8_t *data, uint32_t bytes,
                     unsigned index);
#endif
