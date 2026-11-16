/* tower.h — showcase R4 §6 / D2–D6; integer tower rules and render snapshot.
 * Application task owns the world; views consume copies. Fixed 60 Hz, no LVGL.
 */
#ifndef SHOWCASE_TOWER_H
#define SHOWCASE_TOWER_H
#include "phys.h"
enum { TOWER_HZ = 60, TOWER_SLOTS = 6, TOWER_KINDS = 36, TOWER_PARTICLES = 48,
    TOWER_PLATFORM_X = 280, TOWER_PLATFORM_Y = 620, TOWER_PLATFORM_W = 720,
    TOWER_PLATFORM_H = 64, TOWER_TARGET = 240, TOWER_HOLD = 60,
    TOWER_STABLE = 180, TOWER_GLASS_IMPULSE = 180 * PHYS_ONE,
    TOWER_DUST_IMPULSE = 80 * PHYS_ONE };
typedef enum { TOWER_MENU, TOWER_TUTORIAL, TOWER_HIGH, TOWER_QUAKE, TOWER_FREE } tower_mode;
typedef enum { TOWER_BUILD, TOWER_SHAKE, TOWER_SETTLE, TOWER_RESULT } tower_phase;
typedef struct { int x, y, cls; bool closed; unsigned lost; } tower_input;
typedef struct { int x, y, vx, vy; unsigned life, kind; } tower_particle;
typedef struct { int kind; unsigned dust_at; } tower_block;
typedef struct {
    phys_world world;
    tower_block blocks[PHYS_MAX_BODIES];
    tower_particle particles[TOWER_PARTICLES];
    tower_input hand;
    tower_mode mode;
    tower_phase phase;
    unsigned ticks, stable, hold, tutorial, stars, picked, released, rotations;
    unsigned next_block, particle_next, record, badge, broken;
    int shelf[TOWER_SLOTS], hover, height, peak, stable_height, platform;
    uint32_t rng;
    bool rotate_ready, new_record;
} tower_state;
typedef struct {
    bool used, awake;
    int x, y, kind, frame;
    phys_q angle;
    phys_aabb bounds;
} tower_render_block;
typedef struct {
    tower_render_block blocks[PHYS_MAX_BODIES];
    tower_particle particles[TOWER_PARTICLES];
    tower_input hand;
    int shelf[TOWER_SLOTS], height, peak, platform_x, held, hover;
    unsigned ticks, stable, hold, tutorial, stars, badge, bodies, awake, broken;
    tower_mode mode;
    tower_phase phase;
    bool new_record;
} tower_snapshot;
void tower_init(tower_state *s, tower_mode mode, uint32_t seed, unsigned record);
void tower_step(tower_state *s, tower_input input);
void tower_clear(tower_state *s);
void tower_finish(tower_state *s);
void tower_snapshot_copy(const tower_state *s, tower_snapshot *out);
void tower_geometry(unsigned shape, phys_body_def *def);
phys_vec tower_pivot(unsigned shape);
int tower_spawn(tower_state *s, int kind, int x, int y);
int tower_shelf_hit(int x, int y);
void tower_shelf_position(unsigned slot, int *x, int *y);
uint64_t tower_kinds(tower_mode mode);
unsigned tower_frame_count(unsigned shape);
unsigned tower_frame(unsigned shape, phys_q angle);
void tower_impacts(tower_state *s);
void tower_score(tower_state *s);
const char *tower_name(tower_mode mode);
#endif
