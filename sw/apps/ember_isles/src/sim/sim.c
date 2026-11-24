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

enum relic_id { R_IRON, R_HEART, R_BOOTS, R_BAG, R_STONE, R_LUCK, R_FEATHER,
    R_OIL, R_QUIVER, R_MIRROR, R_COAL, R_BELT, R_BUCKLE, R_BADGE, R_CLOAK,
    R_FROST, R_NEEDLE, R_FILE, R_FANG, R_CORE, R_ICE, R_STAR, R_ANVIL, R_EYE,
    R_FORGE, R_TIDE, R_LENS, R_HOURGLASS, R_RIFT, R_TWINS, R_LAMP, R_NIGHT,
    R_BELL, R_BONE, R_DARK_HEART, R_GALE, R_THORN, R_LINING };
static int relic(const struct ember_sim *s, unsigned id)
{
    return s->player.relic_level[id] ? ember_relics[id].value : 0;
}
static void heal(struct ember_sim *s, int amount);
static void leech(struct ember_sim *s, int damage, int percent);
static void inherited_area(struct ember_sim *s, ember_fixed x, ember_fixed y,
                            int radius, int damage, unsigned depth);
static void energy_add(struct ember_sim *s, int amount);
static void ground_effect(struct ember_sim *s, struct ember_shot *p);
static void pet_hit(struct ember_sim *s, unsigned target, int damage);
static void pet_hit_depth(struct ember_sim *s, unsigned target, int damage, unsigned depth);
static void pet_step(struct ember_sim *s);
static void skill_reflect(struct ember_sim *s, ember_fixed x, ember_fixed y, int damage);
static int content_enemy(struct ember_sim *s, unsigned index);
static void content_death(struct ember_sim *s, unsigned index, unsigned depth,
                          unsigned source_weapon, int damage);
static void content_step(struct ember_sim *s);
static void content_skill(struct ember_sim *s, unsigned key);
static void content_before_hit(struct ember_sim *s, unsigned index,
                               unsigned weapon, struct ember_attack *h);
static void content_after_hit(struct ember_sim *s, unsigned index, unsigned weapon,
                              struct ember_damage_result r, unsigned depth);
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
static unsigned direction8(ember_fixed dx, ember_fixed dy)
{
    if (llabs((int64_t)dx) > llabs((int64_t)dy) * 2) return dx >= 0 ? 2 : 6;
    if (llabs((int64_t)dy) > llabs((int64_t)dx) * 2) return dy >= 0 ? 0 : 4;
    return dy >= 0 ? (dx >= 0 ? 1 : 7) : (dx >= 0 ? 3 : 5);
}
static unsigned direction_frame(unsigned direction)
{
    const unsigned frames[] = {0,1,2,3,4,3,2,1};
    return frames[direction];
}
/* Front/rear is defined by retained facing, including stationary enemies. */
static int enemy_front(const struct ember_enemy *e, ember_fixed x, ember_fixed y)
{
    const uint16_t angles[8] = {16384,8192,0,57344,49152,40960,32768,24576};
    return (int64_t)ember_cos(angles[e->facing8]) * (x - e->x) +
        (int64_t)ember_sin(angles[e->facing8]) * (y - e->y) >= 0;
}
enum { HIT_DIRECTION_SET = 128 };
static unsigned pet_rune(const struct ember_sim *s)
{
    return s->player.pet_weapon == 255 ? 0 : s->player.pet_inscription[s->player.pet_weapon];
}
static struct ember_pet_weapons_row pet_weapon_data(const struct ember_sim *s)
{
    if (s->player.pet_weapon != 255) return ember_pet_weapons[s->player.pet_weapon];
    const struct ember_pets_row *p = &ember_pets[s->pet_kind];
    return (struct ember_pet_weapons_row){.category = p->category,
        .element_index = p->element_index, .damage = p->damage,
        .attack_cooldown = p->attack_cooldown,
        .range_pixels = p->native_range, .speed = p->native_projectile_speed,
        .duration = p->native_duration, .projectile_radius = p->native_radius};
}
static int light_zone_at(const struct ember_sim *s, ember_fixed x, ember_fixed y)
{
    for (unsigned i = 0; i < 8; ++i)
        if (s->pillars[i].lit && within(x, y, s->pillars[i].x, s->pillars[i].y,
            ember_lighting[0].pillar_radius)) return 1;
    if (s->player.relic_level[R_LAMP])
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
            if (s->enemies[i].alive && s->enemies[i].burn &&
                within(x, y, s->enemies[i].x, s->enemies[i].y, ember_relics[R_LAMP].value2)) return 1;
    for (unsigned i = 0; i < 8; ++i)
        if (s->summons[i].life && s->summons[i].kind == 1 &&
            within(x, y, s->summons[i].x, s->summons[i].y, ember_summons[1].light_radius)) return 1;
    if (s->pet_kind != 255 && s->pet.category == 3 &&
        within(x, y, s->pet.x, s->pet.y,
            pet_weapon_data(s).range_pixels)) return 1;
    return 0;
}
static int player_in_light_zone(const struct ember_sim *s)
{
    return !s->stealth && light_zone_at(s, s->player.x, s->player.y);
}
static int enemy_in_dark(const struct ember_sim *s, ember_fixed x, ember_fixed y)
{
    return !light_zone_at(s, x, y) && (s->lamp_disabled ||
        !within(x, y, s->player.x, s->player.y, s->lamp_radius));
}
static int tag_present(const char *tags, const char *tag)
{
    /* GDD 4.1: crit and on_crit are separate tags. */
    size_t length = strlen(tag);
    while (*tags) {
        const char *end = strchr(tags, '|');
        size_t token_length = end ? (size_t)(end - tags) : strlen(tags);
        if (token_length == length && !strncmp(tags, tag, length)) return 1;
        if (!end) break;
        tags = end + 1;
    }
    return 0;
}
static int tagged(unsigned weapon, const char *tag)
{
    return tag_present(ember_weapons[weapon].tags, tag);
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
    (void)tag;
    for (unsigned i = 0; i < EMBER_RELICS_COUNT; ++i) {
        const struct ember_relics_row *r = &ember_relics[i];
        if (strcmp(r->attribute, ember_attributes[a].id) || !s->player.relic_level[i])
            continue;
        flat += r->flat;
        increased += r->increased;
    }
    if (a == EMBER_ATTACK_SPEED && s->in_light && !relic(s, R_NIGHT))
        increased += relic(s, R_BADGE);
    if (a == EMBER_SPEED && !s->in_light) increased += relic(s, R_CLOAK) *
        (100 + relic(s, R_NIGHT)) / 100;
    if (a == EMBER_DODGE && !s->in_light && relic(s, R_CLOAK)) flat += ember_relics[R_CLOAK].value2 * (100 + relic(s, R_NIGHT)) / 100;
    if (a == EMBER_STATUS_DURATION && relic(s, R_COAL)) increased += ember_relics[R_COAL].value2;
    if (a == EMBER_AREA && relic(s, R_LENS)) increased -= ember_relics[R_LENS].value2;
    if (a == EMBER_FUEL_EFFICIENCY && relic(s, R_OIL))
        increased += 10000 / (100 - relic(s, R_OIL)) - 100;
    const struct ember_weapon_system *sub = &s->weapon_system[s->player.sub_weapon];
    if (sub->rarity >= 1 && sub->offhand_attribute == a) flat += sub->offhand_flat;
    int64_t result = (int64_t)(base + flat) * (100 + increased) / 100;
    int64_t cap = minimum(ember_attributes[a].maximum + s->cap_raise[a],
                          ember_attributes[a].range_maximum);
    return (int32_t)(result < ember_attributes[a].minimum ? ember_attributes[a].minimum :
                     result > cap ? cap : result);
}
void ember_sim_attributes(struct ember_sim *s)
{
    const struct ember_characters_row *c = &ember_characters[s->player.character];
    memcpy(s->cap_raise, s->contract_caps, sizeof(s->cap_raise));
    s->cap_raise[EMBER_CRIT] += relic(s, R_RIFT);
    s->cap_raise[EMBER_ATTACK_SPEED] += relic(s, R_GALE);
    s->dual_wield = !!relic(s, R_TWINS);
    s->trigger_bonus = (uint8_t)relic(s, R_BELL);
    s->dot_can_crit = !!relic(s, R_BONE);
    s->lamp_disabled = !!relic(s, R_NIGHT) || !!s->stealth || !!s->boss_blackout;
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
    if (s->curses[0]) s->attributes[EMBER_MAX_HP] = s->attributes[EMBER_MAX_HP] * (100 - ember_contracts[0].value) / 100;
    if (s->curses[2]) s->attributes[EMBER_FUEL_EFFICIENCY] = s->attributes[EMBER_FUEL_EFFICIENCY] * 100 / (100 + ember_contracts[2].value);
    if (s->curses[4]) s->attributes[EMBER_DASH_COUNT] -= ember_contracts[4].value;
    if (s->pet_kind != 255) {
        const struct ember_pets_row *pet = &ember_pets[s->pet_kind];
        for (unsigned a = 0; a < EMBER_ATTRIBUTE_COUNT; ++a)
            if (!strcmp(pet->attribute, ember_attributes[a].id))
                s->attributes[a] += pet->value;
    }
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
        p->dot_type = kind == 2 ? 3 : 0;
        p->x = p->origin_x = x;
        p->y = p->origin_y = y;
        p->damage = p->initial_damage = damage;
        p->radius = (uint16_t)radius;
        p->life = (uint16_t)life;
        p->weapon = p->enemy_kind = 255;
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
            (uint32_t)ember_enemies[e->kind].xp, 1, 0, 0};
        ++s->pickup_count;
        return;
    }
    fputs("ember pickup pool exhausted\n", stderr);
    abort();
}
static void area_hit(struct ember_sim *s, ember_fixed x, ember_fixed y,
                     int radius, int damage, unsigned weapon, unsigned depth, int periodic);
