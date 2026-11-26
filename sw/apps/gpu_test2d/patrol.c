/* patrol.c — gpu-spec 2.8–2.9; Prism Patrol original bullet-hell test.
 * GPU advances object records; CPU consumes hit/free lists and replenishes slots.
 * Clock domain: frame thread, synchronous GPU ownership boundaries.
 */
#include "test.h"
#include <stdio.h>
#include <string.h>
static const unsigned loads[7] = {1000, 2000, 5000, 10000, 20000, 50000, 100000};
/* Keep additive glow readable as overlap grows; object populations stay unchanged. */
static const unsigned glow_alpha[7] = {190, 140, 80, 50, 36, 24, 16};
enum { ENEMIES = 12, SHOTS = 18, ENEMY_FIRST = ENEMIES+SHOTS };
static unsigned boss_health;
static unsigned invulnerable;
static unsigned flash;
static unsigned boss_flash;
static unsigned enemy_flash[ENEMIES];
static unsigned effect_next;
static unsigned drop_next;
struct burst { int x; int y; unsigned born; unsigned damage; };
static struct burst bursts[16];
struct pickup { int x; int y; unsigned alive; unsigned kind; };
static struct pickup drops[12];
struct trail { int x; int y; unsigned born; };
static struct trail missile_trail[32][6];
static void explosion(int x, int y, unsigned damage)
{
    bursts[effect_next++%16] = (struct burst){x,y,test.tick,damage};
    if (damage >= 10) {
        unsigned slot = drop_next++%12;
        drops[slot] = (struct pickup){x,y,1,slot%3 == 0};
    }
}
static int boss_x;
void test2d_capture(unsigned event)
{
    if (event == 1) {
        explosion(boss_x+92, 174, 8);
        bursts[(effect_next-1)%16].born = test.tick-8;
    }
    if (event == 2) {
        explosion(448, 194, 25);
        explosion(483, 216, 10);
        explosion(420, 220, 10);
    }
}
static int target[8][4];
static unsigned get(const struct gpu_object *o, unsigned offset, uint32_t mask, unsigned pos)
{
    return (o->word[offset/4] & mask) >> pos;
}
static void put(struct gpu_object *o, unsigned offset, uint32_t mask, unsigned pos, unsigned value)
{
    o->word[offset/4] = (o->word[offset/4] & ~mask) | ((value << pos) & mask);
}
#define GET(o, f) get(o, EDRV32_GPU_OBJ_##f##_OFFSET, EDRV32_GPU_OBJ_##f##_MASK, \
                       EDRV32_GPU_OBJ_##f##_POS)
#define PUT(o, f, v) put(o, EDRV32_GPU_OBJ_##f##_OFFSET, EDRV32_GPU_OBJ_##f##_MASK, \
                         EDRV32_GPU_OBJ_##f##_POS, (unsigned)(v))
