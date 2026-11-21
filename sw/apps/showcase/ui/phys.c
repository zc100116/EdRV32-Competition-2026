/* phys.c — showcase R4 §6.4 / T-TOWER-PHYS.
 * SAT/clipping manifolds, warm-started sequential impulses, split correction.
 * Fixed 60 Hz integer simulation; no clock domain or platform dependencies.
 */
#include "phys.h"
#include <string.h>

enum { CONTACT_SKIN = PHYS_ONE/2, SOLVER_ITERATIONS = 32 };

/* round(sin(2*pi*i/1024)*65536), generated with Python math.sin. */
static const phys_q sine[1024] = {
    0, 402, 804, 1206, 1608, 2010, 2412, 2814,
    3216, 3617, 4019, 4420, 4821, 5222, 5623, 6023,
    6424, 6824, 7224, 7623, 8022, 8421, 8820, 9218,
    9616, 10014, 10411, 10808, 11204, 11600, 11996, 12391,
    12785, 13180, 13573, 13966, 14359, 14751, 15143, 15534,
    15924, 16314, 16703, 17091, 17479, 17867, 18253, 18639,
    19024, 19409, 19792, 20175, 20557, 20939, 21320, 21699,
    22078, 22457, 22834, 23210, 23586, 23961, 24335, 24708,
    25080, 25451, 25821, 26190, 26558, 26925, 27291, 27656,
    28020, 28383, 28745, 29106, 29466, 29824, 30182, 30538,
    30893, 31248, 31600, 31952, 32303, 32652, 33000, 33347,
    33692, 34037, 34380, 34721, 35062, 35401, 35738, 36075,
    36410, 36744, 37076, 37407, 37736, 38064, 38391, 38716,
    39040, 39362, 39683, 40002, 40320, 40636, 40951, 41264,
    41576, 41886, 42194, 42501, 42806, 43110, 43412, 43713,
    44011, 44308, 44604, 44898, 45190, 45480, 45769, 46056,
    46341, 46624, 46906, 47186, 47464, 47741, 48015, 48288,
    48559, 48828, 49095, 49361, 49624, 49886, 50146, 50404,
    50660, 50914, 51166, 51417, 51665, 51911, 52156, 52398,
    52639, 52878, 53114, 53349, 53581, 53812, 54040, 54267,
    54491, 54714, 54934, 55152, 55368, 55582, 55794, 56004,
    56212, 56418, 56621, 56823, 57022, 57219, 57414, 57607,
    57798, 57986, 58172, 58356, 58538, 58718, 58896, 59071,
    59244, 59415, 59583, 59750, 59914, 60075, 60235, 60392,
    60547, 60700, 60851, 60999, 61145, 61288, 61429, 61568,
    61705, 61839, 61971, 62101, 62228, 62353, 62476, 62596,
    62714, 62830, 62943, 63054, 63162, 63268, 63372, 63473,
    63572, 63668, 63763, 63854, 63944, 64031, 64115, 64197,
    64277, 64354, 64429, 64501, 64571, 64639, 64704, 64766,
    64827, 64884, 64940, 64993, 65043, 65091, 65137, 65180,
    65220, 65259, 65294, 65328, 65358, 65387, 65413, 65436,
    65457, 65476, 65492, 65505, 65516, 65525, 65531, 65535,
    65536, 65535, 65531, 65525, 65516, 65505, 65492, 65476,
    65457, 65436, 65413, 65387, 65358, 65328, 65294, 65259,
    65220, 65180, 65137, 65091, 65043, 64993, 64940, 64884,
    64827, 64766, 64704, 64639, 64571, 64501, 64429, 64354,
    64277, 64197, 64115, 64031, 63944, 63854, 63763, 63668,
    63572, 63473, 63372, 63268, 63162, 63054, 62943, 62830,
    62714, 62596, 62476, 62353, 62228, 62101, 61971, 61839,
    61705, 61568, 61429, 61288, 61145, 60999, 60851, 60700,
    60547, 60392, 60235, 60075, 59914, 59750, 59583, 59415,
    59244, 59071, 58896, 58718, 58538, 58356, 58172, 57986,
    57798, 57607, 57414, 57219, 57022, 56823, 56621, 56418,
    56212, 56004, 55794, 55582, 55368, 55152, 54934, 54714,
    54491, 54267, 54040, 53812, 53581, 53349, 53114, 52878,
    52639, 52398, 52156, 51911, 51665, 51417, 51166, 50914,
    50660, 50404, 50146, 49886, 49624, 49361, 49095, 48828,
    48559, 48288, 48015, 47741, 47464, 47186, 46906, 46624,
    46341, 46056, 45769, 45480, 45190, 44898, 44604, 44308,
    44011, 43713, 43412, 43110, 42806, 42501, 42194, 41886,
    41576, 41264, 40951, 40636, 40320, 40002, 39683, 39362,
    39040, 38716, 38391, 38064, 37736, 37407, 37076, 36744,
    36410, 36075, 35738, 35401, 35062, 34721, 34380, 34037,
    33692, 33347, 33000, 32652, 32303, 31952, 31600, 31248,
    30893, 30538, 30182, 29824, 29466, 29106, 28745, 28383,
    28020, 27656, 27291, 26925, 26558, 26190, 25821, 25451,
    25080, 24708, 24335, 23961, 23586, 23210, 22834, 22457,
    22078, 21699, 21320, 20939, 20557, 20175, 19792, 19409,
    19024, 18639, 18253, 17867, 17479, 17091, 16703, 16314,
    15924, 15534, 15143, 14751, 14359, 13966, 13573, 13180,
    12785, 12391, 11996, 11600, 11204, 10808, 10411, 10014,
    9616, 9218, 8820, 8421, 8022, 7623, 7224, 6824,
    6424, 6023, 5623, 5222, 4821, 4420, 4019, 3617,
    3216, 2814, 2412, 2010, 1608, 1206, 804, 402,
    0, -402, -804, -1206, -1608, -2010, -2412, -2814,
    -3216, -3617, -4019, -4420, -4821, -5222, -5623, -6023,
    -6424, -6824, -7224, -7623, -8022, -8421, -8820, -9218,
    -9616, -10014, -10411, -10808, -11204, -11600, -11996, -12391,
    -12785, -13180, -13573, -13966, -14359, -14751, -15143, -15534,
    -15924, -16314, -16703, -17091, -17479, -17867, -18253, -18639,
    -19024, -19409, -19792, -20175, -20557, -20939, -21320, -21699,
    -22078, -22457, -22834, -23210, -23586, -23961, -24335, -24708,
    -25080, -25451, -25821, -26190, -26558, -26925, -27291, -27656,
    -28020, -28383, -28745, -29106, -29466, -29824, -30182, -30538,
    -30893, -31248, -31600, -31952, -32303, -32652, -33000, -33347,
    -33692, -34037, -34380, -34721, -35062, -35401, -35738, -36075,
    -36410, -36744, -37076, -37407, -37736, -38064, -38391, -38716,
    -39040, -39362, -39683, -40002, -40320, -40636, -40951, -41264,
    -41576, -41886, -42194, -42501, -42806, -43110, -43412, -43713,
    -44011, -44308, -44604, -44898, -45190, -45480, -45769, -46056,
    -46341, -46624, -46906, -47186, -47464, -47741, -48015, -48288,
    -48559, -48828, -49095, -49361, -49624, -49886, -50146, -50404,
    -50660, -50914, -51166, -51417, -51665, -51911, -52156, -52398,
    -52639, -52878, -53114, -53349, -53581, -53812, -54040, -54267,
    -54491, -54714, -54934, -55152, -55368, -55582, -55794, -56004,
    -56212, -56418, -56621, -56823, -57022, -57219, -57414, -57607,
    -57798, -57986, -58172, -58356, -58538, -58718, -58896, -59071,
    -59244, -59415, -59583, -59750, -59914, -60075, -60235, -60392,
    -60547, -60700, -60851, -60999, -61145, -61288, -61429, -61568,
    -61705, -61839, -61971, -62101, -62228, -62353, -62476, -62596,
    -62714, -62830, -62943, -63054, -63162, -63268, -63372, -63473,
    -63572, -63668, -63763, -63854, -63944, -64031, -64115, -64197,
    -64277, -64354, -64429, -64501, -64571, -64639, -64704, -64766,
    -64827, -64884, -64940, -64993, -65043, -65091, -65137, -65180,
    -65220, -65259, -65294, -65328, -65358, -65387, -65413, -65436,
    -65457, -65476, -65492, -65505, -65516, -65525, -65531, -65535,
    -65536, -65535, -65531, -65525, -65516, -65505, -65492, -65476,
    -65457, -65436, -65413, -65387, -65358, -65328, -65294, -65259,
    -65220, -65180, -65137, -65091, -65043, -64993, -64940, -64884,
    -64827, -64766, -64704, -64639, -64571, -64501, -64429, -64354,
    -64277, -64197, -64115, -64031, -63944, -63854, -63763, -63668,
    -63572, -63473, -63372, -63268, -63162, -63054, -62943, -62830,
    -62714, -62596, -62476, -62353, -62228, -62101, -61971, -61839,
    -61705, -61568, -61429, -61288, -61145, -60999, -60851, -60700,
    -60547, -60392, -60235, -60075, -59914, -59750, -59583, -59415,
    -59244, -59071, -58896, -58718, -58538, -58356, -58172, -57986,
    -57798, -57607, -57414, -57219, -57022, -56823, -56621, -56418,
    -56212, -56004, -55794, -55582, -55368, -55152, -54934, -54714,
    -54491, -54267, -54040, -53812, -53581, -53349, -53114, -52878,
    -52639, -52398, -52156, -51911, -51665, -51417, -51166, -50914,
    -50660, -50404, -50146, -49886, -49624, -49361, -49095, -48828,
    -48559, -48288, -48015, -47741, -47464, -47186, -46906, -46624,
    -46341, -46056, -45769, -45480, -45190, -44898, -44604, -44308,
    -44011, -43713, -43412, -43110, -42806, -42501, -42194, -41886,
    -41576, -41264, -40951, -40636, -40320, -40002, -39683, -39362,
    -39040, -38716, -38391, -38064, -37736, -37407, -37076, -36744,
    -36410, -36075, -35738, -35401, -35062, -34721, -34380, -34037,
    -33692, -33347, -33000, -32652, -32303, -31952, -31600, -31248,
    -30893, -30538, -30182, -29824, -29466, -29106, -28745, -28383,
    -28020, -27656, -27291, -26925, -26558, -26190, -25821, -25451,
    -25080, -24708, -24335, -23961, -23586, -23210, -22834, -22457,
    -22078, -21699, -21320, -20939, -20557, -20175, -19792, -19409,
    -19024, -18639, -18253, -17867, -17479, -17091, -16703, -16314,
    -15924, -15534, -15143, -14751, -14359, -13966, -13573, -13180,
    -12785, -12391, -11996, -11600, -11204, -10808, -10411, -10014,
    -9616, -9218, -8820, -8421, -8022, -7623, -7224, -6824,
    -6424, -6023, -5623, -5222, -4821, -4420, -4019, -3617,
    -3216, -2814, -2412, -2010, -1608, -1206, -804, -402,
};

