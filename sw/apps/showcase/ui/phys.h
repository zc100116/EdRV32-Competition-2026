/* phys.h — showcase R4 §6.4 / T-TOWER-PHYS.
 * Integer rigid bodies, fixed 60 Hz, caller-owned world. No clock domain.
 * Inputs: positive density, CCW convex vertices in numeric x/y coordinates,
 * nonoverlapping compound interiors; at most 24 blocks plus a platform, four parts each.
 */
#ifndef SHOWCASE_PHYS_H
#define SHOWCASE_PHYS_H
#include <stdint.h>
#include <stdbool.h>

typedef int32_t phys_q;
#define PHYS_ONE INT32_C(65536)
#define PHYS_PI INT32_C(205887)
#define PHYS_MAX_BODIES 25
#define PHYS_MAX_PAIRS 300

typedef struct { phys_q x, y; } phys_vec;
typedef struct { phys_vec min, max; } phys_aabb;
typedef enum { PHYS_DYNAMIC, PHYS_STATIC, PHYS_KINEMATIC } phys_type;
typedef enum { PHYS_POLYGON, PHYS_CIRCLE } phys_shape_type;
typedef struct {
    phys_shape_type type;
    int count;
    phys_vec vertices[8];
    phys_vec center;
    phys_q radius;
} phys_shape;
typedef struct { phys_q density, friction, restitution; } phys_material;
typedef struct {
    phys_type type;
    phys_vec position;
    phys_q angle;
    phys_vec velocity;
    phys_q angular_velocity;
    phys_material material;
    int part_count;
    phys_shape parts[4];
} phys_body_def;

typedef struct {
    phys_shape shape;
    phys_vec normals[8];
    phys_vec vertices[8];
    phys_vec world_normals[8];
    phys_vec center;
} phys_part;
typedef struct {
    bool used, awake, moved;
    phys_type type;
    phys_vec position, velocity;
    phys_q angle, angular_velocity;
    phys_q mass, inertia, inv_mass, inv_inertia;
    phys_material material;
    phys_q max_normal_impulse;
    int sleep_steps, part_count;
    phys_aabb aabb;
    phys_part parts[4];
    /* Split impulse velocities never contribute to reported impact. */
    phys_vec push_velocity;
    phys_q push_angular;
} phys_body;
typedef struct {
    phys_vec point, normal, ra, rb;
    phys_q separation, normal_mass, tangent_mass;
    phys_q normal_impulse, tangent_impulse, push_impulse, bias, bounce;
} phys_contact;
typedef struct {
    int a, b, count;
    bool block;
    phys_q friction;
    phys_q k11, k12, k22, m11, m12, m22;
    phys_contact contacts[2];
} phys_pair;
typedef struct {
    int body;
    phys_vec offset, target;
    phys_q target_angle;
} phys_grab;
typedef struct { int contact_pairs, iterations; } phys_stats;
typedef struct {
    phys_vec gravity;
    phys_body bodies[PHYS_MAX_BODIES];
    phys_pair pairs[PHYS_MAX_PAIRS];
    phys_grab grab;
    phys_stats stats;
} phys_world;

/* Position is the shape origin on input; returned position is its computed COM.
 * All public numerical fields use Q16.16, pixels, seconds and radians; +y down.
 * Set a kinematic body's velocity/angular_velocity through phys_body_get().
 * Density is mass/pixel²: select the mass scale so inertia and its reciprocal
 * are representable in Q16.16 (e.g. density=64 for 20-pixel wooden blocks).
 */
void phys_world_init(phys_world *world, phys_vec gravity);
void phys_world_clear(phys_world *world);
int phys_body_add(phys_world *world, const phys_body_def *definition);
void phys_body_remove(phys_world *world, int body);
phys_body *phys_body_get(phys_world *world, int body);
/* Grabbed bodies are kinematic; move is exact, release clears both velocities. */
void phys_grab_create(phys_world *world, int body, phys_vec point);
void phys_grab_move(phys_world *world, phys_vec target);
void phys_grab_rotate(phys_world *world, phys_q angle_delta);
void phys_grab_release(phys_world *world);
void phys_body_set_angle(phys_world *world, int body, phys_q angle);
/* Side walls contain each nonstatic body including its rotated extents. */
void phys_confine_x(phys_world *world, phys_q left, phys_q right);
void phys_step(phys_world *world);
phys_stats phys_world_stats(const phys_world *world);
#endif
