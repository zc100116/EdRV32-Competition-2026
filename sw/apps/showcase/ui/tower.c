/* tower.c — block workshop design §6; free play, sky drops, grab and impacts.
 * Application task only, fixed 60 Hz Q16.16; no display or clock dependency.
 */
#include "tower.h"
#include <string.h>
#define Q(n) ((n) * PHYS_ONE)
static uint32_t random_next(tower_state *s)
{
    s->rng = s->rng * 1664525u + 1013904223u;
    return s->rng;
}
unsigned tower_frame_count(unsigned shape)
{
    static const unsigned frames[] = {16,32,32,64,64,64};
    return frames[shape];
}
unsigned tower_frame(unsigned shape, phys_q angle)
{
    /* Every frame advances 2pi/64; symmetric silhouettes wrap earlier. */
    int64_t scaled = (int64_t)angle*64;
    int a = (int)((scaled >= 0 ? scaled+PHYS_PI : scaled-PHYS_PI)/(2*PHYS_PI));
    return (unsigned)a & (tower_frame_count(shape)-1);
}
void tower_geometry(unsigned shape, phys_body_def *d)
{
    memset(d,0,sizeof *d);
    d->type = PHYS_DYNAMIC;
    d->part_count = 1;
    phys_shape *p = &d->parts[0];
    if (shape == 5) {
        p->type = PHYS_CIRCLE;
        p->center = (phys_vec){Q(40),Q(40)};
        p->radius = Q(40);
    } else if (shape == 4) {
        static const int outer[5][2] = {{0,80},{23,23},{80,0},{137,23},{160,80}};
        static const int inner[5][2] = {{40,80},{52,52},{80,40},{108,52},{120,80}};
        d->part_count = 4;
        for (int i = 0; i < 4; ++i) {
            p = &d->parts[i];
            p->count = 4;
            p->vertices[0] = (phys_vec){Q(outer[i][0]),Q(outer[i][1])};
            p->vertices[1] = (phys_vec){Q(outer[i+1][0]),Q(outer[i+1][1])};
            p->vertices[2] = (phys_vec){Q(inner[i+1][0]),Q(inner[i+1][1])};
            p->vertices[3] = (phys_vec){Q(inner[i][0]),Q(inner[i][1])};
        }
    } else if (shape == 3) {
        p->count = 3;
        p->vertices[0] = (phys_vec){Q(60),0};
        p->vertices[1] = (phys_vec){Q(120),Q(80)};
        p->vertices[2] = (phys_vec){0,Q(80)};
    } else {
        static const int widths[] = {80,240,120};
        static const int heights[] = {80,40,60};
        p->count = 4;
        p->vertices[1].x = p->vertices[2].x = Q(widths[shape]);
        p->vertices[2].y = p->vertices[3].y = Q(heights[shape]);
    }
}
phys_vec tower_pivot(unsigned shape)
{
    if (shape == 5) return (phys_vec){Q(40),Q(40)};
    phys_body_def d;
    tower_geometry(shape,&d);
    int64_t area = 0, x = 0, y = 0;
    for (int part = 0; part < d.part_count; ++part) {
        phys_shape *p = &d.parts[part];
        for (int i = 0; i < p->count; ++i) {
            phys_vec a = p->vertices[i];
            phys_vec b = p->vertices[(i+1)%p->count];
            int ax = a.x/PHYS_ONE, ay = a.y/PHYS_ONE;
            int bx = b.x/PHYS_ONE, by = b.y/PHYS_ONE;
            int cross = ax*by-ay*bx;
            area += cross;
            x += (ax+bx)*cross;
            y += (ay+by)*cross;
        }
    }
    return (phys_vec){(phys_q)(x*PHYS_ONE/(3*area)),
                      (phys_q)(y*PHYS_ONE/(3*area))};
}
int tower_spawn(tower_state *s, int kind, int x, int y)
{
    unsigned bodies = 0;
    for (unsigned i = 0; i < PHYS_MAX_BODIES; ++i) bodies += s->world.bodies[i].used;
    if (bodies == PHYS_MAX_BODIES) return -1;
    static const phys_material materials[] = {
        {8,49152,3277}, {16,52429,1966}, {7,3277,1311},
        {24,32768,1311}, {4,58982,52429}, {7,26214,1311}
    };
    phys_body_def d;
    unsigned shape = (unsigned)kind%6;
    tower_geometry(shape,&d);
    phys_vec pivot = tower_pivot(shape);
    /* Center source geometry before integration: full-size planks then keep their
     * Q16.16 inertia representable without changing the physical algorithm. */
    for (int k = 0; k < d.part_count; ++k) {
        d.parts[k].center.x -= pivot.x;
        d.parts[k].center.y -= pivot.y;
        for (int v = 0; v < d.parts[k].count; ++v) {
            d.parts[k].vertices[v].x -= pivot.x;
            d.parts[k].vertices[v].y -= pivot.y;
        }
    }
    d.position = (phys_vec){Q(x),Q(y)};
    d.material = materials[kind/6];
    int id = phys_body_add(&s->world,&d);
    s->blocks[id] = (tower_block){kind,0,++s->sequence};
    return id;
}
void tower_init(tower_state *s, uint32_t seed)
{
    memset(s,0,sizeof *s);
    s->rng = seed;
    s->hover = s->fading = -1;
    s->summon_ready = true;
    phys_world_init(&s->world,(phys_vec){0,Q(900)});
    phys_body_def d = {.type=PHYS_STATIC,.position={Q(TOWER_PLATFORM_X+TOWER_PLATFORM_W/2),
        Q(TOWER_PLATFORM_Y+TOWER_PLATFORM_H/2)},.material={1,52429,0},.part_count=1};
    d.parts[0].count = 4;
    d.parts[0].vertices[1].x = d.parts[0].vertices[2].x = Q(TOWER_PLATFORM_W);
    d.parts[0].vertices[2].y = d.parts[0].vertices[3].y = Q(TOWER_PLATFORM_H);
    for (int v = 0; v < 4; ++v) {
        d.parts[0].vertices[v].x -= Q(TOWER_PLATFORM_W/2);
        d.parts[0].vertices[v].y -= Q(TOWER_PLATFORM_H/2);
    }
    s->platform = phys_body_add(&s->world,&d);
}
static bool contains(const phys_body *b, phys_vec point)
{
    for (int k = 0; k < b->part_count; ++k) {
        const phys_part *p = &b->parts[k];
        if (p->shape.type == PHYS_CIRCLE) {
            int64_t dx = (point.x-p->center.x)/256;
            int64_t dy = (point.y-p->center.y)/256;
            int64_t r = p->shape.radius/256;
            if (dx*dx+dy*dy <= r*r) return true;
        } else {
            bool inside = true;
            for (int j = 0; j < p->shape.count; ++j) {
                phys_vec a = p->vertices[j];
                phys_vec n = p->world_normals[j];
                if ((int64_t)(point.x-a.x)*n.x+(int64_t)(point.y-a.y)*n.y > 0)
                    inside = false;
            }
            if (inside) return true;
        }
    }
    return false;
}
static void particles(tower_state *s, phys_vec at, unsigned kind, unsigned count)
{
    for (unsigned i = 0; i < count; ++i) {
        tower_particle *p = &s->particles[s->particle_next++%TOWER_PARTICLES];
        *p = (tower_particle){at.x/PHYS_ONE,at.y/PHYS_ONE,
            (int)(random_next(s)%9)-4,-(int)(random_next(s)%7)-2,
            kind ? 60 : 24,kind ? 1+i%3 : 0};
    }
}
void tower_impacts(tower_state *s)
{
    for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
        phys_body *b = &s->world.bodies[i];
        if (!b->used || i == s->platform) continue;
        if (s->blocks[i].kind/6 == 5 && b->max_normal_impulse > TOWER_GLASS_IMPULSE) {
            particles(s,b->position,1,12);
            phys_body_remove(&s->world,i);
            ++s->broken;
        } else if (s->blocks[i].kind/6 != 5 &&
                   b->max_normal_impulse > TOWER_DUST_IMPULSE &&
                   s->ticks >= s->blocks[i].dust_at) {
            particles(s,(phys_vec){b->position.x,b->aabb.max.y},0,3);
            s->blocks[i].dust_at = s->ticks+20;
        }
        if (b->used && b->aabb.min.y > Q(720)) phys_body_remove(&s->world,i);
    }
}
static void grab(tower_state *s)
{
    phys_vec point = {Q(s->hand.x),Q(s->hand.y)};
    int held = s->world.grab.body;
    if (held >= 0) {
        if (!s->hand.closed) {
            phys_grab_release(&s->world);
            ++s->released;
        } else {
            phys_grab_move(&s->world,point);
            if (s->hand.cls == 1) s->rotate_ready = true;
            if (s->hand.cls == 2 && s->rotate_ready) {
                phys_grab_rotate(&s->world,PHYS_PI/2);
                s->rotate_ready = false;
                ++s->rotations;
            }
        }
        return;
    }
    int target = -1;
    for (int i = PHYS_MAX_BODIES-1; i >= 0; --i)
        if (i != s->platform && i != s->fading && s->world.bodies[i].used &&
            contains(&s->world.bodies[i],point)) { target = i; break; }
    if (!s->hand.closed || target < 0) { s->hover = -1; s->hold = 0; return; }
    if (s->hover != target) { s->hover = target; s->hold = 0; }
    if (++s->hold < TOWER_HOLD) return;
    phys_grab_create(&s->world,target,point,Q(2000));
    s->rotate_ready = true;
    ++s->picked;
    s->hold = 0;
    s->hover = -1;
}
/* A separate random draw for shape/material avoids the LCG low-bit correlation.
 * Fifteen tickets: two for each ordinary shape and five for balls. */