static phys_q mul(phys_q a, phys_q b) { return (phys_q)(((int64_t)a * b) >> 16); }
static phys_q divide(phys_q a, phys_q b) { return (phys_q)(((int64_t)a * 65536) / b); }
static phys_q absolute(phys_q a) { return a < 0 ? -a : a; }
static phys_q minimum(phys_q a, phys_q b) { return a < b ? a : b; }
static phys_q maximum(phys_q a, phys_q b) { return a > b ? a : b; }
static phys_q clamp(phys_q a, phys_q lo, phys_q hi)
{
    return minimum(maximum(a, lo), hi);
}
static phys_vec add(phys_vec a, phys_vec b) { return (phys_vec){a.x+b.x, a.y+b.y}; }
static phys_vec sub(phys_vec a, phys_vec b) { return (phys_vec){a.x-b.x, a.y-b.y}; }
static phys_vec scale(phys_vec a, phys_q b) { return (phys_vec){mul(a.x,b),mul(a.y,b)}; }
static phys_q dot(phys_vec a, phys_vec b)
{
    return (phys_q)(((int64_t)a.x*b.x + (int64_t)a.y*b.y) >> 16);
}
static phys_q cross(phys_vec a, phys_vec b)
{
    return (phys_q)(((int64_t)a.x*b.y - (int64_t)a.y*b.x) >> 16);
}
static phys_vec spin(phys_q w, phys_vec r) { return (phys_vec){-mul(w,r.y),mul(w,r.x)}; }
static phys_vec tangent(phys_vec v) { return (phys_vec){-v.y,v.x}; }
static phys_q root(uint64_t n)
{
    uint64_t bit = UINT64_C(1) << 62;
    uint64_t result = 0;
    while (bit > n) bit >>= 2;
    while (bit) {
        if (n >= result + bit) {
            n -= result + bit;
            result = (result >> 1) + bit;
        } else result >>= 1;
        bit >>= 2;
    }
    return (phys_q)result;
}
static phys_q length(phys_vec v)
{
    return root((uint64_t)((int64_t)v.x*v.x + (int64_t)v.y*v.y));
}
static phys_vec unit(phys_vec v)
{
    phys_q size = length(v);
    return (phys_vec){divide(v.x,size),divide(v.y,size)};
}
static phys_q wrap(phys_q a)
{
    a %= 2*PHYS_PI;
    if (a > PHYS_PI) a -= 2*PHYS_PI;
    if (a < -PHYS_PI) a += 2*PHYS_PI;
    return a;
}
static phys_vec basis(phys_q angle)
{
    int64_t phase = (int64_t)angle*1024*65536/(2*PHYS_PI);
    unsigned index = (unsigned)(phase >> 16) & 1023;
    phys_q fraction = (phys_q)(phase & 65535);
    phys_q s = sine[index] + mul(sine[(index+1)&1023]-sine[index],fraction);
    phys_q c = sine[(index+256)&1023] +
        mul(sine[(index+257)&1023]-sine[(index+256)&1023],fraction);
    return (phys_vec){c,s};
}
static phys_vec transform(phys_vec v, phys_vec cs)
{
    return (phys_vec){mul(cs.x,v.x)-mul(cs.y,v.y),mul(cs.y,v.x)+mul(cs.x,v.y)};
}
static phys_vec rotate(phys_vec v, phys_q angle) { return transform(v,basis(angle)); }
static void geometry(phys_body *b)
{
    phys_vec cs = basis(b->angle);
    b->aabb.min = (phys_vec){INT32_MAX,INT32_MAX};
    b->aabb.max = (phys_vec){INT32_MIN,INT32_MIN};
    for (int j=0; j<b->part_count; ++j) {
        phys_part *p = &b->parts[j];
        int count = p->shape.type == PHYS_CIRCLE ? 1 : p->shape.count;
        p->center = add(b->position,transform(p->shape.center,cs));
        for (int i=0; i<count; ++i) {
            phys_vec v;
            phys_q r = 0;
            if (p->shape.type == PHYS_CIRCLE) {
                v = p->center;
                r = p->shape.radius;
            } else {
                v = add(b->position,transform(p->shape.vertices[i],cs));
                p->vertices[i] = v;
                p->world_normals[i] = transform(p->normals[i],cs);
            }
            b->aabb.min.x = minimum(b->aabb.min.x,v.x-r);
            b->aabb.min.y = minimum(b->aabb.min.y,v.y-r);
            b->aabb.max.x = maximum(b->aabb.max.x,v.x+r);
            b->aabb.max.y = maximum(b->aabb.max.y,v.y+r);
        }
    }
}
void phys_world_init(phys_world *w, phys_vec gravity)
{
    memset(w,0,sizeof(*w));
    w->gravity = gravity;
    w->grab.body = -1;
}
void phys_world_clear(phys_world *w) { phys_world_init(w,w->gravity); }
phys_body *phys_body_get(phys_world *w, int id) { return &w->bodies[id]; }
phys_stats phys_world_stats(const phys_world *w) { return w->stats; }
int phys_body_add(phys_world *w, const phys_body_def *d)
{
    int id = 0;
    while (w->bodies[id].used) ++id;
    phys_body *b = &w->bodies[id];
    memset(b,0,sizeof(*b));
    b->used = true;
    b->awake = d->type != PHYS_STATIC;
    b->type = d->type;
    b->position = d->position;
    b->angle = d->angle;
    b->velocity = d->velocity;
    b->angular_velocity = d->angular_velocity;
    b->material = d->material;
    b->part_count = d->part_count;
    phys_vec weighted = {0,0};
    for (int j=0; j<d->part_count; ++j) {
        phys_part *p = &b->parts[j];
        p->shape = d->parts[j];
        phys_q mass;
        phys_q inertia;
        phys_vec center;
        if (p->shape.type == PHYS_CIRCLE) {
            phys_q r2 = mul(p->shape.radius,p->shape.radius);
            mass = mul(mul(PHYS_PI,r2),d->material.density);
            center = p->shape.center;
            inertia = mul(mass,r2/2+dot(center,center));
        } else {
            int64_t area2 = 0;
            int64_t moment_x = 0;
            int64_t moment_y = 0;
            int64_t rotational = 0;
            for (int i=0; i<p->shape.count; ++i) {
                phys_vec a = p->shape.vertices[i];
                phys_vec c = p->shape.vertices[(i+1)%p->shape.count];
                phys_q cr = cross(a,c);
                area2 += cr;
                moment_x += (int64_t)(a.x+c.x)*cr/6;
                moment_y += (int64_t)(a.y+c.y)*cr/6;
                /* Apply density before the fourth-order geometric moment. */
                int64_t square = ((int64_t)a.x*a.x+(int64_t)a.y*a.y+
                    (int64_t)a.x*c.x+(int64_t)a.y*c.y+
                    (int64_t)c.x*c.x+(int64_t)c.y*c.y) >> 16;
                rotational += (int64_t)mul(cr,d->material.density)*square/12;
                p->normals[i] = unit((phys_vec){c.y-a.y,a.x-c.x});
            }
            mass = (phys_q)((area2/2*d->material.density) >> 16);
            center = (phys_vec){(phys_q)(moment_x/(area2/2)),
                (phys_q)(moment_y/(area2/2))};
            inertia = (phys_q)(rotational >> 16);
        }
        b->mass += mass;
        b->inertia += inertia;
        weighted = add(weighted,scale(center,mass));
    }
    phys_vec center = {divide(weighted.x,b->mass),divide(weighted.y,b->mass)};
    b->inertia -= mul(b->mass,dot(center,center));
    b->position = add(b->position,rotate(center,b->angle));
    for (int j=0; j<b->part_count; ++j) {
        phys_shape *s = &b->parts[j].shape;
        s->center = sub(s->center,center);
        for (int i=0; i<s->count; ++i) s->vertices[i] = sub(s->vertices[i],center);
    }
    if (b->type == PHYS_DYNAMIC) {
        b->inv_mass = divide(PHYS_ONE,b->mass);
        b->inv_inertia = divide(PHYS_ONE,b->inertia);
    }
    geometry(b);
    return id;
}
void phys_body_remove(phys_world *w, int id)
{
    w->bodies[id].used = false;
    for (int i=0; i<PHYS_MAX_PAIRS; ++i) {
        phys_pair *p = &w->pairs[i];
        if (p->count && (p->a == id || p->b == id)) {
            phys_body *neighbor = &w->bodies[p->a == id ? p->b : p->a];
            if (neighbor->type == PHYS_DYNAMIC) {
                neighbor->awake = true;
                neighbor->sleep_steps = 0;
            }
            p->count = 0;
        }
    }
    if (w->grab.body == id) w->grab.body = -1;
}
static void wake(phys_body *b)
{
    if (b->type == PHYS_DYNAMIC) { b->awake = true; b->sleep_steps = 0; }
}
void phys_body_set_angle(phys_world *w, int id, phys_q angle)
{
    w->bodies[id].angle = angle;
    geometry(&w->bodies[id]);
}
void phys_grab_create(phys_world *w, int id, phys_vec p)
{
    phys_body *b = &w->bodies[id];
    w->grab = (phys_grab){.body=id,.offset=sub(p,b->position),
        .target=p,.target_angle=b->angle};
    b->type = PHYS_KINEMATIC;
    b->inv_mass = b->inv_inertia = 0;
    b->velocity = (phys_vec){0,0};
    b->angular_velocity = 0;
    b->awake = true;
}
void phys_grab_move(phys_world *w, phys_vec p)
{
    /* Contact velocity lets a held body push neighbors; release discards it. */
    phys_vec delta = sub(p,w->grab.target);
    phys_q speed = length(delta);
    if (speed > 20*PHYS_ONE) delta = scale(delta,divide(20*PHYS_ONE,speed));
    w->bodies[w->grab.body].velocity = scale(delta,60*PHYS_ONE);
    w->grab.target = p;
}
void phys_grab_rotate(phys_world *w, phys_q delta)
{
    w->grab.target_angle = wrap(w->grab.target_angle+delta);
}
void phys_grab_release(phys_world *w)
{
    phys_body *b = &w->bodies[w->grab.body];
    b->type = PHYS_DYNAMIC;
    b->inv_mass = divide(PHYS_ONE,b->mass);
    b->inv_inertia = divide(PHYS_ONE,b->inertia);
    b->velocity = (phys_vec){0,0};
    b->angular_velocity = 0;
    wake(b);
    w->grab.body = -1;
}

