/* File: sim.c
 * Spec: ember_isles gdd 2-5, tech 2-3; E3 systems on the E1/E2 content.
 * Description: Integer combat, tagged builds, bounded death triggers and five coast waves.
 * Clock domain: fixed 60 Hz simulation; no presentation or platform dependencies.
 */
#include "sim.h"
#include "data.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int32_t minimum(int32_t a, int32_t b) { return a < b ? a : b; }
static int32_t maximum(int32_t a, int32_t b) { return a > b ? a : b; }
static int32_t clamp(int32_t a, int32_t lo, int32_t hi)
{
    return minimum(maximum(a, lo), hi);
}
static int64_t distance2(ember_fixed x, ember_fixed y, ember_fixed a, ember_fixed b)
{
    int64_t dx = (int64_t)x - a;
    int64_t dy = (int64_t)y - b;
    return dx * dx + dy * dy;
}
static int within(ember_fixed x, ember_fixed y, ember_fixed a, ember_fixed b, int r)
{
    return distance2(x, y, a, b) <= (int64_t)r * r * EMBER_Q * EMBER_Q;
}
static uint32_t square_root(uint64_t n)
{
    uint64_t bit = UINT64_C(1) << 62;
    uint64_t root = 0;
    while (bit > n) bit >>= 2;
    while (bit) {
        if (n >= root + bit) { n -= root + bit; root = (root >> 1) + bit; }
        else root >>= 1;
        bit >>= 2;
    }
    return (uint32_t)root;
}
static void velocity(ember_fixed dx, ember_fixed dy, int speed,
                     ember_fixed *vx, ember_fixed *vy)
{
    uint32_t length = square_root((int64_t)dx * dx + (int64_t)dy * dy);
    if (!length) { *vx = 0; *vy = 0; return; }
    *vx = (ember_fixed)((int64_t)dx * speed * EMBER_Q / (60 * (int64_t)length));
    *vy = (ember_fixed)((int64_t)dy * speed * EMBER_Q / (60 * (int64_t)length));
}
static int illuminated(const struct ember_sim *s, ember_fixed x, ember_fixed y)
{
    if (!s->lamp_disabled && within(x, y, s->player.x, s->player.y, s->lamp_radius)) return 1;
    for (unsigned i = 0; i < 8; ++i)
        if (s->pillars[i].lit && within(x, y, s->pillars[i].x, s->pillars[i].y,
            ember_lighting[0].pillar_radius)) return 1;
    return 0;
}
static int tagged(unsigned weapon, const char *tag)
{
    return strstr(ember_weapons[weapon].tags, tag) != NULL;
}
static int inscription(const struct ember_sim *s, unsigned w, unsigned id)
{
    return s->player.inscription[w][0] == id + 1 ||
           s->player.inscription[w][1] == id + 1;
}
/* gdd 2.2: flat and increased sum; each more modifier has its own product. */
static int32_t attribute(const struct ember_sim *s, unsigned a, int32_t base,
                         const char *tag)
{
    int32_t flat = 0;
    int32_t increased = 0;
    for (unsigned i = 0; i < EMBER_RELICS_COUNT; ++i) {
        const struct ember_relics_row *r = &ember_relics[i];
        if (strcmp(r->attribute, ember_attributes[a].id) ||
            (strcmp(r->effect, "stat") && r->tags[0] &&
             (!tag || !strstr(tag, r->tags)))) continue;
        flat += r->flat * s->player.relic_level[i];
        if (a != EMBER_CRIT) increased += r->increased * s->player.relic_level[i];
    }
    const struct ember_weapon_system *sub = &s->weapon_system[s->player.sub_weapon];
    if (sub->rarity >= 1 && sub->offhand_attribute == a) flat += sub->offhand_flat;
    int64_t result = (int64_t)(base + flat) * (100 + increased) / 100;
    for (unsigned i = 0; i < EMBER_RELICS_COUNT; ++i) {
        const struct ember_relics_row *r = &ember_relics[i];
        if (strcmp(r->attribute, ember_attributes[a].id) ||
            (strcmp(r->effect, "stat") && r->tags[0] &&
             (!tag || !strstr(tag, r->tags)))) continue;
        if (!strcmp(r->effect, "ignite_duration_damage")) continue;
        for (unsigned level = 0; level < s->player.relic_level[i]; ++level)
            result = result * (100 + r->more) / 100;
    }
    int64_t cap = minimum(ember_attributes[a].maximum + s->cap_raise[a],
                          ember_attributes[a].range_maximum);
    return (int32_t)(result < ember_attributes[a].minimum ? ember_attributes[a].minimum :
                     result > cap ? cap : result);
}
void ember_sim_attributes(struct ember_sim *s)
{
    const struct ember_characters_row *c = &ember_characters[0];
    const int32_t base[EMBER_ATTRIBUTE_COUNT] = {
        c->max_hp, c->armor, c->speed, c->attack, c->attack_speed, c->crit,
        c->crit_damage, c->area, c->projectiles, c->projectile_speed, c->duration,
        c->cooldown, c->pierce, c->knockback, c->regen, c->dodge, c->shield,
        c->tenacity, c->dash_count, c->dash_cooldown, c->status_chance,
        c->status_strength, c->status_duration, c->pickup,
        c->xp, c->gold, c->luck, c->healing, c->aura, c->threat, c->ember_damage,
        c->tide_damage, c->iron_damage, c->star_damage, c->shadow_damage,
        100, 100, 100, 0, 0, 0, 0, 0, 0
    };
    for (unsigned i = 0; i < EMBER_ATTRIBUTE_COUNT; ++i)
        s->attributes[i] = attribute(s, i, base[i], NULL);
    s->player.max_hp = s->attributes[EMBER_MAX_HP];
    s->player.armor = s->attributes[EMBER_ARMOR];
    s->player.speed = s->attributes[EMBER_SPEED];
    s->player.defense.armor = s->player.armor;
    s->player.defense.dodge = s->attributes[EMBER_DODGE];
    s->player.defense.tenacity = s->attributes[EMBER_TENACITY];
    s->player.defense.shield_max = s->attributes[EMBER_SHIELD];
    s->player.defense.max_hp = s->player.max_hp;
    for (unsigned i = 0; i < 4; ++i) {
        s->player.defense.resistance[i] = s->attributes[EMBER_FIRE_RESIST + i];
        s->player.defense.resistance_cap[i] =
            ember_attributes[EMBER_FIRE_RESIST + i].maximum +
            s->cap_raise[EMBER_FIRE_RESIST + i];
    }
    s->player.defense.all_resistance = s->attributes[EMBER_ALL_RESIST];
    s->player.defense.reduction[0] = s->attributes[EMBER_REDUCTION];
    s->player.defense.reduction_cap = ember_attributes[EMBER_REDUCTION].maximum +
        s->cap_raise[EMBER_REDUCTION];
}
static void event(struct ember_sim *s, unsigned kind, unsigned value,
                  ember_fixed x, ember_fixed y)
{
    ember_event_push(&s->events, kind, value, x, y);
}
static struct ember_shot *shot(struct ember_sim *s, unsigned kind,
                              ember_fixed x, ember_fixed y, int damage, int radius, int life)
{
    for (unsigned i = 0; i < EMBER_SHOTS; ++i) {
        struct ember_shot *p = &s->shots[i];
        if (p->alive) continue;
        *p = (struct ember_shot){0};
        p->alive = 1;
        p->kind = (uint8_t)kind;
        p->x = x;
        p->y = y;
        p->damage = damage;
        p->radius = (uint16_t)radius;
        p->life = (uint16_t)life;
        p->weapon = 255;
        p->last_hit = -1;
        ++s->shot_count;
        return p;
    }
    fputs("ember shot pool exhausted\n", stderr);
    abort();
}
static void grid_build(struct ember_sim *s)
{
    for (unsigned i = 0; i < EMBER_GRID_COLUMNS * EMBER_GRID_ROWS; ++i) s->grid[i] = -1;
    for (int i = EMBER_ENEMIES - 1; i >= 0; --i) {
        struct ember_enemy *e = &s->enemies[i];
        if (!e->alive) continue;
        int cell = clamp(e->x / (32 * EMBER_Q), 0, EMBER_GRID_COLUMNS - 1) +
                   EMBER_GRID_COLUMNS * clamp(e->y / (32 * EMBER_Q), 0, EMBER_GRID_ROWS - 1);
        s->next_enemy[i] = s->grid[cell];
        s->grid[cell] = (int16_t)i;
    }
}
static void pickup_drop(struct ember_sim *s, const struct ember_enemy *e)
{
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        if (s->pickups[i].alive) continue;
        s->pickups[i] = (struct ember_pickup){e->x, e->y,
            (uint32_t)ember_enemies[e->kind].xp, 1};
        ++s->pickup_count;
        return;
    }
    fputs("ember pickup pool exhausted\n", stderr);
    abort();
}
static void area_hit(struct ember_sim *s, ember_fixed x, ember_fixed y,
                     int radius, int damage, unsigned weapon, unsigned depth, int periodic);