static int signed24(unsigned value)
{
    return (int)(value ^ 0x800000u)-0x800000;
}
static void spawn(unsigned index, int initial)
{
    struct gpu_object_args o = {.alive = 1, .alpha = 190, .w = 8, .h = 8,
        .col_hw = 2, .col_hh = 2, .tgt_mask = 1};
    if (index < ENEMIES) {
        o.px = (48+(index%6)*60+(index%6 >= 3 ? 232 : 0))*256;
        o.py = (initial ? 94+(index/6)*64 : 58)*256;
        o.vy = 28;
        o.life = 0;
        o.w = 32;
        o.h = 32;
        o.u0 = 64+(index%3)*32;
        o.col_hw = 10;
        o.col_hh = 8;
        o.alpha = 255;
    } else if (index < ENEMY_FIRST) {
        o.px = (unsigned)(test.player_x + ((int)(index%3)-1)*6)*256;
        o.py = (unsigned)(initial ? test.player_y-20-(int)(index-ENEMIES)*10 :
                          test.player_y-14)*256;
        o.vy = (uint32_t)(test.weapon == 1 ? -2400 : -1400);
        o.vx = test.weapon == 0 ? (unsigned)(((int)(index%3)-1)*250) : 0;
        if (test.weapon) {
            o.u0 = test.weapon == 2 ? 224 : 8;
            o.v0 = test.weapon == 2 ? 32 : 0;
            o.h = test.weapon == 1 ? 32 : 16;
            o.px = (unsigned)(test.player_x+((int)(index%2)*2-1)*9)*256;
        }
        o.tgt_mask = 254;
        o.u0 = test.weapon == 2 ? 224 : 8;
        o.w = 8;
        o.h = test.weapon == 1 ? 32 : 16;
        o.life = 72;
        o.pal_group = test.weapon == 2 ? 7 : 2;
    } else {
        o.alpha = test.mode == 1 ? glow_alpha[test.level] : 255;
        unsigned phase = (test.tick/240)%3;
        unsigned j = index-ENEMY_FIRST;
        unsigned angle = phase == 0 ? 12+(j%14)*104/13 :
                         phase == 1 ? (j%14)*256/14+(j/14)*5 :
                         (j%14)*256/14;
        angle = (angle+test.tick*(phase == 1 ? 2 : 0))&255;
        int vx = test_sine[(angle+64)&255]*420/16384;
        int vy = test_sine[angle]*420/16384;
        if (phase == 2) {
            vx = test_sine[(test.tick+index*9)&255]*320/16384;
            vy = 300+(int)(index%5)*40;
        }
        unsigned age = initial ? (index-ENEMY_FIRST)/14*6 : 0;
        int x = boss_x + vx*(int)age/256;
        int y = 126 + vy*(int)age/256;
        if (initial && test.mode != 1) {
            int radius = 22+(int)(j/14)*9;
            x = boss_x+test_sine[(angle+64)&255]*radius/16384;
            y = 126+test_sine[angle]*radius/16384;
            if (phase == 2) {
                x = 40+(int)(j%20)*28;
                y = 144+(int)(j/20)*12;
            }
        }
        if (initial && test.mode == 1) {
            x = 24+(int)((index*73)%592);
            y = 60+(int)((index*137)%272);
        }
        o.px = (unsigned)(x*256);
        o.py = (unsigned)(y*256);
        o.vx = (unsigned)vx;
        o.vy = (unsigned)vy;
        o.life = 180 + index%120;
        o.pal_group = phase == 0 ? 3 : phase == 1 ? 6 : 7;
    }
    gpu_object(test.objects+index, &o);
}
void test2d_init(void)
{
    test.objects_count = test.mode == 1 ? loads[test.level] : ENEMY_FIRST+280;
    test.alive_count = test.objects_count;
    test.hit_count = 0;
    test.free_count = 0;
    boss_health = 1200;
    boss_x = 320;
    invulnerable = 0;
    flash = 0;
    boss_flash = 0;
    memset(enemy_flash, 0, sizeof(enemy_flash));
    effect_next = 0;
    drop_next = 0;
    memset(bursts, 0, sizeof(bursts));
    memset(drops, 0, sizeof(drops));
    memset(missile_trail, 0, sizeof(missile_trail));
    for (unsigned i = 0; i < test.objects_count; ++i) spawn(i, 1);
}
static void software_step(void)
{
    test.hit_count = 0;
    test.free_count = 0;
    test.alive_count = 0;
    for (unsigned i = 0; i < test.objects_count; ++i) {
        struct gpu_object *o = test.objects+i;
        if (!GET(o, ALIVE)) continue;
        int vx = (int16_t)GET(o, VX);
        int vy = (int16_t)GET(o, VY);
        int px = signed24(GET(o, PX))+vx;
        int py = signed24(GET(o, PY))+vy;
        unsigned life = GET(o, LIFE);
        unsigned expired = life == 1;
        if (life) --life;
        PUT(o, PX, px);
        PUT(o, PY, py);
        PUT(o, LIFE, life);
        int x = px >> 8;
        int y = py >> 8;
        if (expired || x < -64 || x >= 704 || y < -64 || y >= 424) {
            PUT(o, ALIVE, 0);
            test.released[test.free_count++] = i;
            continue;
        }
        ++test.alive_count;
        unsigned mask = GET(o, TGT_MASK);
        int hw = (int)GET(o, COL_HW);
        int hh = (int)GET(o, COL_HH);
        for (unsigned t = 0; t < 8; ++t)
            if ((mask & (1u << t)) && x-hw < target[t][2] && target[t][0] < x+hw &&
                y-hh < target[t][3] && target[t][1] < y+hh)
                test.hits[test.hit_count++] = i | (t << 24);
    }
}
void test2d_update(uint32_t keys)
{
    if (keys & PLAT_LEFT) test.player_x -= 4;
    if (keys & PLAT_RIGHT) test.player_x += 4;
    if (keys & PLAT_UP) test.player_y -= 4;
    if (keys & PLAT_DOWN) test.player_y += 4;
    if (test.player_x < 20) test.player_x = 20;
    if (test.player_x > 620) test.player_x = 620;
    if (test.player_y < 64) test.player_y = 64;
    if (test.player_y > 316) test.player_y = 316;
    boss_x = 320+test_sine[(test.tick/2)&255]*65/16384;
    target[0][0] = test.player_x-3;
    target[0][1] = test.player_y-3;
    target[0][2] = test.player_x+3;
    target[0][3] = test.player_y+3;
    target[1][0] = boss_x-40;
    target[1][1] = 68;
    target[1][2] = boss_x+40;
    target[1][3] = 146;
    for (unsigned i = 0; i < ENEMIES; ++i) {
        struct gpu_object *o = test.objects+i;
        if (enemy_flash[i]) --enemy_flash[i];
        PUT(o, PAL_GROUP, enemy_flash[i] && (test.tick&1) ? 15 : 0);
        unsigned type = i%3;
        int vx = type == 0 ? test_sine[(test.tick*2+i*17)&255]/90 :
                 type == 1 ? ((test.tick/45+i)%2 ? 200 : -200) :
                 test_sine[(test.tick+i*23)&255]/48;
        PUT(o, VX, vx);
        PUT(o, VY, type == 2 ? 58 : 28);
        if (i < 6) {
            int x = (signed24(GET(o, PX))+vx)/256;
            int y = (signed24(GET(o, PY))+(type == 2 ? 58 : 28))/256;
            target[i+2][0] = x-12;
            target[i+2][1] = y-8;
            target[i+2][2] = x+12;
            target[i+2][3] = y+8;
        }
    }
    if (test.weapon == 2) for (unsigned i = ENEMIES; i < ENEMY_FIRST; ++i) {
        struct gpu_object *o = test.objects+i;
        int x = signed24(GET(o, PX))/256;
        int steering = (boss_x-x)*20;
        if (steering > 650) steering = 650;
        if (steering < -650) steering = -650;
        PUT(o, VX, steering);
    }
    for (unsigned i = 0; i < 12; ++i) if (drops[i].alive) {
        struct pickup *d = drops+i;
        ++d->y;
        int dx = test.player_x-d->x;
        int dy = test.player_y-d->y;
        if (dx*dx+dy*dy < 28*28) {
            if (d->kind) test.health = test.health > 80 ? 100 : test.health+20;
            else test.score += 50;
            d->alive = 0;
            test_sound(3);
        }
        if (d->y > 330) d->alive = 0;
    }
    if (test.tick%240 == 0) flash = 18;
    if (boss_flash) --boss_flash;
    for (unsigned t = 0; t < 8; ++t)
        gpu_collision_target(t, (int16_t)target[t][0], (int16_t)target[t][1],
                             (int16_t)target[t][2], (int16_t)target[t][3]);
    if (invulnerable) --invulnerable;
    if (flash) --flash;
    if (test.tick%9 == 0) test_sound(0);
    if (test.cpu) software_step();
}
void test2d_results(void)
{
    for (unsigned i = 0; i < test.hit_count; ++i) {
        unsigned index = gpu_hit_object(test.hits[i]);
        unsigned t = gpu_hit_target(test.hits[i]);
        if (t == 0 && !invulnerable) {
            if (test.health) --test.health;
            invulnerable = 20;
            flash = 20;
            explosion(test.player_x, test.player_y, 0);
            test_sound(1);
        } else if (t == 1 && index >= ENEMIES && index < ENEMY_FIRST) {
            ++test.score;
            unsigned damage = test.weapon == 0 ? 1 : test.weapon == 1 ? 3 : 8;
            boss_health = boss_health > damage ? boss_health-damage : 0;
            boss_flash = 5;
            if (test.tick%4 == 0) explosion(boss_x+(int)(index%7)*7-24, 96, damage);
            spawn(index, 0);
            test_sound(1);
        } else if (t > 1 && index >= ENEMIES && index < ENEMY_FIRST) {
            test.score += 10;
            flash = 24;
            explosion((target[t][0]+target[t][2])/2, (target[t][1]+target[t][3])/2, 10);
            spawn(t-2, 0);
            enemy_flash[t-2] = 5;
            spawn(index, 0);
            test_sound(2);
        }
    }
    for (unsigned i = 0; i < test.free_count; ++i)
        spawn(gpu_free_object(test.released[i]), 0);
    if (test.weapon == 2) for (unsigned i = 0; i < SHOTS; ++i) {
        const struct gpu_object *o = test.objects+ENEMIES+i;
        missile_trail[i][test.tick%6] = (struct trail){signed24(GET(o, PX))/256,
            signed24(GET(o, PY))/256+8, test.tick};
    }
    test.alive_count = test.objects_count;
    if (!boss_health) { boss_health = 1200; test.score += 500; test_sound(2); }
    if (!test.health) test.health = 100;
}
static void fin(int cx, int cy, unsigned angle)
{
    static const int local[4][2] = {{-16,-16},{16,-16},{16,16},{-16,16}};
    static const unsigned order[6] = {0,1,2,0,2,3};
    unsigned first = test.triangles;
    int scale = 22+test_sine[(test.tick*2)&255]*5/16384;
    for (unsigned i = 0; i < 6; ++i) {
        unsigned k = order[i];
        int x = local[k][0]*scale/22;
        int y = local[k][1]*scale/22;
        int rx = (x*test_sine[(angle+64)&255]-y*test_sine[angle])/16384;
        int ry = (x*test_sine[angle]+y*test_sine[(angle+64)&255])/16384;
        test_vertex(cx+rx, cy+ry, 0, 0xffff,
                    (k == 1 || k == 2 ? 255 : 224)*256, (k > 1 ? 32 : 0)*256, 0);
    }
    test_draw(1, first, 2, 0, 1, 0);
}