void phys_grab_throw(phys_world *w, phys_vec velocity)
{
    phys_body *b = &w->bodies[w->grab.body];
    phys_q speed = length(velocity);
    phys_grab_release(w);
    if (speed < 300*PHYS_ONE) return;
    if (speed > 1200*PHYS_ONE)
        velocity = scale(velocity,divide(1200*PHYS_ONE,speed));
    b->velocity = velocity;
    b->angular_velocity = clamp(velocity.x/120,-8*PHYS_ONE,8*PHYS_ONE);
}

/* Infinite invisible side walls: constrain the complete rotated silhouette. */
void phys_confine_x(phys_world *w, phys_q left, phys_q right)
{
    for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
        phys_body *b = &w->bodies[i];
        if (!b->used || b->type == PHYS_STATIC) continue;
        phys_q shift = 0;
        if (b->aabb.min.x < left) shift = left-b->aabb.min.x;
        else if (b->aabb.max.x > right) shift = right-b->aabb.max.x;
        if (!shift) continue;
        b->position.x += shift;
        if ((shift > 0 && b->velocity.x < 0) || (shift < 0 && b->velocity.x > 0))
            b->velocity.x = -mul(b->velocity.x,b->material.restitution);
        geometry(b);
    }
}

/* Outward face with largest minimum separation. */
static phys_q face_axis(const phys_part *a, const phys_part *b, int *edge)
{
    phys_q best = INT32_MIN;
    for (int i=0; i<a->shape.count; ++i) {
        phys_q separation = INT32_MAX;
        for (int j=0; j<b->shape.count; ++j)
            separation = minimum(separation,
                dot(a->world_normals[i],sub(b->vertices[j],a->vertices[i])));
        if (separation > best) { best = separation; *edge = i; }
    }
    return best;
}
static int clip(phys_vec in[2], phys_vec out[2], phys_vec normal, phys_q offset)
{
    phys_q d0 = dot(normal,in[0])-offset;
    phys_q d1 = dot(normal,in[1])-offset;
    int count = 0;
    if (d0 <= 0) out[count++] = in[0];
    if (d1 <= 0) out[count++] = in[1];
    if ((d0 < 0 && d1 > 0) || (d0 > 0 && d1 < 0))
        out[count++] = add(in[0],scale(sub(in[1],in[0]),divide(d0,d0-d1)));
    return count;
}
/* Keep both support points across subpixel separation during rocking.
 * A half-pixel contact skin prevents the manifold from shedding one corner. */
