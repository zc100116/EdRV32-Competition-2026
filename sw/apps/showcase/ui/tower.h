/* tower.h — block workshop design §6 / T-PHYS-BLOCKS.
 * Free rigid-body play and render snapshots; application task owns the world.
 * Fixed 60 Hz integer simulation, no display or clock dependency.
 */
#ifndef SHOWCASE_TOWER_H
#define SHOWCASE_TOWER_H
#include "phys.h"
enum { TOWER_HZ = 60, TOWER_KINDS = 12, TOWER_PARTICLES = 48,
    TOWER_PLATFORM_X = 280, TOWER_PLATFORM_Y = 620, TOWER_PLATFORM_W = 720,
    TOWER_PLATFORM_H = 64, TOWER_SUMMON = 18, TOWER_FADE = 18,
    TOWER_GLASS_IMPULSE = 180 * PHYS_ONE, TOWER_DUST_IMPULSE = 80 * PHYS_ONE };
typedef struct { int x, y, cls; bool closed; unsigned lost; } tower_input;
typedef struct { int x, y, vx, vy; unsigned life, kind; } tower_particle;
typedef struct { int kind; unsigned dust_at, born; } tower_block;
typedef struct {
    phys_world world;
    tower_block blocks[PHYS_MAX_BODIES];
    tower_particle particles[TOWER_PARTICLES];
    tower_input hand;
    unsigned ticks, picked, released, rotations, particle_next, broken;
    unsigned summon_hold, sequence, fade_ticks;
    int platform, fading, pending_x;
    uint32_t rng;
    bool rotate_ready, summon_ready;
} tower_state;
typedef struct {
    bool used, awake;
    int x, y, kind, frame;
    phys_q angle;
    phys_aabb bounds;
    unsigned opacity;
} tower_render_block;
typedef struct {
    tower_render_block blocks[PHYS_MAX_BODIES];
    tower_particle particles[TOWER_PARTICLES];
    tower_input hand;
    int platform_x, held;
    unsigned ticks, bodies, awake, broken;
} tower_snapshot;
void tower_init(tower_state *s, uint32_t seed);
void tower_step(tower_state *s, tower_input input);
void tower_snapshot_copy(const tower_state *s, tower_snapshot *out);
void tower_geometry(unsigned shape, phys_body_def *def);
phys_vec tower_pivot(unsigned shape);
int tower_spawn(tower_state *s, int kind, int x, int y);
void tower_summon(tower_state *s, int x);
unsigned tower_frame_count(unsigned shape);
unsigned tower_frame(unsigned shape, phys_q angle);
void tower_impacts(tower_state *s);
#endif