static void sky_drop(tower_state *s, int x)
{
    unsigned ticket = (random_next(s)>>16)%15;
    unsigned shape = ticket < 10 ? ticket%5 : 5;
    unsigned material = (random_next(s)>>16)%6;
    int id = tower_spawn(s,(int)(material*6+shape),x,-160);
    s->world.bodies[id].angular_velocity = (phys_q)((random_next(s)>>16)%32769)-16384;
}
void tower_summon(tower_state *s, int x)
{
    if (s->world.grab.body >= 0 || s->fading >= 0) return;
    if (x < TOWER_PLATFORM_X) x = TOWER_PLATFORM_X;
    if (x > TOWER_PLATFORM_X+TOWER_PLATFORM_W) x = TOWER_PLATFORM_X+TOWER_PLATFORM_W;
    unsigned count = 0;
    int oldest = -1;
    for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
        if (i == s->platform || !s->world.bodies[i].used) continue;
        ++count;
        if (oldest < 0 || s->blocks[i].born < s->blocks[oldest].born) oldest = i;
    }
    if (count == 24) {
        s->fading = oldest;
        s->fade_ticks = 0;
        s->pending_x = x;
    } else sky_drop(s,x);
}
void tower_step(tower_state *s, tower_input input)
{
    s->hand = input;
    ++s->ticks;
    for (unsigned i = 0; i < TOWER_PARTICLES; ++i) {
        tower_particle *p = &s->particles[i];
        if (!p->life) continue;
        --p->life;
        p->x += p->vx;
        p->y += p->vy;
        if (s->ticks%4 == 0) ++p->vy;
    }
    if (s->fading >= 0 && ++s->fade_ticks == TOWER_FADE) {
        phys_body_remove(&s->world,s->fading);
        s->fading = -1;
        sky_drop(s,s->pending_x);
    }
    grab(s);
    if (input.cls != 8) {
        s->summon_hold = 0;
        s->summon_ready = true;
    } else if (!input.lost && s->world.grab.body < 0 && s->summon_ready) {
        if (++s->summon_hold == TOWER_SUMMON) {
            tower_summon(s,input.x);
            s->summon_ready = false;
        }
    } else s->summon_hold = 0;
    phys_step(&s->world);
    tower_impacts(s);
}
void tower_snapshot_copy(const tower_state *s, tower_snapshot *o)
{
    memset(o,0,sizeof *o);
    o->hand = s->hand;
    o->ticks = s->ticks;
    o->hold = s->hold;
    o->hover = s->hover;
    o->broken = s->broken;
    o->held = s->world.grab.body;
    o->platform_x = TOWER_PLATFORM_X;
    memcpy(o->particles,s->particles,sizeof o->particles);
    for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
        const phys_body *b = &s->world.bodies[i];
        if (i == s->platform || !b->used) continue;
        ++o->bodies;
        o->awake += b->awake;
        o->blocks[i] = (tower_render_block){true,b->awake,b->position.x/PHYS_ONE,
            b->position.y/PHYS_ONE,s->blocks[i].kind,
            (int)tower_frame((unsigned)s->blocks[i].kind%6,b->angle),b->angle,b->aabb,
            i == s->fading ? (TOWER_FADE-s->fade_ticks)*255/TOWER_FADE : 255};
    }
}