static int polygons(const phys_part *a, const phys_part *b, phys_contact c[2], phys_vec *n)
{
    int ea = 0;
    int eb = 0;
    phys_q sa = face_axis(a,b,&ea);
    if (sa > CONTACT_SKIN) return 0;
    phys_q sb = face_axis(b,a,&eb);
    if (sb > CONTACT_SKIN) return 0;
    bool flip = sb > sa+655;
    const phys_part *ref = flip ? b : a;
    const phys_part *inc = flip ? a : b;
    int edge = flip ? eb : ea;
    phys_vec normal = ref->world_normals[edge];
    int incident = 0;
    phys_q best = INT32_MAX;
    for (int i=0; i<inc->shape.count; ++i) {
        phys_q d = dot(normal,inc->world_normals[i]);
        if (d < best) { best = d; incident = i; }
    }
    phys_vec v1 = ref->vertices[edge];
    phys_vec v2 = ref->vertices[(edge+1)%ref->shape.count];
    phys_vec side = tangent(normal);
    phys_vec in[2] = {inc->vertices[incident],
        inc->vertices[(incident+1)%inc->shape.count]};
    phys_vec out[2];
    if (clip(in,out,scale(side,-PHYS_ONE),-dot(side,v1)) < 2) return 0;
    if (clip(out,in,side,dot(side,v2)) < 2) return 0;
    int count = 0;
    for (int i=0; i<2; ++i) {
        phys_q s = dot(normal,sub(in[i],v1));
        if (s <= CONTACT_SKIN) {
            c[count].point = sub(in[i],scale(normal,s/2));
            c[count++].separation = s;
        }
    }
    if (count == 2) {
        phys_vec spacing = sub(c[0].point,c[1].point);
        if ((int64_t)spacing.x*spacing.x+(int64_t)spacing.y*spacing.y <
            INT64_C(4294967296)) count = 1;
    }
    *n = flip ? scale(normal,-PHYS_ONE) : normal;
    return count;
}
static int circles(const phys_part *a, const phys_part *b, phys_contact *c, phys_vec *n)
{
    phys_vec delta = sub(b->center,a->center);
    phys_q distance = length(delta);
    phys_q r = a->shape.radius+b->shape.radius;
    if (distance > r) return 0;
    *n = distance ? unit(delta) : (phys_vec){PHYS_ONE,0};
    c->separation = distance-r;
    c->point = add(a->center,scale(*n,a->shape.radius+c->separation/2));
    return 1;
}
static int polygon_circle(const phys_part *a, const phys_part *b,
                          phys_contact *c, phys_vec *n)
{
    phys_q best = INT32_MIN;
    int edge = 0;
    for (int i=0; i<a->shape.count; ++i) {
        phys_q s = dot(a->world_normals[i],sub(b->center,a->vertices[i]));
        if (s > b->shape.radius) return 0;
        if (s > best) { best = s; edge = i; }
    }
    phys_vec v = a->vertices[edge];
    phys_vec e = sub(a->vertices[(edge+1)%a->shape.count],v);
    phys_vec relative = sub(b->center,v);
    int64_t projection = (int64_t)relative.x*e.x+(int64_t)relative.y*e.y;
    int64_t edge_square = ((int64_t)e.x*e.x+(int64_t)e.y*e.y) >> 16;
    phys_q t = clamp((phys_q)(projection/edge_square),0,PHYS_ONE);
    phys_vec nearest = add(v,scale(e,t));
    phys_vec delta = sub(b->center,nearest);
    phys_q distance = length(delta);
    if (best > 0 && distance > b->shape.radius) return 0;
    *n = best <= 0 ? a->world_normals[edge] : unit(delta);
    c->separation = (best <= 0 ? best : distance)-b->shape.radius;
    c->point = sub(b->center,scale(*n,b->shape.radius+c->separation/2));
    return 1;
}
static bool overlap(phys_aabb a, phys_aabb b)
{
    return a.min.x <= b.max.x+CONTACT_SKIN && a.max.x+CONTACT_SKIN >= b.min.x &&
        a.min.y <= b.max.y+CONTACT_SKIN && a.max.y+CONTACT_SKIN >= b.min.y;
}
static void manifold(phys_body *a, phys_body *b, phys_pair *p)
{
    if (!overlap(a->aabb,b->aabb)) { p->count = 0; return; }
    phys_pair old = *p;
    p->count = 0;
    phys_contact candidates[32];
    int candidate_count = 0;
    for (int i=0; i<a->part_count; ++i) for (int j=0; j<b->part_count; ++j) {
        phys_part *pa = &a->parts[i];
        phys_part *pb = &b->parts[j];
        phys_contact contacts[2] = {0};
        phys_vec n;
        int count;
        if (pa->shape.type == PHYS_POLYGON && pb->shape.type == PHYS_POLYGON)
            count = polygons(pa,pb,contacts,&n);
        else if (pa->shape.type == PHYS_CIRCLE && pb->shape.type == PHYS_CIRCLE)
            count = circles(pa,pb,contacts,&n);
        else if (pa->shape.type == PHYS_POLYGON)
            count = polygon_circle(pa,pb,contacts,&n);
        else {
            count = polygon_circle(pb,pa,contacts,&n);
            n = scale(n,-PHYS_ONE);
        }
        for (int k=0; k<count; ++k) {
            contacts[k].normal = n;
            candidates[candidate_count++] = contacts[k];
        }
    }
    if (candidate_count <= 2) {
        p->count = candidate_count;
        for (int i=0; i<candidate_count; ++i) p->contacts[i] = candidates[i];
    } else {
        /* Keep the deepest point and the widest support across all parts. */
        int deepest = 0;
        int farthest = 0;
        int64_t distance = 0;
        for (int i=1; i<candidate_count; ++i)
            if (candidates[i].separation < candidates[deepest].separation) deepest = i;
        for (int i=0; i<candidate_count; ++i) {
            phys_vec delta = sub(candidates[i].point,candidates[deepest].point);
            int64_t ds = (int64_t)delta.x*delta.x+(int64_t)delta.y*delta.y;
            if (ds > distance) { distance = ds; farthest = i; }
        }
        p->contacts[0] = candidates[deepest];
        p->contacts[1] = candidates[farthest];
        p->count = distance < INT64_C(4294967296) ? 1 : 2;
    }
    p->block = p->count == 2 && dot(p->contacts[0].normal,p->contacts[1].normal) > 65470;
    for (int i=0; i<p->count; ++i) {
        phys_contact *c = &p->contacts[i];
        int64_t distance = INT64_C(4)*65536*65536;
        for (int j=0; j<old.count; ++j) {
            phys_vec d = sub(c->point,old.contacts[j].point);
            int64_t ds = (int64_t)d.x*d.x+(int64_t)d.y*d.y;
            if (dot(c->normal,old.contacts[j].normal) > 58982 && ds < distance) {
                distance = ds;
                c->normal_impulse = old.contacts[j].normal_impulse;
                c->tangent_impulse = old.contacts[j].tangent_impulse;
            }
        }
    }
}
static phys_vec velocity(const phys_body *b, phys_vec r, bool push)
{
    return add(push ? b->push_velocity : b->velocity,
        spin(push ? b->push_angular : b->angular_velocity,r));
}
/* Multiply the lever arm by inverse inertia before reducing to Q16.16.
 * Full-size metal impacts exceed the 32768 range of an intermediate torque. */
