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
static unsigned current, count, roll, cooldown, angle, swing, hitstop, shake;
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
        test.palettes[12*256+i]=0xf0000|test_color(r+((255-r)/4),g*3/4,b*3/4);
    }
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
    char text[100];
    snprintf(text, sizeof(text), "%s %s %u  BLK %u FPS %u.%u CPU %u.%03u GPU %u us",
             test.mode ? "STRESS" : "PLAY", test.game == 3 ? "OBJ" : "TRI",
             test.game == 3 ? test.alive_count : test.triangles/3, blocks,
             test.fps10/10, test.fps10%10, test.cpu_us/1000, test.cpu_us%1000, test.gpu_us);
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
        particles[i] = (struct particle){x*256,y*256,0,-220,30,7,amount};
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
    r->seen = 1;
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
    if (choice) {
        if (pressed&PLAT_LEFT) selected=(selected+2)%3;
        if (pressed&PLAT_RIGHT) selected=(selected+1)%3;
        if (pressed&PLAT_A) { ++item[(selected+current)%4]; choice=0; }
        return;
    }
    if (complete || failed) { if (pressed&PLAT_A) rogue_init(); return; }
    for (unsigned i = 0; i < 512; ++i) if (particles[i].life) {
        struct particle *p = &particles[i]; --p->life;
        p->x+=p->vx; p->y+=p->vy; if (!p->text) p->vy+=25;
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
    if(r->door && r->door<16) ++r->door;
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
    if(slot==4){
        unsigned first=test.triangles;
        test_sprite(x-48,y-48,96,96,0,64,64,64);
        if(white)for(unsigned i=first;i<test.triangles;++i)
            test.vertices[i].word[2]=(test.vertices[i].word[2]&65535)|(0xffffu<<16);
    }else test_quad(x-(int)size/2,y-(int)size/2,size,size,
                   (slot%4)*64,(slot/4)*64,white?15:0,255);
}
static void rotated(int x,int y,unsigned a,int length,unsigned color)
{
    static const int corner[6][2]={{0,-7},{1,-7},{1,7},{0,-7},{1,7},{0,7}};
    for(unsigned i=0;i<6;++i) {
        int lx=corner[i][0]*length,ly=corner[i][1];
        test_vertex(x+(lx*cs(a)-ly*sn(a))/16384,y+(lx*sn(a)+ly*cs(a))/16384,0,
            color,(64+(corner[i][0]?63:0))*256,(64+(corner[i][1]>0?63:0))*256,0);
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
    for(int y=48;y<336;y+=32) for(int x=32;x<608;x+=32)
        test_quad(x+sx,y+sy,32,32,(unsigned)((x/32+y/32+current)%3)*32,0,current%2?12:0,255);
    for(int x=32;x<608;x+=32) {
        test_quad(x,48,32,20,96,0,0,255);test_quad(x,316,32,20,96,0,0,255);
    }
    for(int y=64;y<316;y+=28) {
        test_quad(32,y,18,28,96,0,0,255);test_quad(590,y,18,28,96,0,0,255);
    }
    for(unsigned i=0;i<9;++i) if(i!=current) {
        int dx=rooms[i].x-rooms[current].x,dy=rooms[i].y-rooms[current].y;
        if(abs(dx)+abs(dy)!=1)continue;
        int x=dx==0?296:dx>0?584:32,y=dy==0?164:dy>0?310:48;
        unsigned w=dx?24:48,h=dx?48:20;
        test_quad(x,y,w,h,128,0,0,255);
        if(rooms[current].clear)
            test_quad(x+4,y+4,w-8,(h-8)*(rooms[current].door?rooms[current].door:16)/16,
                      160,0,0,255);
    }
    for(unsigned k=0;k<64;++k)if(loot[k].alive)
        test_quad(loot[k].x-6,loot[k].y-6,12,12,64,96,0,255);
    test_draw(0,first,test.quads_count-first,6,0,0);
    first=test.quads_count;
    unsigned actors_first=test.triangles;
    if(rooms[current].type==2)actor(320,180,6,48,0);
    if(rooms[current].type==3)actor(320,180,7,48,0);
    for(unsigned i=0;i<132;++i)if(enemies[i].hp>0) {
        struct enemy *e=&enemies[i];
        actor(e->x/256+sx,e->y/256+sy,e->type==3?4:e->type==4?3:e->type+1,
              e->type==3?64:e->type==4?20:32,e->flash);
    }
    if(roll)for(int i=3;i>0;--i)
        test_quad(px/256-16-cs(angle)*i/1500,py/256-16-sn(angle)*i/1500,32,32,0,0,2,65);
    actor(px/256+sx,py/256+sy,0,32,flash && (test.tick&2));
    test_draw(0,first,test.quads_count-first,0,1,0);
    test_draw(1,actors_first,(test.triangles-actors_first)/3,0,1,0);
    first=test.triangles;
    if(test.weapon<2){
        gun(px/256,py/256,(unsigned)aim,test.weapon?22:15,5,0x1085);
        gun(px/256,py/256,(unsigned)aim,test.weapon?20:13,3,test.weapon?0xfd29:0x3fff);
    }
    if(swing) for(unsigned t=0;t<4;++t)
        rotated(px/256,py/256,(unsigned)(aim-48+(10-swing)*10-(int)t*9),48-t*4,
                t?test_color(30,100+30*t,150+20*t):0xffff);
    test_draw(1,first,(test.triangles-first)/3,0,1,0);
    first=test.triangles;
    if(swing)for(unsigned j=0;j<12;++j) {
        unsigned a=(unsigned)(aim-52+(10-swing)*10-(int)j*5);
        int x=px/256,y=py/256;
        test_vertex(x+cs(a)*55/16384,y+sn(a)*55/16384,0,0x3fff,256,256,0);
        test_vertex(x+cs(a+5)*55/16384,y+sn(a+5)*55/16384,0,0x3fff,256,256,0);
        test_vertex(x+cs(a+5)*40/16384,y+sn(a+5)*40/16384,0,0x3fff,256,256,0);
        test_vertex(x+cs(a)*55/16384,y+sn(a)*55/16384,0,0x3fff,256,256,0);
        test_vertex(x+cs(a+5)*40/16384,y+sn(a+5)*40/16384,0,0x3fff,256,256,0);
        test_vertex(x+cs(a)*40/16384,y+sn(a)*40/16384,0,0x3fff,256,256,0);
    }
    test_draw(1,first,(test.triangles-first)/3,0,2,0);
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
        if(p->color==9)test_quad(p->x/256,p->y/256,3,2,248,248,7,255);
        else test_quad(p->x/256,p->y/256,4,4,0,96,p->color,220);
    }
    for(unsigned i=0;i<6;++i) {
        int x=i%2?565:60,y=85+(int)(i/2)*95;
        test_quad(x-12,y-12,32,32,16,96,i%2?4:2,140+(test.tick+i*13)%70);
    }
    test_draw(0,first,test.quads_count-first,6,2,0);
    test_draw(2,0,test.objects_count,6,2,0);
    test.alive_count=active;
    first=test.quads_count;
    for(unsigned i=0;i<512;++i)if(particles[i].life&&particles[i].text) {
        char number[12];snprintf(number,sizeof(number),"%u",particles[i].text);
        demo_text(particles[i].x/256,particles[i].y/256,number,7);
    }
    test_panel(8,8,200,36,2);demo_text(16,10,"棱炉地宫",1);
    test_rect(16,28,100,6,9);test_rect(16,28,test.health,6,3);
    char s[80];snprintf(s,sizeof(s),"SEED %08x",initial_seed);demo_text(218,47,s,9);
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
    int minx=0,miny=0;
    for(unsigned i=0;i<9;++i){
        if(rooms[i].x<minx)minx=rooms[i].x;
        if(rooms[i].y<miny)miny=rooms[i].y;
    }
    for(unsigned i=0;i<9;++i)if(rooms[i].seen||i==current) {
        int x=501+(rooms[i].x-minx)*13,y=253+(rooms[i].y-miny)*12;
        test_rect(x,y,10,9,i==current?7:rooms[i].clear?2:6);
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
        for(unsigned i=0;i<132;++i)if(enemies[i].type==3&&enemies[i].hp>0){
            enemies[i].hp=420;enemies[i].age=35;
        }
    }
    if(event==2){test.weapon=2;swing=9;aim=220;spawn(0,355,220);}
    if(event==3){choice=1;selected=1;}
    if(event==4){for(unsigned i=0;i<9;++i)rooms[i].seen=1;}
    if(event==5){enter_room(1);px=320*256;py=250*256;}
}
