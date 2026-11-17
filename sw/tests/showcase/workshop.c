/* workshop.c — T-WS-GAME acceptance; deterministic pure C interaction coverage. */
#include "workshop.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static workshop_state s;
static workshop_snapshot a,b;
static void step(int x,int y,int cls)
{
    workshop_step(&s,(ws_input){x,y,cls,false,0});
}
static void ticks(unsigned count,int x,int y,int cls)
{
    for (unsigned i=0;i<count;++i) step(x,y,cls);
}
static void empty(void)
{
    workshop_init(&s);
    s.menu=false;
}
static void connectivity(void)
{
    empty();
    int support=workshop_add(&s,WS_STONE,0,4,10);
    int lower=workshop_add(&s,WS_STONE,0,4,9);
    int upper=workshop_add(&s,WS_PLANK,0,5,9);
    workshop_add(&s,WS_STONE,0,5,10);
    /* Remove the alternate floor then the pillar; connected pair falls together. */
    workshop_remove(&s,s.grid[10][5]);
    workshop_remove(&s,support);
    assert(s.blocks[lower].group && s.blocks[lower].group==s.blocks[upper].group);
    ticks(4,0,0,0);
    assert(s.falls[s.blocks[lower].group-1].offset>0);
    ticks(60,0,0,0);
    assert(s.blocks[lower].y==10 && s.blocks[upper].y==10);
    assert(!s.blocks[lower].group && !s.blocks[upper].group);
    empty();
    workshop_add(&s,WS_STONE,0,4,10);
    workshop_add(&s,WS_STONE,0,4,9);
    workshop_add(&s,WS_STONE,0,4,8);
    int pillar=workshop_add(&s,WS_STONE,0,4,7);
    int bridge=workshop_add(&s,WS_BEAM,0,4,6);
    workshop_remove(&s,pillar);
    ticks(60,0,0,0);
    assert(s.blocks[bridge].y==7 && !s.blocks[bridge].group);
    empty();
    workshop_add(&s,WS_STONE,0,4,10);
    workshop_add(&s,WS_STONE,0,4,9);
    int sand=workshop_add(&s,WS_SAND,0,5,9);
    assert(s.blocks[sand].group);
    ticks(60,0,0,0);
    assert(s.blocks[sand].y==10 && !s.blocks[sand].group);
}
static void shapes(void)
{
    empty();
    int beam=workshop_add(&s,WS_BEAM,0,4,10);
    assert(s.grid[10][4]==beam && s.grid[10][5]==beam);
    assert(workshop_add(&s,WS_DOOR,0,5,10)<0);
    assert(workshop_rotate(WS_BEAM,0)==1 && workshop_rotate(WS_DOOR,0)==0);
    for (unsigned i=0;i<4;++i) assert(workshop_rotate(WS_WOOD_SLOPE,i)==(i+1)%4);
    assert(workshop_add(&s,WS_BEAM,1,7,10)>=0);
    step(376,656,1);
    assert(s.held==beam && s.grid[10][4]<0 && s.grid[10][5]<0);
    step(520,656,0); /* occupied pillar: return starts, then exactly 12 steps */
    assert(s.return_ticks==12);
    ticks(11,520,656,0);
    assert(s.held==beam);
    step(520,656,0);
    assert(s.held<0 && s.grid[10][4]==beam);
    /* A falling block fills the origin while the held block is away. */
    step(376,656,1);
    assert(s.held==beam);
    int above=workshop_add(&s,WS_BEAM,0,4,8);
    ticks(60,700,300,1);
    assert(s.blocks[above].y==10);
    step(520,656,0);
    assert(s.return_ticks==12 && s.origin_y==9);
    ticks(12,520,656,0);
    assert(s.held<0 && s.blocks[beam].y==9 && !s.blocks[beam].group);
    s.selected=WS_WOOD_SLOPE;
    step(700,400,2);
    assert(s.orientation==1);
    ticks(4,700,400,2);
    assert(s.orientation==1);
    step(700,400,0); step(700,400,2);
    assert(s.orientation==2);
}
static void mining(void)
{
    const unsigned materials[]={WS_DIRT,WS_PLANK,WS_STONE,WS_METAL};
    const unsigned durations[]={24,48,72,120};
    for (unsigned i=0;i<4;++i) {
        empty();
        int id=workshop_add(&s,materials[i],0,4,10);
        s.selected=WS_PICK;
        ticks(durations[i]-1,376,656,1);
        assert(s.blocks[id].used && s.mine_ticks==durations[i]-1);
        step(376,656,1);
        assert(!s.blocks[id].used && s.breaks==1);
        unsigned debris=0;
        for (unsigned p=0;p<WS_PARTICLES;++p) if (s.particles[p].life) ++debris;
        assert(debris==8);
    }
    empty();
    int id=workshop_add(&s,WS_METAL,0,4,10);
    workshop_add(&s,WS_METAL,0,5,10);
    s.selected=WS_PICK;
    ticks(60,376,656,1);
    assert(s.mine_ticks==60);
    step(424,656,1);
    assert(s.mine_ticks==1 && s.mining!=id);
    step(424,656,0);
    assert(s.mining<0 && s.mine_ticks==0);
}
static void inventory(void)
{
    empty();
    s.selected=WS_STONE;
    ticks(29,0,0,7); assert(!s.inventory);
    step(0,0,7); assert(s.inventory);
    ticks(60,0,0,7); assert(s.inventory);
    step(0,0,0); ticks(30,0,0,7); assert(!s.inventory);
    step(0,0,0); ticks(30,0,0,7); assert(s.inventory);
    unsigned places=s.places;
    step(330,175,1);
    assert(!s.inventory && s.selected==WS_HAND && s.places==places);
    step(0,0,0);
    workshop_key(&s,3); assert(s.inventory);
    workshop_key(&s,1); workshop_key(&s,3);
    assert(!s.inventory && s.selected==WS_PICK);
    /* Continuous placement must enter the central 60% of the next cell. */
    s.selected=WS_PLANK;
    step(376,656,0); step(376,656,1);
    assert(s.places==1);
    step(402,656,1); assert(s.places==1);
    step(424,656,1); assert(s.places==2);
    workshop_key(&s,3);
    step(472,656,1);
    assert(s.places==2 && s.inventory);
}
static void animals_test(void)
{
    workshop_scene(&s,0);
    s.animal_count=1;
    ws_animal *p=&s.animals[0];
    p->action=WS_WALK; p->timer=300; p->phase=0; p->direction=1;
    int x=p->x;
    ticks(5,0,0,0); assert(p->x==x);
    step(0,0,0); assert(p->frame==1 && p->x==x+8);
    /* Put the foot 24px before a one-cell step. */
    p->x=(WS_X+4*48-24)*2; p->y=(WS_Y+9*48)*2; p->phase=50;
    workshop_add(&s,WS_STONE,0,4,8);
    step(0,0,0); assert(p->action==WS_JUMP);
    ticks(18,0,0,0); assert(p->y==(WS_Y+8*48)*2 && p->action==WS_WALK);
    workshop_add(&s,WS_STONE,0,5,8);
    workshop_add(&s,WS_STONE,0,5,7);
    workshop_add(&s,WS_STONE,0,5,6);
    p->x=(WS_X+5*48-24)*2; p->phase=50; p->direction=1;
    step(0,0,0); assert(p->direction==-1);
    p->x=(WS_X+4*48+24)*2; p->velocity=0;
    workshop_remove(&s,s.grid[8][4]);
    int y=p->y; step(0,0,0); assert(p->y>y);
    int hx=p->x/2,hy=p->y/2-20;
    step(hx,hy,1); assert(p->action==WS_LIFT && s.lifted==0);
    step(700,300,1); assert(p->x==1400 && p->action==WS_LIFT);
    step(700,300,0); assert(p->action==WS_FALL && s.lifted<0);
    ticks(80,0,0,0); assert(p->action==WS_IDLE);
    s.selected=WS_PICK;
    step(p->x/2-4,p->y/2-20,1); assert(p->action==WS_STUN && p->timer==60);
    ticks(59,0,0,0); assert(p->action==WS_STUN);
    step(0,0,0); assert(p->action==WS_RUN && p->timer==180);
}
static unsigned char damaged[1280*720];
static unsigned area;
static void mark(ws_rect r,void *unused)
{
    (void)unused;
    for (int y=r.y;y<r.y+r.h;++y) for (int x=r.x;x<r.x+r.w;++x)
        if (x>=0 && x<1280 && y>=0 && y<720 && !damaged[y*1280+x]) {
            damaged[y*1280+x]=1; ++area;
        }
}
static void measure(const char *name)
{
    memset(damaged,0,sizeof damaged); area=0;
    workshop_dirty(&a,&b,mark,NULL);
    printf("dirty operation=%s pixels=%u\n",name,area);
}
static void areas(void)
{
    workshop_scene(&s,0); s.animal_count=1;
    s.animals[0].action=WS_WALK; s.animals[0].timer=300; s.animals[0].phase=50;
    workshop_snapshot_copy(&s,&a); step(0,0,0); workshop_snapshot_copy(&s,&b);
    measure("animal-walk");
    s.animal_count=0; step(376,608,1); workshop_snapshot_copy(&s,&a);
    step(384,612,1); workshop_snapshot_copy(&s,&b); measure("block-drag");
    empty();
    for (int x=4;x<14;++x) for (int y=4;y<7;++y)
        s.blocks[(x-4)*3+y-4]=(ws_block){true,WS_STONE,0,(int16_t)x,(int16_t)y,0};
    workshop_reconnect(&s); workshop_snapshot_copy(&s,&a);
    ticks(4,0,0,0); workshop_snapshot_copy(&s,&b); measure("30-cell-fall");
    workshop_snapshot_copy(&s,&a); s.inventory=true;
    workshop_snapshot_copy(&s,&b); measure("inventory-open");
}
int main(void)
{
    for (unsigned scene=0;scene<3;++scene) {
        workshop_scene(&s,scene);
        for (int i=0;i<WS_BLOCKS;++i) assert(!s.blocks[i].used || !s.blocks[i].group);
    }
    connectivity(); shapes(); mining(); inventory(); animals_test(); areas();
    puts("PASS workshop connectivity, sand, shapes, mining, inventory, animals, scenes");
}