static phys_q angular_impulse(phys_vec r, phys_vec p, phys_q inverse)
{
    int64_t torque = (int64_t)r.x*p.y-(int64_t)r.y*p.x;
    return (phys_q)((torque/PHYS_ONE)*inverse/PHYS_ONE);
}
static void impulse(phys_body *a, phys_body *b, phys_vec ra, phys_vec rb,
                    phys_vec p, bool push)
{
    if (push) {
        a->push_velocity = sub(a->push_velocity,scale(p,a->inv_mass));
        a->push_angular -= angular_impulse(ra,p,a->inv_inertia);
        b->push_velocity = add(b->push_velocity,scale(p,b->inv_mass));
        b->push_angular += angular_impulse(rb,p,b->inv_inertia);
    } else {
        a->velocity = sub(a->velocity,scale(p,a->inv_mass));
        a->angular_velocity -= angular_impulse(ra,p,a->inv_inertia);
        b->velocity = add(b->velocity,scale(p,b->inv_mass));
        b->angular_velocity += angular_impulse(rb,p,b->inv_inertia);
    }
}
static phys_q effective(phys_body *a, phys_body *b, phys_contact *c, phys_vec n)
{
    phys_q ra = cross(c->ra,n);
    phys_q rb = cross(c->rb,n);
    return divide(PHYS_ONE,a->inv_mass+b->inv_mass+
        mul(mul(ra,a->inv_inertia),ra)+mul(mul(rb,b->inv_inertia),rb));
}
static void prepare(phys_body *a, phys_body *b, phys_pair *p)
{
    p->friction = root((uint64_t)((int64_t)a->material.friction*b->material.friction));
    for (int i=0; i<p->count; ++i) {
        phys_contact *c = &p->contacts[i];
        phys_vec t = tangent(c->normal);
        c->ra = sub(c->point,a->position);
        c->rb = sub(c->point,b->position);
        c->normal_mass = effective(a,b,c,c->normal);
        c->tangent_mass = effective(a,b,c,t);
        c->bias = mul(12*PHYS_ONE,maximum(0,-c->separation-3277));
        c->push_impulse = 0;
        phys_q vn = dot(sub(velocity(b,c->rb,false),velocity(a,c->ra,false)),c->normal);
        c->bounce = vn < -30*PHYS_ONE ? -mul(maximum(a->material.restitution,
            b->material.restitution),vn) : 0;
    }
    if (p->block) {
        phys_q a1 = cross(p->contacts[0].ra,p->contacts[0].normal);
        phys_q a2 = cross(p->contacts[1].ra,p->contacts[1].normal);
        phys_q b1 = cross(p->contacts[0].rb,p->contacts[0].normal);
        phys_q b2 = cross(p->contacts[1].rb,p->contacts[1].normal);
        p->k11 = divide(PHYS_ONE,p->contacts[0].normal_mass);
        p->k22 = divide(PHYS_ONE,p->contacts[1].normal_mass);
        p->k12 = mul(a->inv_mass+b->inv_mass,
            dot(p->contacts[0].normal,p->contacts[1].normal))+mul(mul(a1,a->inv_inertia),a2)+
            mul(mul(b1,b->inv_inertia),b2);
        int64_t determinant = (int64_t)p->k11*p->k22-(int64_t)p->k12*p->k12;
        p->m11 = (phys_q)((int64_t)p->k22*INT64_C(4294967296)/determinant);
        p->m22 = (phys_q)((int64_t)p->k11*INT64_C(4294967296)/determinant);
        p->m12 = (phys_q)(-(int64_t)p->k12*INT64_C(4294967296)/determinant);
    }
}
/* The two face points form a 2x2 complementarity problem. Solving them
 * together removes the artificial rocking of a tall symmetric stack. */
