/* File: e5a_coast_test.c; plan 1a: first-version coast arena content.
 * Description: Exercise both starts, the actual acquisition pools and rune effects.
 * Clock domain: deterministic directed 60 Hz tests, separate from victory recordings.
 */
#include "sim/sim.c"
#include <assert.h>
static struct ember_sim first, second;
static void start(struct ember_sim *s, unsigned weapon, unsigned seed)
{
    struct ember_run_config c;
    ember_run_config_default(&c);
    c.main_weapon = (uint8_t)weapon;
    c.sub_weapon = (uint8_t)(weapon == 0 ? 2 : 0);
    ember_sim_begin(s, seed, &c);
    ember_sim_step(s, EMBER_START);
    s->rest = 100000;
}
static unsigned enemy(struct ember_sim *s, int offset, int hp, unsigned affix)
{
    unsigned n = ember_sim_spawn(s, 0, affix,
        s->player.x + offset * EMBER_Q, s->player.y + 20 * EMBER_Q);
    s->enemies[n].hp = s->enemies[n].defense.max_hp = hp;
    memset(s->enemies[n].defense.resistance, 0, sizeof(s->enemies[n].defense.resistance));
    return n;
}
static int different(const struct ember_sim *a, const struct ember_sim *b)
{
    if (a->damage_total != b->damage_total || a->player.hp != b->player.hp ||
        a->shot_count != b->shot_count) return 1;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
        if (a->enemies[i].hp != b->enemies[i].hp ||
            memcmp(a->enemies[i].defense.status, b->enemies[i].defense.status,
                sizeof(a->enemies[i].defense.status))) return 1;
    for (unsigned i = 0; i < EMBER_SHOTS; ++i)
        if (a->shots[i].alive != b->shots[i].alive ||
            (a->shots[i].alive && (a->shots[i].x != b->shots[i].x ||
                a->shots[i].y != b->shots[i].y || a->shots[i].radius != b->shots[i].radius)))
            return 1;
    return 0;
}
static void rune_effects(void)
{
    for (unsigned row = 0; row < EMBER_COAST_POOL_COUNT; ++row) {
        if (ember_coast_pool[row].kind != EMBER_ITEM_INSCRIPTION) continue;
        unsigned rune = (unsigned)ember_coast_pool[row].item_index;
        unsigned effective = 0;
        for (unsigned w = 0; w <= 2 && !effective; w += 2) {
            start(&first, w, 43);
            if (!rune_allowed(&first, rune, w)) continue;
            for (unsigned scenario = 0; scenario < 2 && !effective; ++scenario) {
                start(&first, w, 43); start(&second, w, 43);
                first.player.hp = second.player.hp = 100;
                second.player.inscription[w][0] = (uint8_t)(rune + 1);
                if (rune == 8)
                    first.player.inscription[w][1] = second.player.inscription[w][1] = 1;
                ember_sim_attributes(&first);
                ember_sim_attributes(&second);
                for (unsigned i = 0; i < (rune == 8 ? 1u : 3u); ++i) {
                    enemy(&first, 60 + (int)i * 20, scenario ? 60 : 100000, 0);
                    enemy(&second, 60 + (int)i * 20, scenario ? 60 : 100000, 0);
                }
                for (unsigned f = 0; f < 180 && !effective; ++f) {
                    uint16_t input = EMBER_J | (f % 60 < 30 ? EMBER_UP : EMBER_DOWN);
                    ember_sim_step(&first, input); ember_sim_step(&second, input);
                    effective = (unsigned)different(&first, &second);
                }
            }
        }
        if (!effective) fprintf(stderr, "No coast effect for rune %u\n", rune);
        assert(effective);
        printf("PASS coast rune %u: actual damage/status/projectile/healing differs\n", rune);
    }
}
static unsigned settled_damage(unsigned item, unsigned weapon, unsigned evolution, int dot)
{
    start(&first, weapon, 19);
    if (item != 255) first.player.relic_level[item] = 1;
    first.player.weapon_level[weapon] = 5;
    ember_sim_evolve(&first, weapon, evolution);
    ember_sim_attributes(&first);
    first.attributes[EMBER_CRIT] = 0;
    unsigned n = enemy(&first, 40, 100000, 0);
    grid_build(&first);
    enemy_hit(&first, n, 100, weapon, 0, dot);
    return first.damage_total;
}
static void selected_effects(void)
{
    const unsigned damage_items[] = {4,9,10,11,19,26};
    for (unsigned i = 0; i < sizeof(damage_items) / sizeof(damage_items[0]); ++i) {
        unsigned r = damage_items[i], w = r == 11 ? 2 : 0;
        unsigned evolution = r == 26 ? 2 : 0;
        assert(settled_damage(r, w, evolution, r == 10) >
            settled_damage(255, w, evolution, r == 10));
    }
    start(&first, 0, 19); start(&second, 0, 19);
    second.player.relic_level[3] = 1; ember_sim_attributes(&second);
    int radius = first.attributes[EMBER_PICKUP] + 1;
    drop_resource(&first, EMBER_DROP_XP, 0, 0, 7,
        first.player.x + radius * EMBER_Q, first.player.y);
    drop_resource(&second, EMBER_DROP_XP, 0, 0, 7,
        second.player.x + radius * EMBER_Q, second.player.y);
    pickups_step(&first, 0); pickups_step(&second, 0);
    assert(!first.player.xp && second.player.xp == 7);
    start(&first, 0, 19); start(&second, 0, 19);
    second.player.relic_level[6] = 1; ember_sim_attributes(&second);
    assert(second.attributes[EMBER_CRIT] == first.attributes[EMBER_CRIT] + 2);
    start(&first, 0, 19); start(&second, 0, 19);
    second.player.relic_level[7] = 1; ember_sim_attributes(&second);
    for (unsigned i = 0; i < 60; ++i) {
        ember_sim_step(&first, 0); ember_sim_step(&second, 0);
    }
    assert(second.oil > first.oil);
    start(&first, 0, 19); start(&second, 0, 19);
    second.player.relic_level[13] = 1;
    first.player.x = first.pillars[0].x; first.player.y = first.pillars[0].y;
    second.player.x = second.pillars[0].x; second.player.y = second.pillars[0].y;
    ember_sim_step(&first, EMBER_INTERACT); ember_sim_step(&second, EMBER_INTERACT);
    assert(first.in_light && second.in_light &&
        second.attributes[EMBER_ATTACK_SPEED] > first.attributes[EMBER_ATTACK_SPEED]);
    start(&first, 0, 19); start(&second, 0, 19);
    second.player.relic_level[30] = 1;
    enemy(&first, 40, 100000, 0); enemy(&second, 40, 100000, 0);
    ember_sim_status(&first, 0, EMBER_IGNITE, 0);
    ember_sim_status(&second, 0, EMBER_IGNITE, 0);
    assert(!light_zone_at(&first, first.enemies[0].x, first.enemies[0].y));
    assert(light_zone_at(&second, second.enemies[0].x, second.enemies[0].y));
    start(&first, 0, 19); start(&second, 0, 19);
    second.player.relic_level[33] = 1;
    ember_sim_attributes(&second);
    first.attributes[EMBER_CRIT] = second.attributes[EMBER_CRIT] = 100;
    enemy(&first, 40, 100000, 0); enemy(&second, 40, 100000, 0);
    grid_build(&first); grid_build(&second);
    enemy_hit(&first, 0, 100, 0, 0, 1); enemy_hit(&second, 0, 100, 0, 0, 1);
    assert(second.damage_total > first.damage_total);
    const unsigned blessings[] = {1,2,4,6,8,9};
    for (unsigned i = 0; i < 6; ++i) {
        unsigned b = blessings[i];
        start(&first, 0, 19); start(&second, 0, 19);
        ember_sim_blessing(&second, b);
        if (b == 6) {
            energy_add(&first, 10); energy_add(&second, 10);
            assert(first.player.charge == 10 && second.player.charge == 14);
            continue;
        }
        if (b == 1) {
            ember_sim_step(&first, EMBER_DASH); ember_sim_step(&second, EMBER_DASH);
            assert(second.dash_buff);
        }
        unsigned n = enemy(&first, 40, b == 4 ? 1 : 100000, b == 4 ? 1 : 0);
        enemy(&second, 40, b == 4 ? 1 : 100000, b == 4 ? 1 : 0);
        if (b == 2) {
            first.pillars[0].lit = second.pillars[0].lit = 1;
            first.pillars[0].x = second.pillars[0].x = first.enemies[n].x;
            first.pillars[0].y = second.pillars[0].y = first.enemies[n].y;
        }
        if (b == 8) for (unsigned j = 0; j < 9; ++j) {
            enemy(&first, 40, 100000, 0); enemy(&second, 40, 100000, 0);
        }
        first.attributes[EMBER_CRIT] = second.attributes[EMBER_CRIT] = 0;
        grid_build(&first); grid_build(&second);
        enemy_hit(&first, n, 100, 0, 0, 0); enemy_hit(&second, n, 100, 0, 0, 0);
        if (b == 4) {
            assert(second.pickup_count == first.pickup_count + 1);
            assert(second.pickups[0].kind == EMBER_DROP_RELIC &&
                item_allowed(&second, EMBER_ITEM_RELIC, second.pickups[0].id));
        } else assert(second.damage_total > first.damage_total);
    }
    puts("PASS coast selected relics and blessings: actual acquisition/combat/light/oil effects");
}
static void arena_timing(void)
{
    start(&first, 0, 19);
    first.rest = 0;
    unsigned n = enemy(&first, 300, 100000, 0);
    first.spawned = wave_target_count(&first);
    first.wave_frame = (unsigned)ember_waves[0].time_limit - 1;
    ember_sim_step(&first, 0);
    assert(first.wave == 2 && first.enemies[n].alive && first.alive_count == 1);
    start(&first, 0, 19);
    first.wave = 5; enemy_spawn(&first);
    assert(first.enemies[0].kind == 15 && first.enemies[0].defense.rank == 2);
    enemy_spawn(&first);
    assert(first.enemies[1].affix && first.enemies[1].defense.rank == 1);
    start(&first, 0, 19);
    first.wave = 10; enemy_spawn(&first);
    assert(first.enemies[0].kind == 18 && first.enemies[0].defense.rank == 3);
    start(&first, 0, 19);
    first.stage_frame = (unsigned)(ember_stages[0].time_limit +
        ember_stages[0].shrink_interval - 1);
    first.pillars[0].x = 0; first.pillars[0].lit = 1;
    ember_sim_step(&first, 0);
    assert(first.safe_left == ember_stages[0].shrink_pixels * EMBER_Q);
    ember_sim_step(&first, 0);
    assert(!first.pillars[0].lit);
    puts("PASS coast timers: 60-second overlap, head/elite/Boss roles, 12-minute shrink");
}
int main(void)
{
    unsigned counts[18] = {0};
    for (unsigned i = 0; i < EMBER_COAST_POOL_COUNT; ++i)
        ++counts[ember_coast_pool[i].kind];
    assert(counts[0] == 2 && counts[1] == 12 && counts[2] == 12 && counts[8] == 6);
    for (unsigned weapon = 0; weapon <= 2; weapon += 2) {
        start(&first, weapon, 19);
        assert(first.player.main_weapon == weapon &&
            first.player.sub_weapon == (weapon == 0 ? 2 : 0));
        assert(first.player.weapon_level[0] == 1 && first.player.weapon_level[2] == 1);
        assert(first.pet_kind == 255 && !first.rifts_count);
        enemy(&first, 40, 100000, 0);
        for (unsigned f = 0; f < 60; ++f) ember_sim_step(&first, EMBER_J);
        assert(first.damage_total);
        ember_sim_step(&first, EMBER_SWAP);
        assert(first.player.sub_weapon == weapon);
    }
    for (unsigned seed = 1; seed <= 100; ++seed) {
        start(&first, 0, seed);
        upgrade_offer(&first);
        for (unsigned i = 0; i < 3; ++i) {
            struct ember_choice c = first.choices[i];
            assert(c.kind <= 2 && item_allowed(&first, c.kind, c.id));
        }
        shop_stock(&first);
        for (unsigned i = 0; i < 3; ++i) {
            struct ember_choice c = first.shop_stock[i];
            assert((c.kind == EMBER_ITEM_RELIC || c.kind == EMBER_ITEM_INSCRIPTION) &&
                item_allowed(&first, c.kind, c.id));
        }
        struct ember_altar_choice choices[3];
        assert(ember_sim_altar_choices(&first, choices) == 3);
        for (unsigned i = 0; i < 3; ++i)
            assert(!choices[i].kind && item_allowed(&first, EMBER_ITEM_BLESSING, choices[i].id));
    }
    start(&first, 0, 19);
    unsigned n = enemy(&first, 20, 1, 1);
    content_enemy(&first, n);
    assert(!first.enemies[n].capturable);
    player_step(&first, EMBER_INTERACT, EMBER_INTERACT);
    assert(first.pet_kind == 255 && first.enemies[n].alive);
    first.enemies[n].alive = 0; first.alive_count = 0;
    first.wave = 10;
    modes_cleared(&first);
    assert(first.stage_clear && !first.shop_available);
    first.exit = (struct ember_point){first.player.x,first.player.y};
    assert(modes_interact(&first) && first.phase == EMBER_WON && !first.config.stage);
    rune_effects(); selected_effects(); arena_timing();
    puts("PASS coast: paired starts, 100 acquisition pools, no pet/rift/resonance, ten-wave exit");
    return 0;
}
