/* parse.c: showcase design 4.5; runtime EDGP layout roundtrip on host.
 * Clock domain: host test process.
 */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "game_pack.h"
int main(int argc, char **argv)
{
    assert(argc == 2);
    FILE *file = fopen(argv[1], "rb");
    assert(file);
    assert(fseek(file, 0, SEEK_END) == 0);
    long length = ftell(file);
    assert(length > 0);
    rewind(file);
    unsigned char *bytes = malloc((size_t)length);
    assert(bytes);
    assert(fread(bytes, 1, (size_t)length, file) == (size_t)length);
    assert(fclose(file) == 0);
    const struct game_pack_header *header = (const void *)bytes;
    const struct game_pack_entry *entries = (const void *)(header + 1);
    assert(memcmp(header->magic, "EDGP", 4) == 0);
    assert(header->version == 1 && header->count == 2);
    assert(strcmp(entries[0].name, "测试游戏") == 0);
    assert(strcmp(entries[1].name, "名字卡片") == 0);
    for (unsigned i = 0; i < header->count; ++i) {
        assert(entries[i].rom_length == 16 + 16384 + 8192);
        assert(memcmp(bytes + entries[i].rom_offset, "NES\x1a", 4) == 0);
    }
    assert(entries[0].icon_width == 64 && entries[0].icon_height == 64);
    assert(entries[0].icon_format == GAME_PACK_ARGB8888);
    assert(entries[0].icon_offset % 4 == 0);
    assert(entries[1].icon_offset == 0);
    assert(entries[1].icon_width == 0 && entries[1].icon_height == 0);
    free(bytes);
    puts("PASS runtime C EDGP layout/UTF-8/ROM/icon roundtrip");
    return 0;
}