static void block_normal(phys_body *a, phys_body *b, phys_pair *p, bool push)
{
    phys_contact *c1 = &p->contacts[0];
    phys_contact *c2 = &p->contacts[1];
    phys_q old1 = push ? c1->push_impulse : c1->normal_impulse;
    phys_q old2 = push ? c2->push_impulse : c2->normal_impulse;
    phys_q v1 = dot(sub(velocity(b,c1->rb,push),velocity(a,c1->ra,push)),c1->normal);
    phys_q v2 = dot(sub(velocity(b,c2->rb,push),velocity(a,c2->ra,push)),c2->normal);
    phys_q rhs1 = v1-(push ? c1->bias : c1->bounce)-mul(p->k11,old1)-mul(p->k12,old2);
    phys_q rhs2 = v2-(push ? c2->bias : c2->bounce)-mul(p->k12,old1)-mul(p->k22,old2);
    phys_q x1 = -mul(p->m11,rhs1)-mul(p->m12,rhs2);
    phys_q x2 = -mul(p->m12,rhs1)-mul(p->m22,rhs2);
    if (x1 < 0 || x2 < 0) {
        x1 = maximum(0,-mul(c1->normal_mass,rhs1));
        x2 = 0;
        if (rhs2+mul(p->k12,x1) < 0) {
            x1 = 0;
            x2 = maximum(0,-mul(c2->normal_mass,rhs2));
        }
    }
    if (push) { c1->push_impulse=x1; c2->push_impulse=x2; }
    else { c1->normal_impulse=x1; c2->normal_impulse=x2; }
    impulse(a,b,c1->ra,c1->rb,scale(c1->normal,x1-old1),push);
    impulse(a,b,c2->ra,c2->rb,scale(c2->normal,x2-old2),push);
}
static void solve(phys_body *a, phys_body *b, phys_pair *p)
{
    if (p->block) {
        block_normal(a,b,p,false);
        block_normal(a,b,p,true);
    }
    for (int i=0; i<p->count; ++i) {
        phys_contact *c = &p->contacts[i];
        phys_vec n = c->normal;
        phys_vec t = tangent(n);
        phys_vec dv = sub(velocity(b,c->rb,false),velocity(a,c->ra,false));
        phys_q old = c->normal_impulse;
        if (!p->block) {
            c->normal_impulse = maximum(0,old+mul(c->normal_mass,c->bounce-dot(dv,n)));
            impulse(a,b,c->ra,c->rb,scale(n,c->normal_impulse-old),false);
        }
        dv = sub(velocity(b,c->rb,false),velocity(a,c->ra,false));
        phys_q limit = mul(p->friction,c->normal_impulse);
        old = c->tangent_impulse;
        c->tangent_impulse = clamp(old-mul(c->tangent_mass,dot(dv,t)),-limit,limit);
        impulse(a,b,c->ra,c->rb,scale(t,c->tangent_impulse-old),false);
        dv = sub(velocity(b,c->rb,true),velocity(a,c->ra,true));
        old = c->push_impulse;
        if (!p->block) {
            c->push_impulse = maximum(0,old+mul(c->normal_mass,c->bias-dot(dv,n)));
            impulse(a,b,c->ra,c->rb,scale(n,c->push_impulse-old),true);
        }
    }
}

