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
    return shape ? 1 : 16;
}
unsigned tower_frame(unsigned shape, phys_q angle)
{
    if (shape) return 0;
    int64_t scaled = (int64_t)angle*64;
    int a = (int)((scaled >= 0 ? scaled+PHYS_PI : scaled-PHYS_PI)/(2*PHYS_PI));
    return (unsigned)a & 15;
}
void tower_geometry(unsigned shape, phys_body_def *d)
{
    memset(d,0,sizeof *d);
    d->type = PHYS_DYNAMIC;
    d->part_count = 1;
    phys_shape *p = &d->parts[0];
    if (shape) {
        p->type = PHYS_CIRCLE;
        p->center = (phys_vec){Q(40),Q(40)};
        p->radius = Q(40);
    } else {
        p->count = 4;
        p->vertices[1].x = p->vertices[2].x = Q(80);
        p->vertices[2].y = p->vertices[3].y = Q(80);
    }
}
phys_vec tower_pivot(unsigned shape)
{
    (void)shape;
    return (phys_vec){Q(40),Q(40)};
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
    unsigned shape = (unsigned)kind%2;
    tower_geometry(shape,&d);
    phys_vec pivot = tower_pivot(shape);
    /* Integrate and render around the shared 40 px center. */
    for (int k = 0; k < d.part_count; ++k) {
        d.parts[k].center.x -= pivot.x;
        d.parts[k].center.y -= pivot.y;
        for (int v = 0; v < d.parts[k].count; ++v) {
            d.parts[k].vertices[v].x -= pivot.x;
            d.parts[k].vertices[v].y -= pivot.y;
        }
    }
    d.position = (phys_vec){Q(x),Q(y)};
    d.material = materials[kind/2];
    if (!shape) d.material.restitution = 0;
    int id = phys_body_add(&s->world,&d);
    s->blocks[id] = (tower_block){kind,0,++s->sequence};
    return id;
}
void tower_init(tower_state *s, uint32_t seed)
{
    memset(s,0,sizeof *s);
    s->rng = seed;
    s->fading = -1;
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
    for (int i = 0; i < 6; ++i) {
        int id = tower_spawn(s,i*2+(i%2),340+i*120,TOWER_PLATFORM_Y-40);
        s->world.bodies[id].awake = false;
    }
}
static bool contains(const phys_body *b, phys_vec point)
{
    for (int k = 0; k < b->part_count; ++k) {
        const phys_part *p = &b->parts[k];
        if (p->shape.type == PHYS_CIRCLE) {
            int64_t dx = (point.x-p->center.x)/256;
            int64_t dy = (point.y-p->center.y)/256;
            int64_t r = (p->shape.radius+Q(12))/256;
            if (dx*dx+dy*dy <= r*r) return true;
        } else {
            bool inside = true;
            for (int j = 0; j < p->shape.count; ++j) {
                phys_vec a = p->vertices[j];
                phys_vec n = p->world_normals[j];
                if ((int64_t)(point.x-a.x)*n.x+(int64_t)(point.y-a.y)*n.y > (int64_t)Q(12)*PHYS_ONE)
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
        if (s->blocks[i].kind/2 == 5 && b->max_normal_impulse > TOWER_GLASS_IMPULSE) {
            particles(s,b->position,1,12);
            phys_body_remove(&s->world,i);
            ++s->broken;
        } else if (s->blocks[i].kind/2 != 5 &&
                   b->max_normal_impulse > TOWER_DUST_IMPULSE &&
                   s->ticks >= s->blocks[i].dust_at) {
            particles(s,(phys_vec){b->position.x,b->aabb.max.y},0,3);
            s->blocks[i].dust_at = s->ticks+20;
        }
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
    if (!s->hand.closed || target < 0) return;
    phys_grab_create(&s->world,target,point);
    s->rotate_ready = true;
    ++s->picked;
}
/* Draw shape and material independently from the upper LCG bits. */
static void sky_drop(tower_state *s, int x)
{
    unsigned shape = (random_next(s)>>16)%2;
    unsigned material = (random_next(s)>>16)%6;
    int id = tower_spawn(s,(int)(material*2+shape),x,-160);
    s->world.bodies[id].angular_velocity = (phys_q)((random_next(s)>>16)%32769)-16384;
}
void tower_summon(tower_state *s, int x)
{
    if (s->world.grab.body >= 0 || s->fading >= 0) return;
    if (x < TOWER_PLATFORM_X+57) x = TOWER_PLATFORM_X+57;
    if (x > TOWER_PLATFORM_X+TOWER_PLATFORM_W-57)
        x = TOWER_PLATFORM_X+TOWER_PLATFORM_W-57;
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
    for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
        phys_body *b = &s->world.bodies[i];
        if (!b->used || b->awake || i == s->platform || s->blocks[i].kind%2) continue;
        phys_q quarter = PHYS_PI/2;
        phys_q nearest = ((b->angle+(b->angle >= 0 ? quarter/2 : -quarter/2))/quarter)*quarter;
        phys_q delta = b->angle-nearest;
        if (delta && delta < PHYS_PI*4/180 && delta > -PHYS_PI*4/180)
            phys_body_set_angle(&s->world,i,nearest);
    }
    phys_confine_x(&s->world,Q(TOWER_PLATFORM_X),Q(TOWER_PLATFORM_X+TOWER_PLATFORM_W));
    tower_impacts(s);
}
void tower_snapshot_copy(const tower_state *s, tower_snapshot *o)
{
    memset(o,0,sizeof *o);
    o->hand = s->hand;
    o->ticks = s->ticks;
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
            (int)tower_frame((unsigned)s->blocks[i].kind%2,b->angle),b->angle,b->aabb,
            i == s->fading ? (TOWER_FADE-s->fade_ticks)*255/TOWER_FADE : 255};
    }
}
