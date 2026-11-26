/* state_test.c — G-4; seeded room topology and slash/Boss combat transitions. */
#include "../rogue.c"
#include <assert.h>
struct test_state test;
const int16_t test_sine[256]={
#include "sine.inc"
};
void test_sound(unsigned effect){(void)effect;}
int main(void)
{
    for(unsigned run=0;run<1024;++run){
        test.mode=0;rogue_init();
        unsigned seen[9]={1},types[5]={0};
        for(unsigned i=0;i<9;++i){
            ++types[rooms[i].type];
            for(unsigned j=0;j<i;++j)
                assert(rooms[i].x!=rooms[j].x||rooms[i].y!=rooms[j].y);
        }
        for(unsigned pass=0;pass<9;++pass)for(unsigned i=0;i<9;++i)if(seen[i])
            for(unsigned j=0;j<9;++j)
                if(abs(rooms[i].x-rooms[j].x)+abs(rooms[i].y-rooms[j].y)==1)seen[j]=1;
        for(unsigned i=0;i<9;++i)assert(seen[i]);
        assert(types[0]==1&&types[1]==5&&types[2]==1&&types[3]==1&&types[4]==1);
    }
    next_seed=0x264b42;rogue_init();
    struct room baseline[9];memcpy(baseline,rooms,sizeof(rooms));
    next_seed=0x264b42;rogue_init();assert(!memcmp(baseline,rooms,sizeof(rooms)));
    memset(enemies,0,sizeof(enemies));spawn(0,350,245);
    test.weapon=2;test.tick=1;swing=10;aim=0;
    rogue_update(0);assert(enemies[0].hp==12&&hitstop==4);
    memset(enemies,0,sizeof(enemies));memset(bullets,0,sizeof(bullets));
    spawn(3,320,120);enemies[0].hp=420;enemies[0].age=39;hitstop=0;
    rogue_update(0);unsigned n=0;
    for(unsigned i=0;i<8448;++i)n+=bullets[i].life!=0;
    assert(n==18);
    puts("PASS G-4: 1024 seeded connected maps, reproducibility, slash hitstop, Boss phase2");
    return 0;
}
