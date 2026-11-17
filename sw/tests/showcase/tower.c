/* tower.c — R4 §6 acceptance; real rules/physics and premultiplied atlas sampling.
 * Native C, deterministic fixed steps, no LVGL or hardware.
 */
#include "tower.h"
#include "sprite_rot.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static tower_state game;
static tower_input hand = {640,580,1,true,0};
static void step(unsigned n) { while (n--) tower_step(&game,hand); }
static void grab_rotation(void)
{
    tower_init(&game,1);
    int body = tower_spawn(&game,0,640,580);
    step(60);
    assert(game.world.grab.body == body && game.picked == 1);
    hand.cls = 2;
    phys_q initial = game.world.grab.target_angle;
    step(1);
    assert(game.rotations == 1 && game.world.grab.target_angle == initial+PHYS_PI/2);
    step(30);
    assert(game.rotations == 1);
    hand.cls = 8;
    step(1);
    hand.cls = 2;
    step(1);
    assert(game.rotations == 1);
    hand.cls = 5;
    step(1);
    hand.cls = 2;
    step(1);
    assert(game.rotations == 1); /* Grip holds the joint but does not re-arm rotation. */
    hand.cls = 1;
    step(1);
    hand.cls = 2;
    step(1);
    assert(game.rotations == 2);
    hand.x = 640;
    hand.y = 300;
    step(120);
    hand.closed = false;
    step(1);
    assert(game.world.grab.body == -1 && game.released == 1);
    /* An existing body can be picked again, not just shelf-generated blocks. */
    phys_body *b = &game.world.bodies[body];
    hand.x = b->position.x/PHYS_ONE;
    hand.y = b->position.y/PHYS_ONE;
    hand.closed = true;
    hand.cls = 1;
    game.world.gravity.y = 0;
    b->velocity = (phys_vec){0,0};
    b->angular_velocity = 0;
    step(60);
    assert(game.world.grab.body == body && game.picked == 2);
}
static void impacts(void)
{
    tower_init(&game,2);
    int id = tower_spawn(&game,30,640,200);
    game.world.bodies[id].max_normal_impulse = TOWER_GLASS_IMPULSE;
    tower_impacts(&game);
    assert(game.world.bodies[id].used && game.broken == 0);
    game.world.bodies[id].max_normal_impulse++;
    tower_impacts(&game);
    assert(!game.world.bodies[id].used && game.broken == 1);
    assert(game.particles[0].life == 60);
    hand = (tower_input){640,200,0,false,0};
    step(60);
    for (unsigned i = 0; i < TOWER_PARTICLES; ++i) assert(!game.particles[i].life);
    /* Calibrate the threshold with actual 80 px glass blocks at one/two heights. */
    for (unsigned height = 80; height <= 160; height += 80) {
        tower_init(&game,2);
        id = tower_spawn(&game,30,640,580-(int)height);
        int peak = 0;
        for (int t = 0; t < 240; ++t) {
            phys_step(&game.world);
            if (game.world.bodies[id].max_normal_impulse > peak)
                peak = game.world.bodies[id].max_normal_impulse;
        }
        printf("glass drop=%u impulse=%d\n",height,peak/PHYS_ONE);
        fflush(stdout);
        game.world.bodies[id].max_normal_impulse = peak;
        tower_impacts(&game);
        assert(game.broken == (height == 160));
    }
}
static void geometry(void)
{
    tower_init(&game,9);
    for (int kind = 0; kind < TOWER_KINDS; ++kind) {
        int id = tower_spawn(&game,kind,640,300);
        phys_body *b = &game.world.bodies[id];
        assert(b->mass > 0 && b->inertia > 0 && b->inv_inertia > 0);
        phys_body_remove(&game.world,id);
    }
    for (unsigned i = 1; i < PHYS_MAX_BODIES; ++i)
        assert(tower_spawn(&game,0,640,300) == (int)i);
    assert(tower_spawn(&game,0,640,300) == -1);
    assert(game.world.bodies[game.platform].aabb.min.x == TOWER_PLATFORM_X*PHYS_ONE);
    assert(game.world.bodies[game.platform].aabb.min.y == TOWER_PLATFORM_Y*PHYS_ONE);
}
static unsigned count(void)
{
    tower_snapshot snap;
    tower_snapshot_copy(&game,&snap);
    return snap.bodies;
}
static void summon_test(void)
{
    tower_init(&game,42);
    hand = (tower_input){100,200,8,false,0};
    step(17);
    assert(count() == 0);
    step(1);
    assert(count() == 1);
    phys_body *b = &game.world.bodies[1];
    assert(b->position.x/PHYS_ONE == TOWER_PLATFORM_X && b->aabb.max.y < 0);
    assert(b->angular_velocity >= -16384 && b->angular_velocity <= 16384);
    step(40);
    assert(game.sequence == 1);
    hand.cls = 0;
    step(1);
    hand.cls = 8;
    hand.x = 1200;
    step(18);
    assert(game.sequence == 2);
    assert(game.world.bodies[2].position.x/PHYS_ONE == TOWER_PLATFORM_X+TOWER_PLATFORM_W);
    phys_grab_create(&game.world,1,b->position,2000*PHYS_ONE);
    hand.closed = true;
    hand.cls = 1;
    step(1);
    hand.cls = 8;
    step(30);
    tower_summon(&game,640);
    assert(game.sequence == 2);
    phys_grab_release(&game.world);
    /* Fill at rest: keep the 24 blocks in place while observing the fade. */
    tower_init(&game,42);
    game.world.gravity.y = 0;
    for (int i = 0; i < 24; ++i) {
        int id = tower_spawn(&game,0,300+i*28,400);
        game.world.bodies[id].awake = false;
    }
    tower_summon(&game,640);
    assert(count() == 24 && game.fading == 1 && game.sequence == 24);
    hand = (tower_input){640,200,0,false,0};
    step(9);
    tower_snapshot snap;
    tower_snapshot_copy(&game,&snap);
    assert(snap.blocks[1].opacity > 0 && snap.blocks[1].opacity < 255);
    step(8);
    assert(game.sequence == 24);
    step(1);
    assert(game.sequence == 25 && count() == 24 && game.fading == -1);
    assert(game.blocks[1].born == 25 && game.world.bodies[1].aabb.max.y < 0);
    /* All 36 kinds occur; the fixed seed produces approximately one-third balls. */
    tower_init(&game,42);
    unsigned frequencies[36] = {0}, balls = 0;
    for (int n = 0; n < 3600; ++n) {
        tower_summon(&game,640);
        ++frequencies[game.blocks[1].kind];
        balls += game.blocks[1].kind%6 == 5;
        phys_body_remove(&game.world,1);
    }
    for (int k = 0; k < 36; ++k) assert(frequencies[k]);
    printf("summon seed=42 balls=%u/3600\n",balls);
    assert(balls > 1080 && balls < 1320);
    int id = tower_spawn(&game,0,100,800);
    tower_impacts(&game);
    assert(!game.world.bodies[id].used);
}
#include "tower_scenes.h"
static void stability(void)
{
    hand = (tower_input){640,100,0,false,0};
    for (unsigned scene = 0; scene < 3; ++scene) {
        tower_scene(&game,scene);
        tower_snapshot first, now;
        unsigned asleep = 0, changes = 0;
        for (unsigned t = 1; t <= 90; ++t) {
            tower_step(&game,hand);
            tower_snapshot_copy(&game,&first);
            if (!first.awake && !asleep) asleep = t;
        }
        printf("jitter scene=%u slept_step=%u awake_at_90=%u\n",scene,asleep,first.awake);
        fflush(stdout);
        unsigned awake_samples = 0;
        for (unsigned t = 0; t < 180; ++t) {
            tower_step(&game,hand);
            tower_snapshot_copy(&game,&now);
            awake_samples += now.awake;
            assert(now.bodies == 5);
            for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
                const tower_render_block *a = &first.blocks[i], *b = &now.blocks[i];
                changes += a->used != b->used || (a->used &&
                    (a->x != b->x || a->y != b->y || a->frame != b->frame));
            }
        }
        printf("jitter scene=%u display_changes_3s=%u\n",scene,changes);
        assert(asleep && first.awake == 0 && first.bodies == 5);
        assert(changes == 0 && awake_samples == 0);
        /* A sleeping upper body must fall when its support is removed. */
        if (!scene) {
            phys_q y = game.world.bodies[2].position.y;
            phys_body_remove(&game.world,1);
            step(20);
            assert(game.world.bodies[2].position.y > y+PHYS_ONE);
        }
    }
}
void tower_geo_test(const char *art_path);
int main(int argc, char **argv)
{
    assert(argc == 2);
    geometry(); grab_rotation(); impacts(); summon_test(); stability(); tower_geo_test(argv[1]);
    puts("PASS tower grab/release/regrab, rotation latch, free play, glass drop/threshold,"
         " particles, summons/fade, three stable scenes, 36 geometries, frame counts and alpha");
}
