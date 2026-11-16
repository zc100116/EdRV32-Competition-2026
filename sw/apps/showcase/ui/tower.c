/* tower.c — showcase R4 §6; grab joint, shelf, impacts and timed challenges.
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
uint64_t tower_kinds(tower_mode mode)
{
    if (mode == TOWER_TUTORIAL) return UINT64_C(1) | (UINT64_C(1)<<3);
    if (mode == TOWER_HIGH) return UINT64_C(0x3f) | (UINT64_C(0x7)<<6);
    if (mode == TOWER_QUAKE) return UINT64_C(0x3f) | (UINT64_C(0x7)<<18) |
        (UINT64_C(1)<<30);
    return (UINT64_C(1)<<TOWER_KINDS)-1;
}
static int replenish(tower_state *s)
{
    uint64_t mask = tower_kinds(s->mode);
    unsigned index = s->mode == TOWER_FREE ? random_next(s)%36 : s->next_block%36;
    while (!(mask & (UINT64_C(1)<<index))) index = (index+1)%36;
    if (s->mode != TOWER_FREE) s->next_block = index+1;
    return (int)index;
}
void tower_shelf_position(unsigned slot, int *x, int *y)
{
    *x = slot < 3 ? 120 : 1160;
    *y = 220 + (int)(slot%3)*140;
}
int tower_shelf_hit(int x, int y)
{
    for (unsigned i = 0; i < TOWER_SLOTS; ++i) {
        int sx, sy;
        tower_shelf_position(i,&sx,&sy);
        if (x >= sx-80 && x < sx+80 && y >= sy-60 && y < sy+60) return (int)i;
    }
    return -1;
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
    s->blocks[id] = (tower_block){kind,0};
    return id;
}
void tower_clear(tower_state *s)
{
    for (int i = 0; i < PHYS_MAX_BODIES; ++i)
        if (i != s->platform && s->world.bodies[i].used) phys_body_remove(&s->world,i);
    memset(s->particles,0,sizeof s->particles);
    s->height = s->stable = s->hold = 0;
    s->hover = -1;
}
void tower_init(tower_state *s, tower_mode mode, uint32_t seed, unsigned record)
{
    memset(s,0,sizeof *s);
    s->mode = mode;
    s->rng = seed;
    s->record = record;
    s->hover = -1;
    phys_world_init(&s->world,(phys_vec){0,Q(900)});
    phys_body_def d = {.type=PHYS_KINEMATIC,.position={Q(TOWER_PLATFORM_X+TOWER_PLATFORM_W/2),
        Q(TOWER_PLATFORM_Y+TOWER_PLATFORM_H/2)},.material={1,52429,0},.part_count=1};
    d.parts[0].count = 4;
    d.parts[0].vertices[1].x = d.parts[0].vertices[2].x = Q(TOWER_PLATFORM_W);
    d.parts[0].vertices[2].y = d.parts[0].vertices[3].y = Q(TOWER_PLATFORM_H);
    for (int v = 0; v < 4; ++v) {
        d.parts[0].vertices[v].x -= Q(TOWER_PLATFORM_W/2);
        d.parts[0].vertices[v].y -= Q(TOWER_PLATFORM_H/2);
    }
    s->platform = phys_body_add(&s->world,&d);
    for (unsigned i = 0; i < TOWER_SLOTS; ++i) s->shelf[i] = replenish(s);
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
void tower_finish(tower_state *s)
{
    if (s->mode == TOWER_TUTORIAL) s->stars = s->tutorial == 2 ? 3 : 0;
    if (s->mode == TOWER_HIGH && s->height >= TOWER_TARGET && s->stable >= TOWER_STABLE)
        s->stars = s->ticks <= 45*60 ? 3 : s->ticks <= 70*60 ? 2 : 1;
    if (s->mode == TOWER_QUAKE) {
        s->stars = (unsigned)s->height/80;
        if (s->stars > 3) s->stars = 3;
    }
    s->phase = TOWER_RESULT;
    phys_grab_release(&s->world);
    int score = s->mode == TOWER_QUAKE ? s->height : s->peak;
    if (s->mode == TOWER_HIGH) {
        s->stars = s->height >= TOWER_TARGET && s->stable >= TOWER_STABLE ?
            (s->ticks < 45*60 ? 3 : s->ticks < 70*60 ? 2 : 1) : 0;
    } else s->stars = score >= 320 ? 3 : score >= 160 ? 2 : score > 0 ? 1 : 0;
}
void tower_score(tower_state *s)
{
    int height = 0;
    for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
        const phys_body *b = &s->world.bodies[i];
        if (!b->used || i == s->platform || b->awake || i == s->world.grab.body) continue;
        int h = TOWER_PLATFORM_Y-b->aabb.min.y/PHYS_ONE;
        if (h > height) height = h;
    }
    s->height = height;
    if (height > s->peak) s->peak = height;
    if ((unsigned)height > s->record) {
        s->record = (unsigned)height;
        s->new_record = true;
        s->badge = 120;
    }
    int change = height-s->stable_height;
    if (change < 0) change = -change;
    if (change >= 2 || s->world.grab.body >= 0) {
        s->stable_height = height;
        s->stable = 0;
    } else ++s->stable;
    if (s->mode == TOWER_HIGH && ((height >= TOWER_TARGET &&
        s->stable >= TOWER_STABLE) || s->ticks >= 90*60)) tower_finish(s);
    if (s->mode == TOWER_QUAKE) {
        if (s->ticks == 60*60) {
            s->phase = TOWER_SHAKE;
            for (int i = 0; i < PHYS_MAX_BODIES; ++i)
                if (s->world.bodies[i].used) {
                    s->world.bodies[i].awake = true;
                    s->world.bodies[i].sleep_steps = 0;
                }
        }
        if (s->ticks == 65*60) {
            s->phase = TOWER_SETTLE;
            s->stable = 0;
        }
        if (s->phase == TOWER_SETTLE && s->stable >= TOWER_STABLE) tower_finish(s);
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
            if (s->mode == TOWER_TUTORIAL && s->tutorial == 0 &&
                s->hand.x >= TOWER_PLATFORM_X &&
                s->hand.x <= TOWER_PLATFORM_X+TOWER_PLATFORM_W &&
                s->hand.y < TOWER_PLATFORM_Y) s->tutorial = 1;
        } else {
            phys_grab_move(&s->world,point);
            if (s->hand.cls == 1) s->rotate_ready = true;
            if (s->hand.cls == 2 && s->rotate_ready) {
                phys_grab_rotate(&s->world,PHYS_PI/2);
                s->rotate_ready = false;
                ++s->rotations;
                if (s->mode == TOWER_TUTORIAL && s->tutorial == 1) s->tutorial = 2;
            }
        }
        return;
    }
    int slot = tower_shelf_hit(s->hand.x,s->hand.y);
    int target = -1;
    if (slot >= 0) target = PHYS_MAX_BODIES+slot;
    else for (int i = PHYS_MAX_BODIES-1; i >= 0; --i)
        if (i != s->platform && s->world.bodies[i].used &&
            contains(&s->world.bodies[i],point)) { target = i; break; }
    if (!s->hand.closed || target < 0) { s->hover = -1; s->hold = 0; return; }
    if (s->hover != target) { s->hover = target; s->hold = 0; }
    if (++s->hold < TOWER_HOLD) return;
    if (slot >= 0) {
        target = tower_spawn(s,s->shelf[slot],s->hand.x,s->hand.y);
        if (target < 0) return;
        s->shelf[slot] = replenish(s);
    }
    phys_grab_create(&s->world,target,point,Q(2000));
    s->rotate_ready = true;
    ++s->picked;
    s->hold = 0;
    s->hover = -1;
}
void tower_step(tower_state *s, tower_input input)
{
    s->hand = input;
    if (s->phase == TOWER_RESULT) return;
    ++s->ticks;
    if (s->mode == TOWER_MENU) return;
    if (s->badge) --s->badge;
    for (unsigned i = 0; i < TOWER_PARTICLES; ++i) {
        tower_particle *p = &s->particles[i];
        if (!p->life) continue;
        --p->life;
        p->x += p->vx;
        p->y += p->vy;
        if (s->ticks%4 == 0) ++p->vy;
    }
    if (s->phase == TOWER_BUILD) grab(s);
    else phys_grab_release(&s->world);
    phys_body *platform = &s->world.bodies[s->platform];
    if (s->phase == TOWER_SHAKE) {
        /* A 30-step triangle wave, amplitude 20 px, exactly 2 Hz. */
        int phase = (int)(s->ticks%30);
        int offset = phase < 15 ? -20+phase*40/15 : 20-(phase-15)*40/15;
        platform->velocity.x = (Q(TOWER_PLATFORM_X+TOWER_PLATFORM_W/2+offset)-
                                platform->position.x)*60;
        for (int i = 0; i < PHYS_MAX_BODIES; ++i)
            if (s->world.bodies[i].used) s->world.bodies[i].awake = true;
    } else platform->velocity.x = 0;
    phys_step(&s->world);
    tower_impacts(s);
    tower_score(s);
    if (s->mode == TOWER_TUTORIAL && s->tutorial == 2 && s->released >= 2)
        tower_finish(s);
}
void tower_snapshot_copy(const tower_state *s, tower_snapshot *o)
{
    memset(o,0,sizeof *o);
    o->hand = s->hand;
    o->mode = s->mode;
    o->phase = s->phase;
    o->height = s->height;
    o->peak = s->peak;
    o->ticks = s->ticks;
    o->stable = s->stable;
    o->hold = s->hold;
    o->hover = s->hover;
    o->tutorial = s->tutorial;
    o->stars = s->stars;
    o->badge = s->badge;
    o->broken = s->broken;
    o->new_record = s->new_record;
    o->held = s->world.grab.body;
    o->platform_x = s->world.bodies[s->platform].aabb.min.x/PHYS_ONE;
    memcpy(o->shelf,s->shelf,sizeof o->shelf);
    memcpy(o->particles,s->particles,sizeof o->particles);
    for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
        const phys_body *b = &s->world.bodies[i];
        if (i == s->platform || !b->used) continue;
        ++o->bodies;
        o->awake += b->awake;
        o->blocks[i] = (tower_render_block){true,b->awake,b->position.x/PHYS_ONE,
            b->position.y/PHYS_ONE,s->blocks[i].kind,
            (int)tower_frame((unsigned)s->blocks[i].kind%6,b->angle),b->angle,b->aabb};
    }
}
const char *tower_name(tower_mode mode)
{
    static const char *const names[] = {"积木塔","教学","挑战一","挑战二","自由"};
    return names[mode];
}