void phys_step(phys_world *w)
{
    w->stats = (phys_stats){0,SOLVER_ITERATIONS};
    for (int i=0; i<PHYS_MAX_BODIES; ++i) {
        phys_body *b = &w->bodies[i];
        if (!b->used) continue;
        b->moved = false;
        b->max_normal_impulse = 0;
        b->push_velocity = (phys_vec){0,0};
        b->push_angular = 0;
    }
    if (w->grab.body >= 0) {
        phys_body *b = &w->bodies[w->grab.body];
        phys_vec target = sub(w->grab.target,w->grab.offset);
        b->angular_velocity = wrap(w->grab.target_angle-b->angle)*60;
        b->position = target;
        b->angle = w->grab.target_angle;
        geometry(b);
    }
    int index = 0;
    for (int i=0; i<PHYS_MAX_BODIES; ++i) for (int j=i+1; j<PHYS_MAX_BODIES; ++j) {
        phys_body *a = &w->bodies[i];
        phys_body *b = &w->bodies[j];
        phys_pair *p = &w->pairs[index++];
        p->a = i;
        p->b = j;
        if (!a->used || !b->used || (a->type != PHYS_DYNAMIC && b->type != PHYS_DYNAMIC)) {
            p->count = 0;
            continue;
        }
        if ((a->type == PHYS_DYNAMIC && a->awake) ||
            (b->type == PHYS_DYNAMIC && b->awake) ||
            (a->type == PHYS_KINEMATIC &&
             (a->velocity.x || a->velocity.y || a->angular_velocity)) ||
            (b->type == PHYS_KINEMATIC &&
             (b->velocity.x || b->velocity.y || b->angular_velocity))) manifold(a,b,p);
        if (p->count) ++w->stats.contact_pairs;
    }
    /* Propagate wake through the contact graph, including a moving platform. */
    for (int pass=0; pass<PHYS_MAX_BODIES; ++pass) {
        bool changed = false;
        for (int i=0; i<PHYS_MAX_PAIRS; ++i) {
            phys_pair *p = &w->pairs[i];
            if (!p->count) continue;
            phys_body *a = &w->bodies[p->a];
            phys_body *b = &w->bodies[p->b];
            bool active_a = (a->type == PHYS_DYNAMIC && a->awake) ||
                (a->type == PHYS_KINEMATIC &&
                 (a->velocity.x || a->velocity.y || a->angular_velocity));
            bool active_b = (b->type == PHYS_DYNAMIC && b->awake) ||
                (b->type == PHYS_KINEMATIC &&
                 (b->velocity.x || b->velocity.y || b->angular_velocity));
            if (active_a && b->type == PHYS_DYNAMIC && !b->awake) {
                wake(b); changed = true;
            }
            if (active_b && a->type == PHYS_DYNAMIC && !a->awake) {
                wake(a); changed = true;
            }
        }
        if (!changed) break;
    }
    for (int i=0; i<PHYS_MAX_BODIES; ++i) {
        phys_body *b = &w->bodies[i];
        if (b->used && b->type == PHYS_DYNAMIC && b->awake)
            b->velocity = add(b->velocity,(phys_vec){w->gravity.x/60,w->gravity.y/60});
    }
    int active[PHYS_MAX_PAIRS];
    int active_count = 0;
    for (int i=0; i<PHYS_MAX_PAIRS; ++i) {
        phys_pair *p = &w->pairs[i];
        if (p->count &&
            ((w->bodies[p->a].type == PHYS_DYNAMIC && w->bodies[p->a].awake) ||
             (w->bodies[p->b].type == PHYS_DYNAMIC && w->bodies[p->b].awake))) {
            active[active_count++] = i;
            prepare(&w->bodies[p->a],&w->bodies[p->b],p);
        }
    }
    for (int i=0; i<active_count; ++i) {
        phys_pair *p = &w->pairs[active[i]];
        phys_body *a = &w->bodies[p->a];
        phys_body *b = &w->bodies[p->b];
        for (int j=0; j<p->count; ++j) {
            phys_contact *c = &p->contacts[j];
            impulse(a,b,c->ra,c->rb,add(scale(c->normal,c->normal_impulse),
                scale(tangent(c->normal),c->tangent_impulse)),false);
        }
    }
    for (int iteration=0; iteration<SOLVER_ITERATIONS; ++iteration) {
        for (int i=0; i<active_count; ++i) {
            phys_pair *p = &w->pairs[active[i]];
            solve(&w->bodies[p->a],&w->bodies[p->b],p);
        }
    }
    for (int i=0; i<active_count; ++i) {
        phys_pair *p = &w->pairs[active[i]];
        for (int j=0; j<p->count; ++j) {
            phys_q impulse_value = p->contacts[j].normal_impulse;
            phys_body *a = &w->bodies[p->a];
            phys_body *b = &w->bodies[p->b];
            a->max_normal_impulse = maximum(a->max_normal_impulse,impulse_value);
            b->max_normal_impulse = maximum(b->max_normal_impulse,impulse_value);
        }
    }
    /* Contact islands sleep together: a newly sleeping block must not be
     * immediately woken by a quiet neighbor that is one frame behind it. */
    /* Quiet means <0.05 px/step and <0.025 rad/s for 0.5 s; sleeping islands
     * then retain exact positions/angles until a grab or collision wakes them. */
    int island[PHYS_MAX_BODIES];
    int quiet[PHYS_MAX_BODIES];
    for (int i=0; i<PHYS_MAX_BODIES; ++i) {
        phys_body *b = &w->bodies[i];
        island[i] = i;
        quiet[i] = 30;
        if (!b->used || b->type != PHYS_DYNAMIC || !b->awake) continue;
        if (absolute(b->velocity.x) < 3*PHYS_ONE && absolute(b->velocity.y) < 3*PHYS_ONE &&
            absolute(b->angular_velocity) < 1638) ++b->sleep_steps;
        else b->sleep_steps = 0;
        if (w->grab.body == i) b->sleep_steps = 0;
        quiet[i] = b->sleep_steps;
    }
    for (int i=0; i<PHYS_MAX_PAIRS; ++i) {
        phys_pair *p = &w->pairs[i];
        if (!p->count || w->bodies[p->a].type != PHYS_DYNAMIC ||
            w->bodies[p->b].type != PHYS_DYNAMIC) continue;
        int a = p->a;
        int b = p->b;
        while (island[a] != a) a = island[a];
        while (island[b] != b) b = island[b];
        island[b] = a;
    }
    for (int i=0; i<PHYS_MAX_BODIES; ++i) {
        int r = i;
        while (island[r] != r) r = island[r];
        island[i] = r;
        quiet[r] = minimum(quiet[r],quiet[i]);
    }
    for (int i=0; i<PHYS_MAX_BODIES; ++i) {
        phys_body *b = &w->bodies[i];
        if (!b->used || b->type == PHYS_STATIC || !b->awake || w->grab.body == i) continue;
        phys_vec previous = b->position;
        phys_q angle = b->angle;
        phys_vec v = add(b->velocity,b->push_velocity);
        b->position = add(b->position,(phys_vec){v.x/60,v.y/60});
        b->angle = wrap(b->angle+(b->angular_velocity+b->push_angular)/60);
        b->moved = previous.x != b->position.x || previous.y != b->position.y ||
            angle != b->angle;
        geometry(b);
        if (b->type == PHYS_DYNAMIC && quiet[island[i]] >= 30) {
            b->awake = false;
            b->velocity = (phys_vec){0,0};
            b->angular_velocity = 0;
        }
    }
}
