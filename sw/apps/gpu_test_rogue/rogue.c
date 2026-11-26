/* rogue.c — G-4; room dungeon, fixed-point combat, GPU sprites and rotating cleaver.
 * CPU frame thread owns state; command submission is synchronous in shared runtime.
 */
#include "demo.h"
#include "rogue_assets.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
struct room { int x, y; unsigned type, seen, clear, door; };
struct enemy { int x, y, vx, vy, hp; unsigned type, age, flash, struck; };
struct bullet { int x, y, vx, vy; unsigned life, enemy, pierce; };
struct particle { int x, y, vx, vy; unsigned life, color, text; };
struct loot {int x,y;unsigned alive;};
static struct loot loot[64];
static struct room rooms[9];
static struct enemy enemies[132];
static struct bullet bullets[8448];
static struct particle particles[512];
static unsigned seed, initial_seed, next_seed=0x264b42u;
static unsigned current, count, roll, cooldown, angle, swing, hitstop, shake, door_close;
static unsigned coins, choice, selected, item[4], complete, failed, press_time;
static uint32_t previous;
static int px, py, aim, flash;
static unsigned rng(void) { seed = seed*1664525u+1013904223u; return seed; }
static int sn(unsigned a) { return test_sine[a&255]; }
static int cs(unsigned a) { return sn(a+64); }
static unsigned direction(int x, int y)
{
    int best = -2147483647;
    unsigned result = 0;
    for (unsigned a = 0; a < 256; a += 4) {
        int dot = x*cs(a)+y*sn(a);
        if (dot > best) { best = dot; result = a; }
    }
    return result;
}
void demo_load(void)
{
    for(unsigned i=32;i<104;++i){
        unsigned c=test.palettes[i]&65535;
        unsigned r=((c>>11)&31)*8,g=((c>>5)&63)*4,b=(c&31)*8;
        test.palettes[12*256+i]=0xf0000|test_color(r+12,g*7/8,b*7/8);
        test.palettes[13*256+i]=0xf0000|test_color(r*7/8,g+8,b+8);
    }
    for(unsigned p=0;p<16;++p)test.palettes[p*256+104]=0x80000|0x0865;
    memcpy(test.textures, rogue_primary, sizeof(rogue_primary));
    memcpy(test.textures+65536, rogue_tiles, sizeof(rogue_tiles));
    for (unsigned g = 0; g < sizeof(demo_chinese)/sizeof(*demo_chinese); ++g)
        for (unsigned y = 0; y < 12; ++y) for (unsigned x = 0; x < 12; ++x) {
            unsigned u = 128+(g%10)*12+x, v = 128+(g/10)*12+y;
            unsigned bx = u/2;
            unsigned address = 8*((v/2)*64+bx/2)+2*((bx&1)+2*(v&1))+(u&1);
            test.textures[address] = demo_glyphs[g*144+y*12+x];
        }
}
void demo_text(int x, int y, const char *s, unsigned color)
{
    while (*s) {
        unsigned c = (unsigned char)*s++, w = 8, h = 16, u, v;
        if (c < 128) { c -= 32; u = (c%16)*8; v = 128+(c/16)*16; }
        else {
            unsigned cp = (c&15)<<12;
            cp |= ((unsigned char)*s++&63)<<6;
            cp |= (unsigned char)*s++&63;
            unsigned g = 0;
            while (demo_chinese[g] != cp) ++g;
            u = 128+(g%10)*12; v = 128+(g/10)*12; w = h = 12;
        }
        test_quad(x, y, w, h, u, v, color, 255);
        x += (int)w;
    }
}
void demo_diagnostics(unsigned blocks)
{
    unsigned first = test.quads_count;
    test_panel(8, 338, 624, 20, 2);
    char text[128];
    if(test.game==3)
        snprintf(text,sizeof(text),"SEED %08x 对象 %u FPS %u.%u CPU %u.%03u ms GPU %u us",
            initial_seed,test.alive_count,(unsigned)test.fps10/10,(unsigned)test.fps10%10,
            (unsigned)test.cpu_us/1000,(unsigned)test.cpu_us%1000,(unsigned)test.gpu_us);
    else
        snprintf(text,sizeof(text),"%s 三角形 %u BLK %u FPS %u.%u CPU %u.%03u ms GPU %u us",
            test.mode?"压测":"正常",test.triangles/3,blocks,
            (unsigned)test.fps10/10,(unsigned)test.fps10%10,
            (unsigned)test.cpu_us/1000,(unsigned)test.cpu_us%1000,(unsigned)test.gpu_us);
    demo_text(14, 340, text, 1);
    test_draw(0, first, test.quads_count-first, 0, 1, 0);
}
static void burst(int x, int y, unsigned color, unsigned number)
{
    unsigned made = 0;
    for (unsigned i = 0; i < 512 && made < number; ++i) if (!particles[i].life) {
        unsigned a = rng()&255;
        particles[i] = (struct particle){x*256,y*256,cs(a)/24,sn(a)/24,20+rng()%20,color,0};
        ++made;
    }
}
static void damage_text(int x, int y, unsigned amount)
{
    for (unsigned i = 0; i < 512; ++i) if (!particles[i].life) {
        particles[i] = (struct particle){x*256,y*256,0,-430,36,7,amount};
        return;
    }
}
static void spawn(unsigned type, int x, int y)
{
    for (unsigned i = 0; i < 132; ++i) if (enemies[i].hp <= 0) {
        enemies[i] = (struct enemy){x*256,y*256,0,0,type == 3 ? 900 : type == 4 ? 12 : 40,
                                    type,rng()%90,0,0};
        return;
    }
}
static void shoot(int x, int y, unsigned a, int speed, unsigned hostile)
{
    for (unsigned i = 0; i < 8448; ++i) if (!bullets[i].life) {
        bullets[i] = (struct bullet){x,y,cs(a)*speed/64,sn(a)*speed/64,180,hostile,0};
        return;
    }
}
static unsigned living(void)
{
    unsigned n = 0;
    for (unsigned i = 0; i < 132; ++i) n += enemies[i].hp > 0;
    return n;
}
static void enter_room(unsigned n)
{
    current = n;
    struct room *r = &rooms[n];
    r->seen = 1;door_close=r->clear?0:16;
    memset(enemies,0,sizeof(enemies));
    memset(bullets,0,sizeof(bullets));
    memset(loot,0,sizeof(loot));
    choice = 0; swing = roll = 0;
    if (r->clear) return;
    if (r->type == 4) spawn(3,320,125);
    if (r->type == 1) for (unsigned i = 0; i < 5+n; ++i)
        spawn(i%3,100+(int)(rng()%430),90+(int)(rng()%170));
}
void rogue_init(void)
{
    initial_seed=next_seed;seed=initial_seed;next_seed=next_seed*1664525u+1013904223u;
    memset(rooms,0,sizeof(rooms));
    memset(enemies,0,sizeof(enemies));
    memset(bullets,0,sizeof(bullets));
    memset(particles,0,sizeof(particles));
    memset(item,0,sizeof(item));
    count = 1;
    static const int dx[4] = {1,0,-1,0}, dy[4] = {0,1,0,-1};
    while (count < 9) {
        int cx[36], cy[36]; unsigned parent[36], available = 0;
        for (unsigned i = 0; i < count; ++i) for (unsigned d = 0; d < 4; ++d) {
            int x = rooms[i].x+dx[d], y = rooms[i].y+dy[d], occupied = 0;
            for (unsigned j = 0; j < count; ++j) occupied |= rooms[j].x == x && rooms[j].y == y;
            if (!occupied) { cx[available]=x; cy[available]=y; parent[available++]=i; }
        }
        unsigned k = rng()%available;
        /* All empty neighbours are collected explicitly, including endpoints with <4 free cells. */
        if (count < 6) {
            unsigned start = 0;
            for (unsigned i = 0; i < available; ++i) if (parent[i] == count-1) { start=i; break; }
            k = start+rng()%(available-start);
        }
        rooms[count++] = (struct room){cx[k],cy[k],1,0,0,0};
    }
    rooms[0].clear = 1;
    rooms[6].type = 2;
    rooms[7].type = 3;
    rooms[8].type = 4;
    px = 320*256; py = 245*256;
    memset(loot,0,sizeof(loot));
    coins = choice = selected = complete = failed = press_time = 0;
    cooldown = hitstop = shake = 0; angle = 192; flash = 0; previous = 0;
    test.health = 100; test.objects_count = 0;
    enter_room(0);
    if (test.mode) {
        rooms[0].type = 1; rooms[0].clear = 0;
        unsigned n = 32u << (test.level%3);
        for (unsigned i = 0; i < n; ++i) spawn(i%3,65+(int)(rng()%510),80+(int)(rng()%210));
    }
}
static void hurt(struct enemy *e, unsigned amount)
{
    e->hp -= (int)amount; e->flash = 4;
    e->x += (e->x > px ? 1 : -1)*3*256;
    damage_text(e->x/256,e->y/256,amount);
    hitstop = test.weapon == 2 ? 4 : 2; shake = 5;
    burst(e->x/256,e->y/256,4,7);
    burst(e->x/256,e->y/256,9,5);
    test_sound(1);
    if (item[2] && test.health < 100) ++test.health;
    if (e->hp <= 0) {
        burst(e->x/256,e->y/256,e->type == 0 ? 3 : 7,12);
        for(unsigned k=0;k<64;++k)if(!loot[k].alive){
            loot[k]=(struct loot){e->x/256,e->y/256,1};break;}
        test.score += 10;
        if (e->type == 2) { spawn(4,e->x/256-15,e->y/256); spawn(4,e->x/256+15,e->y/256); }
        if (e->type == 3) complete = 1;
    }
}
void rogue_update(uint32_t keys)
{
    uint32_t pressed = keys&~previous; previous = keys;
    if(door_close)--door_close;
    if(rooms[current].door&&rooms[current].door<16)++rooms[current].door;
    if (choice) {
        if (pressed&PLAT_LEFT) selected=(selected+2)%3;
        if (pressed&PLAT_RIGHT) selected=(selected+1)%3;
        if (pressed&PLAT_A) { ++item[(selected+current)%4]; choice=0; }
        return;
    }
    if (complete || failed) { if (pressed&PLAT_A) rogue_init(); return; }
    for (unsigned i = 0; i < 512; ++i) if (particles[i].life) {
        struct particle *p = &particles[i]; --p->life;
        p->x+=p->vx; p->y+=p->vy; p->vy+=p->text?19:25;
    }
    if (flash) --flash;
    if (shake) --shake;
    if (hitstop) { --hitstop; return; }
    if (cooldown) --cooldown;
    if (roll) --roll;
    if (swing) --swing;
    if (keys&PLAT_A) ++press_time;
    else {
        if (press_time && press_time < 30 && !cooldown) { roll=12; cooldown=45; test_sound(0); }
        press_time=0;
    }
    if ((pressed&PLAT_B) && !cooldown) { roll=12; cooldown=45; }
    int dx=0,dy=0;
    if (keys&(PLAT_UP|PLAT_DOWN)) {
        dx = !!(keys&PLAT_RIGHT)-!!(keys&PLAT_LEFT);
        dy = !!(keys&PLAT_DOWN)-!!(keys&PLAT_UP);
        if (dx || dy) angle=direction(dx,dy);
    } else {
        if (keys&PLAT_LEFT) angle=(angle+252)&255;
        if (keys&PLAT_RIGHT) angle=(angle+4)&255;
        dx=cs(angle); dy=sn(angle);
    }
    if (dx >= -1 && dx <= 1 && dy >= -1 && dy <= 1) { dx*=16384; dy*=16384; }
    int speed=roll ? 1300 : 420;
    if (keys&PLAT_A) {
        int ax=!!(keys&PLAT_RIGHT)-!!(keys&PLAT_LEFT);
        int ay=!!(keys&PLAT_DOWN)-!!(keys&PLAT_UP);
        if(ax||ay)aim=(int)direction(ax,ay);
    } else { px+=dx*speed/16384; py+=dy*speed/16384; }
    if (px<48*256) px=48*256;
    if (px>592*256) px=592*256;
    if (py<64*256) py=64*256;
    if (py>312*256) py=312*256;
    int best=2147483647;
    for (unsigned i=0;i<132;++i) if (enemies[i].hp>0) {
        int x=(enemies[i].x-px)/256,y=(enemies[i].y-py)/256,d=x*x+y*y;
        if (d<best) { best=d; if (!(keys&PLAT_A)) aim=(int)direction(x,y); }
    }
    if (best<2147483647 && test.tick%(test.weapon==0?12:test.weapon==1?36:28)==0) {
        if (test.weapon==2) { swing=10; for (unsigned i=0;i<132;++i) enemies[i].struck=0; }
        else {
            unsigned n=test.weapon==1?5:1;
            for (unsigned j=0;j<n+item[1];++j) shoot(px,py,(unsigned)(aim+(int)j*6-(int)n*3),7,0);
            burst(px/256+cs((unsigned)aim)/1400,py/256+sn((unsigned)aim)/1400,4,3);
            burst(px/256-6,py/256+4,9,1);
            test_sound(0);
        }
    }
    for (unsigned i=0;i<132;++i) {
        struct enemy *e=&enemies[i]; if (e->hp<=0) continue;
        ++e->age; if(e->flash) --e->flash;
        int x=(px-e->x)/256,y=(py-e->y)/256,d=abs(x)+abs(y)+1;
        if (e->type==0) {
            if (e->age%100==24) { e->vx=x*1400/d; e->vy=y*1400/d; }
            if (e->age%100>=24 && e->age%100<46) { e->x+=e->vx; e->y+=e->vy; }
        } else if(e->type==1) {
            if(d<160) {e->x-=x*90/d;e->y-=y*90/d;}
            if(e->age%90==0) for(int j=-1;j<=1;++j)
                shoot(e->x,e->y,direction(x,y)+(unsigned)(j*9),3,1);
        } else if(e->type!=3) {e->x+=x*150/d;e->y+=y*150/d;}
        else if(e->age%(e->hp<450?40:70)==0) {
            unsigned n=e->hp<450?18:10;
            for(unsigned j=0;j<n;++j) shoot(e->x,e->y,e->age+j*256/n,2,1);
            if(e->hp<450 && e->age%120==0) spawn(e->age%2,150+(int)(rng()%340),100);
        }
        if(e->x<55*256)e->x=55*256;
        if(e->x>585*256)e->x=585*256;
        if(e->y<75*256)e->y=75*256;
        if(e->y>300*256)e->y=300*256;
        if(swing && !e->struck && x*x+y*y<75*75) {
            int dot=x*cs((unsigned)aim)+y*sn((unsigned)aim);
            if(dot<0) {e->struck=1;hurt(e,28);}
        }
        if(x*x+y*y<22*22 && !flash && roll<=4) {
            unsigned harm=item[3]?4:9; test.health=test.health>harm?test.health-harm:0;
            flash=35;shake=8; px-=x*100/d;py-=y*100/d; test_sound(2);
        }
    }
    for(unsigned i=0;i<8448;++i) if(bullets[i].life) {
        struct bullet *b=&bullets[i]; --b->life;b->x+=b->vx;b->y+=b->vy;
        if(b->x<40*256||b->x>600*256||b->y<60*256||b->y>320*256) {b->life=0;continue;}
        if(b->enemy) {
            int x=(b->x-px)/256,y=(b->y-py)/256;
            if(x*x+y*y<13*13 && !flash && roll<=4) {
                test.health=test.health>7?test.health-7:0; flash=35;shake=8;b->life=0;test_sound(2);
            }
        } else for(unsigned j=0;j<132 && b->life;++j) if(enemies[j].hp>0) {
            int x=(b->x-enemies[j].x)/256,y=(b->y-enemies[j].y)/256;
            if(x*x+y*y<(enemies[j].type==3?42*42:17*17)) {
                hurt(&enemies[j],test.weapon==1?8:12);
                if(!item[0] || b->pierce) b->life=0; else {b->pierce=1;b->x+=b->vx*3;b->y+=b->vy*3;}
            }
        }
    }
    for(unsigned k=0;k<64;++k)if(loot[k].alive){
        int x=px/256-loot[k].x,y=py/256-loot[k].y;
        if(x*x+y*y<80*80){loot[k].x+=x/5;loot[k].y+=y/5;}
        if(x*x+y*y<18*18){loot[k].alive=0;coins+=2;test_sound(3);}
    }
    if(!test.health) failed=1;
    struct room *r=&rooms[current];
    if(r->type==2 && !r->clear && abs(px/256-320)+abs(py/256-180)<50) {
        coins+=15;r->clear=1;choice=1;test_sound(3);
    }
    if(r->type==3 && !r->clear && abs(px/256-320)+abs(py/256-180)<50 && coins>=5) {
        coins-=5;test.health=100;r->clear=1;test_sound(3);
    }
    if(!living() && !r->clear && (r->type==1 || r->type==4)) {
        r->clear=1;r->door=1;if(r->type==1) {choice=1;coins+=5;}
    }
    if(r->clear) for(unsigned i=0;i<9;++i) if(i!=current) {
        int x=rooms[i].x-r->x,y=rooms[i].y-r->y;
        int go=(x==1&&y==0&&px>575*256&&abs(py/256-185)<35)||
            (x==-1&&y==0&&px<65*256&&abs(py/256-185)<35)||
            (y==1&&x==0&&py>300*256&&abs(px/256-320)<40)||
            (y==-1&&x==0&&py<77*256&&abs(px/256-320)<40);
        if(go) {px=(x? (x>0?85:555):320)*256;py=(y?(y>0?95:280):185)*256;enter_room(i);break;}
    }
    if(test.mode) {
        unsigned target=512u<<(2*(test.level%3));
        unsigned n=0;for(unsigned i=0;i<8448;++i)n+=bullets[i].life!=0;
        for(unsigned i=n;i<target;++i) shoot((80+(int)(rng()%480))*256,
            (90+(int)(rng()%190))*256,rng()&255,1,1);
        if(!living()) for(unsigned i=0;i<(32u<<(test.level%3));++i)
            spawn(i%3,80+(int)(rng()%480),90+(int)(rng()%190));
        choice=0;test.health=100;
    }
}
static void actor(int x,int y,unsigned slot,unsigned size,unsigned white)
{
    unsigned source=slot<4?32:slot<6?64:48;
    unsigned u=(slot%4)*64,v=(slot/4)*64+(slot==0?32:0);
    /* Hit flash uses the white palette while preserving the sprite silhouette. */
    if(white&&slot<4){
        test_quad(x-16,y-16,32,32,u,v,15,255);
        return;
    }
    test_sprite(x-(int)size/2,y-(int)size/2,(int)size,(int)size,u,v,source,source);
}
static void rotated(int x,int y,unsigned a,int length,unsigned color)
{
    static const int corner[6][2]={{0,-13},{1,-13},{1,13},{0,-13},{1,13},{0,13}};
    for(unsigned i=0;i<6;++i) {
        int lx=corner[i][0]*length,ly=corner[i][1];
        test_vertex(x+(lx*cs(a)-ly*sn(a))/16384,y+(lx*sn(a)+ly*cs(a))/16384,0,
            color,(64+(corner[i][0]?63:0))*256,(85+(corner[i][1]>0?25:0))*256,0);
    }
}
static void gun(int x,int y,unsigned a,int length,int half,unsigned color)
{
    static const int corners[6][2]={{0,-1},{1,-1},{1,1},{0,-1},{1,1},{0,1}};
    for(unsigned i=0;i<6;++i){
        int dx=10+corners[i][0]*length,dy=corners[i][1]*half;
        test_vertex(x+(dx*cs(a)-dy*sn(a))/16384,y+(dx*sn(a)+dy*cs(a))/16384,
                    0,color,256,256,0);
    }
}
void rogue_scene(void)
{
    int sx=shake?(int)(test.tick%5)-2:0,sy=shake?(int)(test.tick%3)-1:0;
    unsigned first=test.quads_count;
    unsigned theme=current%3==1?12:current%3==2?13:0;
    for(int y=48;y<336;y+=16) for(int x=16;x<624;x+=16) {
        unsigned variant=((unsigned)(x/16)*13+(unsigned)(y/16)*7+current*3)%17;
        test_quad(x+sx,y+sy,16,16,(variant<11?3:variant%3)*16,0,theme,255);
    }
    for(int x=16;x<624;x+=32) {
        test_quad(x,48,32,32,(x/32)%4==1?64:0,32,theme,255);
        test_quad(x,312,32,24,32,32,theme,255);
    }
    for(int y=80;y<312;y+=32) {
        test_quad(16,y,24,32,32,32,theme,255);
        test_quad(600,y,24,32,32,32,theme,255);
        if(y%96==16){test_quad(16,y,24,32,0,32,theme,255);
                    test_quad(600,y,24,32,64,32,theme,255);}
    }
    test_draw(0,first,test.quads_count-first,6,0,0);
    /* Four-frame copper leaves slide apart inside a cyan emissive frame. */
    first=test.quads_count;
    for(unsigned i=0;i<9;++i) if(i!=current) {
        int dx=rooms[i].x-rooms[current].x,dy=rooms[i].y-rooms[current].y;
        if(abs(dx)+abs(dy)!=1)continue;
        int x=dx==0?304:dx>0?592:16,y=dy==0?172:dy>0?304:48;
        unsigned open=rooms[current].clear?(rooms[current].door?rooms[current].door:16):door_close;
        unsigned gap=(open/4)*3;
        test_quad(x,y,32,32,96,32,0,255);
        test_quad(x+5,y+4,22,24,160,0,0,255);
        test_quad(x+4-(int)gap,y+4,12,24,101,36,0,255);
        test_quad(x+16+(int)gap,y+4,12,24,112,36,0,255);
    }
    for(unsigned k=0;k<64;++k)if(loot[k].alive)
        test_quad(loot[k].x-6,loot[k].y-6,12,12,64,96,0,255);
    test_draw(0,first,test.quads_count-first,6,0,0);
    first=test.quads_count;
    /* Ellipses use alpha blending and are submitted before all feet. */
    for(unsigned i=0;i<132;++i)if(enemies[i].hp>0) {
        int x=enemies[i].x/256,y=enemies[i].y/256;
        test_quad(x-16,y+(enemies[i].type==3?37:10),32,12,80,96,0,160);
        if(enemies[i].type==3)test_quad(x+8,y+37,32,12,80,96,0,160);
    }
    test_quad(px/256-16,py/256+10,32,12,80,96,0,180);
    test_draw(0,first,test.quads_count-first,6,1,0);
    first=test.quads_count;
    unsigned actors_first=test.triangles;
    if(rooms[current].type==2)actor(320,180,6,48,0);
    if(rooms[current].type==3)actor(320,180,7,48,0);
    for(unsigned i=0;i<132;++i)if(enemies[i].hp>0) {
        struct enemy *e=&enemies[i];
        actor(e->x/256+sx,e->y/256+sy,e->type==3?4:e->type==4?3:e->type+1,
              e->type==3?116:e->type==4?20:e->type==0?38:34,e->flash);
    }
    if(roll)for(int i=3;i>0;--i)
        test_quad(px/256-16-cs(angle)*i/1500,py/256-16-sn(angle)*i/1500,32,32,0,32,2,65);
    actor(px/256+sx,py/256+sy,0,32,flash && (test.tick&2));
    test_draw(0,first,test.quads_count-first,0,1,0);
    test_draw(1,actors_first,(test.triangles-actors_first)/3,0,1,0);
    first=test.triangles;
    if(test.weapon<2){
        gun(px/256,py/256,(unsigned)aim,test.weapon?22:15,5,0x1085);
        gun(px/256,py/256,(unsigned)aim,test.weapon?20:13,3,test.weapon?0xfd29:0x3fff);
    }
    if(swing) for(unsigned t=0;t<1;++t)
        rotated(px/256,py/256,(unsigned)(aim-48+(10-swing)*10-(int)t*9),58-t*4,
                t?test_color(30,100+30*t,150+20*t):0xffff);
    test_draw(1,first,(test.triangles-first)/3,0,1,0);
    first=test.triangles;
    if(swing)for(unsigned j=0;j<18;++j) {
        unsigned a=(unsigned)(aim-52+(10-swing)*10-(int)j*4);
        int x=px/256,y=py/256;
        unsigned u=(128+j*30/18)*256;
        test_vertex(x+cs(a)*65/16384,y+sn(a)*65/16384,0,0x7fff,u,96*256,0);
        test_vertex(x+cs(a+4)*65/16384,y+sn(a+4)*65/16384,0,0x7fff,u,96*256,0);
        test_vertex(x+cs(a+4)*37/16384,y+sn(a+4)*37/16384,0,0x3fff,u,111*256,0);
        test_vertex(x+cs(a)*65/16384,y+sn(a)*65/16384,0,0x7fff,u,96*256,0);
        test_vertex(x+cs(a+4)*37/16384,y+sn(a+4)*37/16384,0,0x3fff,u,111*256,0);
        test_vertex(x+cs(a)*37/16384,y+sn(a)*37/16384,0,0x3fff,u,111*256,0);
    }
    test_draw(1,first,(test.triangles-first)/3,6,2,0);
    first=test.quads_count;
    unsigned active=living()+1;
    test.objects_count=0;
    for(unsigned i=0;i<8448;++i)if(bullets[i].life) {
        ++active;struct bullet *b=&bullets[i];
        struct gpu_object_args obj={.alive=1,.px=(unsigned)b->x,.py=(unsigned)b->y,
            .w=8,.h=8,.u0=0,.v0=96,.pal_group=b->enemy?4:2,.alpha=200};
        gpu_object(&test.objects[test.objects_count++],&obj);
    }
    for(unsigned i=0;i<512;++i)if(particles[i].life&&!particles[i].text) {
        ++active;struct particle *p=&particles[i];
        if(p->color==9)test_quad(p->x/256,p->y/256,8,8,112,96,0,255);
        else test_quad(p->x/256,p->y/256,4,4,0,96,p->color,220);
    }
    for(unsigned i=0;i<6;++i) {
        int x=i%2?578:50,y=98+(int)(i/2)*92;
        test_quad(x-16,y-16,32,32,16,96,i%2?4:2,95+(test.tick+i*13)%90);
    }
    test_draw(0,first,test.quads_count-first,6,2,0);
    test_draw(2,0,test.objects_count,6,2,0);
    first=test.quads_count;
    for(unsigned i=0;i<6;++i) {
        int x=i%2?578:50,y=98+(int)(i/2)*92;
        test_quad(x-5,y+7,10,5,0,32,0,255);
        test_quad(x-8,y-16,16,24,128+((test.tick/6+i)%4)*16,32,0,255);
    }
    test_draw(0,first,test.quads_count-first,6,1,0);
    test.alive_count=active;
    first=test.quads_count;
    unsigned numbers=test.triangles;
    for(unsigned i=0;i<512;++i)if(particles[i].life&&particles[i].text) {
        char number[12];snprintf(number,sizeof(number),"%u",particles[i].text);
        unsigned scale=particles[i].life>28?448+(36-particles[i].life)*12:384;
        int x=particles[i].x/256,y=particles[i].y/256;
        for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx)if(dx||dy)
            test_scaled_text(x+dx,y+dy,number,scale,0x0865);
        test_scaled_text(x,y,number,scale,0xffa5);
    }
    test_draw(1,numbers,(test.triangles-numbers)/3,0,1,0);
    test_panel(8,8,200,36,2);demo_text(16,10,"棱炉地宫",1);
    test_rect(16,28,100,6,9);test_rect(16,28,test.health,6,3);
    char s[80];
    snprintf(s,sizeof(s),"金币 %u",coins);demo_text(125,24,s,7);
    test_panel(456,8,176,34,2);
    demo_text(464,10,test.weapon==0?"点射枪":test.weapon==1?"霰弹枪":"弧刃",2);
    snprintf(s,sizeof(s),"房间 %u/9",current+1);demo_text(536,25,s,1);
    if(rooms[current].type==4) {
        test_panel(220,8,222,34,6);demo_text(266,10,"棱炉监工",1);
        unsigned hp=0;
        for(unsigned i=0;i<132;++i)
            if(enemies[i].type==3&&enemies[i].hp>0)hp=(unsigned)enemies[i].hp;
        test_rect(230,28,hp*200/900,5,hp<450?3:6);
    }
    test_panel(493,245,134,87,2);
    int minx=0,miny=0,maxx=0,maxy=0;
    for(unsigned i=0;i<9;++i){
        if(rooms[i].x<minx)minx=rooms[i].x;
        if(rooms[i].y<miny)miny=rooms[i].y;
        if(rooms[i].x>maxx)maxx=rooms[i].x;
        if(rooms[i].y>maxy)maxy=rooms[i].y;
    }
    int cellx=118/(maxx-minx+1),celly=68/(maxy-miny+1);
    if(cellx>20)cellx=20;
    if(celly>18)celly=18;
    for(unsigned i=0;i<9;++i)for(unsigned j=i+1;j<9;++j) {
        int dx=rooms[j].x-rooms[i].x,dy=rooms[j].y-rooms[i].y;
        if(abs(dx)+abs(dy)!=1)continue;
        int x=503+(rooms[i].x-minx)*cellx,y=255+(rooms[i].y-miny)*celly;
        test_rect(dx<0?x-cellx:x,dy<0?y-celly:y,
                  dx?cellx+4:4,dy?celly+4:4,rooms[i].seen&&rooms[j].seen?2:9);
    }
    for(unsigned i=0;i<9;++i) {
        int x=500+(rooms[i].x-minx)*cellx,y=252+(rooms[i].y-miny)*celly;
        test_rect(x,y,11,10,rooms[i].seen?1:9);
        test_rect(x+1,y+1,9,8,i==current?7:rooms[i].seen?rooms[i].clear?2:6:8);
        if(i==current)test_rect(x+4,y+3,3,3,1);
    }
    if(choice) {
        test_panel(84,108,472,143,2);demo_text(226,116,"选择强化",1);
        static const char *names[]={"穿透","多弹","吸血","护盾"};
        for(unsigned i=0;i<3;++i) {
            test_panel(100+(int)i*148,148,138,84,i==selected?7:9);
            demo_text(131+(int)i*148,172,names[(i+current)%4],i==selected?7:1);
            demo_text(116+(int)i*148,206,i==selected?"> ENTER":"  NEXT",2);
        }
    }
    if(complete||failed) {
        test_panel(180,135,280,85,complete?2:3);
        demo_text(260,150,complete?"探索完成":"挑战失败",1);
        demo_text(216,184,"ENTER 重新开始",7);
    }
    test_draw(0,first,test.quads_count-first,0,1,0);
    demo_diagnostics(1);
}
void rogue_capture(unsigned event)
{
    if(event==1){
        enter_room(8);px=320*256;py=255*256;
        spawn(0,170,235);spawn(1,180,130);spawn(2,480,185);spawn(0,455,245);
        for(unsigned i=0;i<132;++i)if(enemies[i].type==3&&enemies[i].hp>0){
            enemies[i].hp=420;enemies[i].age=35;
        }
    }
    if(event==2){
        enter_room(1);test.weapon=2;px=290*256;py=242*256;swing=9;aim=235;
        spawn(0,341,226);damage_text(350,201,28);burst(345,223,4,15);burst(348,225,9,9);
    }
    if(event==3){choice=1;selected=1;}
    if(event==4){for(unsigned i=0;i<9;++i)rooms[i].seen=1;}
    if(event==5){
        enter_room(1);px=320*256;py=250*256;
        for(unsigned i=0;i<6;++i)shoot((160+(int)i*58)*256,160*256,64,2,1);
    }
}