void test2d_scene(void)
{
    int shake = flash ? ((test.tick&1) ? 3 : -3) : 0;
    unsigned first = test.triangles;
    test_sprite(shake-2, -2, 644, 364, 0, 128, 255, 127);
    test_draw(1, first, 2, 6, 0, 0);
    first = test.quads_count;
    for (unsigned layer = 0; layer < 2; ++layer)
        for (unsigned i = 0; i < 42; ++i) {
            unsigned x = (i*137+layer*59)%640;
            unsigned y = (i*83+test.tick/(layer ? 2 : 6))%360;
            test_quad((int)x+shake, (int)y, layer ? 2 : 1, layer ? 2 : 1,
                      248, 248, layer ? 2 : 9, layer ? 170 : 200);
        }
    test_quad(50+shake, 100-(int)(test.tick/24%20), 96, 96, 128, 0, 0, 255);
    for (unsigned i = 0; i < 5; ++i)
        test_quad((i&1 ? 490 : 12)+(int)((i*47+test.tick/3)%120)+shake,
                  75+(int)((i*83+test.tick/2)%248), 32, 32, 224, 0, 0, 255);
    for (unsigned i = 0; i < 12; ++i) if (drops[i].alive)
        test_quad(drops[i].x-8, drops[i].y-8, 16, 16,
                  drops[i].kind ? 144 : 128, 96, 0, test.tick%20 < 10 ? 255 : 150);
    test_draw(0, first, test.quads_count-first, 6, 1, 0);
    first = test.quads_count;
    test_quad(boss_x-64+shake, 64, 128, 96, 0, 0,
              boss_flash && test.tick%8 == 0 ? 15 : 0, 255);
    test_draw(0, first, test.quads_count-first, 6, 1, 0);
    first = test.quads_count;
    test_quad(test.player_x-16+shake, test.player_y-16, 32, 32, 32, 0,
              invulnerable && (test.tick&2) ? 15 : 0, 255);
    test_draw(0, first, test.quads_count-first, 0, 1, 0);
    for (unsigned i = 0; i < 4; ++i) {
        unsigned a = (test.tick+i*64)&255;
        unsigned leg = a*3/256;
        unsigned t = a*3%256;
        static const int path[3][2] = {{-65,-20},{65,-20},{0,44}};
        unsigned next = (leg+1)%3;
        fin(boss_x+(path[leg][0]*(256-(int)t)+path[next][0]*(int)t)/256+shake,
            110+(path[leg][1]*(256-(int)t)+path[next][1]*(int)t)/256, a);
    }
    /* Enemy sprites and glowing ammunition share hardware OBJ_STEP draw ordering. */
    test_draw(2, 0, ENEMIES, 0, 1, 0);
    test_draw(2, ENEMIES, test.objects_count-ENEMIES, 0, 2, 0);
    first = test.quads_count;
    test_quad(test.player_x-6+shake, test.player_y+12, 12, 24,
              16+(test.tick/4%4)*12, 32, 0, 255);
    test_quad(test.player_x-32+shake, test.player_y-32, 64, 64, 64, 32,
              2, invulnerable ? 230 : 80+(test.tick%20)*3);
    if (test.weapon == 2) for (unsigned i = 0; i < SHOTS; ++i)
        for (unsigned j = 0; j < 6; ++j) {
            const struct trail *t = &missile_trail[i][j];
            unsigned age = test.tick-t->born;
            if (t->born && age < 6)
                test_quad(t->x-4, t->y-4, 8, 8, 0, 0, 7, 190-age*28);
        }
    for (unsigned i = 0; i < 16; ++i) {
        struct burst *b = bursts+i;
        unsigned age = test.tick-b->born;
        if (!b->born || age >= 40) continue;
        if (b->damage && b->damage < 8) {
            if (age < 10)
                test_quad(b->x-4+shake, b->y-4, 8, 8, 0, 0, 7, 220-age*20);
            continue;
        }
        test_quad(b->x-16+shake, b->y-16, 32, 32, 128+(age/5%4)*32, 64+(age/20)*32, 0, 255);
        for (unsigned j = 0; j < 12; ++j) {
            unsigned a = (j*21+i*7)&255;
            int radius = (int)age*2;
            test_quad(b->x+test_sine[(a+64)&255]*radius/16384-4+shake,
                      b->y+test_sine[a]*radius/16384-4, 8, 8, 0, 0, j%2 ? 4 : 7,
                      240-age*6);
        }
    }
    test_draw(0, first, test.quads_count-first, 0, 2, 0);
    if (test.weapon == 1 && test.player_y > 72) {
        unsigned beam = test.triangles;
        test_sprite(test.player_x-5, 56, 10, test.player_y-70, 8, 0, 8, 32);
        test_draw(1, beam, 2, 0, 2, 0);
    }
    unsigned start = test.triangles;
    for (unsigned i = 0; i < 16; ++i) {
        struct burst *b = bursts+i;
        unsigned age = test.tick-b->born;
        if (!b->born || b->damage < 3 || age >= 40) continue;
        char number[12];
        snprintf(number, sizeof(number), "+%u", b->damage);
        unsigned scale = age < 6 ? 384+age*32 : age < 12 ? 576-(age-6)*48 : 288;
        test_scaled_text(b->x-12, b->y-20-(int)age, number, scale,
                         b->damage >= 10 ? 0xffa5 : 0x7fff);
    }
    test_draw(1, start, (test.triangles-start)/3, 0, 1, 0);
}
void test2d_hud(void)
{
    test_panel(234, 8, 172, 36, 3);
    test_text(246, 10, "赤焰核心", 3);
    test_rect(244, 30, 152, 8, 9);
    test_rect(246, 32, boss_health*148/1200, 4, 3);
    static const char *phases[3] = {"RADIAL", "SPIRAL", "WAVE"};
    test_text(320, 10, phases[(test.tick/240)%3], 7);
    static const char *weapons[3] = {"散射", "激光", "追踪导弹"};
    test_panel(480, 8, 148, 36, 2);
    test_quad(490, 18, 8, 16, test.weapon == 2 ? 224 : 8,
              test.weapon == 2 ? 32 : 0, 2, 255);
    test_text(508, 10, "武器", 2);
    test_text(508, 26, weapons[test.weapon], 1);
}
