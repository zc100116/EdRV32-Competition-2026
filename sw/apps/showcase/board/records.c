/* records.c — showcase design 4.5.5; EDGP v2 and EDG2 boundary parsing.
 * Reject malformed external records explicitly; clk_sys or host tests. */
#include "records.h"
#include <string.h>
uint16_t record_u16(const uint8_t *p) { return p[0] | (uint16_t)p[1] << 8; }
uint32_t record_u32(const uint8_t *p) { return record_u16(p) | (uint32_t)record_u16(p+2)<<16; }
void record_put32(uint8_t *p, uint32_t v)
{
    for (unsigned i = 0; i < 4; ++i) p[i] = (uint8_t)(v >> (i * 8));
}
static int span(uint32_t off, uint32_t len, uint32_t total)
{
    return off >= 100 && !(off & 3) && off <= total && len <= total - off;
}
int game_record_parse(struct game_record *r, const uint8_t *d, uint32_t bytes)
{
    if (bytes < 100 || memcmp(d, "EDG2", 4) || record_u16(d+4) != 2) return 2;
    uint32_t total = record_u32(d+8);
    uint32_t no = record_u32(d+16), co = record_u32(d+24), ro = record_u32(d+28);
    *r = (struct game_record){.base=d, .total=total, .name_w=record_u16(d+12),
        .name_h=record_u16(d+14), .cover_w=record_u16(d+20), .cover_h=record_u16(d+22),
        .rom_len=record_u32(d+32), .text=(const char *)d+36};
    if (total != bytes || !memchr(d+36, 0, 64) || !r->name_w || !r->name_h ||
        !span(no, (uint32_t)r->name_w*r->name_h, total) ||
        !span(ro, r->rom_len, total) || !r->rom_len ||
        (co && (!r->cover_w || !r->cover_h || r->cover_w>120 || r->cover_h>160 ||
        !span(co, (uint32_t)r->cover_w*r->cover_h*2, total)))) return 2;
    r->name=d+no; r->rom=d+ro; r->cover=co ? d+co : 0;
    return 0;
}
int game_pack_count(const uint8_t *d, uint32_t bytes, unsigned *count)
{
    if (bytes < 8 || memcmp(d,"EDGP",4) || record_u16(d+4)!=2) return 2;
    *count=record_u16(d+6);
    return *count > (bytes-8)/4 ? 2 : 0;
}
int game_pack_record(struct game_record *r,const uint8_t *d,uint32_t bytes,unsigned i)
{
    uint32_t off=record_u32(d+8+i*4);
    if ((off&3) || off>bytes || bytes-off<100) return 2;
    uint32_t total=record_u32(d+off+8);
    if (total>bytes-off) return 2;
    return game_record_parse(r,d+off,total);
}