/* gdd 4.2/4.5: shards also follow a fatal hit, within the same trigger limit. */
static void shatter(struct ember_sim *s, unsigned index, unsigned depth)
{
    struct ember_enemy *e = &s->enemies[index];
    e->defense.frozen = 0;
    struct ember_attack linked = {.base = ember_system[0].shatter_damage *
        (s->resonances[4] ? ember_resonances[4].shard_percent : 100) / 100 *
        (100 + (s->blessings[7] ? ember_blessings[7].value : 0)) / 100,
        .attack = 100, .crit_damage = 150, .share = {100,0,0,0,0,0},
        .depth = (uint8_t)(depth + 1)};
    for (unsigned n = 0; n < EMBER_ENEMIES; ++n)
        if (s->enemies[n].alive && n != index && within(e->x, e->y,
            s->enemies[n].x, s->enemies[n].y, ember_system[0].chain_range))
            ember_sim_hit(s, n, &linked);
}
struct ember_damage_result ember_sim_hit(struct ember_sim *s, unsigned index,
                                         const struct ember_attack *hit)
{
    struct ember_enemy *e = &s->enemies[index];
    if (!e->alive || hit->depth > 3u + s->trigger_bonus)
        return (struct ember_damage_result){0};
    if (hit->depth > s->trigger_peak) s->trigger_peak = hit->depth;
    int frozen = e->defense.frozen;
    int vulnerability = e->defense.vulnerability;
    if (e->hunter_mark) e->defense.vulnerability += ember_characters[EMBER_DATA_CHARACTERS_HUNTER].skill_l_value;
    if (e->owl_mark) e->defense.vulnerability += ember_pets[3].skill_value;
    if (s->blessings[2] && !relic(s, R_NIGHT) && light_zone_at(s, e->x, e->y))
        e->defense.vulnerability += ember_blessings[2].value;
    if (ember_characters[s->player.character].mechanism == 5 && s->ultimate_time &&
        within(s->player.x, s->player.y, e->x, e->y, ember_characters[5].ultimate_radius))
        e->defense.vulnerability += ember_characters[5].ultimate_value2;
    struct ember_damage_result r = ember_damage(&s->combat_rng, hit, &e->defense, &e->hp);
    e->defense.vulnerability = vulnerability;
    e->shield = e->defense.permanent_shield + e->defense.temporary[EMBER_DAMAGE_TYPES];
    if (r.dodged) {
        event(s, 1, 0, e->x, e->y);
        s->events.item[s->events.count - 1].outcome = 1;
        return r;
    }
    if (!r.damage && !r.absorbed) {
        if (r.blocked) {
            event(s, 1, 0, e->x, e->y);
            s->events.item[s->events.count - 1].outcome = 2;
        }
        return r;
    }
    if (hit->leech) leech(s, r.damage, hit->leech);
    e->flash = (uint16_t)ember_system[0].enemy_flash_frames;
    s->damage_total += (unsigned)r.damage;
    event(s, 1, (unsigned)(r.damage + r.absorbed), e->x, e->y);
    s->events.item[s->events.count - 1].outcome = r.blocked ? 2 : 0;
    s->events.item[s->events.count - 1].tier = r.crit;
    s->events.item[s->events.count - 1].damage_type = r.dominant;
    energy_add(s, r.damage > 0);
    if (e->hp > 0) {
        if (hit->depth == 3 + s->trigger_bonus) return r;
        struct ember_attack linked = {.attack = 100, .crit_damage = 150,
                                       .depth = (uint8_t)(hit->depth + 1)};
        if (frozen && r.part[EMBER_DAMAGE_IRON]) shatter(s, index, hit->depth);
        if (r.crit && e->defense.status[EMBER_BREAK_ARMOR].frames) {
            linked.base = ember_system[0].heavy_damage;
            linked.share[EMBER_DAMAGE_IRON] = 100;
            ember_sim_hit(s, index, &linked);
        }
        if (r.crit && e->defense.status[EMBER_BLIND].frames &&
            enemy_in_dark(s, e->x, e->y)) {
            linked.base = ember_system[0].blind_crit;
            linked.share[EMBER_DAMAGE_IRON] = 0;
            linked.share[EMBER_DAMAGE_SHADOW] = 100;
            ember_sim_hit(s, index, &linked);
        }
        return r;
    }
    e->retiring = 1;
    e->alive = 0;
    --s->alive_count;
    content_death(s, index, hit->depth, hit->source_weapon, r.damage);
    ++s->player.kills;
    if (e->defense.status[EMBER_CORRODE].frames)
        heal(s, ember_system[0].corrode_heal);
    energy_add(s, ember_characters[s->player.character].charge_kill);
    pickup_drop(s, e);
    event(s, 2, (unsigned)r.damage, e->x, e->y);
    if (frozen && r.part[EMBER_DAMAGE_IRON] && hit->depth < 3 + s->trigger_bonus)
        shatter(s, index, hit->depth);
    if (s->player.character == 0 && e->burn && hit->depth < 3 + s->trigger_bonus) {
        int radius = ember_characters[s->player.character].passive_radius *
            s->attributes[EMBER_AREA] / 100;
        struct ember_shot *p = shot(s, 1, e->x, e->y, 0, radius,
                                    ember_characters[s->player.character].passive_frames);
        p->tick = 1;
        area_hit(s, e->x, e->y, radius, ember_characters[s->player.character].passive_damage,
                 e->burn_weapon, hit->depth + 1, 0);
    }
    e->retiring = 0;
    return r;
}
void ember_sim_status(struct ember_sim *s, unsigned index, unsigned status, unsigned depth)
{
    struct ember_enemy *e = &s->enemies[index];
    if (!e->alive || depth > 3u + s->trigger_bonus) return;
    unsigned reaction = ember_status_apply(&e->defense, status,
        ember_statuses[status].duration * s->attributes[EMBER_STATUS_DURATION] / 100,
        s->attributes[EMBER_STATUS_STRENGTH]);
    if (status == EMBER_CHILL && relic(s, R_FROST) &&
        e->defense.status[EMBER_CHILL].stacks >= ember_statuses[EMBER_CHILL].stacks - relic(s, R_FROST) &&
        e->defense.rank < 2)
        e->defense.frozen = (uint16_t)(ember_statuses[EMBER_CHILL].freeze_frames *
            (100 - e->defense.tenacity) / 100);
    e->defense.break_bonus = relic(s, R_FILE);
    e->defense.rust = s->resonances[4] ? ember_resonances[4].value : 0;
    e->burn = e->defense.status[EMBER_IGNITE].frames;
    if (reaction & 1u) {
        area_hit(s, e->x, e->y, ember_system[0].chain_range,
            ember_system[0].steam_damage * (100 + (s->blessings[7] ? ember_blessings[7].value : 0)) / 100, 255, depth + 1, 0);
        if (s->resonances[0] && depth < 3u + s->trigger_bonus) {
            struct ember_shot *cloud = shot(s, 2, e->x, e->y, 0, ember_resonances[0].radius, ember_resonances[0].lifetime);
            cloud->effect = 11;
            cloud->depth = (uint8_t)(depth + 1);
        }
    }
    if (reaction & 2u) {
        int last = (int)index;
        uint8_t visited[EMBER_ENEMIES] = {0};
        visited[index] = 1;
        int damage = ember_statuses[EMBER_SHOCK].damage;
        for (int jump = 0; jump < ember_system[0].chain_jumps + relic(s, R_NEEDLE) +
            (s->resonances[5] ? ember_resonances[5].value : 0); ++jump) {
            int next = -1;
            int64_t best = INT64_MAX;
            int wet = !!s->enemies[last].defense.status[EMBER_WET].frames;
            int range = ember_system[0].chain_range * (wet ? ember_system[0].wet_chain_range_percent : 100) / 100;
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
            damage = damage * (100 + relic(s, R_STAR)) / 100;
            if (s->resonances[2] && s->enemies[next].burn)
                inherited_area(s, s->enemies[next].x, s->enemies[next].y,
                    ember_resonances[2].radius, ember_resonances[2].damage, depth + 2);
            if (!(wet && s->resonances[5] &&
                s->enemies[next].defense.status[EMBER_WET].frames) && (!wet || jump))
                damage = damage * (100 - ember_system[0].chain_decay) / 100;
            visited[next] = 1;
            last = next;
        }
    }
}
enum attack_tags {
    TAG_FIRE = 1u << EMBER_DATA_TAGS_EMBER, TAG_WATER = 1u << EMBER_DATA_TAGS_TIDE,
    TAG_IRON = 1u << EMBER_DATA_TAGS_IRON, TAG_STAR = 1u << EMBER_DATA_TAGS_STAR,
    TAG_SHADOW = 1u << EMBER_DATA_TAGS_SHADOW,
    TAG_PROJECTILE = 1u << EMBER_DATA_TAGS_PROJECTILE, TAG_AREA = 1u << EMBER_DATA_TAGS_AREA,
    TAG_MELEE = 1u << EMBER_DATA_TAGS_MELEE, TAG_DOT = 1u << EMBER_DATA_TAGS_DOT,
    TAG_SINGLE = 1u << EMBER_DATA_TAGS_SINGLE, TAG_GROUP = 1u << EMBER_DATA_TAGS_GROUP,
    TAG_CHARGE = 1u << EMBER_DATA_TAGS_CHARGE, TAG_COMBO = 1u << EMBER_DATA_TAGS_COMBO
};
uint32_t ember_sim_weapon_tags(const struct ember_sim *s, unsigned weapon)
{
    uint32_t tags = s->weapon_system[weapon].tags;
    if (s->weapon_system[weapon].category == EMBER_STAFF &&
        s->player.evolution[weapon] == 2)
        tags = (tags & ~(TAG_AREA | TAG_GROUP)) | TAG_SINGLE | TAG_CHARGE;
    return tags;
}
static void player_modifiers(struct ember_sim *s, unsigned index,
                              struct ember_attack *h, uint32_t tags)
{
    const struct ember_enemy *e = &s->enemies[index];
    if (s->in_light && !relic(s, R_NIGHT)) h->increased += ember_lighting[0].ally_damage *
        s->attributes[EMBER_LIGHT_EFFECT] / 100;
    if (e->defense.status[EMBER_CORRODE].frames)
        h->leech += ember_system[0].corrode_leech + relic(s, R_FANG);
    h->conversion += relic(s, R_FORGE);
    if (!(h->flags & EMBER_DOT)) h->added[EMBER_DAMAGE_WATER] += relic(s, R_TIDE);
    h->element_more[EMBER_DAMAGE_FIRE] += relic(s, R_CORE);
    if (e->defense.frozen) h->more[2] += relic(s, R_ICE);
    if (tags & TAG_PROJECTILE) h->increased += relic(s, R_QUIVER);
    if ((tags & TAG_AREA) && relic(s, R_MIRROR)) h->increased += ember_relics[R_MIRROR].value2;
    if (tags & TAG_MELEE) h->increased += relic(s, R_BELT);
    if (tags & TAG_SINGLE) h->more[3] += relic(s, R_LENS);
    h->increased += s->attributes[EMBER_ARMOR] * relic(s, R_ANVIL) / ember_relics[R_ANVIL].armor_step;
    if (!s->in_light) h->crit_damage = h->crit_damage * (100 + relic(s, R_EYE) *
        (100 + relic(s, R_NIGHT)) / 100) / 100;
    if (h->flags & EMBER_DOT) h->increased += relic(s, R_COAL);
    const unsigned attrs[5] = {EMBER_IRON_DAMAGE, EMBER_EMBER_DAMAGE, EMBER_TIDE_DAMAGE,
                              EMBER_STAR_DAMAGE, EMBER_SHADOW_DAMAGE};
    const unsigned bits[5] = {TAG_IRON,TAG_FIRE,TAG_WATER,TAG_STAR,TAG_SHADOW};
    tags &= ~(TAG_IRON | TAG_FIRE | TAG_WATER | TAG_STAR | TAG_SHADOW);
    int shares[5]; memcpy(shares, h->share, sizeof(shares));
    int converted = shares[EMBER_DAMAGE_IRON] * h->conversion / 100;
    shares[EMBER_DAMAGE_IRON] -= converted; shares[EMBER_DAMAGE_FIRE] += converted;
    for (unsigned i = 0; i < 5; ++i) {
        h->increased += (s->attributes[attrs[i]] - 100) * shares[i] / 100;
        if (shares[i]) tags |= bits[i];
    }
    if (s->blessings[0] && shares[EMBER_DAMAGE_FIRE]) tags |= TAG_WATER;
    for (unsigned i = 0; i < EMBER_TAGS_COUNT; ++i) {
        if ((!strcmp(ember_tags[i].id, "light") && s->in_light && !relic(s, R_NIGHT)) ||
            (!strcmp(ember_tags[i].id, "dark") && !s->in_light)) tags |= 1u << i;
        if (tags & (1u << i)) h->increased += s->tag_damage[i] *
            (relic(s, R_NIGHT) && !strcmp(ember_tags[i].id, "dark") ? (100 + relic(s, R_NIGHT)) / 100 : 1);
    }
}
static void player_hit_effects(struct ember_sim *s, unsigned index,
                                struct ember_damage_result r, uint32_t tags)
{
    if (!r.damage) return;
    if ((tags & TAG_MELEE) && relic(s, R_BELT)) {
        while (s->belt_count && s->combat_frame - s->belt_frames[s->belt_first] >= (unsigned)ember_relics[R_BELT].value4) {
            s->belt_first = (s->belt_first + 1) % 5; --s->belt_count;
        }
        if (s->belt_count < ember_relics[R_BELT].value3) {
            s->belt_frames[(s->belt_first + s->belt_count) % 5] = s->combat_frame;
            ++s->belt_count; heal(s, ember_relics[R_BELT].value2);
        }
    }
    if (relic(s, R_HOURGLASS) && !s->hourglass_seen[index]) {
        s->hourglass_seen[index] = 1;
        if (++s->hourglass_count == ember_relics[R_HOURGLASS].value2) {
            s->hourglass_count = 0;
            memset(s->hourglass_seen, 0, sizeof(s->hourglass_seen));
            s->player.cooldown_k = (uint16_t)maximum(0, s->player.cooldown_k - relic(s, R_HOURGLASS));
            s->player.cooldown_b = (uint16_t)maximum(0, s->player.cooldown_b - relic(s, R_HOURGLASS));
        }
    }
}
static void enemy_hit_flags(struct ember_sim *s, unsigned index, int damage,
                      unsigned weapon, unsigned depth, int periodic, unsigned flags)
{
    struct ember_enemy *e = &s->enemies[index];
    if (!e->alive || depth > 3u + s->trigger_bonus) return;
    struct ember_attack hit = {.base = damage, .attack = s->attributes[EMBER_ATTACK],
        .crit = s->attributes[EMBER_CRIT], .crit_damage = s->attributes[EMBER_CRIT_DAMAGE],
        .penetration = s->attributes[EMBER_PIERCE], .share = {0,100,0,0,0,0},
        .depth = (uint8_t)depth, .flags = periodic ? EMBER_DOT : 0,
        .source_weapon = weapon < EMBER_WEAPONS_COUNT ? (uint8_t)(weapon + 1) : 0};
    hit.flags |= (uint8_t)(flags & ~HIT_DIRECTION_SET);
    if (!(flags & HIT_DIRECTION_SET) && enemy_front(e, s->player.x, s->player.y))
        hit.flags |= EMBER_FRONT;
    if (s->dot_can_crit) hit.flags |= EMBER_DOT_CRIT;
    uint32_t tags = TAG_FIRE | TAG_AREA | TAG_GROUP;
    if (weapon < EMBER_WEAPONS_COUNT) {
        const struct ember_weapon_system *w = &s->weapon_system[weapon];
        memcpy(hit.share, w->share, sizeof(hit.share));
        memcpy(hit.added, w->added, sizeof(hit.added));
        memcpy(hit.more, w->more, sizeof(hit.more));
        tags = ember_sim_weapon_tags(s, weapon);
        hit.conversion = w->conversion;
        hit.increased += w->increased;
        hit.penetration += w->penetration;
        if (inscription(s, weapon, 5)) hit.leech += ember_inscriptions[5].value;
        if (inscription(s, weapon, 14)) hit.status_strength = 100 + ember_inscriptions[14].value;
        if (inscription(s, weapon, 15)) hit.flags |= EMBER_IGNORE_BLOCK;
        if (inscription(s, weapon, 17)) {
            memset(hit.share, 0, sizeof(hit.share));
            const unsigned types[] = {1, 2, 0, 3, 4};
            hit.share[types[(s->attack_count[weapon] - 1) % 5]] = 100;
        }
        if (s->player.evolution[weapon] == 2 && w->category == EMBER_SWORD &&
            !s->player.combo) hit.flags |= EMBER_FORCE_CRIT;
        if (s->player.evolution[weapon] == 2 && w->category == EMBER_BLADES &&
            !(hit.flags & EMBER_FRONT)) hit.leech += ember_weapons[weapon].evo_b_leech;
        if (s->player.evolution[weapon] == 2 && w->category == EMBER_GUN &&
            (hit.flags & EMBER_CHARGED) && e->defense.rank) hit.more[0] += ember_weapons[weapon].evo_b_rank_more;
    }
    if (periodic) tags = (tags & ~(TAG_PROJECTILE | TAG_MELEE | TAG_CHARGE | TAG_COMBO)) | TAG_DOT;
    if (periodic >= 2)
        tags = (tags & ~(TAG_PROJECTILE | TAG_MELEE | TAG_SINGLE | TAG_CHARGE | TAG_COMBO)) |
            TAG_AREA | TAG_GROUP | TAG_DOT;
    if (periodic == 1 || periodic == 3) {
        memset(hit.share, 0, sizeof(hit.share));
        memset(hit.added, 0, sizeof(hit.added));
        hit.share[EMBER_DAMAGE_FIRE] = 100;
        hit.conversion = 0;
    }
    player_modifiers(s, index, &hit, tags);
    if (!periodic && weapon < EMBER_WEAPONS_COUNT &&
        inscription(s, weapon, 4) && (s->hit_count[weapon] + 1) % ember_inscriptions[4].value == 0)
        hit.flags |= EMBER_FORCE_CRIT;
    content_before_hit(s, index, weapon, &hit);
    struct ember_damage_result result = ember_sim_hit(s, index, &hit);
    if (!periodic && weapon < EMBER_WEAPONS_COUNT && (result.damage || result.absorbed))
        ++s->hit_count[weapon];
    if (!periodic) {
        player_hit_effects(s, index, result, tags);
        content_after_hit(s, index, weapon, result, depth);
    }
    if (!periodic && weapon < EMBER_WEAPONS_COUNT && result.damage) {
        if (inscription(s, weapon, 11) && result.crit)
            ember_sim_status(s, index, EMBER_SHOCK, depth + 1);
        if (inscription(s, weapon, 13) && depth < 3u + s->trigger_bonus) {
            struct ember_shot *ground = shot(s, 2, e->x, e->y, damage * ember_inscriptions[13].value2 / 100,
                ember_inscriptions[13].value3, ember_inscriptions[13].duration);
            ground->weapon = (uint8_t)weapon;
            ground->depth = (uint8_t)(depth + 1);
        }
    }
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
        if (weapon < EMBER_WEAPONS_COUNT) {
            if (inscription(s, weapon, 2) && ember_random(&s->combat_rng) % 100 < (unsigned)ember_inscriptions[2].value)
                ember_sim_status(s, index, EMBER_IGNITE, depth);
            if (inscription(s, weapon, 3)) ember_sim_status(s, index, EMBER_WET, depth);
            if (s->weapon_system[weapon].category == EMBER_HAMMER &&
                s->player.evolution[weapon] == 1)
                ember_sim_status(s, index, EMBER_BREAK_ARMOR, depth);
        }
        e->burn_weapon = (uint8_t)weapon;
        e->burn_pet = 0;
    }
}
static void enemy_hit(struct ember_sim *s, unsigned index, int damage,
                      unsigned weapon, unsigned depth, int periodic)
{
    enemy_hit_flags(s, index, damage, weapon, depth, periodic, 0);
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
static int nearest_at(const struct ember_sim *s, ember_fixed x, ember_fixed y)
{
    int target = -1;
    int64_t best = INT64_MAX;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        const struct ember_enemy *e = &s->enemies[i];
        if (!e->alive) continue;
        int64_t d = distance2(e->x, e->y, x, y);
        if (d < best) { target = (int)i; best = d; }
    }
    return target;
}
static int nearest(const struct ember_sim *s)
{
    return nearest_at(s, s->player.x, s->player.y);
}
static void player_action(struct ember_sim *s, unsigned action, unsigned duration)
{
    s->player.action = (uint8_t)action;
    s->player.action_time = (uint16_t)duration;
    s->player.action_ticks = 0;
}
static void enemy_target(const struct ember_sim *s, const struct ember_enemy *e,
                           ember_fixed *x, ember_fixed *y)
{
    *x = s->player.x; *y = s->player.y;
    if (e->taunted) return;
    int64_t best = distance2(e->x, e->y, *x, *y);
    for (unsigned i = 0; i < 8; ++i) if (s->summons[i].life) {
        int64_t d = distance2(e->x, e->y, s->summons[i].x, s->summons[i].y);
        if (d < best) { best = d; *x = s->summons[i].x; *y = s->summons[i].y; }
    }
}
static void player_hurt_resolved(struct ember_sim *s, int damage, unsigned wave,
                        ember_fixed source_x, ember_fixed source_y, unsigned type, unsigned flags,
                        int increased)
{
    struct ember_player *p = &s->player;
    if (p->invulnerable || p->dash || s->stealth) return;
    struct ember_attack hit = {.base = damage * ember_waves[wave - 1].damage_percent / 100,
        .attack = 100, .crit_damage = 150, .share = {100,0,0,0,0,0}};
    memset(hit.share, 0, sizeof(hit.share));
    hit.share[type] = 100;
    hit.flags = (uint8_t)flags;
    hit.increased = increased;
    struct ember_damage_result r = ember_damage(&s->combat_rng, &hit, &p->defense, &p->hp);
    if (r.dodged || (!r.damage && !r.absorbed)) {
        if (r.dodged || r.blocked) {
            event(s, 8, 0, p->x, p->y);
            s->events.item[s->events.count - 1].outcome = r.dodged ? 1 : 2;
        }
        return;
    }
    if (ember_characters[p->character].mechanism == 0 && r.damage) {
        p->defense.temporary[6] += r.damage * ember_characters[p->character].passive_value / 100;
        p->defense.shield_frames[6] = (uint16_t)ember_characters[p->character].passive_duration;
    }
    if ((ember_characters[p->character].mechanism == 0 && s->skill_time) ||
        (s->player.evolution[p->main_weapon] == 2 &&
         s->weapon_system[p->main_weapon].category == EMBER_HAMMER)) {
        skill_reflect(s, source_x, source_y, r.damage);
    }
    if (relic(s, R_THORN) && s->combat_frame >= s->thorn_next) {
        skill_reflect(s, source_x, source_y, p->armor * relic(s, R_THORN) / 100);
        s->thorn_next = s->combat_frame + (uint32_t)ember_relics[R_THORN].value2;
    }
    if (relic(s, R_LINING) && r.damage) {
        p->defense.temporary[6] += r.damage * relic(s, R_LINING) / 100;
        p->defense.shield_frames[6] = (uint16_t)ember_relics[R_LINING].value2;
    }
    if (s->blessings[12] && s->combat_frame >= s->recoil_next) {
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i) if (s->enemies[i].alive &&
            within(p->x, p->y, s->enemies[i].x, s->enemies[i].y, ember_blessings[12].value2)) {
            ember_fixed vx, vy;
            velocity(s->enemies[i].x - p->x, s->enemies[i].y - p->y, ember_blessings[12].knockback_speed, &vx, &vy);
            s->enemies[i].x += vx * ember_blessings[12].knockback_frames;
            s->enemies[i].y += vy * ember_blessings[12].knockback_frames;
        }
        inherited_area(s, p->x, p->y, ember_blessings[12].value2,
            ember_blessings[12].value, 0);
        s->recoil_next = s->combat_frame + (uint32_t)ember_blessings[12].cooldown;
    }
    p->invulnerable = p->defense.invulnerable;
    p->flash = (uint16_t)ember_system[0].hurt_animation_frames;
    player_action(s, EMBER_HURT, ember_system[0].hurt_animation_frames);
    energy_add(s, r.damage);
    event(s, 8, (unsigned)r.damage, p->x, p->y);
    s->events.item[s->events.count - 1].outcome = r.blocked ? 2 : 0;
    if (p->hp <= 0) { player_action(s, EMBER_DEAD, 0); s->phase = EMBER_LOST; }
}
static void player_hurt_typed(struct ember_sim *s, int damage, unsigned wave,
                        ember_fixed x, ember_fixed y, unsigned type, unsigned flags)
{
    player_hurt_resolved(s, damage, wave, x, y, type, flags,
        enemy_in_dark(s, x, y) ? ember_lighting[0].dark_damage : 0);
}
static void player_hurt(struct ember_sim *s, int damage, unsigned wave,
                        ember_fixed x, ember_fixed y)
{
    player_hurt_typed(s, damage, wave, x, y, EMBER_DAMAGE_IRON, 0);
}
static void enemy_spawn(struct ember_sim *s)
{
    const struct ember_waves_row *w = &ember_waves[s->wave - 1];
    unsigned candidates[21];
    unsigned count = 0;
    for (unsigned k = 0; k < EMBER_ENEMIES_COUNT; ++k)
        if (strstr(w->enemy, ember_enemies[k].id)) candidates[count++] = k;
    unsigned kind = candidates[ember_random(&s->spawn_rng) % count];
    uint16_t angle = (uint16_t)ember_random(&s->spawn_rng);
    int radius = w->spawn_radius + (int)(ember_random(&s->spawn_rng) % w->spawn_jitter);
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        struct ember_enemy *e = &s->enemies[i];
        if (e->alive) continue;
        ember_fixed x = clamp(s->player.x + ember_cos(angle) * radius,
            ember_system[0].spawn_boundary_margin * EMBER_Q, s->world_width - ember_system[0].spawn_boundary_margin * EMBER_Q);
        ember_fixed y = clamp(s->player.y + ember_sin(angle) * radius,
            ember_system[0].spawn_boundary_margin * EMBER_Q, s->world_height - ember_system[0].spawn_boundary_margin * EMBER_Q);
        unsigned affix = w->elite ? 1 + s->spawned % EMBER_AFFIXES_COUNT : 0;
        unsigned spawned = ember_sim_spawn(s, kind, affix, x, y);
        e = &s->enemies[spawned];
        e->hp = e->hp * w->hp_percent / 100;
        e->defense.max_hp = e->hp;
        e->timer = (uint16_t)(ember_enemies[kind].initial_delay +
            ember_random(&s->spawn_rng) % ember_enemies[kind].delay_jitter);
        ++s->spawned;
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
static int enemy_speed(const struct ember_sim *s, const struct ember_enemy *e)
{
    const struct ember_enemies_row *d = &ember_enemies[e->kind];
    int speed = d->speed;
    if (e->defense.status[EMBER_CHILL].frames)
        speed = speed * (100 - e->defense.status[EMBER_CHILL].stacks *
        ember_statuses[EMBER_CHILL].strength) / 100;
    for (unsigned n = 0; n < 8; ++n)
        if (s->pillars[n].lit && within(e->x, e->y, s->pillars[n].x, s->pillars[n].y,
        ember_lighting[0].pillar_radius)) { speed = speed *
            (100 - ember_lighting[0].enemy_slow) / 100; break; }
    if (e->affix) speed = speed * ember_affixes[e->affix - 1].speed_percent / 100;
    if (e->second_affix) speed = speed * ember_affixes[e->second_affix - 1].speed_percent / 100;
    return speed;
}
static void enemies_step(struct ember_sim *s)
{
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        struct ember_enemy *e = &s->enemies[i];
        if (!e->alive) continue;
        const struct ember_enemies_row *d = &ember_enemies[e->kind];
        if (e->flash) --e->flash;
        if (e->hunter_mark) --e->hunter_mark;
        if (e->owl_mark) --e->owl_mark;
        if (e->taunted) --e->taunted;
        e->marked = (uint16_t)maximum(e->hunter_mark, e->owl_mark);
        int controlled = e->defense.frozen || e->defense.status[EMBER_STUN].frames ||
            e->defense.broken;
        e->burn = e->defense.status[EMBER_IGNITE].frames;
        if (e->burn && ++e->burn_tick >= ember_statuses[0].interval) {
            e->burn_tick = 0;
            int damage = ember_statuses[0].damage * e->defense.status[EMBER_IGNITE].stacks *
                s->attributes[EMBER_STATUS_STRENGTH] / 100;
            if (e->burn_pet) {
                struct ember_attack hit = {.base = ember_statuses[0].damage *
                    e->defense.status[EMBER_IGNITE].stacks, .attack = 100,
                    .share = {0,100,0,0,0,0}, .flags = EMBER_DOT};
                ember_sim_hit(s, i, &hit);
            } else enemy_hit(s, i, damage, e->burn_weapon, 0, 1);
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
        int speed = enemy_speed(s, e);
        if (e->timer) --e->timer;
        ember_fixed target_x, target_y;
        enemy_target(s, e, &target_x, &target_y);
        ember_fixed dx = target_x - e->x;
        ember_fixed dy = target_y - e->y;
        if (content_enemy(s, i)) {
            /* Content AI owns velocity and attacks for this species. */
        } else if (e->kind == 1) {
            if (e->mode == 1 && !e->timer) {
                e->mode = 2;
                e->timer = (uint16_t)d->charge_duration;
                velocity(dx, dy, d->charge_speed, &e->vx, &e->vy);
            } else if (e->mode == 2 && !e->timer) {
                e->mode = 0;
                e->timer = (uint16_t)d->attack_cooldown;
            } else if (e->mode == 0 && !e->timer &&
                       within(e->x, e->y, target_x, target_y, d->attack_range)) {
                e->mode = 1;
                e->timer = (uint16_t)d->charge_frames;
                e->vx = 0;
                e->vy = 0;
            }
            if (e->mode == 0) velocity(dx, dy, speed, &e->vx, &e->vy);
        } else if (e->kind == 2) {
            int range = d->attack_range;
            if (within(e->x, e->y, target_x, target_y, range - d->range_hysteresis))
                velocity(-dx, -dy, speed, &e->vx, &e->vy);
            else if (!within(e->x, e->y, target_x, target_y, range + d->range_hysteresis))
                velocity(dx, dy, speed, &e->vx, &e->vy);
            else { e->vx = 0; e->vy = 0; }
            if (!e->timer && (!e->defense.status[EMBER_BLIND].frames ||
                ember_random(&s->combat_rng) % 100 >=
                    (unsigned)ember_statuses[EMBER_BLIND].strength)) {
                struct ember_shot *p = shot(s, 6, e->x, e->y, d->damage,
                                            d->projectile_radius, d->projectile_life);
                e->attacking = (uint16_t)ember_system[0].attack_frames;
                p->hostile = 1;
                p->damage_type = (uint8_t)d->element_index;
                p->enemy_increased = enemy_in_dark(s, e->x, e->y) ?
                    ember_lighting[0].dark_damage : 0;
                p->weapon = (uint8_t)e->wave;
                velocity(dx, dy, d->projectile_speed, &p->vx, &p->vy);
                e->timer = (uint16_t)d->attack_cooldown;
                event(s, 0, (unsigned)d->damage, e->x, e->y);
            }
        } else velocity(dx, dy, speed, &e->vx, &e->vy);
        e->facing8 = (uint8_t)direction8((e->vx || e->vy) && !e->attacking ? e->vx : dx,
            (e->vx || e->vy) && !e->attacking ? e->vy : dy);
        if (e->attacking) --e->attacking;
        e->in_dark = (uint8_t)enemy_in_dark(s, e->x, e->y);
        e->facing_frame = (uint8_t)direction_frame(e->facing8);
        e->flip_x = e->facing8 >= 5;
        e->x = clamp(e->x + e->vx, ember_system[0].enemy_boundary_margin * EMBER_Q, s->world_width - ember_system[0].enemy_boundary_margin * EMBER_Q);
        e->y = clamp(e->y + e->vy, ember_system[0].enemy_boundary_margin * EMBER_Q, s->world_height - ember_system[0].enemy_boundary_margin * EMBER_Q);
        obstacles_resolve(s, &e->x, &e->y, d->radius);
        if (within(e->x, e->y, s->player.x, s->player.y,
                   d->radius + ember_characters[s->player.character].body_radius))
            if (!e->defense.status[EMBER_BLIND].frames ||
                ember_random(&s->combat_rng) % 100 >=
                    (unsigned)ember_statuses[EMBER_BLIND].strength)
                player_hurt_typed(s, d->damage, e->wave, e->x, e->y,
                    (unsigned)d->element_index, d->rank == 3 ? EMBER_UNDODGEABLE : 0);
    }
}
static int charging_weapon(const struct ember_sim *s, unsigned w)
{
    return ember_weapons[w].charge_frames ||
        (s->weapon_system[w].category == EMBER_STAFF && s->player.evolution[w] == 2);
}
static void weapon_fire_once(struct ember_sim *s, unsigned w, unsigned repeat)
{
    struct ember_player *player = &s->player;
    int target = nearest(s);
    if (target < 0) return;
    const struct ember_weapons_row *d = &ember_weapons[w];
    unsigned category = s->weapon_system[w].category;
    int loaded = s->loaded && category >= EMBER_BOW && category <= EMBER_STAFF;
    if (loaded) s->loaded = 0;
    int forced_arrow = s->next_crit && ember_characters[player->character].mechanism == 2 &&
        (category == EMBER_BOW || category == EMBER_CROSSBOW);
    if (forced_arrow) s->next_crit = 0;
    int damage = d->damage * (100 + d->damage_per_level *
        ((int)player->weapon_level[w] - 1)) / 100;
    if (loaded) damage = damage * ember_characters[player->character].loaded_percent / 100;
    if (s->dual_wield) damage = damage * (100 - relic(s, R_TWINS)) / 100;
    unsigned charge_time = (unsigned)(category == EMBER_STAFF ? d->evo_charge_frames : d->charge_frames);
    if (charging_weapon(s, w) && inscription(s, w, 10)) charge_time = charge_time * (100 - ember_inscriptions[10].value) / 100;
    int charged = charging_weapon(s, w) && s->charge_frames >= charge_time;
    if (charged) damage = damage * d->charge_percent / 100;
    if (d->element_index == EMBER_DAMAGE_SHADOW && !s->in_light)
        damage = damage * (100 + d->dark_bonus * (100 + relic(s, R_NIGHT)) / 100) / 100;
    ++s->attack_count[w];
    int radius = d->radius * s->attributes[EMBER_AREA] / 100;
    int count = d->count + (tagged(w, "projectile") ? s->attributes[EMBER_PROJECTILES] - 1 : 0);
    if (category == EMBER_CROSSBOW) count = (player->evolution[w] == 1 ?
        d->evo_a_count : d->burst_count) + s->attributes[EMBER_PROJECTILES] - 1;
    if (category == EMBER_GUN && charged) count = d->charge_count + s->attributes[EMBER_PROJECTILES] - 1;
    if (ember_characters[player->character].mechanism == 2 && s->ultimate_time &&
        (category == EMBER_BOW || category == EMBER_CROSSBOW)) count = count * ember_characters[player->character].ultimate_value / 100;
    if (category == EMBER_STAFF && player->evolution[w] == 1) count *= d->evo_a_count;
    if (category == EMBER_CODEX && player->evolution[w] == 1) radius = radius * d->evo_a_radius_percent / 100;
    if (category == EMBER_CODEX && player->evolution[w] == 2) {
        damage = damage * d->evo_b_damage_percent / 100;
        radius = radius * d->evo_b_radius_percent / 100;
    }
    if (inscription(s, w, 1)) count += ember_inscriptions[1].value;
    if (inscription(s, w, 1)) damage = damage * (100 - ember_inscriptions[1].value2) / 100;
    if (inscription(s, w, 16)) damage = damage * (100 - ember_inscriptions[16].value) / 100;
    if (loaded) count = 1;
    int rate = s->attributes[EMBER_ATTACK_SPEED];
    if (category == (unsigned)ember_characters[player->character].affinity_a ||
        category == (unsigned)ember_characters[player->character].affinity_b)
        rate = rate * (100 + ember_characters[player->character].affinity_speed_percent) / 100;
    if (ember_characters[player->character].mechanism == 5 && s->ultimate_time)
        rate = rate * (100 + ember_characters[player->character].ultimate_value) / 100;
    rate = minimum(rate, ember_attributes[EMBER_ATTACK_SPEED].maximum +
        s->cap_raise[EMBER_ATTACK_SPEED]);
    if (charged && inscription(s, w, 10)) damage = damage * (100 + ember_inscriptions[10].value2) / 100;
    s->weapon_timer[w] = (uint16_t)maximum(1,
        d->cooldown * (100 - s->attributes[EMBER_COOLDOWN]) / rate);
    ember_fixed dx = s->enemies[target].x - player->x;
    ember_fixed dy = s->enemies[target].y - player->y;
    player->facing8 = (uint8_t)direction8(dx, dy);
    player->facing_frame = (uint8_t)direction_frame(player->facing8);
    player->flip_x = player->facing8 >= 5;
    player_action(s, EMBER_ATTACKING, (unsigned)minimum(ember_system[0].attack_frames, s->weapon_timer[w]));
    unsigned combos = (unsigned)d->combo_count;
    player->combo = (uint8_t)((player->combo + 1) % combos);
    if (category <= EMBER_HAMMER) {
        int reach = d->range_pixels * s->attributes[EMBER_AREA] / 100;
        if (category == EMBER_GREATSWORD && charged) {
            ember_fixed vx, vy;
            velocity(dx, dy, d->charge_dash_speed, &vx, &vy);
            if (within(player->x, player->y, s->enemies[target].x,
                s->enemies[target].y, d->range_pixels * d->charge_dash_range_percent / 100)) {
                player->x = s->enemies[target].x;
                player->y = s->enemies[target].y;
            } else { player->x += vx * d->charge_dash_frames; player->y += vy * d->charge_dash_frames; }
            if (player->evolution[w] == 1) {
                reach = reach * d->evo_a_radius_percent / 100;
                struct ember_shot *ground = shot(s, 2, player->x, player->y,
                    damage * d->evo_a_ground_percent / 100, reach, d->evo_a_duration);
                ground->weapon = (uint8_t)w;
                ground->dot_type = 2;
            }
        }
        int spin = category == EMBER_SWORD && player->evolution[w] == 1 && !player->combo;
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
            struct ember_enemy *e = &s->enemies[i];
            if (!e->alive || !within(player->x, player->y, e->x, e->y, reach)) continue;
            int64_t ex = (e->x - player->x) / EMBER_Q;
            int64_t ey = (e->y - player->y) / EMBER_Q;
            int64_t ax = dx / EMBER_Q, ay = dy / EMBER_Q;
            if (category != EMBER_HAMMER && !spin &&
                !(category == EMBER_SPEAR && player->evolution[w] == 2 && !player->combo) &&
                (ex * ax + ey * ay) * 1000 <
                (int64_t)d->melee_cos_permille * square_root(ex * ex + ey * ey) *
                square_root(ax * ax + ay * ay)) continue;
            if (((category == EMBER_SPEAR && player->combo) ||
                (category == EMBER_SWORD && !player->combo && !spin)) && llabs(ex * ay - ey * ax) >
                (int64_t)d->thrust_width * square_root(ax * ax + ay * ay)) continue;
            int dealt = damage;
            if (category == EMBER_GREATSWORD && charged && player->evolution[w] == 2 &&
                e->hp * 100LL < e->defense.max_hp * d->evo_b_threshold) dealt = dealt * d->evo_b_damage_percent / 100;
            if (category == EMBER_SPEAR && player->evolution[w] == 2 && !player->combo) {
                velocity(player->x - e->x, player->y - e->y, d->evo_b_pull_speed, &e->vx, &e->vy);
                e->x += e->vx * d->evo_b_pull_frames;
                e->y += e->vy * d->evo_b_pull_frames;
            }
            enemy_hit_flags(s, i, dealt, w, 0, 0, charged ? EMBER_CHARGED : 0);
            if (e->alive && category == EMBER_HAMMER) ember_sim_status(s, i, EMBER_STUN, 0);
            if (e->alive && category == EMBER_GREATSWORD)
                velocity(e->x - player->x, e->y - player->y,
                    s->attributes[EMBER_KNOCKBACK], &e->vx, &e->vy);
        }
    } else {
        unsigned kind = category == EMBER_CODEX ? 2 : 0;
        if (category == EMBER_CODEX)
            for (unsigned i = 0; i < EMBER_SHOTS; ++i) {
                struct ember_shot *p = &s->shots[i];
                if (p->alive && p->weapon == w && p->kind == 2 && p->repeat_slot == repeat) {
                    p->life = (uint16_t)(s->weapon_timer[w] + 2);
                    p->damage = damage;
                    p->radius = (uint16_t)radius;
                    p->follow = player->evolution[w] != 2;
                    return;
                }
            }
        for (int n = 0; n < count; ++n) {
            if (category == EMBER_BOW && ++s->arrow_count[w] % d->evo_a_interval == 0 &&
                player->evolution[w] == 1)
                area_hit(s, s->enemies[target].x, s->enemies[target].y, d->evo_a_range,
                    damage * d->evo_a_damage_percent / 100, w, 0, 0);
            struct ember_shot *p = shot(s, kind, player->x, player->y, damage,
                category == EMBER_CODEX ? radius : d->projectile_radius,
                d->duration * s->attributes[EMBER_DURATION] / 100);
            p->weapon = (uint8_t)w;
            p->repeat_slot = (uint8_t)repeat;
            if (category == EMBER_CROSSBOW && player->evolution[w] != 1)
                p->delay = (uint16_t)(n * d->burst_interval);
            if (category == EMBER_CODEX) p->dot_type = 2;
            if (charged) p->hit_flags |= EMBER_CHARGED;
            if (loaded || (forced_arrow && n == 0)) p->hit_flags |= EMBER_FORCE_CRIT;
            p->homing = ember_characters[player->character].mechanism == 2 &&
                s->ultimate_time && (category == EMBER_BOW || category == EMBER_CROSSBOW);
            if (kind == 0) {
                p->life = (uint16_t)(d->range_pixels * 60 /
                    (d->speed * s->attributes[EMBER_PROJECTILE_SPEED] / 100));
                if (category == EMBER_GUN && charged && player->evolution[w] == 2)
                    p->life = (uint16_t)(p->life * d->evo_b_range_percent / 100);
            }
            p->follow = (uint8_t)(category == EMBER_CODEX || inscription(s, w, 9));
            p->pierce = (uint8_t)(d->pass_through + (charged && category == EMBER_BOW ? d->charge_pass_through : 0) +
                (inscription(s, w, 0) ? ember_inscriptions[0].value : 0) +
                (loaded ? ember_characters[player->character].loaded_pass_through : 0));
            if (category == EMBER_BOW && charged && player->evolution[w] == 2) p->pierce = 255;
            if (category == EMBER_CODEX && player->evolution[w] == 2) {
                p->follow = 0;
                p->x = s->enemies[target].x;
                p->y = s->enemies[target].y;
            }
            if (kind == 0) {
                p->speed = d->speed * s->attributes[EMBER_PROJECTILE_SPEED] / 100;
                velocity(dx, dy, p->speed, &p->vx, &p->vy);
                uint16_t angle = category == EMBER_CROSSBOW && player->evolution[w] != 1 ? 0 :
                    (uint16_t)((n * 2 - count + 1) * d->spread_angle);
                ember_fixed vx = ember_mul(p->vx, ember_cos(angle)) -
                                 ember_mul(p->vy, ember_sin(angle));
                p->vy = ember_mul(p->vx, ember_sin(angle)) + ember_mul(p->vy, ember_cos(angle));
                p->vx = vx;
            }
        }
    }
    if (category == EMBER_SPEAR && player->evolution[w] == 1) {
        struct ember_shot *blade = shot(s, 0, player->x, player->y, damage, d->evo_projectile_radius, d->evo_a_duration);
        blade->weapon = (uint8_t)w;
        blade->pierce = (uint8_t)d->evo_a_pierce;
        blade->speed = d->evo_a_speed;
        velocity(dx, dy, d->evo_a_speed, &blade->vx, &blade->vy);
    }
    if (category == EMBER_HAMMER && player->evolution[w] == 1) {
        for (unsigned n = 1; n <= (unsigned)d->evo_a_count; ++n) {
            ember_fixed vx, vy;
            velocity(dx, dy, d->evo_a_speed, &vx, &vy);
            area_hit(s, player->x + vx * n * d->evo_a_gap_frames, player->y + vy * n * d->evo_a_gap_frames,
                d->evo_a_range, damage, w, 0, 0);
        }
    }
    if (category == EMBER_HAMMER && player->evolution[w] == 2 && s->attack_count[w] % d->evo_b_interval == 0)
        area_hit(s, player->x, player->y, radius, damage, w, 1, 0);
    event(s, 0, (unsigned)damage, player->x, player->y);
}
static void weapon_fire(struct ember_sim *s, unsigned w)
{
    unsigned count = inscription(s, w, 16) ? (unsigned)ember_inscriptions[16].value2 : 1;
    for (unsigned n = 0; n < count; ++n) weapon_fire_once(s, w, n);
}
static void weapons_step(struct ember_sim *s, uint16_t input)
{
    for (unsigned w = 0; w < EMBER_WEAPONS_COUNT; ++w) if (s->weapon_timer[w]) --s->weapon_timer[w];
    struct ember_player *p = &s->player;
    if (p->defense.frozen || p->defense.status[EMBER_STUN].frames) return;
    unsigned main = p->main_weapon;
    if (input & EMBER_J) {
        int target = nearest(s);
        if (target >= 0) {
            p->facing8 = (uint8_t)direction8(s->enemies[target].x - p->x,
                s->enemies[target].y - p->y);
            p->facing_frame = (uint8_t)direction_frame(p->facing8);
            p->flip_x = p->facing8 >= 5;
        }
    }
    unsigned secondary = p->sub_weapon;
    int charge_main = charging_weapon(s, main);
    int charge_sub = s->dual_wield && charging_weapon(s, secondary);
    if ((input & EMBER_J) && (charge_main || charge_sub)) {
        if (!s->charge_frames && charge_main) player_action(s, EMBER_CHARGING, 0);
        ++s->charge_frames;
    }
    if (!(input & EMBER_J) && s->charge_frames) {
        if (charge_main && !s->weapon_timer[main]) weapon_fire(s, main);
        if (charge_sub && !s->weapon_timer[secondary]) weapon_fire(s, secondary);
        s->charge_frames = 0;
        if (p->action == EMBER_CHARGING) player_action(s, EMBER_IDLE, 0);
    }
    if (input & EMBER_J) {
        if (!charge_main && !s->weapon_timer[main]) weapon_fire(s, main);
        if (s->dual_wield && !charge_sub && !s->weapon_timer[secondary])
            weapon_fire(s, secondary);
    }
    unsigned sub = p->sub_weapon;
    if (s->weapon_system[sub].rarity >= 2 && s->weapon_system[sub].offhand &&
        !s->weapon_timer[sub]) weapon_fire(s, sub);
    pet_step(s);
}

