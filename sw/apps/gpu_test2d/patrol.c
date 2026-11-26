/* patrol.c — gpu-spec 2.8–2.9; Prism Patrol original bullet-hell test.
 * GPU advances object records; CPU consumes hit/free lists and replenishes slots.
 * Clock domain: frame thread, synchronous GPU ownership boundaries.
 */
#include "test.h"
#include <stdio.h>
#include <string.h>
static const unsigned loads[7] = {1000, 2000, 5000, 10000, 20000, 50000, 100000};
static unsigned boss_health;
static unsigned invulnerable;
static unsigned flash;
static unsigned last_damage;
static int boss_x;
static int target[8][4];
static unsigned enemy_tick[6];
static int enemy_y[6];
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
    if (index < 24) {
        o.px = (80+(index%8)*68)*256;
        o.py = (initial ? 75+(index/8)*28 : 58)*256;
        o.vy = 60;
        o.life = 0;
        if (index < 6) {
            enemy_tick[index] = test.tick;
            enemy_y[index] = initial ? 75 : 58;
        }
        o.w = 32;
        o.h = 32;
        o.u0 = 64;
        o.col_hw = 10;
        o.col_hh = 8;
        o.alpha = 255;
    } else if (index < 88) {
        o.px = (unsigned)(test.player_x + ((int)(index%3)-1)*6)*256;
        o.py = (unsigned)(initial ? 60+(int)(index-24)*4 : test.player_y-14)*256;
        o.vy = (uint32_t)-1400;
        o.tgt_mask = 254;
        o.life = 72;
        o.pal_group = 2;
    } else {
        unsigned phase = (test.tick/240)%3;
        unsigned angle = (index*97 + test.tick*(phase == 1 ? 3 : 1)) & 255;
        int vx = test_sine[(angle+64)&255]*420/16384;
        int vy = test_sine[angle]*420/16384;
        if (phase == 2) {
            vx = test_sine[(test.tick+index*9)&255]*320/16384;
            vy = 300+(int)(index%5)*40;
        }
        unsigned age = initial ? index*137%180 : 0;
        int x = boss_x + vx*(int)age/256;
        int y = 96 + vy*(int)age/256;
        if (initial) {
            x = 24+(int)((index*73)%592);
            y = 60+(int)((index*137)%272);
        }
        o.px = (unsigned)(x*256);
        o.py = (unsigned)(y*256);
        o.vx = (unsigned)vx;
        o.vy = (unsigned)vy;
        o.life = 180 + index%120;
        o.pal_group = phase == 0 ? 3 : phase == 1 ? 7 : 2;
    }
    gpu_object(test.objects+index, &o);
}
void test2d_init(void)
{
    test.objects_count = test.mode == 1 ? loads[test.level] : 1500;
    test.alive_count = test.objects_count;
    test.hit_count = 0;
    test.free_count = 0;
    boss_health = 1200;
    boss_x = 320;
    invulnerable = 0;
    flash = 0;
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
    boss_x = 320+test_sine[(test.tick/2)&255]*120/16384;
    target[0][0] = test.player_x-3;
    target[0][1] = test.player_y-3;
    target[0][2] = test.player_x+3;
    target[0][3] = test.player_y+3;
    target[1][0] = boss_x-26;
    target[1][1] = 68;
    target[1][2] = boss_x+26;
    target[1][3] = 120;
    for (unsigned t = 2; t < 8; ++t) {
        /* Six target boxes follow deterministic formation trajectories, no table scan. */
        int x = 80+(int)(t-2)*68;
        int y = enemy_y[t-2]+(int)(((test.tick-enemy_tick[t-2])*60)/256);
        target[t][0] = x-12;
        target[t][1] = y-8;
        target[t][2] = x+12;
        target[t][3] = y+8;
    }
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
            test_sound(1);
        } else if (t == 1 && index >= 24 && index < 88) {
            ++test.score;
            if (boss_health) --boss_health;
            flash = 12;
            last_damage = 1;
            spawn(index, 0);
            test_sound(1);
        } else if (t > 1 && index >= 24 && index < 88) {
            test.score += 10;
            flash = 24;
            last_damage = 10;
            spawn(t-2, 0);
            spawn(index, 0);
            test_sound(2);
        }
    }
    for (unsigned i = 0; i < test.free_count; ++i)
        spawn(gpu_free_object(test.released[i]), 0);
    test.alive_count = test.objects_count;
    if (!boss_health) { boss_health = 1200; test.score += 500; test_sound(2); }
    if (!test.health) test.health = 100;
}
static void fin(int cx, int cy, unsigned angle)
{
    const int local[3][2] = {{-10,-14},{10,-14},{0,28}};
    unsigned first = test.triangles;
    int scale = 22+test_sine[(test.tick*2)&255]*5/16384;
    for (unsigned i = 0; i < 3; ++i) {
        int x = local[i][0]*scale/22;
        int y = local[i][1]*scale/22;
        int rx = (x*test_sine[(angle+64)&255]-y*test_sine[angle])/16384;
        int ry = (x*test_sine[angle]+y*test_sine[(angle+64)&255])/16384;
        test_vertex(cx+rx, cy+ry, 0, 0xffff, (250+(i==1 ? 3 : 0))*256,
                    (250+(i==2 ? 3 : 0))*256, 0);
    }
    test_draw(1, first, 1, 0, 1, 0);
}
void test2d_scene(void)
{
    unsigned first = test.quads_count;
    for (unsigned layer = 0; layer < 2; ++layer) {
        unsigned size = layer ? 32 : 64;
        for (unsigned y = 0; y < 7; ++y) for (unsigned x = 0; x < 11; ++x)
            test_quad((int)(x*64)-(int)((test.tick/(layer ? 2 : 5))%64),
                      (int)(y*64)-(int)((test.tick/(layer ? 1 : 3))%64),
                      size, size, 0, 64, 0, layer ? 100 : 255);
    }
    test_draw(0, first, test.quads_count-first, 0, 1, 0);
    first = test.quads_count;
    test_quad(boss_x-32, 64, 64, 64, 96, 0, 0, 255);
    test_quad(test.player_x-16, test.player_y-16, 32, 32, 32, 0, 0,
              invulnerable && (test.tick&2) ? 90 : 255);
    test_draw(0, first, test.quads_count-first, 0, 1, 0);
    for (unsigned i = 0; i < 4; ++i) {
        unsigned a = (test.tick+i*64)&255;
        fin(boss_x+test_sine[(a+64)&255]*46/16384,
            96+test_sine[a]*30/16384, a);
    }
    test_draw(2, 0, test.objects_count, 0, 1, 0);
    first = test.quads_count;
    for (unsigned i = 0; i < 48; ++i) {
        unsigned a = (i*41+test.tick*2)&255;
        unsigned age = (test.tick+i*7)%36;
        int x = boss_x+test_sine[(a+64)&255]*(int)age/4096;
        int y = 96+test_sine[a]*(int)age/4096;
        test_quad(x-8, y-8, 16, 16, 0, 32, 0, (36-age)*5);
    }
    if (flash) for (unsigned i = 0; i < 32; ++i) {
        unsigned a = (i*8)&255;
        int radius = (24-(int)flash)*3;
        test_quad(test.player_x+test_sine[(a+64)&255]*radius/16384-8,
                  test.player_y+test_sine[a]*radius/16384-8, 16, 16, 0, 32, 0, flash*8);
    }
    test_draw(0, first, test.quads_count-first, 0, 2, 0);
    first = test.quads_count;
    test_rect(boss_x-60, 55, boss_health/10, 3, 3);
    for (unsigned i = 0; flash && i < 5; ++i) {
        char number[12];
        snprintf(number, sizeof(number), "%u", last_damage);
        test_text(boss_x-45+(int)i*21, 120-(int)((test.tick+i*9)%42), number, 7);
    }
    static const char *phases[3] = {"RADIAL", "SPIRAL", "WAVE"};
    test_text(520, 56, phases[(test.tick/240)%3], 3);
    test_draw(0, first, test.quads_count-first, 0, 1, 0);
}
