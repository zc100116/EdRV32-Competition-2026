/* tower.c — R4 §6 acceptance; real rules/physics and premultiplied atlas sampling.
 * Native C, deterministic fixed steps, no LVGL or hardware.
 */
#include "tower.h"
#include "sprite_rot.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static tower_state game;
static tower_input hand = {120,220,1,true,0};
static void step(unsigned n) { while (n--) tower_step(&game,hand); }
static void grab_rotation(void)
{
    tower_init(&game,TOWER_FREE,1,0);
    int old = game.shelf[0];
    step(60);
    int body = game.world.grab.body;
    assert(body > 0 && game.blocks[body].kind == old && game.picked == 1);
    assert(game.next_block == 0 && game.shelf[0] != old);
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
    tower_init(&game,TOWER_FREE,2,0);
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
        tower_init(&game,TOWER_FREE,2,0);
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
static void stable_score(void)
{
    tower_init(&game,TOWER_HIGH,3,0);
    int id = tower_spawn(&game,0,640,340);
    phys_body *b = &game.world.bodies[id];
    b->awake = false;
    b->aabb.min.y = (TOWER_PLATFORM_Y-TOWER_TARGET)*PHYS_ONE;
    for (unsigned i = 0; i < 179; ++i) { ++game.ticks; tower_score(&game); }
    assert(game.phase == TOWER_BUILD);
    ++game.ticks;
    tower_score(&game);
    assert(game.phase == TOWER_BUILD); /* first sample establishes baseline */
    ++game.ticks;
    tower_score(&game);
    assert(game.phase == TOWER_RESULT && game.stars == 3 && game.height == TOWER_TARGET);
    tower_init(&game,TOWER_HIGH,3,0);
    game.ticks = 90*60;
    tower_score(&game);
    assert(game.phase == TOWER_RESULT && game.stars == 0);
    tower_init(&game,TOWER_QUAKE,3,0);
    game.ticks = 60*60;
    tower_score(&game);
    assert(game.phase == TOWER_SHAKE);
    game.ticks = 65*60;
    tower_score(&game);
    assert(game.phase == TOWER_SETTLE && game.stable == 0);
    id = tower_spawn(&game,0,640,400);
    b = &game.world.bodies[id];
    b->awake = false;
    b->aabb.min.y = 460*PHYS_ONE;
    for (unsigned i = 0; i < 181; ++i) { ++game.ticks; tower_score(&game); }
    assert(game.phase == TOWER_RESULT && game.stars == 2 && game.height == 160);
    tower_init(&game,TOWER_FREE,3,0);
    id = tower_spawn(&game,0,640,400);
    b = &game.world.bodies[id];
    b->awake = false;
    b->aabb.min.y = 460*PHYS_ONE;
    tower_score(&game);
    game.stable = 100;
    b->aabb.min.y -= 2*PHYS_ONE;
    tower_score(&game);
    assert(game.stable == 0);
    phys_grab_create(&game.world,id,b->position,2000*PHYS_ONE);
    tower_score(&game);
    assert(game.stable == 0);
}
static void geometry(void)
{
    tower_init(&game,TOWER_FREE,9,0);
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
void tower_geo_test(const char *art_path);
int main(int argc, char **argv)
{
    assert(argc == 2);
    geometry(); grab_rotation(); impacts(); stable_score(); tower_geo_test(argv[1]);
    puts("PASS tower grab/release/regrab, rotation latch, replenishment, glass drop/threshold,"
         " particles, stability, challenges, 36 geometries, frame counts and alpha");
}