static void shots_step(struct ember_sim *s)
{
    for (unsigned i = 0; i < EMBER_SHOTS; ++i) {
        struct ember_shot *p = &s->shots[i];
        if (!p->alive) continue;
        if (p->delay) { --p->delay; continue; }
        if (!p->hostile && (p->homing ||
            (p->pet && (s->pet.category == 2 || pet_rune(s) == 8)) ||
            (p->weapon < EMBER_WEAPONS_COUNT && inscription(s, p->weapon, 7)))) {
            int target = nearest_at(s, p->x, p->y);
            if (target >= 0) velocity(s->enemies[target].x - p->x,
                s->enemies[target].y - p->y, p->speed, &p->vx, &p->vy);
        }
        if (!p->hostile && ((!p->pet && p->weapon < EMBER_WEAPONS_COUNT &&
            inscription(s, p->weapon, 8)) || (p->pet && pet_rune(s) == 9))) {
            if (!p->returning && (p->life <= 1 || !within(p->origin_x, p->origin_y, p->x, p->y,
                p->pet ? pet_weapon_data(s).range_pixels :
                    ember_weapons[p->weapon].range_pixels))) {
                p->returning = 1;
                p->life = (uint16_t)ember_inscriptions[8].duration;
                memset(p->hit_bits, 0, sizeof(p->hit_bits));
            }
            if (p->returning) {
                velocity(s->player.x - p->x, s->player.y - p->y, p->speed, &p->vx, &p->vy);
                if (within(p->x, p->y, s->player.x, s->player.y, ember_system[0].return_contact_radius)) p->life = 1;
            }
        }
        p->previous_x = p->x;
        p->previous_y = p->y;
        int64_t best_dot = INT64_MIN;
        for (unsigned direction = 0; direction < 16; ++direction) {
            int64_t dot = (int64_t)p->vx * ember_cos((uint16_t)(-((int)direction * 4096))) +
                (int64_t)p->vy * ember_sin((uint16_t)(-((int)direction * 4096)));
            if (dot > best_dot) { best_dot = dot; p->dir16 = (uint8_t)direction; }
        }
        p->x += p->vx;
        p->y += p->vy;
        if (!p->hostile && p->weapon < EMBER_WEAPONS_COUNT &&
            s->weapon_system[p->weapon].category == EMBER_CODEX &&
            s->player.evolution[p->weapon] == 2) {
            int target = nearest(s);
            if (target >= 0) { p->x = s->enemies[target].x; p->y = s->enemies[target].y; }
        }
        if (!p->hostile && p->follow && p->kind != 3) { p->x = s->player.x; p->y = s->player.y; }
        if (p->kind == 3) {
            p->z = maximum(0, p->z + p->vz);
            p->vz -= ember_weapons[p->weapon].lob_gravity_q16;
        }
        if (p->kind == 4) {
            for (unsigned n = 0; n < EMBER_ENEMIES; ++n)
                if (s->enemies[n].alive && within(p->x, p->y,
                    s->enemies[n].x, s->enemies[n].y, p->trigger_radius)) { p->life = 1; break; }
        }
        --p->life;
        if (p->hostile) {
            if (within(p->x, p->y, s->player.x, s->player.y,
                       p->radius + ember_characters[s->player.character].body_radius)) {
                player_hurt_resolved(s, p->damage, p->weapon, p->x, p->y,
                    p->damage_type, p->hit_flags, p->enemy_increased);
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
                        if (!p->alive || !enemy->alive ||
                            (p->hit_bits[e / 32] & (1u << (e % 32)))) continue;
                        if (within(p->x, p->y, enemy->x, enemy->y,
                                   p->radius + ember_enemies[enemy->kind].radius)) {
                            if (enemy->affix == 4 || enemy->second_affix == 4) {
                                p->hostile = 1;
                                p->weapon = (uint8_t)enemy->wave;
                                p->damage_type = EMBER_DAMAGE_IRON;
                                p->enemy_increased = enemy_in_dark(s, enemy->x, enemy->y) ?
                                    ember_lighting[0].dark_damage : 0;
                                velocity(s->player.x - p->x, s->player.y - p->y,
                                    ember_affixes[3].reflect_speed, &p->vx, &p->vy);
                                goto collision_done;
                            }
                            if (p->pet) {
                                pet_hit_depth(s, (unsigned)e, p->damage, p->depth);
                            } else enemy_hit_flags(s, (unsigned)e, p->damage,
                                p->weapon, p->depth, 0, p->hit_flags | HIT_DIRECTION_SET |
                                (enemy_front(enemy, p->previous_x, p->previous_y) ? EMBER_FRONT : 0));
                            p->last_hit = (int16_t)e;
                            p->hit_bits[e / 32] |= 1u << (e % 32);
                            if ((!p->pet && p->weapon < EMBER_WEAPONS_COUNT) || p->pet) {
                                if (((!p->pet && inscription(s, p->weapon, 6)) ||
                                    (p->pet && pet_rune(s) == 7)) &&
                                    p->depth < 3u + s->trigger_bonus) {
                                    for (unsigned n = 0; n < (unsigned)ember_inscriptions[6].value; ++n) {
                                        struct ember_shot *child = shot(s, 0, p->x, p->y,
                                            p->damage, p->radius, ember_inscriptions[6].duration);
                                        *child = *p;
                                        child->alive = 1; child->depth = (uint8_t)(p->depth + 1);
                                        child->life = (uint16_t)ember_inscriptions[6].duration;
                                        uint16_t a = (uint16_t)(((int)n * 2 - ember_inscriptions[6].value + 1) * ember_inscriptions[6].spread_angle / 2);
                                        child->vx = ember_mul(p->vx, ember_cos(a)) -
                                            ember_mul(p->vy, ember_sin(a));
                                        child->vy = ember_mul(p->vx, ember_sin(a)) +
                                            ember_mul(p->vy, ember_cos(a));
                                    }
                                }
                                if (!p->pet &&
                                    ((s->weapon_system[p->weapon].category == EMBER_STAFF &&
                                      s->player.evolution[p->weapon] != 2) ||
                                    (s->weapon_system[p->weapon].category == EMBER_GUN &&
                                     s->player.evolution[p->weapon] == 1)))
                                    area_hit(s, p->x, p->y, ember_weapons[p->weapon].radius,
                                        p->damage * ember_weapons[p->weapon].splash_percent / 100, p->weapon, 1, 0);
                            }
                            if (p->pierce == 255) {
                                ++p->passed;
                                p->damage = p->initial_damage * (100 + p->passed * ember_weapons[p->weapon].pass_damage_growth) / 100;
                            }
                            else if (p->pierce) --p->pierce;
                            else p->alive = 0;
                        }
                    }
collision_done:
            ;
        } else if ((p->kind == 1 || p->kind == 5) && !p->tick) {
            area_hit(s, p->x, p->y, p->radius, p->damage, p->weapon, 0, 0);
            p->tick = 1;
        } else if (p->kind == 2 && p->effect) {
            ground_effect(s, p);
        } else if (p->kind == 2) {
            if (!p->tick) {
                area_hit(s, p->x, p->y, p->radius, p->damage, p->weapon, p->depth, p->dot_type);
                p->tick = (uint16_t)(p->weapon < EMBER_WEAPONS_COUNT &&
                    s->weapon_system[p->weapon].category == EMBER_CODEX &&
                    s->player.evolution[p->weapon] == 1 ? ember_weapons[p->weapon].pulse_interval : ember_system[0].ground_interval);
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
    int shield_before = p->defense.permanent_shield;
    ember_defense_step(&p->defense);
    if (s->blessings[5] && shield_before < p->defense.shield_max &&
        p->defense.permanent_shield == p->defense.shield_max)
        inherited_area(s, p->x, p->y, ember_blessings[5].value2,
            ember_blessings[5].value, 0);
    ++p->action_ticks;
    if (p->action_time && !--p->action_time) player_action(s, EMBER_IDLE, 0);
    if (p->cooldown_k) --p->cooldown_k;
    if (p->cooldown_a && !--p->cooldown_a) {
        ++p->dash_charges;
        if (p->dash_charges < s->attributes[EMBER_DASH_COUNT])
            p->cooldown_a = (uint16_t)s->attributes[EMBER_DASH_COOLDOWN];
    }
    if (p->dash_charges > s->attributes[EMBER_DASH_COUNT])
        p->dash_charges = (uint8_t)s->attributes[EMBER_DASH_COUNT];
    if (p->cooldown_b) --p->cooldown_b;
    if (p->invulnerable) --p->invulnerable;
    if (p->flash) --p->flash;
    if (s->combat_frame % 60 == 0)
        heal(s, s->attributes[EMBER_REGEN]);
    if (p->defense.frozen || p->defense.status[EMBER_STUN].frames) return;
    int dx = !!(input & EMBER_RIGHT) - !!(input & EMBER_LEFT);
    int dy = !!(input & EMBER_DOWN) - !!(input & EMBER_UP);
    if (dx || dy) {
        p->facing8 = (uint8_t)direction8(dx, dy);
        p->facing_frame = (uint8_t)direction_frame(p->facing8);
        p->flip_x = p->facing8 >= 5;
    }
    if (pressed & EMBER_SWAP) {
        unsigned old = p->main_weapon;
        p->main_weapon = p->sub_weapon;
        p->sub_weapon = (uint8_t)old;
        p->combo = 0;
        ember_sim_attributes(s);
    }
    if ((pressed & EMBER_U) && p->charge == 100) {
        content_skill(s, 2);
        p->charge = 0;
        event(s, 5, 0, p->x, p->y);
    }
    if ((pressed & EMBER_K) && !p->cooldown_k) {
        content_skill(s, 0);
        p->cooldown_k = (uint16_t)(ember_characters[p->character].skill_k_cooldown *
            (100 - s->attributes[EMBER_COOLDOWN]) / 100);
        event(s, 3, 0, p->x, p->y);
    }
    if ((pressed & EMBER_L) && !p->cooldown_b) {
        content_skill(s, 1);
        p->cooldown_b = (uint16_t)(ember_characters[p->character].skill_l_cooldown *
            (100 - s->attributes[EMBER_COOLDOWN]) / 100);
        event(s, 4, 0, p->x, p->y);
    }
    if ((pressed & EMBER_DASH) && p->dash_charges) {
        --p->dash_charges;
        if (!dx && !dy) {
            const int x[8] = {0,1,1,1,0,-1,-1,-1};
            const int y[8] = {1,1,0,-1,-1,-1,0,1};
            dx = x[p->facing8]; dy = y[p->facing8];
        }
        velocity(dx * EMBER_Q, dy * EMBER_Q,
                 p->speed * ember_characters[s->player.character].dash_speed_percent / 100,
                 &s->dash_vx, &s->dash_vy);
        p->dash = (uint16_t)ember_characters[s->player.character].dash_frames;
        p->defense.invulnerable = p->dash;
        if (!p->cooldown_a) p->cooldown_a = (uint16_t)s->attributes[EMBER_DASH_COOLDOWN];
        event(s, 3, 0, p->x, p->y);
    }
    if (pressed & EMBER_INTERACT) {
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
            struct ember_enemy *e = &s->enemies[i];
            if (e->alive && e->capturable && !enemy_in_dark(s, e->x, e->y) &&
                within(p->x, p->y, e->x, e->y, ember_system[0].interact_capture_radius)) {
                ember_sim_pet(s, (unsigned)ember_enemies[e->kind].pet_kind, 255);
                e->alive = 0;
                --s->alive_count;
                player_action(s, EMBER_INTERACTING, ember_system[0].cast_frames);
                break;
            }
        }
        for (unsigned i = 0; i < 8; ++i) {
            if (!s->pillars[i].lit && within(p->x, p->y, s->pillars[i].x, s->pillars[i].y,
                ember_lighting[0].interact_radius) && s->oil >= ember_lighting[0].pillar_cost) {
                s->oil -= ember_lighting[0].pillar_cost;
                s->pillars[i].lit = 1;
                s->boss_blackout = 0;
                s->lamp_disabled = !!relic(s, R_NIGHT) || !!s->stealth;
                player_action(s, EMBER_INTERACTING, ember_system[0].cast_frames);
                break;
            }
        }
    }
    if (p->dash) {
        if (p->action != EMBER_DASHING) player_action(s, EMBER_DASHING, p->dash);
        p->x += s->dash_vx;
        p->y += s->dash_vy;
        if (s->flame_dash && p->dash % ember_characters[s->player.character].trail_interval == 0)
            shot(s, 2, p->x, p->y, ember_characters[s->player.character].trail_damage,
                 ember_characters[s->player.character].trail_radius *
                    s->attributes[EMBER_AREA] / 100,
                 ember_characters[s->player.character].trail_duration);
        --p->dash;
    } else {
        if (!p->action_time && p->action != EMBER_CHARGING) {
            unsigned action = dx || dy ? EMBER_MOVE : EMBER_IDLE;
            if (p->action != action) player_action(s, action, 0);
        }
        ember_fixed vx, vy;
        int speed = p->speed;
        if (p->defense.status[EMBER_CHILL].frames)
            speed = speed * (100 - p->defense.status[EMBER_CHILL].stacks *
                ember_statuses[EMBER_CHILL].strength) / 100;
        velocity(dx * EMBER_Q, dy * EMBER_Q, speed, &vx, &vy);
        p->x += vx;
        p->y += vy;
    }
    obstacles_resolve(s, &p->x, &p->y, ember_characters[s->player.character].body_radius);
    p->x = clamp(p->x, ember_characters[s->player.character].boundary_margin * EMBER_Q,
                 s->world_width - ember_characters[s->player.character].boundary_margin * EMBER_Q);
    p->y = clamp(p->y, ember_characters[s->player.character].boundary_margin * EMBER_Q,
                 s->world_height - ember_characters[s->player.character].boundary_margin * EMBER_Q);
}
static void pickups_step(struct ember_sim *s, int all)
{
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        struct ember_pickup *p = &s->pickups[i];
        if (p->alive && p->kind) {
            if (within(p->x, p->y, s->player.x, s->player.y, s->attributes[EMBER_PICKUP])) {
                unsigned equipped = 0;
                for (unsigned n = 0; n < EMBER_RELICS_COUNT; ++n)
                    equipped += !!s->player.relic_level[n];
                if (equipped < 6 && !s->player.relic_level[p->id]) {
                    s->player.relic_level[p->id] = 1;
                    p->alive = 0;
                    --s->pickup_count;
                    ember_sim_attributes(s);
                }
            }
            continue;
        }
        if (p->alive && (all || within(p->x, p->y, s->player.x, s->player.y,
                                      s->attributes[EMBER_PICKUP]))) {
            s->oil = minimum(ember_lighting[0].oil_max, s->oil + ember_lighting[0].ember_oil);
            energy_add(s, ember_characters[s->player.character].charge_kill);
            s->player.xp += p->xp * (unsigned)s->attributes[EMBER_XP] / 100;
            p->alive = 0;
            --s->pickup_count;
        }
    }
}
static unsigned choice_weight(const struct ember_sim *s, const struct ember_choice *c)
{
    unsigned grade = c->kind == 0 ? (unsigned)ember_weapons[c->id].grade :
        c->kind == 1 ? (unsigned)ember_relics[c->id].grade :
        c->kind == 2 ? (unsigned)ember_inscriptions[c->id].grade : 0;
    const struct ember_rarities_row *r = &ember_rarities[grade];
    return (unsigned)(r->weight * (100 + s->attributes[EMBER_LUCK] * r->luck_factor));
}
static void upgrade_offer(struct ember_sim *s)
{
    struct ember_choice eligible[2000];
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
            if (i == 10 && !charging_weapon(s, w)) continue;
            if ((i == 0 || i == 1 || i == 6 || i == 7 || i == 8) &&
                !tagged(w, "projectile")) continue;
            if (i == 9 && !tagged(w, "area")) continue;
            eligible[count++] = (struct ember_choice){2, (uint8_t)i, (uint8_t)w};
        }
    }
    for (unsigned w = 0; w < EMBER_WEAPONS_COUNT; ++w) {
        if (s->player.weapon_level[w] != 5 || s->player.evolution[w]) continue;
        for (unsigned branch = 1; branch <= 2; ++branch) {
            if (ember_sim_evolution_ready(s, w, branch))
                eligible[count++] = (struct ember_choice){3, (uint8_t)branch, (uint8_t)w};
        }
    }
    if (s->pet_kind != 255 && s->pet_level < 5)
        eligible[count++] = (struct ember_choice){4, s->pet_kind, 0};
    for (unsigned i = 0; i < 3; ++i) {
        unsigned total = 0;
        for (unsigned n = 0; n < count; ++n) total += choice_weight(s, &eligible[n]);
        unsigned roll = ember_random(&s->loot_rng) % total;
        unsigned pick = 0;
        while (roll >= choice_weight(s, &eligible[pick])) {
            roll -= choice_weight(s, &eligible[pick]); ++pick;
        }
        s->choices[i] = eligible[pick];
        eligible[pick] = eligible[--count];
    }
    s->selected = 0;
    s->phase = EMBER_UPGRADE;
    s->player.xp -= s->player.next_xp;
    ++s->player.level;
    s->player.next_xp += ember_characters[s->player.character].xp_per_level;
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
    else if (c->kind == 3) {
        ember_sim_evolve(s, c->slot, c->id);
        s->free_evolution = 0;
    } else if (c->kind == 4) ++s->pet_level;
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
    s->previous_player_x = s->player.x; s->previous_player_y = s->player.y;
    s->player.level = 1;
    s->player.next_xp = (uint32_t)ember_characters[s->player.character].initial_xp;
    s->player.weapon_level[0] = s->player.weapon_level[1] = 1;
    s->player.main_weapon = 0;
    s->player.sub_weapon = 1;
    s->player.pet_weapon = 255;
    s->pet_kind = 255;
    ember_defense_init(&s->player.defense, ember_characters[s->player.character].max_hp);
    s->player.defense.hurt_frames = (uint16_t)ember_characters[s->player.character].hurt_interval;
    s->oil = ember_lighting[0].oil_max;
    s->pet.damage = ember_system[0].pet_damage;
    s->pet.cooldown = (uint16_t)ember_system[0].pet_cooldown;
    for (unsigned i = 0; i < EMBER_WEAPONS_COUNT; ++i) {
        s->weapon_system[i].category = (uint8_t)ember_weapons[i].category;
        s->weapon_system[i].share[ember_weapons[i].element_index] = 100;
        s->weapon_system[i].rarity = !strcmp(ember_weapons[i].rarity, "fine") ? 1 :
            !strcmp(ember_weapons[i].rarity, "rare") ? 2 :
            !strcmp(ember_weapons[i].rarity, "legendary") ? 3 : 0;
        s->weapon_system[i].offhand_attribute = (uint8_t)ember_weapons[i].offhand_attribute;
        s->weapon_system[i].offhand_flat = ember_weapons[i].offhand_flat;
        for (unsigned t = 0; t < EMBER_TAGS_COUNT; ++t)
            if (tag_present(ember_weapons[i].tags, ember_tags[t].id))
                s->weapon_system[i].tags |= 1u << t;
    }
    for (unsigned i = 0; i < 8; ++i) {
        s->pillars[i].x = s->player.x + ((int)(i % 4) - 2) *
            ember_lighting[0].pillar_spacing * EMBER_Q;
        s->pillars[i].y = s->player.y + ((int)(i / 4) * 2 - 1) *
            ember_lighting[0].pillar_spacing * EMBER_Q;
    }
    s->pet_kind = 255;
    ember_sim_attributes(s);
    s->player.hp = s->player.max_hp;
    s->player.dash_charges = (uint8_t)s->attributes[EMBER_DASH_COUNT];
    s->pet_kind = 255;
    s->player.pet_weapon = 255;
    s->marked_target = s->fuse_target = -1;
    s->pet.category = 1;
    s->in_light = 0;
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
    if (s->phase == EMBER_LOST) ++s->player.action_ticks;
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
    unsigned was_in_light = s->in_light;
    for (unsigned i = 0; i < 8; ++i) {
        if (s->pillars[i].x < s->safe_left || s->pillars[i].x > s->safe_right ||
            s->pillars[i].y < s->safe_top || s->pillars[i].y > s->safe_bottom)
            s->pillars[i].lit = 0;
    }
    s->in_light = (uint8_t)player_in_light_zone(s);
    if (was_in_light != s->in_light) ember_sim_attributes(s);
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
    content_step(s);
    weapons_step(s, input);
    shots_step(s);
    const uint8_t cardinal[8] = {1,0,0,0,3,2,2,2};
    s->player.facing = cardinal[s->player.facing8];
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
        if (s->enemies[i].alive) s->enemies[i].facing = cardinal[s->enemies[i].facing8];
    s->player.action_frame = (uint8_t)((s->player.action_ticks / 4) % 8);
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
        "pet=%d,%d,%u facing=%u hand=%d,%d character=%u pet_kind=%u pet_level=%u "
        "evolution=%u,%u charge_frames=%u direction=%u,%u,%u",
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
        (int)s->pet.x, (int)s->pet.y, p->pet_timer, p->facing, p->hand_x, p->hand_y,
        p->character, s->pet_kind, s->pet_level, p->evolution[p->main_weapon],
        p->evolution[p->sub_weapon], (unsigned)s->charge_frames,
        p->facing8, p->facing_frame, p->flip_x);
}

#include "content.inc"

#include "enemy_content.inc"