struct ember_damage_result ember_sim_hit(struct ember_sim *s, unsigned index,
                                         const struct ember_attack *hit)
{
    struct ember_enemy *e = &s->enemies[index];
    if (!e->alive || hit->depth > 3u + s->trigger_bonus)
        return (struct ember_damage_result){0};
    if (hit->depth > s->trigger_peak) s->trigger_peak = hit->depth;
    int frozen = e->defense.frozen;
    struct ember_damage_result r = ember_damage(&s->combat_rng, hit, &e->defense, &e->hp);
    e->shield = e->defense.permanent_shield + e->defense.temporary[EMBER_DAMAGE_TYPES];
    if (r.dodged) {
        event(s, 1, 0, e->x, e->y);
        s->events.item[s->events.count - 1].outcome = 1;
        return r;
    }
    if (!r.damage && !r.absorbed) return r;
    if (hit->leech) s->player.hp = minimum(s->player.max_hp,
        s->player.hp + r.damage * hit->leech / 100);
    e->flash = 6;
    s->damage_total += (unsigned)r.damage;
    event(s, 1, (unsigned)(r.damage + r.absorbed), e->x, e->y);
    s->events.item[s->events.count - 1].outcome = r.blocked ? 2 : 0;
    s->events.item[s->events.count - 1].tier = r.crit;
    s->events.item[s->events.count - 1].damage_type = r.dominant;
    s->player.charge = (uint16_t)minimum(ember_characters[0].charge_max,
        s->player.charge + (r.damage > 0));
    if (e->hp > 0) {
        if (hit->depth == 3 + s->trigger_bonus) return r;
        struct ember_attack linked = {.attack = 100, .crit_damage = 150,
                                       .depth = (uint8_t)(hit->depth + 1)};
        if (frozen && r.part[EMBER_DAMAGE_IRON]) {
            e->defense.frozen = 0;
            linked.base = ember_system[0].shatter_damage;
            linked.share[EMBER_DAMAGE_IRON] = 100;
            for (unsigned n = 0; n < EMBER_ENEMIES; ++n)
                if (s->enemies[n].alive && n != index && within(e->x, e->y,
                    s->enemies[n].x, s->enemies[n].y, ember_system[0].chain_range))
                    ember_sim_hit(s, n, &linked);
        }
        if (r.crit && e->defense.status[EMBER_BREAK_ARMOR].frames) {
            linked.base = ember_system[0].heavy_damage;
            linked.share[EMBER_DAMAGE_IRON] = 100;
            ember_sim_hit(s, index, &linked);
        }
        if (r.crit && e->defense.status[EMBER_BLIND].frames &&
            !illuminated(s, e->x, e->y)) {
            linked.base = ember_system[0].blind_crit;
            linked.share[EMBER_DAMAGE_IRON] = 0;
            linked.share[EMBER_DAMAGE_SHADOW] = 100;
            ember_sim_hit(s, index, &linked);
        }
        return r;
    }
    e->alive = 0;
    --s->alive_count;
    ++s->player.kills;
    if (e->defense.status[EMBER_CORRODE].frames)
        s->player.hp = minimum(s->player.max_hp, s->player.hp + ember_system[0].corrode_heal);
    s->player.charge = (uint16_t)minimum(ember_characters[0].charge_max,
        s->player.charge + ember_characters[0].charge_kill);
    pickup_drop(s, e);
    event(s, 2, (unsigned)r.damage, e->x, e->y);
    if (e->burn && hit->depth < 3 + s->trigger_bonus) {
        int radius = ember_characters[0].passive_radius * s->attributes[EMBER_AREA] / 100;
        if (e->burn_weapon < EMBER_WEAPONS_COUNT && inscription(s, e->burn_weapon, 3))
            radius = radius * (100 + ember_inscriptions[3].value) / 100;
        struct ember_shot *p = shot(s, 1, e->x, e->y, 0, radius,
                                    ember_characters[0].passive_frames);
        p->tick = 1;
        area_hit(s, e->x, e->y, radius, ember_characters[0].passive_damage,
                 e->burn_weapon, hit->depth + 1, 0);
    }
    return r;
}
void ember_sim_status(struct ember_sim *s, unsigned index, unsigned status, unsigned depth)
{
    struct ember_enemy *e = &s->enemies[index];
    if (!e->alive || depth > 3u + s->trigger_bonus) return;
    unsigned reaction = ember_status_apply(&e->defense, status,
        ember_statuses[status].duration * s->attributes[EMBER_STATUS_DURATION] / 100,
        s->attributes[EMBER_STATUS_STRENGTH]);
    e->burn = e->defense.status[EMBER_IGNITE].frames;
    if (reaction & 1u) area_hit(s, e->x, e->y, ember_system[0].chain_range,
                               ember_system[0].steam_damage, 255, depth + 1, 0);
    if (reaction & 2u) {
        int last = (int)index;
        uint8_t visited[EMBER_ENEMIES] = {0};
        visited[index] = 1;
        int damage = ember_statuses[EMBER_SHOCK].damage;
        for (int jump = 0; jump < ember_system[0].chain_jumps; ++jump) {
            int next = -1;
            int64_t best = INT64_MAX;
            int wet = !!s->enemies[last].defense.status[EMBER_WET].frames;
            int range = ember_system[0].chain_range * (wet ? 150 : 100) / 100;
            for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
                struct ember_enemy *n = &s->enemies[i];
                if (!n->alive || visited[i] || !within(n->x, n->y,
                    s->enemies[last].x, s->enemies[last].y, range)) continue;
                int64_t dist = distance2(n->x, n->y, s->enemies[last].x, s->enemies[last].y);
                if (dist < best) { best = dist; next = (int)i; }
            }
            if (next < 0) break;
            struct ember_attack linked = {.base = damage, .attack = 100, .crit_damage = 150,
                .share = {0, 0, 0, 100, 0, 0}, .depth = (uint8_t)(depth + 1)};
            ember_sim_hit(s, (unsigned)next, &linked);
            damage = damage * (100 + ember_system[0].chain_growth) / 100;
            if (!wet || jump) damage = damage * (100 - ember_system[0].chain_decay) / 100;
            visited[next] = 1;
            last = next;
        }
    }
}
static void enemy_hit(struct ember_sim *s, unsigned index, int damage,
                      unsigned weapon, unsigned depth, int periodic)
{
    struct ember_enemy *e = &s->enemies[index];
    if (!e->alive || depth > 3u + s->trigger_bonus) return;
    struct ember_attack hit = {.base = damage, .attack = s->attributes[EMBER_ATTACK],
        .crit = s->attributes[EMBER_CRIT], .crit_damage = s->attributes[EMBER_CRIT_DAMAGE],
        .penetration = s->attributes[EMBER_PIERCE], .share = {0,100,0,0,0,0},
        .depth = (uint8_t)depth, .flags = periodic ? EMBER_DOT : 0};
    if ((int64_t)e->vx * (s->player.x - e->x) +
        (int64_t)e->vy * (s->player.y - e->y) >= 0) hit.flags |= EMBER_FRONT;
    if (s->dot_can_crit) hit.flags |= EMBER_DOT_CRIT;
    if (s->in_light) hit.increased += ember_lighting[0].ally_damage *
        s->attributes[EMBER_LIGHT_EFFECT] / 100;
    if (e->defense.status[EMBER_CORRODE].frames) hit.leech = ember_system[0].corrode_leech;
    if (weapon < EMBER_WEAPONS_COUNT) {
        const struct ember_weapon_system *w = &s->weapon_system[weapon];
        memcpy(hit.share, w->share, sizeof(hit.share));
        memcpy(hit.added, w->added, sizeof(hit.added));
        memcpy(hit.more, w->more, sizeof(hit.more));
        uint32_t tags = w->tags;
        for (unsigned i = 0; i < EMBER_TAGS_COUNT; ++i) {
            if ((!strcmp(ember_tags[i].id, "light") && s->in_light) ||
                (!strcmp(ember_tags[i].id, "dark") && !s->in_light)) tags |= 1u << i;
            if (tags & (1u << i)) hit.increased += s->tag_damage[i];
        }
        hit.conversion = w->conversion;
        hit.increased += w->increased;
        hit.penetration += w->penetration;
        if (e->burn && inscription(s, weapon, 2)) hit.more[0] += ember_inscriptions[2].value;
    }
    if (periodic) {
        memset(hit.share, 0, sizeof(hit.share));
        memset(hit.added, 0, sizeof(hit.added));
        hit.share[EMBER_DAMAGE_FIRE] = 100;
        hit.conversion = 0;
    }
    const unsigned attrs[5] = {EMBER_IRON_DAMAGE, EMBER_EMBER_DAMAGE, EMBER_TIDE_DAMAGE,
                              EMBER_STAR_DAMAGE, EMBER_SHADOW_DAMAGE};
    for (unsigned i = 0; i < 5; ++i)
        hit.increased += (s->attributes[attrs[i]] - 100) * hit.share[i] / 100;
    struct ember_damage_result result = ember_sim_hit(s, index, &hit);
    if (e->alive && !periodic && !result.dodged && (result.damage || result.absorbed)) {
        for (unsigned i = 0; i < 5; ++i) {
            if (!hit.share[i] || (int)(ember_random(&s->combat_rng) % 100) >=
                s->attributes[EMBER_STATUS_CHANCE]) continue;
            unsigned state = i == EMBER_DAMAGE_FIRE ? EMBER_IGNITE :
                i == EMBER_DAMAGE_WATER ? EMBER_WET :
                i == EMBER_DAMAGE_STAR ? EMBER_SHOCK : i == EMBER_DAMAGE_SHADOW ? EMBER_CORRODE :
                EMBER_BREAK_ARMOR;
            ember_sim_status(s, index, state, depth);
        }
        if (weapon < EMBER_WEAPONS_COUNT)
            for (unsigned state = 0; state < EMBER_STATUS_COUNT; ++state)
                if (s->weapon_system[weapon].status_mask & (1u << state))
                    ember_sim_status(s, index, state, depth);
        e->burn_weapon = (uint8_t)weapon;
    }
}
static void area_hit(struct ember_sim *s, ember_fixed x, ember_fixed y,
                     int radius, int damage, unsigned weapon, unsigned depth, int periodic)
{
    int x0 = clamp((x / EMBER_Q - radius - 12) / 32, 0, EMBER_GRID_COLUMNS - 1);
    int x1 = clamp((x / EMBER_Q + radius + 12) / 32, 0, EMBER_GRID_COLUMNS - 1);
    int y0 = clamp((y / EMBER_Q - radius - 12) / 32, 0, EMBER_GRID_ROWS - 1);
    int y1 = clamp((y / EMBER_Q + radius + 12) / 32, 0, EMBER_GRID_ROWS - 1);
    for (int cy = y0; cy <= y1; ++cy) for (int cx = x0; cx <= x1; ++cx)
        for (int i = s->grid[cy * EMBER_GRID_COLUMNS + cx]; i >= 0; i = s->next_enemy[i]) {
            struct ember_enemy *e = &s->enemies[i];
            if (e->alive && within(x, y, e->x, e->y, radius + ember_enemies[e->kind].radius))
                enemy_hit(s, (unsigned)i, damage, weapon, depth, periodic);
        }
}
static int nearest(const struct ember_sim *s)
{
    int target = -1;
    int64_t best = INT64_MAX;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        const struct ember_enemy *e = &s->enemies[i];
        if (!e->alive) continue;
        int64_t d = distance2(e->x, e->y, s->player.x, s->player.y);
        if (d < best) { target = (int)i; best = d; }
    }
    return target;
}
static void player_hurt(struct ember_sim *s, int damage, unsigned wave,
                        ember_fixed source_x, ember_fixed source_y)
{
    struct ember_player *p = &s->player;
    if (p->invulnerable || p->dash) return;
    struct ember_attack hit = {.base = damage * ember_waves[wave - 1].damage_percent / 100,
        .attack = 100, .crit_damage = 150, .share = {100,0,0,0,0,0}};
    int lit = illuminated(s, source_x, source_y);
    if (!lit) hit.increased = ember_lighting[0].dark_damage;
    struct ember_damage_result r = ember_damage(&s->combat_rng, &hit, &p->defense, &p->hp);
    if (r.dodged || (!r.damage && !r.absorbed)) return;
    p->invulnerable = p->defense.invulnerable;
    p->flash = 8;
    p->action = EMBER_HURT;
    p->action_time = 8;
    p->charge = (uint16_t)minimum(ember_characters[0].charge_max, p->charge + r.damage);
    event(s, 8, (unsigned)r.damage, p->x, p->y);
    if (p->hp <= 0) { p->action = EMBER_DEAD; s->phase = EMBER_LOST; }
}
static void enemy_spawn(struct ember_sim *s)
{
    const struct ember_waves_row *w = &ember_waves[s->wave - 1];
    unsigned candidates[3];
    unsigned count = 0;
    for (unsigned k = 0; k < EMBER_ENEMIES_COUNT; ++k)
        if (strstr(w->enemy, ember_enemies[k].id)) candidates[count++] = k;
    unsigned kind = candidates[ember_random(&s->spawn_rng) % count];
    uint16_t angle = (uint16_t)ember_random(&s->spawn_rng);
    int radius = w->spawn_radius + (int)(ember_random(&s->spawn_rng) % w->spawn_jitter);
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        struct ember_enemy *e = &s->enemies[i];
        if (e->alive) continue;
        *e = (struct ember_enemy){0};
        e->alive = 1;
        e->kind = (uint8_t)kind;
        e->x = clamp(s->player.x + ember_cos(angle) * radius,
                     12 * EMBER_Q, s->world_width - 12 * EMBER_Q);
        e->y = clamp(s->player.y + ember_sin(angle) * radius,
                     12 * EMBER_Q, s->world_height - 12 * EMBER_Q);
        e->hp = ember_enemies[kind].hp * w->hp_percent / 100;
        e->wave = s->wave;
        e->timer = (uint16_t)(ember_enemies[kind].initial_delay +
            ember_random(&s->spawn_rng) % ember_enemies[kind].delay_jitter);
        if (w->elite) {
            e->affix = (uint8_t)(1 + s->spawned % EMBER_AFFIXES_COUNT);
            e->hp = e->hp * ember_affixes[e->affix - 1].hp_percent / 100;
            e->shield = ember_affixes[e->affix - 1].shield;
        }
        ember_defense_init(&e->defense, e->hp);
        e->defense.armor = ember_enemies[kind].armor;
        if (w->elite) e->defense.tenacity = 50;
        e->defense.temporary[EMBER_DAMAGE_TYPES] = e->shield;
        ++s->spawned;
        ++s->alive_count;
        return;
    }
    fputs("ember enemy pool exhausted\n", stderr);
    abort();
}
/* Resolve circular reefs geometrically; project the proposed position to the rim. */
static void obstacles_resolve(const struct ember_sim *s, ember_fixed *x,
                              ember_fixed *y, int radius)
{
    for (unsigned i = 0; i < s->obstacle_count; ++i) {
        const struct ember_obstacle *o = &s->obstacles[i];
        int r = radius + o->radius;
        if (!within(*x, *y, o->x, o->y, r)) continue;
        ember_fixed dx = *x - o->x;
        ember_fixed dy = *y - o->y;
        uint32_t length = square_root((int64_t)dx * dx + (int64_t)dy * dy);
        if (!length) { *x = o->x + r * EMBER_Q; continue; }
        *x = o->x + (ember_fixed)((int64_t)dx * r * EMBER_Q / length);
        *y = o->y + (ember_fixed)((int64_t)dy * r * EMBER_Q / length);
    }
}
static void enemies_step(struct ember_sim *s)
{
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        struct ember_enemy *e = &s->enemies[i];
        if (!e->alive) continue;
        const struct ember_enemies_row *d = &ember_enemies[e->kind];
        if (e->flash) --e->flash;
        int controlled = e->defense.frozen || e->defense.status[EMBER_STUN].frames ||
            e->defense.broken;
        e->burn = e->defense.status[EMBER_IGNITE].frames;
        if (e->burn && ++e->burn_tick >= ember_statuses[0].interval) {
            e->burn_tick = 0;
            int damage = ember_statuses[0].damage * e->defense.status[EMBER_IGNITE].stacks *
                s->attributes[EMBER_STATUS_STRENGTH] / 100;
            enemy_hit(s, i, damage, e->burn_weapon, 0, 1);
            if (!e->alive) continue;
        }
        ember_defense_step(&e->defense);
        e->burn = e->defense.status[EMBER_IGNITE].frames;
        int max_hp = (int)((int64_t)e->defense.max_hp * (100 -
            e->defense.status[EMBER_CORRODE].stacks *
            ember_statuses[EMBER_CORRODE].strength) / 100);
        e->hp = minimum(e->hp, max_hp);
        if (controlled) {
            e->vx = e->vy = 0;
            continue;
        }
        int speed = d->speed;
        if (e->defense.status[EMBER_CHILL].frames)
            speed = speed * (100 - e->defense.status[EMBER_CHILL].stacks *
                ember_statuses[EMBER_CHILL].strength) / 100;
        for (unsigned n = 0; n < 8; ++n)
            if (s->pillars[n].lit && within(e->x, e->y, s->pillars[n].x, s->pillars[n].y,
                ember_lighting[0].pillar_radius)) { speed = speed *
                    (100 - ember_lighting[0].enemy_slow) / 100; break; }
        if (e->affix) speed = speed * ember_affixes[e->affix - 1].speed_percent / 100;
        if (e->timer) --e->timer;
        ember_fixed dx = s->player.x - e->x;
        ember_fixed dy = s->player.y - e->y;
        if (e->kind == 1) {
            if (e->mode == 1 && !e->timer) {
                e->mode = 2;
                e->timer = (uint16_t)d->charge_duration;
                velocity(dx, dy, d->charge_speed, &e->vx, &e->vy);
            } else if (e->mode == 2 && !e->timer) {
                e->mode = 0;
                e->timer = (uint16_t)d->attack_cooldown;
            } else if (e->mode == 0 && !e->timer &&
                       within(e->x, e->y, s->player.x, s->player.y, d->attack_range)) {
                e->mode = 1;
                e->timer = (uint16_t)d->charge_frames;
                e->vx = 0;
                e->vy = 0;
            }
            if (e->mode == 0) velocity(dx, dy, speed, &e->vx, &e->vy);
        } else if (e->kind == 2) {
            int range = d->attack_range;
            if (within(e->x, e->y, s->player.x, s->player.y, range - d->range_hysteresis))
                velocity(-dx, -dy, speed, &e->vx, &e->vy);
            else if (!within(e->x, e->y, s->player.x, s->player.y, range + d->range_hysteresis))
                velocity(dx, dy, speed, &e->vx, &e->vy);
            else { e->vx = 0; e->vy = 0; }
            if (!e->timer) {
                struct ember_shot *p = shot(s, 6, e->x, e->y, d->damage,
                                            d->projectile_radius, d->projectile_life);
                p->hostile = 1;
                p->weapon = (uint8_t)e->wave;
                velocity(dx, dy, d->projectile_speed, &p->vx, &p->vy);
                e->timer = (uint16_t)d->attack_cooldown;
                event(s, 0, (unsigned)d->damage, e->x, e->y);
            }
        } else velocity(dx, dy, speed, &e->vx, &e->vy);
        e->x = clamp(e->x + e->vx, 8 * EMBER_Q, s->world_width - 8 * EMBER_Q);
        e->y = clamp(e->y + e->vy, 8 * EMBER_Q, s->world_height - 8 * EMBER_Q);
        obstacles_resolve(s, &e->x, &e->y, d->radius);
        if (within(e->x, e->y, s->player.x, s->player.y,
                   d->radius + ember_characters[0].body_radius))
            if (!e->defense.status[EMBER_BLIND].frames ||
                ember_random(&s->combat_rng) % 100 >=
                    (unsigned)ember_statuses[EMBER_BLIND].strength)
                player_hurt(s, d->damage, e->wave, e->x, e->y);
    }
}
static void weapon_fire(struct ember_sim *s, unsigned w)
{
    struct ember_player *player = &s->player;
    int target = nearest(s);
    if (target < 0) return;
    const struct ember_weapons_row *d = &ember_weapons[w];
    unsigned category = s->weapon_system[w].category;
    int damage = d->damage * (100 + d->damage_per_level *
        ((int)player->weapon_level[w] - 1)) / 100;
    if (s->dual_wield) damage = damage * 70 / 100;
    int radius = d->radius * s->attributes[EMBER_AREA] / 100;
    int count = d->count + s->attributes[EMBER_PROJECTILES] - 1;
    if (category == EMBER_CROSSBOW) count = 3;
    if (inscription(s, w, 0)) count *= ember_inscriptions[0].value;
    int rate = attribute(s, EMBER_ATTACK_SPEED, s->attributes[EMBER_ATTACK_SPEED], d->tags);
    s->weapon_timer[w] = (uint16_t)maximum(1,
        d->cooldown * (100 - s->attributes[EMBER_COOLDOWN]) / rate);
    ember_fixed dx = s->enemies[target].x - player->x;
    ember_fixed dy = s->enemies[target].y - player->y;
    player->facing = abs(dx) >= abs(dy) ? (dx >= 0 ? 0 : 2) : (dy >= 0 ? 1 : 3);
    player->action = EMBER_ATTACKING;
    player->action_time = (uint16_t)minimum(12, s->weapon_timer[w]);
    unsigned combos = category == EMBER_SWORD || category == EMBER_SPEAR ? 3 :
                      category == EMBER_BLADES ? 4 : category == EMBER_GREATSWORD ? 2 : 1;
    player->combo = (uint8_t)((player->combo + 1) % combos);
    if (category <= EMBER_HAMMER) {
        int reach = maximum(40, radius);
        if (category == EMBER_SPEAR) reach *= 2;
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
            struct ember_enemy *e = &s->enemies[i];
            if (!e->alive || !within(player->x, player->y, e->x, e->y, reach)) continue;
            int64_t ex = (e->x - player->x) / EMBER_Q;
            int64_t ey = (e->y - player->y) / EMBER_Q;
            int64_t ax = dx / EMBER_Q, ay = dy / EMBER_Q;
            if (category != EMBER_HAMMER &&
                ex * ax + ey * ay < 0) continue;
            if (category == EMBER_SPEAR && llabs(ex * ay - ey * ax) >
                (int64_t)16 * square_root(ax * ax + ay * ay)) continue;
            enemy_hit(s, i, damage, w, 0, 0);
            if (e->alive && category == EMBER_HAMMER) ember_sim_status(s, i, EMBER_STUN, 0);
            if (e->alive && category == EMBER_GREATSWORD)
                velocity(e->x - player->x, e->y - player->y,
                    s->attributes[EMBER_KNOCKBACK], &e->vx, &e->vy);
        }
    } else {
        unsigned kind = category == EMBER_CODEX ? 2 : 0;
        for (int n = 0; n < count; ++n) {
            struct ember_shot *p = shot(s, kind, player->x, player->y, damage,
                category == EMBER_CODEX ? maximum(radius, 40) : minimum(radius, 8),
                maximum(d->area_frames, d->duration * s->attributes[EMBER_DURATION] / 100));
            p->weapon = (uint8_t)w;
            p->follow = (uint8_t)(category == EMBER_CODEX || inscription(s, w, 1));
            p->pierce = (uint8_t)d->pierce;
            if (kind == 0) {
                velocity(dx, dy, maximum(180, d->speed) *
                    s->attributes[EMBER_PROJECTILE_SPEED] / 100, &p->vx, &p->vy);
                uint16_t angle = (uint16_t)((n * 2 - count + 1) * d->spread_angle);
                ember_fixed vx = ember_mul(p->vx, ember_cos(angle)) -
                                 ember_mul(p->vy, ember_sin(angle));
                p->vy = ember_mul(p->vx, ember_sin(angle)) + ember_mul(p->vy, ember_cos(angle));
                p->vx = vx;
            }
        }
    }
    event(s, 0, (unsigned)damage, player->x, player->y);
}
static void weapons_step(struct ember_sim *s, uint16_t input)
{
    for (unsigned w = 0; w < 4; ++w) if (s->weapon_timer[w]) --s->weapon_timer[w];
    struct ember_player *p = &s->player;
    if (input & EMBER_J) {
        if (!s->weapon_timer[p->main_weapon]) weapon_fire(s, p->main_weapon);
        if (s->dual_wield && !s->weapon_timer[p->sub_weapon]) weapon_fire(s, p->sub_weapon);
    }
    unsigned sub = p->sub_weapon;
    if (s->weapon_system[sub].rarity >= 2 && s->weapon_system[sub].offhand &&
        !s->weapon_timer[sub]) weapon_fire(s, sub);
    s->pet.x = p->x - 20 * EMBER_Q;
    s->pet.y = p->y + 16 * EMBER_Q;
    if (p->pet_weapon == 255) return;
    if (p->pet_timer) { --p->pet_timer; return; }
    int target = nearest(s);
    if (target < 0) return;
    p->pet_timer = s->pet.cooldown;
    struct ember_attack h = {.base = s->pet.damage, .attack = 100, .crit_damage = 150,
        .share = {100,0,0,0,0,0}};
    struct ember_enemy *e = &s->enemies[target];
    if (s->pet.category == 0) {
        if (within(s->pet.x, s->pet.y, e->x, e->y, 48)) ember_sim_hit(s, target, &h);
    } else if (s->pet.category == 3) {
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
            if (s->enemies[i].alive && within(s->pet.x, s->pet.y,
                s->enemies[i].x, s->enemies[i].y, ember_lighting[0].pillar_radius))
                ember_sim_hit(s, i, &h);
    } else {
        struct ember_shot *q = shot(s, 0, s->pet.x, s->pet.y, s->pet.damage, 4, 120);
        q->pet = 1;
        velocity(e->x - q->x, e->y - q->y, 240, &q->vx, &q->vy);
    }
}
static void shots_step(struct ember_sim *s)
{
    for (unsigned i = 0; i < EMBER_SHOTS; ++i) {
        struct ember_shot *p = &s->shots[i];
        if (!p->alive) continue;
        if (p->pet && s->pet.category == 2) {
            int target = nearest(s);
            if (target >= 0) velocity(s->enemies[target].x - p->x,
                s->enemies[target].y - p->y, 240, &p->vx, &p->vy);
        }
        p->x += p->vx;
        p->y += p->vy;
        if (p->follow && p->kind != 3) { p->x = s->player.x; p->y = s->player.y; }
        if (p->kind == 3) {
            p->z = maximum(0, p->z + p->vz);
            p->vz -= ember_weapons[p->weapon].lob_gravity_q16;
        }
        --p->life;
        if (p->hostile) {
            if (within(p->x, p->y, s->player.x, s->player.y,
                       p->radius + ember_characters[0].body_radius)) {
                player_hurt(s, p->damage, p->weapon, p->x, p->y);
                p->alive = 0;
            }
        } else if (p->kind == 0) {
            int cx = clamp(p->x / (32 * EMBER_Q), 0, EMBER_GRID_COLUMNS - 1);
            int cy = clamp(p->y / (32 * EMBER_Q), 0, EMBER_GRID_ROWS - 1);
            for (int y = maximum(0, cy - 1); y <= minimum(EMBER_GRID_ROWS - 1, cy + 1); ++y)
                for (int x = maximum(0, cx - 1); x <= minimum(EMBER_GRID_COLUMNS - 1, cx + 1); ++x)
                    for (int e = s->grid[y * EMBER_GRID_COLUMNS + x]; e >= 0;
                         e = s->next_enemy[e]) {
                        struct ember_enemy *enemy = &s->enemies[e];
                        if (!p->alive || !enemy->alive || e == p->last_hit) continue;
                        if (within(p->x, p->y, enemy->x, enemy->y,
                                   p->radius + ember_enemies[enemy->kind].radius)) {
                            if (p->pet) {
                                struct ember_attack hit = {.base = p->damage, .attack = 100,
                                    .crit_damage = 150, .share = {100,0,0,0,0,0}};
                                ember_sim_hit(s, (unsigned)e, &hit);
                            } else enemy_hit(s, (unsigned)e, p->damage, p->weapon, 0, 0);
                            p->last_hit = (int16_t)e;
                            if (p->pierce) --p->pierce;
                            else p->alive = 0;
                        }
                    }
        } else if ((p->kind == 1 || p->kind == 5) && !p->tick) {
            area_hit(s, p->x, p->y, p->radius, p->damage, p->weapon, 0, 0);
            p->tick = 1;
        } else if (p->kind == 2) {
            if (!p->tick) {
                area_hit(s, p->x, p->y, p->radius, p->damage, p->weapon, 0, 0);
                p->tick = (uint16_t)ember_weapons[2].tick_interval;
            }
            --p->tick;
        } else if ((p->kind == 3 || p->kind == 4) && !p->life) {
            if (p->follow) { p->x = s->player.x; p->y = s->player.y; }
            p->kind = 1;
            p->z = 0;
            p->vx = 0;
            p->vy = 0;
            p->life = (uint16_t)ember_weapons[1].area_frames;
            area_hit(s, p->x, p->y, p->radius, p->damage, p->weapon, 0, 0);
            p->tick = 1;
        }
        if (!p->life || p->x < -32 * EMBER_Q || p->x > s->world_width + 32 * EMBER_Q ||
            p->y < -32 * EMBER_Q || p->y > s->world_height + 32 * EMBER_Q) p->alive = 0;
        if (!p->alive) --s->shot_count;
    }
}
static void player_step(struct ember_sim *s, uint16_t input, uint16_t pressed)
{
    struct ember_player *p = &s->player;
    ember_defense_step(&p->defense);
    if (p->action_time) --p->action_time;
    else p->action = EMBER_IDLE;
    if (p->cooldown_k) --p->cooldown_k;
    if (p->cooldown_a) --p->cooldown_a;
    if (p->cooldown_b) --p->cooldown_b;
    if (p->invulnerable) --p->invulnerable;
    if (p->flash) --p->flash;
    if (s->combat_frame % ember_characters[0].charge_interval == 0 &&
        p->charge < ember_characters[0].charge_max) ++p->charge;
    if (s->combat_frame % 60 == 0)
        p->hp = minimum(p->max_hp, p->hp + s->attributes[EMBER_REGEN]);
    int dx = !!(input & EMBER_RIGHT) - !!(input & EMBER_LEFT);
    int dy = !!(input & EMBER_DOWN) - !!(input & EMBER_UP);
    if (dx) p->facing = dx > 0 ? 0 : 2;
    else if (dy) p->facing = dy > 0 ? 1 : 3;
    if (pressed & EMBER_SWAP) {
        unsigned old = p->main_weapon;
        p->main_weapon = p->sub_weapon;
        p->sub_weapon = (uint8_t)old;
        p->combo = 0;
        ember_sim_attributes(s);
    }
    if ((pressed & EMBER_U) && p->charge == ember_characters[0].charge_max) {
        shot(s, 5, p->x, p->y, ember_characters[0].ultimate_damage,
             ember_characters[0].ultimate_radius * s->attributes[EMBER_AREA] / 100,
             ember_characters[0].ultimate_frames);
        p->charge = 0;
        p->action = EMBER_CAST;
        p->action_time = 12;
        event(s, 5, (unsigned)ember_characters[0].ultimate_damage, p->x, p->y);
    }
    if (((pressed & EMBER_DASH) && !p->cooldown_a) ||
        ((pressed & EMBER_K) && !p->cooldown_k)) {
        if (!dx && !dy) {
            dx = p->facing == 0 ? 1 : p->facing == 2 ? -1 : 0;
            dy = p->facing == 1 ? 1 : p->facing == 3 ? -1 : 0;
        }
        velocity(dx * EMBER_Q, dy * EMBER_Q,
                 p->speed * ember_characters[0].dash_speed_percent / 100,
                 &s->dash_vx, &s->dash_vy);
        p->dash = (uint16_t)ember_characters[0].dash_frames;
        p->defense.invulnerable = p->dash;
        if (pressed & EMBER_K) p->cooldown_k = (uint16_t)s->attributes[EMBER_DASH_COOLDOWN];
        else p->cooldown_a = (uint16_t)s->attributes[EMBER_DASH_COOLDOWN];
        event(s, 3, 0, p->x, p->y);
    }
    if ((pressed & EMBER_L) && !p->cooldown_b) {
        shot(s, 4, p->x, p->y, ember_characters[0].seed_damage,
             ember_characters[0].seed_radius * s->attributes[EMBER_AREA] / 100,
             ember_characters[0].seed_delay);
        p->cooldown_b = (uint16_t)(ember_characters[0].seed_cooldown *
            (100 - s->attributes[EMBER_COOLDOWN]) / 100);
        p->action = EMBER_CAST;
        p->action_time = 12;
        event(s, 4, (unsigned)ember_characters[0].seed_damage, p->x, p->y);
    }
    if (pressed & EMBER_INTERACT) {
        for (unsigned i = 0; i < 8; ++i) {
            if (!s->pillars[i].lit && within(p->x, p->y, s->pillars[i].x, s->pillars[i].y,
                ember_lighting[0].interact_radius) && s->oil >= ember_lighting[0].pillar_cost) {
                s->oil -= ember_lighting[0].pillar_cost;
                s->pillars[i].lit = 1;
                p->action = EMBER_INTERACTING;
                p->action_time = 12;
                break;
            }
        }
    }
    if (p->dash) {
        p->action = EMBER_DASHING;
        p->x += s->dash_vx;
        p->y += s->dash_vy;
        if (p->dash % ember_characters[0].trail_interval == 0)
            shot(s, 2, p->x, p->y, ember_characters[0].trail_damage,
                 ember_characters[0].trail_radius * s->attributes[EMBER_AREA] / 100,
                 ember_characters[0].trail_duration);
        --p->dash;
    } else {
        if ((dx || dy) && !p->action_time) p->action = EMBER_MOVE;
        ember_fixed vx, vy;
        velocity(dx * EMBER_Q, dy * EMBER_Q, p->speed, &vx, &vy);
        p->x += vx;
        p->y += vy;
    }
    obstacles_resolve(s, &p->x, &p->y, ember_characters[0].body_radius);
    p->x = clamp(p->x, ember_characters[0].boundary_margin * EMBER_Q,
                 s->world_width - ember_characters[0].boundary_margin * EMBER_Q);
    p->y = clamp(p->y, ember_characters[0].boundary_margin * EMBER_Q,
                 s->world_height - ember_characters[0].boundary_margin * EMBER_Q);
}
static void pickups_step(struct ember_sim *s, int all)
{
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        struct ember_pickup *p = &s->pickups[i];
        if (p->alive && (all || within(p->x, p->y, s->player.x, s->player.y,
                                      s->attributes[EMBER_PICKUP]))) {
            s->oil = minimum(ember_lighting[0].oil_max, s->oil + ember_lighting[0].ember_oil);
            s->player.charge = (uint16_t)minimum(ember_characters[0].charge_max,
                s->player.charge + ember_characters[0].charge_kill);
            s->player.xp += p->xp * (unsigned)s->attributes[EMBER_XP] / 100;
            p->alive = 0;
            --s->pickup_count;
        }
    }
}
static void upgrade_offer(struct ember_sim *s)
{
    struct ember_choice eligible[42];
    unsigned count = 0;
    unsigned weapons = 0;
    unsigned relics = 0;
    for (unsigned i = 0; i < EMBER_WEAPONS_COUNT; ++i) weapons += !!s->player.weapon_level[i];
    for (unsigned i = 0; i < EMBER_RELICS_COUNT; ++i) relics += !!s->player.relic_level[i];
    for (unsigned i = 0; i < EMBER_WEAPONS_COUNT; ++i) {
        if (s->player.weapon_level[i] < ember_weapons[i].level_max &&
            (s->player.weapon_level[i] || weapons < 2))
            eligible[count++] = (struct ember_choice){0, (uint8_t)i, 0};
    }
    for (unsigned i = 0; i < EMBER_RELICS_COUNT; ++i)
        if (s->player.relic_level[i] < ember_relics[i].level_max &&
            (s->player.relic_level[i] || relics < 6))
            eligible[count++] = (struct ember_choice){1, (uint8_t)i, 0};
    for (unsigned w = 0; w < EMBER_WEAPONS_COUNT; ++w) {
        if (!s->player.weapon_level[w] || s->player.inscription[w][1]) continue;
        for (unsigned i = 0; i < EMBER_INSCRIPTIONS_COUNT; ++i) {
            if (inscription(s, w, i)) continue;
            if (i == 0 && !tagged(w, "projectile")) continue;
            if (i == 1 && !tagged(w, "area")) continue;
            eligible[count++] = (struct ember_choice){2, (uint8_t)i, (uint8_t)w};
        }
    }
    /* Existing five-wave content does not exhaust its eligible upgrades. */
    for (unsigned i = 0; i < 3; ++i) {
        unsigned pick = ember_random(&s->loot_rng) % count;
        s->choices[i] = eligible[pick];
        eligible[pick] = eligible[--count];
    }
    s->selected = 0;
    s->phase = EMBER_UPGRADE;
    s->player.xp -= s->player.next_xp;
    ++s->player.level;
    s->player.next_xp += ember_characters[0].xp_per_level;
    event(s, 6, 0, s->player.x, s->player.y);
}
static void upgrade_choose(struct ember_sim *s)
{
    const struct ember_choice *c = &s->choices[s->selected];
    int old_hp = s->player.max_hp;
    if (c->kind == 0) {
        if (!s->player.weapon_level[c->id]) s->player.sub_weapon = c->id;
        ++s->player.weapon_level[c->id];
    }
    else if (c->kind == 1) ++s->player.relic_level[c->id];
    else {
        unsigned slot = !!s->player.inscription[c->slot][0];
        s->player.inscription[c->slot][slot] = (uint8_t)(c->id + 1);
    }
    ember_sim_attributes(s);
    s->player.hp += s->player.max_hp - old_hp;
    s->phase = EMBER_PLAY;
    event(s, 7, 0, s->player.x, s->player.y);
}
void ember_sim_init(struct ember_sim *s, uint32_t seed)
{
    memset(s, 0, sizeof(*s));
    s->phase = EMBER_MENU;
    s->rng_seed = seed;
    /* Independent odd stream seeds also give seed zero a defined nonzero stream. */
    s->spawn_rng.state = seed * 2u + 1u;
    s->combat_rng.state = seed * 2u + 3u;
    s->loot_rng.state = seed * 2u + 5u;
    s->world_width = ember_stages[0].width * EMBER_Q;
    s->world_height = ember_stages[0].height * EMBER_Q;
    s->safe_right = s->world_width;
    s->safe_bottom = s->world_height;
    for (unsigned i = 0; i < EMBER_OBSTACLES_COUNT; ++i) {
        if (strcmp(ember_obstacles[i].stage, ember_stages[0].id)) continue;
        s->obstacles[s->obstacle_count++] = (struct ember_obstacle){
            ember_obstacles[i].x * EMBER_Q, ember_obstacles[i].y * EMBER_Q,
            (uint16_t)ember_obstacles[i].radius};
    }
    s->player.x = s->world_width / 2;
    s->player.y = s->world_height / 2;
    s->player.level = 1;
    s->player.next_xp = (uint32_t)ember_characters[0].initial_xp;
    s->player.weapon_level[0] = s->player.weapon_level[1] = 1;
    s->player.main_weapon = 0;
    s->player.sub_weapon = 1;
    s->player.pet_weapon = 0;
    ember_defense_init(&s->player.defense, ember_characters[0].max_hp);
    s->player.defense.hurt_frames = (uint16_t)ember_characters[0].hurt_interval;
    s->oil = ember_lighting[0].oil_max;
    s->pet.damage = ember_system[0].pet_damage;
    s->pet.cooldown = (uint16_t)ember_system[0].pet_cooldown;
    for (unsigned i = 0; i < 4; ++i) {
        s->weapon_system[i].category = i == 1 ? EMBER_CODEX : EMBER_STAFF;
        s->weapon_system[i].share[EMBER_DAMAGE_FIRE] = 100;
        for (unsigned t = 0; t < EMBER_TAGS_COUNT; ++t)
            if (strstr(ember_weapons[i].tags, ember_tags[t].id))
                s->weapon_system[i].tags |= 1u << t;
    }
    for (unsigned i = 0; i < 8; ++i) {
        s->pillars[i].x = s->player.x + ((int)(i % 4) - 2) *
            ember_lighting[0].pillar_spacing * EMBER_Q;
        s->pillars[i].y = s->player.y + ((int)(i / 4) * 2 - 1) *
            ember_lighting[0].pillar_spacing * EMBER_Q;
    }
    ember_sim_attributes(s);
    s->player.hp = s->player.max_hp;
    s->pet.category = 1;
    s->in_light = 1;
    s->lamp_radius = ember_lighting[0].radius_base +
        s->oil * ember_lighting[0].radius_per_oil / 10000;
    grid_build(s);
}
void ember_sim_step(struct ember_sim *s, uint16_t input)
{
    uint16_t pressed = input & (uint16_t)~s->previous_input;
    s->previous_input = input;
    s->events.count = 0;
    ++s->frame;
    if (s->phase == EMBER_MENU) {
        if (pressed & EMBER_START) { s->phase = EMBER_PLAY; s->wave = 1; }
        return;
    }
    if (s->phase == EMBER_UPGRADE) {
        if (pressed & (EMBER_UP | EMBER_LEFT)) s->selected = (s->selected + 2) % 3;
        if (pressed & (EMBER_DOWN | EMBER_RIGHT)) s->selected = (s->selected + 1) % 3;
        if (pressed & EMBER_A) upgrade_choose(s);
        return;
    }
    if (s->phase != EMBER_PLAY) return;
    if (pressed & EMBER_START) s->paused ^= 1;
    if (s->paused) return;
    ++s->combat_frame;
    player_step(s, input, pressed);
    const struct ember_lighting_row *light = &ember_lighting[0];
    s->oil_fraction += s->combat_frame > (unsigned)ember_stages[0].time_limit ?
        light->tide_drain * 100 / s->attributes[EMBER_FUEL_EFFICIENCY] :
        light->drain * 100 / s->attributes[EMBER_FUEL_EFFICIENCY];
    s->oil = maximum(0, s->oil - s->oil_fraction / 60);
    s->oil_fraction %= 60;
    s->lamp_radius = (light->radius_base + s->oil * light->radius_per_oil / 10000) *
        s->attributes[EMBER_LAMP_RADIUS] / 100;
    s->in_light = (uint8_t)illuminated(s, s->player.x, s->player.y);
    for (unsigned i = 0; i < 8; ++i) {
        if (s->pillars[i].x < s->safe_left || s->pillars[i].x > s->safe_right ||
            s->pillars[i].y < s->safe_top || s->pillars[i].y > s->safe_bottom)
            s->pillars[i].lit = 0;
        if (s->pillars[i].lit && within(s->player.x, s->player.y,
            s->pillars[i].x, s->pillars[i].y, light->pillar_radius)) s->in_light = 1;
    }
    const struct ember_stages_row *stage = &ember_stages[0];
    if (s->combat_frame > (unsigned)stage->time_limit) {
        if ((s->combat_frame - stage->time_limit) % stage->shrink_interval == 0) {
            int inset = stage->shrink_pixels * EMBER_Q;
            s->safe_left = minimum(s->world_width / 2, s->safe_left + inset);
            s->safe_top = minimum(s->world_height / 2, s->safe_top + inset);
            s->safe_right = maximum(s->world_width / 2, s->safe_right - inset);
            s->safe_bottom = maximum(s->world_height / 2, s->safe_bottom - inset);
        }
        if (s->combat_frame % 60 == 0 &&
            (s->player.x < s->safe_left || s->player.x > s->safe_right ||
             s->player.y < s->safe_top || s->player.y > s->safe_bottom))
            player_hurt(s, stage->outside_damage, s->wave, s->player.x, s->player.y);
    }
    const struct ember_waves_row *w = &ember_waves[s->wave - 1];
    if (!s->rest) {
        if (s->spawned < (unsigned)w->count && s->wave_frame % w->spawn_interval == 0)
            enemy_spawn(s);
        ++s->wave_frame;
    }
    grid_build(s);
    enemies_step(s);
    grid_build(s);
    weapons_step(s, input);
    shots_step(s);
    s->player.action_frame = (uint8_t)((s->combat_frame / 4) % 8);
    s->player.hand_x = (int16_t)(s->player.facing == 0 ? 8 : s->player.facing == 2 ? -8 : 0);
    s->player.hand_y = (int16_t)(s->player.facing == 1 ? 8 : s->player.facing == 3 ? -8 : 2);
    if (s->player.action == EMBER_ATTACKING) {
        s->player.hand_x += (int16_t)((int)s->player.action_frame - 4);
        s->player.hand_y -= (int16_t)(s->player.combo * 2);
    }
    pickups_step(s, !!s->rest);
    if (s->phase == EMBER_LOST) return;
    if (s->rest) {
        if (!--s->rest) {
            ++s->wave;
            s->wave_frame = 0;
            s->spawned = 0;
        }
    } else if (!s->alive_count && s->spawned == (unsigned)w->count) {
        pickups_step(s, 1);
        if (s->wave == EMBER_WAVES_COUNT) {
            s->phase = EMBER_WON;
            event(s, 9, 0, s->player.x, s->player.y);
            return;
        }
        s->rest = (unsigned)w->rest_frames;
    } else if (s->wave_frame >= (unsigned)w->time_limit && s->wave < EMBER_WAVES_COUNT) {
        ++s->wave;
        s->wave_frame = 0;
        s->spawned = 0;
    }
    if (s->player.xp >= s->player.next_xp) upgrade_offer(s);
}
void ember_sim_summary(const struct ember_sim *s, char *text, size_t bytes)
{
    const struct ember_player *p = &s->player;
    int32_t enemy_hp = 0;
    int32_t enemy_shield = 0;
    unsigned burning = 0;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) if (s->enemies[i].alive) {
        enemy_hp += s->enemies[i].hp;
        enemy_shield += s->enemies[i].shield;
        burning += !!s->enemies[i].burn;
    }
    unsigned status_frames[EMBER_STATUS_COUNT] = {0};
    int32_t posture = 0;
    unsigned pillars = 0;
    for (unsigned i = 0; i < 8; ++i) pillars |= s->pillars[i].lit << i;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) if (s->enemies[i].alive) {
        posture += s->enemies[i].defense.posture;
        for (unsigned n = 0; n < EMBER_STATUS_COUNT; ++n)
            status_frames[n] += s->enemies[i].defense.status[n].frames;
    }
    snprintf(text, bytes,
        "frame=%u combat=%u phase=%u paused=%u wave=%u wave_frame=%u rest=%u spawned=%u "
        "enemies=%u shots=%u pickups=%u hp=%d max_hp=%d armor=%d speed=%d x=%d y=%d "
        "xp=%u next_xp=%u level=%u kills=%u damage=%u charge=%u a=%u b=%u dash=%u "
        "enemy_hp=%d enemy_shield=%d burning=%u weapons=%u,%u,%u,%u "
        "relics=%u,%u,%u,%u,%u,%u inscriptions=%u,%u,%u,%u,%u,%u,%u,%u "
        "attack=%d area=%d rate=%d timers=%u,%u,%u,%u safe=%d,%d,%d,%d "
        "rng=%u,%u,%u seed=%u oil=%d radius=%d light=%u slots=%u,%u,%u action=%u,%u "
        "shield=%d chain=%u pillars=%u posture=%d statuses=%u,%u,%u,%u,%u,%u,%u,%u "
        "pet=%d,%d,%u facing=%u hand=%d,%d",
        (unsigned)s->frame, (unsigned)s->combat_frame, (unsigned)s->phase, (unsigned)s->paused,
        (unsigned)s->wave, (unsigned)s->wave_frame, (unsigned)s->rest, (unsigned)s->spawned,
        (unsigned)s->alive_count, (unsigned)s->shot_count, (unsigned)s->pickup_count, (int)p->hp,
        (int)p->max_hp, (int)p->armor, (int)p->speed, (int)p->x, (int)p->y, (unsigned)p->xp,
        (unsigned)p->next_xp, (unsigned)p->level, (unsigned)p->kills, (unsigned)s->damage_total,
        (unsigned)p->charge, (unsigned)p->cooldown_a, (unsigned)p->cooldown_b, (unsigned)p->dash,
        (int)enemy_hp, (int)enemy_shield, (unsigned)burning, (unsigned)p->weapon_level[0],
        (unsigned)p->weapon_level[1], (unsigned)p->weapon_level[2], (unsigned)p->weapon_level[3],
        (unsigned)p->relic_level[0], (unsigned)p->relic_level[1], (unsigned)p->relic_level[2],
        (unsigned)p->relic_level[3], (unsigned)p->relic_level[4], (unsigned)p->relic_level[5],
        (unsigned)p->inscription[0][0], (unsigned)p->inscription[0][1],
        (unsigned)p->inscription[1][0], (unsigned)p->inscription[1][1],
        (unsigned)p->inscription[2][0], (unsigned)p->inscription[2][1],
        (unsigned)p->inscription[3][0], (unsigned)p->inscription[3][1],
        (int)s->attributes[EMBER_ATTACK], (int)s->attributes[EMBER_AREA],
        (int)s->attributes[EMBER_ATTACK_SPEED], (unsigned)s->weapon_timer[0],
        (unsigned)s->weapon_timer[1], (unsigned)s->weapon_timer[2], (unsigned)s->weapon_timer[3],
        (int)s->safe_left, (int)s->safe_top, (int)s->safe_right, (int)s->safe_bottom,
        (unsigned)s->spawn_rng.state, (unsigned)s->combat_rng.state, (unsigned)s->loot_rng.state,
        (unsigned)s->rng_seed, (int)s->oil, (int)s->lamp_radius, s->in_light,
        p->main_weapon, p->sub_weapon, p->pet_weapon, p->action, p->action_frame,
        (int)p->defense.permanent_shield, s->trigger_peak, pillars, (int)posture,
        status_frames[0], status_frames[1], status_frames[2], status_frames[3],
        status_frames[4], status_frames[5], status_frames[6], status_frames[7],
        (int)s->pet.x, (int)s->pet.y, p->pet_timer, p->facing, p->hand_x, p->hand_y);
}
