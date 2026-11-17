/* tower.c — T-GRAB-EXP: fixed-step rules, contact stability and actual atlas art.
 * Native C; deterministic inputs and no display or hardware dependency.
 */
#include "tower.h"
#include "sprite_rot.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static tower_state game;
static void empty(void)
{
    tower_init(&game,42);
    for (int i = 1; i < PHYS_MAX_BODIES; ++i) phys_body_remove(&game.world,i);
}
static void initial(void)
{
    tower_init(&game,42);
    phys_vec positions[7];
    unsigned squares = 0, balls = 0, materials = 0;
    for (int i = 1; i <= 6; ++i) {
        positions[i] = game.world.bodies[i].position;
        squares += game.blocks[i].kind%2 == 0;
        balls += game.blocks[i].kind%2 == 1;
        materials |= 1u << (game.blocks[i].kind/2);
    }
    assert(squares == 3 && balls == 3 && materials == 63);
    for (unsigned t = 0; t < 180; ++t) {
        tower_step(&game,(tower_input){640,200,0,false,0});
        for (int i = 1; i <= 6; ++i) {
            const phys_body *b = &game.world.bodies[i];
            assert(!b->awake && b->position.x == positions[i].x &&
                   b->position.y == positions[i].y && b->angle == 0);
        }
    }
    puts("initial 3 squares + 3 balls: zero movement for 180 steps");
}
static void grab_test(void)
{
    empty();
    int id = tower_spawn(&game,6,640,300); /* steel square */
    tower_step(&game,(tower_input){690,300,1,true,0}); /* 10 px outside */
    assert(game.world.grab.body == id && game.picked == 1);
    assert(game.world.bodies[id].type == PHYS_KINEMATIC);
    for (int t = 0; t < 60; ++t) {
        tower_step(&game,(tower_input){690+t,200+t,1,true,0});
        assert(game.world.bodies[id].position.x == (640+t)*PHYS_ONE);
        assert(game.world.bodies[id].position.y == (200+t)*PHYS_ONE);
    }
    tower_step(&game,(tower_input){749,259,2,true,0});
    assert(game.rotations == 1 && game.world.bodies[id].angle == PHYS_PI/2);
    tower_step(&game,(tower_input){749,259,2,true,0});
    assert(game.rotations == 1);
    tower_step(&game,(tower_input){749,259,1,true,0});
    tower_step(&game,(tower_input){749,259,2,true,0});
    assert(game.rotations == 2);
    phys_vec stable = game.world.bodies[id].position;
    game.world.gravity.y = 0;
    game.world.bodies[id].angular_velocity = PHYS_ONE;
    tower_step(&game,(tower_input){949,59,0,false,0});
    assert(game.world.grab.body == -1 && game.released == 1);
    assert(game.world.bodies[id].type == PHYS_DYNAMIC);
    assert(game.world.bodies[id].velocity.x == 0 &&
           game.world.bodies[id].velocity.y == 0 &&
           game.world.bodies[id].angular_velocity == 0);
    assert(game.world.bodies[id].position.x == stable.x &&
           game.world.bodies[id].position.y == stable.y);
    game.world.gravity.y = 900*PHYS_ONE;
    tower_step(&game,(tower_input){949,59,0,false,0});
    assert(game.world.bodies[id].velocity.x == 0 &&
           game.world.bodies[id].velocity.y > 0 &&
           game.world.bodies[id].position.y > stable.y);
    /* A held steel block pushes a sleeping neighbor and stays on the cursor. */
    empty();
    id = tower_spawn(&game,6,600,400);
    int other = tower_spawn(&game,0,685,400);
    game.world.bodies[other].awake = false;
    game.world.gravity.y = 0;
    tower_step(&game,(tower_input){600,400,1,true,0});
    for (int x = 601; x <= 650; ++x)
        tower_step(&game,(tower_input){x,400,1,true,0});
    assert(game.world.bodies[id].position.x == 650*PHYS_ONE);
    assert(game.world.bodies[other].position.x > 700*PHYS_ONE);
    puts("immediate expanded-shape pick; steel cursor error=0; "
         "zero-speed stable release; kinematic push PASS");
}
static void side_walls(void)
{
    for (unsigned shape = 0; shape < 2; ++shape) {
        for (int side = 0; side < 2; ++side) {
            empty();
            int id = tower_spawn(&game,(int)shape,side ? 1200 : 80,200);
            phys_body *b = &game.world.bodies[id];
            b->velocity.x = (side ? 1200 : -1200)*PHYS_ONE;
            b->angular_velocity = PHYS_ONE;
            for (int t = 0; t < 180; ++t) {
                tower_step(&game,(tower_input){640,100,0,false,0});
                assert(b->used && b->aabb.min.x >= 0 &&
                       b->aabb.max.x <= 1280*PHYS_ONE);
            }
            /* Drag beyond either edge and rotate while against the wall. */
            tower_step(&game,(tower_input){b->position.x/PHYS_ONE,
                b->position.y/PHYS_ONE,1,true,0});
            assert(game.world.grab.body == id);
            tower_step(&game,(tower_input){side ? 1500 : -200,300,2,true,0});
            assert(b->aabb.min.x >= 0 && b->aabb.max.x <= 1280*PHYS_ONE);
            tower_step(&game,(tower_input){640,0,0,false,0});
            assert(b->velocity.x == 0);
        }
    }
    /* Falling beyond the old platform edges no longer deletes the block. */
    empty();
    int id = tower_spawn(&game,0,60,760);
    tower_step(&game,(tower_input){640,100,0,false,0});
    assert(game.world.bodies[id].used);
    assert(TOWER_PLATFORM_X == 0 && TOWER_PLATFORM_W == 1280);
    puts("full platform; dynamic/rotating/held side walls; no off-platform deletion PASS");
}
static void sleep_snap(void)
{
    empty();
    int id = tower_spawn(&game,0,640,580);
    phys_body *b = &game.world.bodies[id];
    phys_body_set_angle(&game.world,id,PHYS_PI/2+PHYS_PI*3/180);
    b->awake = false;
    tower_step(&game,(tower_input){640,100,0,false,0});
    assert(b->angle == PHYS_PI/2);
    phys_body_set_angle(&game.world,id,PHYS_PI/2+PHYS_PI*5/180);
    tower_step(&game,(tower_input){640,100,0,false,0});
    assert(b->angle == PHYS_PI/2+PHYS_PI*5/180);
}
static void summons(void)
{
    empty();
    unsigned kinds = 0;
    for (int n = 0; n < 120; ++n) {
        tower_summon(&game,n%2 ? 0 : 1280);
        const phys_body *b = &game.world.bodies[1];
        kinds |= 1u << game.blocks[1].kind;
        assert(b->aabb.min.x >= TOWER_PLATFORM_X*PHYS_ONE);
        assert(b->aabb.max.x <= (TOWER_PLATFORM_X+TOWER_PLATFORM_W)*PHYS_ONE);
        assert(b->aabb.max.y < 0);
        phys_body_remove(&game.world,1);
    }
    assert(kinds == (1u<<TOWER_KINDS)-1);
    puts("all 12 summon kinds inside platform PASS");
}
static void summon_timing_and_fade(void)
{
    empty();
    unsigned sequence = game.sequence;
    tower_input hand = {640,100,8,false,0};
    for (unsigned t = 0; t < 17; ++t) tower_step(&game,hand);
    assert(game.sequence == sequence);
    tower_step(&game,hand);
    assert(game.sequence == sequence+1);
    for (unsigned t = 0; t < 40; ++t) tower_step(&game,hand);
    assert(game.sequence == sequence+1);
    empty();
    game.world.gravity.y = 0;
    for (int i = 0; i < 24; ++i) {
        int id = tower_spawn(&game,0,300+i*28,400);
        game.world.bodies[id].awake = false;
    }
    sequence = game.sequence;
    tower_summon(&game,640);
    assert(game.fading == 1);
    hand.cls = 0;
    for (unsigned t = 0; t < 9; ++t) tower_step(&game,hand);
    tower_snapshot snap;
    tower_snapshot_copy(&game,&snap);
    assert(snap.bodies == 24 && snap.blocks[1].opacity > 0 && snap.blocks[1].opacity < 255);
    for (unsigned t = 0; t < 9; ++t) tower_step(&game,hand);
    assert(game.sequence == sequence+1 && game.fading == -1);
    assert(game.blocks[1].born == sequence+1 && game.world.bodies[1].aabb.max.y < 0);
}
static void heavy_corner(void)
{
    empty();
    game.world.gravity.y = 0;
    int id = tower_spawn(&game,6,640,580);
    phys_body *b = &game.world.bodies[id];
    phys_body_set_angle(&game.world,id,PHYS_PI/180);
    b->material.friction = 0;
    b->velocity.y = 1200*PHYS_ONE;
    phys_step(&game.world);
    printf("metal corner vy=%d angular=%d\n",b->velocity.y/PHYS_ONE,
           b->angular_velocity/PHYS_ONE);
    fflush(stdout);
    /* The right lower corner receives an upward impulse: clockwise velocity decreases. */
    assert(b->angular_velocity < 0 && b->velocity.y > 0);
}
static void impact_energy(void)
{
    empty();
    int lower = tower_spawn(&game,4,640,580);
    int upper = tower_spawn(&game,6,634,40);
    phys_body_set_angle(&game.world,upper,3688);
    double peak = 0;
    for (int t = 0; t < 360; ++t) {
        phys_step(&game.world);
        double energy = 0;
        for (int i = lower; i <= upper; ++i) {
            const phys_body *b = &game.world.bodies[i];
            double vx = b->velocity.x/65536.0, vy = b->velocity.y/65536.0;
            double angular = b->angular_velocity/65536.0;
            energy += b->mass/65536.0*(vx*vx+vy*vy)+
                b->inertia/65536.0*angular*angular;
        }
        if (energy > peak) peak = energy;
        /* Twice kinetic energy; 4e6 exceeds the initial drop energy by over 2x. */
        assert(energy < 4000000);
    }
    printf("metal onto ice peak twice-kinetic-energy=%.0f\n",peak);
}
static void impacts(void)
{
    for (int height = 80; height <= 160; height += 80) {
        empty();
        int id = tower_spawn(&game,10,640,580-height);
        int peak = 0;
        for (int t = 0; t < 240; ++t) {
            phys_step(&game.world);
            if (game.world.bodies[id].max_normal_impulse > peak)
                peak = game.world.bodies[id].max_normal_impulse;
        }
        game.world.bodies[id].max_normal_impulse = peak;
        tower_impacts(&game);
        printf("glass drop=%d impulse=%d\n",height,peak/PHYS_ONE);
        assert(game.broken == (height == 160));
    }
}
#include "tower_scenes.h"
static void stability(void)
{
    for (unsigned scene = 0; scene < 3; ++scene) {
        tower_scene(&game,scene);
        tower_input hand = {640,100,0,false,0};
        for (unsigned t = 0; t < 600; ++t) tower_step(&game,hand);
        tower_snapshot first, now;
        tower_snapshot_copy(&game,&first);
        printf("jitter scene=%u bodies=%u awake=%u\n",scene,first.bodies,first.awake);
        fflush(stdout);
        assert(first.bodies == 5 && first.awake == 0);
        for (unsigned t = 0; t < 180; ++t) {
            tower_step(&game,hand);
            tower_snapshot_copy(&game,&now);
            assert(now.bodies == 5 && now.awake == 0);
            for (int i = 1; i <= 5; ++i) {
                assert(now.blocks[i].x == first.blocks[i].x);
                assert(now.blocks[i].y == first.blocks[i].y);
                assert(now.blocks[i].angle == first.blocks[i].angle);
            }
        }
        if (scene == 0) {
            phys_q y = game.world.bodies[2].position.y;
            phys_body_remove(&game.world,1);
            for (unsigned t = 0; t < 20; ++t) tower_step(&game,hand);
            assert(game.world.bodies[2].position.y > y+PHYS_ONE);
        }
    }
}
void tower_geo_test(const char *art_path);
int main(int argc, char **argv)
{
    assert(argc == 2);
    initial(); grab_test(); side_walls(); sleep_snap(); summons(); summon_timing_and_fade();
    heavy_corner(); impact_energy(); impacts(); stability(); tower_geo_test(argv[1]);
    puts("PASS grablab rules, contact stability and GEO art");
}
