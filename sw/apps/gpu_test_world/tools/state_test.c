/* state_test.c — G-4; cached height continuity, LODs, pickup, landmark and day cycle. */
#include "../world.c"
#include <assert.h>
struct test_state test;
const int16_t test_sine[256]={
#include "sine.inc"
};
void test_sound(unsigned effect){(void)effect;}
int main(void)
{
    test.textures=malloc(TEST_TEXTURE_BYTES);
    assert(test.textures);
    world_init();
    for(int z=448;z<1024;z+=4)for(int x=704;x<1280;x+=4)
        assert(sample(x,z)==height(x,z));
    stopped=1;world_update(0);
    unsigned levels[3]={0};
    for(unsigned i=0;i<visible_count;++i)++levels[visible[i].lod];
    assert(levels[0]&&levels[1]&&levels[2]);
    player_x=(700+(int)(random_at(0,7)%700))*256;
    player_z=(680+(int)(random_at(0,9)%700))*256;
    unsigned before=generated;world_update(0);
    assert(picked[0]&&collected&&generated-before<=2);
    player_x=landmark[0][0]*256;player_z=(landmark[0][1]-30)*256;
    world_update(0);assert((discovered&1)&&toast);
    world_time=0;test.tick=3375;world_update(0);int dusk=fog_r;
    test.tick+=10800;world_update(0);assert(fog_r==dusk);
    test.tick=0;world_update(0);assert(fog_r!=dusk);
    free(test.textures);
    puts("PASS G-4: cached heights, all LODs, two-block generation, pickup, discovery, repeating day cycle");
    return 0;
}
