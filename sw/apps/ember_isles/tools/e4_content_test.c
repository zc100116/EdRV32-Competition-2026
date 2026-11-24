/* File: e4_content_test.c; tech 6 E4 and gdd 3.3/4.6/5b/5c/5e.
 * Directed content verification through deterministic simulation operations.
 * Clock domain: fixed 60 Hz. Includes sim.c to exercise individual hit/AI rules.
 */
#include "../src/sim/sim.c"
#include <assert.h>
static struct ember_sim fixture;
static unsigned assertions;
#define CHECK(condition) do { ++assertions; if (!(condition)) { \
    fprintf(stderr, "FAIL E4 line %d: %s\n", __LINE__, #condition); exit(1); } } while (0)
static void setup(void)
{
    ember_sim_init(&fixture, 11);
    fixture.phase = EMBER_PLAY;
    fixture.wave = 1;
    fixture.rest = 60000;
    fixture.player.pet_weapon = 255;
    fixture.attributes[EMBER_CRIT] = 0;
}
static unsigned target(int offset)
{
    unsigned i = ember_sim_spawn(&fixture, 0, 0,
        fixture.player.x + offset * EMBER_Q, fixture.player.y);
    fixture.enemies[i].hp = fixture.enemies[i].defense.max_hp = 100000;
    memset(fixture.enemies[i].defense.resistance, 0,
        sizeof(fixture.enemies[i].defense.resistance));
    return i;
}
static unsigned weapon(unsigned category, unsigned element)
{
    for (unsigned w = 0; w < EMBER_WEAPONS_COUNT; ++w)
        if (ember_weapons[w].category == (int)category &&
            ember_weapons[w].element_index == (int)element) return w;
    abort();
}
static void equip(unsigned w)
{
    memset(fixture.player.weapon_level, 0, sizeof(fixture.player.weapon_level));
    fixture.player.weapon_level[w] = 5;
    fixture.player.main_weapon = (uint8_t)w;
}
static void row(const char *table, const char *id) { printf("COVER,%s,%s\n", table, id); }
static void weapons(void)
{
    for (unsigned w = 0; w < EMBER_WEAPONS_COUNT; ++w) {
        setup(); target(20); grid_build(&fixture); equip(w);
        unsigned before = fixture.damage_total;
        fixture.charge_frames = (uint16_t)ember_weapons[w].charge_frames;
        weapon_fire(&fixture, w);
        CHECK(fixture.damage_total > before || fixture.shot_count > 0);
        CHECK(fixture.weapon_system[w].share[ember_weapons[w].element_index] == 100);
        for (unsigned branch = 1; branch <= 2; ++branch) {
            ember_sim_evolve(&fixture, w, branch);
            fixture.weapon_timer[w] = 0;
            weapon_fire(&fixture, w);
            CHECK(fixture.player.evolution[w] == branch);
        }
        row("weapons", ember_weapons[w].id);
    }
    for (unsigned c = 0; c < 10; ++c) {
        setup(); target(200); equip(weapon(c, 1));
        ember_sim_step(&fixture, EMBER_J);
        int charge = c == 1 || c == 5 || c == 7;
        CHECK(charge ? !fixture.shot_count && !fixture.damage_total :
            fixture.shot_count || fixture.damage_total || c < 5);
        unsigned attacks = fixture.attack_count[fixture.player.main_weapon];
        ember_sim_step(&fixture, 0);
        CHECK(fixture.attack_count[fixture.player.main_weapon] == attacks + charge);
    }
    setup(); unsigned w = weapon(5, 1); equip(w); target(50);
    fixture.player.evolution[w] = 2; fixture.charge_frames = 30;
    weapon_fire(&fixture, w); CHECK(fixture.shots[0].pierce == 255);
    setup(); w = weapon(8, 1); equip(w); target(30);
    ember_sim_status(&fixture, 0, EMBER_IGNITE, 0);
    ember_sim_status(&fixture, 0, EMBER_IGNITE, 0);
    fixture.player.evolution[w] = 2;
    enemy_hit(&fixture, 0, 100, w, 0, 0);
    CHECK(fixture.damage_total >= 300);
    CHECK(fixture.enemies[0].defense.status[EMBER_IGNITE].stacks <= 1);
}
static void evolutions(void)
{
    for (unsigned c = 0; c < 10; ++c) for (unsigned b = 1; b <= 2; ++b) {
        setup(); unsigned w = weapon(c, 1); equip(w);
        target(20); target(c == EMBER_SWORD && b == 1 ? -20 : 40);
        grid_build(&fixture); fixture.player.evolution[w] = (uint8_t)b;
        fixture.player.combo = 2; fixture.attack_count[w] = 2;
        fixture.hit_count[w] = 3; fixture.arrow_count[w] = 4;
        fixture.charge_frames = 30;
        fixture.enemies[0].facing8 = EMBER_EAST;
        fixture.player.hp = 100;
        if (c == EMBER_GREATSWORD && b == 2) fixture.enemies[0].hp = 20000;
        if (c == EMBER_STAFF && b == 2) {
            ember_sim_status(&fixture, 0, EMBER_IGNITE, 0);
            ember_sim_status(&fixture, 0, EMBER_IGNITE, 0);
        }
        weapon_fire(&fixture, w);
        switch (c) {
        case EMBER_SWORD:
            if (b == 1) CHECK(fixture.enemies[1].hp < 100000);
            else CHECK(fixture.events.item[0].tier >= 1);
            break;
        case EMBER_GREATSWORD:
            if (b == 1) CHECK(fixture.shots[0].kind == 2 && fixture.shots[0].radius > 75);
            else CHECK(fixture.damage_total >= 440);
            break;
        case EMBER_SPEAR:
            if (b == 1) CHECK(fixture.shots[0].kind == 0);
            else CHECK(fixture.enemies[0].x < fixture.player.x + 20 * EMBER_Q);
            break;
        case EMBER_BLADES:
            if (b == 1) CHECK(fixture.shot_count >= 4);
            else CHECK(fixture.player.hp > 100 &&
                fixture.enemies[0].defense.status[EMBER_IGNITE].stacks >= 2);
            break;
        case EMBER_HAMMER:
            if (b == 1) CHECK(fixture.enemies[0].defense.status[EMBER_BREAK_ARMOR].stacks);
            else CHECK(fixture.damage_total >= 192);
            break;
        case EMBER_BOW:
            if (b == 1) CHECK(fixture.damage_total);
            else CHECK(fixture.shots[0].pierce == 255);
            break;
        case EMBER_CROSSBOW:
            if (b == 1) CHECK(fixture.shot_count == 9);
            else { for (unsigned f = 0; f < 5; ++f) shots_step(&fixture);
                CHECK(fixture.enemies[1].hp < 100000); }
            break;
        case EMBER_GUN:
            if (b == 1) { for (unsigned f = 0; f < 5; ++f) shots_step(&fixture);
                CHECK(fixture.enemies[1].hp < 100000); }
            else CHECK(fixture.shots[0].life == 144);
            break;
        case EMBER_STAFF:
            if (b == 1) CHECK(fixture.shot_count == 3);
            else { for (unsigned f = 0; f < 5; ++f) shots_step(&fixture);
                CHECK(fixture.damage_total >= 300); }
            break;
        case EMBER_CODEX:
            if (b == 1) CHECK(fixture.shots[0].radius == 90);
            else { fixture.enemies[0].y += 30 * EMBER_Q; shots_step(&fixture);
                CHECK(fixture.shots[0].y == fixture.enemies[0].y); }
            break;
        }
        printf("EVOLUTION,%u,%u\n", c, b);
    }
}
static void relics(void)
{
    for (unsigned i = 0; i < EMBER_RELICS_COUNT; ++i) {
        setup(); fixture.player.relic_level[i] = 1;
        if (i == R_BADGE) fixture.in_light = 1;
        ember_sim_attributes(&fixture);
        switch (i) {
        case R_THORN:
            target(20); player_hurt_typed(&fixture, 100, 1,
                fixture.enemies[0].x, fixture.enemies[0].y, 0, 0);
            CHECK(fixture.damage_total > 0 && fixture.thorn_next == 30); break;
        case R_LINING:
            target(20); player_hurt_typed(&fixture, 100, 1,
                fixture.enemies[0].x, fixture.enemies[0].y, 0, 0);
            CHECK(fixture.player.defense.temporary[6] > 0 &&
                fixture.player.defense.shield_frames[6] == 240); break;
        case R_IRON: CHECK(fixture.player.armor == 30); break;
        case R_HEART: CHECK(fixture.player.max_hp == 290); break;
        case R_BOOTS: CHECK(fixture.player.speed == 129); break;
        case R_BAG: CHECK(fixture.attributes[EMBER_PICKUP] == 62); break;
        case R_STONE: CHECK(fixture.attributes[EMBER_ATTACK] == 105); break;
        case R_LUCK:
            CHECK(fixture.attributes[EMBER_LUCK] == 5);
            CHECK(choice_weight(&fixture, &(struct ember_choice){1,R_STAR,0}) == 2200);
            CHECK(choice_weight(&fixture, &(struct ember_choice){1,R_IRON,0}) == 10000);
            break;
        case R_FEATHER: CHECK(fixture.attributes[EMBER_CRIT] == 7); break;
        case R_OIL: CHECK(fixture.attributes[EMBER_FUEL_EFFICIENCY] > 100); break;
        case R_MIRROR: CHECK(fixture.attributes[EMBER_AREA] == 115); break;
        case R_COAL: CHECK(fixture.attributes[EMBER_DURATION] == 120); break;
        case R_BUCKLE: CHECK(fixture.attributes[EMBER_DASH_COUNT] == 2); break;
        case R_BADGE: CHECK(fixture.attributes[EMBER_ATTACK_SPEED] == 115); break;
        case R_CLOAK:
            fixture.in_light = 0; ember_sim_attributes(&fixture);
            CHECK(fixture.player.speed == 138 && fixture.attributes[EMBER_DODGE] == 5); break;
        case R_FROST:
            target(20); ember_sim_status(&fixture, 0, EMBER_CHILL, 0);
            ember_sim_status(&fixture, 0, EMBER_CHILL, 0);
            CHECK(fixture.enemies[0].defense.frozen); break;
        case R_FILE:
            target(20); ember_sim_status(&fixture, 0, EMBER_BREAK_ARMOR, 0);
            CHECK(fixture.enemies[0].defense.break_bonus == 2); break;
        case R_RIFT: CHECK(fixture.cap_raise[EMBER_CRIT] == 30); break;
        case R_TWINS: CHECK(fixture.dual_wield); break;
        case R_NIGHT: CHECK(fixture.lamp_disabled); break;
        case R_BELL: CHECK(fixture.trigger_bonus == 1); break;
        case R_BONE: CHECK(fixture.dot_can_crit); break;
        case R_GALE: CHECK(fixture.cap_raise[EMBER_ATTACK_SPEED] == 50); break;
        default: {
            target(20); grid_build(&fixture);
            fixture.player.hp = 100;
            fixture.in_light = 0;
            fixture.enemies[0].defense.frozen = 90;
            fixture.enemies[0].defense.status[EMBER_CORRODE].frames = 180;
            fixture.enemies[0].burn = 180;
            fixture.curses[0] = 1;
            if (i == R_LAMP) CHECK(!enemy_in_dark(&fixture, fixture.enemies[0].x,
                fixture.enemies[0].y));
            unsigned w = weapon(i == R_BELT ? 0 : 8, i == R_ANVIL ? 0 : 1);
            unsigned old = fixture.damage_total;
            enemy_hit(&fixture, 0, 100, w, 0, i == R_COAL);
            CHECK(fixture.damage_total > old);
            break;
        }
        }
        row("relics", ember_relics[i].id);
    }
}
static unsigned relic_damage(unsigned item, unsigned category, unsigned element,
                              int critical, int frozen, int periodic)
{
    setup(); target(20); grid_build(&fixture);
    if (item < EMBER_RELICS_COUNT) fixture.player.relic_level[item] = 1;
    ember_sim_attributes(&fixture);
    fixture.attributes[EMBER_CRIT] = critical ? 100 : 0;
    fixture.in_light = critical ? 0 : 1;
    fixture.enemies[0].defense.frozen = frozen ? 90 : 0;
    fixture.enemies[0].defense.armor = 100;
    fixture.curses[0] = 1;
    enemy_hit(&fixture, 0, 100, weapon(category, element), 0, periodic);
    return fixture.damage_total;
}
static void relic_rules(void)
{
    const unsigned damage_items[] = {R_QUIVER,R_MIRROR,R_COAL,R_BELT,R_CORE,
        R_ICE,R_ANVIL,R_EYE,R_FORGE,R_TIDE,R_LENS,R_DARK_HEART};
    for (unsigned n = 0; n < sizeof(damage_items) / sizeof(damage_items[0]); ++n) {
        unsigned item = damage_items[n];
        unsigned category = item == R_BELT || item == R_LENS ? 3 : 8;
        unsigned element = item == R_FORGE ? 0 : 1;
        unsigned before = relic_damage(99, category, element, item == R_EYE,
            item == R_ICE, item == R_COAL);
        unsigned after = relic_damage(item, category, element, item == R_EYE,
            item == R_ICE, item == R_COAL);
        CHECK(after > before);
    }
    setup(); fixture.player.relic_level[R_NEEDLE] = 1;
    for (unsigned n = 0; n < 5; ++n) target(20 + (int)n * 20);
    ember_sim_status(&fixture, 0, EMBER_SHOCK, 0);
    CHECK(fixture.enemies[4].hp < 100000);
    setup(); fixture.player.relic_level[R_STAR] = 1;
    target(20); target(40); target(60);
    ember_sim_status(&fixture, 0, EMBER_SHOCK, 0);
    CHECK(100000 - fixture.enemies[2].hp >= 8);
    setup(); fixture.player.relic_level[R_FANG] = 1;
    target(20); fixture.player.hp = 100;
    ember_sim_status(&fixture, 0, EMBER_CORRODE, 0);
    enemy_hit(&fixture, 0, 100, 0, 0, 0);
    CHECK(fixture.player.hp >= 105);
    setup(); fixture.player.relic_level[R_HOURGLASS] = 1;
    fixture.player.cooldown_k = 120;
    for (unsigned n = 0; n < 5; ++n) {
        target(20 + (int)n * 20);
        enemy_hit(&fixture, n, 1, 0, 0, 0);
    }
    CHECK(fixture.player.cooldown_k == 60);
    setup(); fixture.player.relic_level[R_LAMP] = 1; target(400);
    fixture.enemies[0].burn = 180;
    CHECK(!enemy_in_dark(&fixture, fixture.enemies[0].x, fixture.enemies[0].y));
}
static void inscriptions(void)
{
    for (unsigned i = 0; i < EMBER_INSCRIPTIONS_COUNT; ++i) {
        setup(); unsigned w = weapon(i == 9 ? 9 : i == 10 ? 5 : 8, 1); equip(w);
        fixture.player.inscription[w][0] = (uint8_t)(i + 1);
        fixture.player.hp = 100;
        target(40); target(70); grid_build(&fixture);
        fixture.attack_count[w] = 2;
        fixture.charge_frames = 30;
        weapon_fire(&fixture, w);
        for (unsigned f = 0; f < 30; ++f) shots_step(&fixture);
        CHECK(fixture.damage_total > 0);
        if (i == 3) CHECK(fixture.enemies[0].defense.status[EMBER_WET].frames);
        if (i == 5) CHECK(fixture.player.hp > 100);
        if (i == 13) CHECK(fixture.shot_count);
        row("inscriptions", ember_inscriptions[i].id);
    }
}
static void characters(void)
{
    for (unsigned c = 0; c < EMBER_CHARACTERS_COUNT; ++c) {
        setup(); ember_sim_character(&fixture, c); target(40); grid_build(&fixture);
        unsigned w = fixture.player.main_weapon;
        CHECK(fixture.player.weapon_level[w] == 1);
        content_skill(&fixture, 0); content_skill(&fixture, 1); content_skill(&fixture, 2);
        CHECK(fixture.player.action == EMBER_CAST);
        CHECK(fixture.ultimate_time);
        for (unsigned f = 0; f < 10; ++f) content_step(&fixture);
        row("characters", ember_characters[c].id);
    }
}
static void pets(void)
{
    for (unsigned i = 0; i < EMBER_PET_WEAPONS_COUNT; ++i) {
        setup(); target(30); ember_sim_pet(&fixture, 0, i);
        pet_step(&fixture);
        CHECK(fixture.damage_total || fixture.shot_count);
        row("pet_weapons", ember_pet_weapons[i].id);
    }
    for (unsigned i = 0; i < EMBER_PETS_COUNT; ++i) {
        setup(); target(30); ember_sim_pet(&fixture, i, 3); pet_step(&fixture);
        CHECK(fixture.pet_skill_timer);
        row("pets", ember_pets[i].id);
    }
}
static void pet_runes(void)
{
    setup(); target(20); ember_sim_pet(&fixture, 0, 3);
    fixture.player.pet_inscription[3] = 6;
    fixture.player.hp = 100;
    for (unsigned i = 0; i < 3; ++i) pet_hit(&fixture, 0, 12);
    CHECK(fixture.player.hp > 100);
    ember_sim_pet(&fixture, 0, 4); CHECK(pet_rune(&fixture) == 0);
    ember_sim_pet(&fixture, 0, 3); CHECK(pet_rune(&fixture) == 6);
    fixture.player.pet_inscription[3] = 18;
    fixture.pet_attack_count = 1;
    fixture.events.count = 0; pet_hit(&fixture, 0, 12);
    CHECK(fixture.events.item[0].damage_type == EMBER_DAMAGE_FIRE);
    fixture.pet_attack_count = 2;
    fixture.events.count = 0; pet_hit(&fixture, 0, 12);
    CHECK(fixture.events.item[0].damage_type == EMBER_DAMAGE_WATER);
    fixture.player.pet_inscription[3] = 5;
    fixture.pet_hit_count = 2;
    fixture.events.count = 0; pet_hit(&fixture, 0, 12);
    CHECK(fixture.events.item[0].tier == 1);
    setup(); target(20); ember_sim_pet(&fixture, 0, 3);
    fixture.player.pet_inscription[3] = 17; pet_step(&fixture);
    CHECK(fixture.shot_count == 2);
    for (unsigned kind = 0; kind < 6; ++kind) {
        setup(); target(20); ember_sim_pet(&fixture, kind, 255);
        CHECK(fixture.player.pet_weapon == 255 && !pet_rune(&fixture));
        pet_step(&fixture); CHECK(fixture.damage_total || fixture.shot_count);
    }
}
static void enemies(void)
{
    for (unsigned i = 0; i < EMBER_ENEMIES_COUNT; ++i) {
        setup(); unsigned e = ember_sim_spawn(&fixture, i, 0,
            fixture.player.x + 80 * EMBER_Q, fixture.player.y);
        CHECK(fixture.enemies[e].defense.rank == ember_enemies[i].rank);
        for (unsigned f = 0; f < 160; ++f) content_enemy(&fixture, e);
        if (i >= 15) {
            fixture.enemies[e].hp = ember_enemies[i].hp / 4;
            content_enemy(&fixture, e);
            CHECK(fixture.enemies[e].stage);
        }
        row("enemies", ember_enemies[i].id);
    }
    for (unsigned a = 1; a <= EMBER_AFFIXES_COUNT; ++a) {
        setup(); unsigned e = ember_sim_spawn(&fixture, 0, a,
            fixture.player.x + 40 * EMBER_Q, fixture.player.y);
        CHECK(fixture.enemies[e].defense.tenacity == 50);
        content_enemy(&fixture, e);
        row("affixes", ember_affixes[a - 1].id);
    }
}
static void class_shapes(void)
{
    setup(); unsigned w = weapon(EMBER_CROSSBOW, EMBER_DAMAGE_IRON); equip(w);
    target(100); weapon_fire(&fixture, w);
    CHECK(fixture.shot_count == (unsigned)ember_weapons[w].burst_count);
    CHECK(fixture.shots[0].delay == 0 &&
        fixture.shots[1].delay == ember_weapons[w].burst_interval);
    ember_fixed old_x = fixture.shots[1].x;
    shots_step(&fixture); CHECK(fixture.shots[1].x == old_x);
    for (unsigned f = 0; f < (unsigned)ember_weapons[w].burst_interval; ++f)
        shots_step(&fixture);
    CHECK(fixture.shots[1].x != old_x);
    setup(); w = weapon(EMBER_CROSSBOW, EMBER_DAMAGE_IRON); equip(w); target(100);
    fixture.player.evolution[w] = 1; weapon_fire(&fixture, w);
    CHECK(fixture.shot_count == (unsigned)ember_weapons[w].evo_a_count);
    CHECK(fixture.shots[1].delay == 0 && fixture.shots[0].vy != fixture.shots[8].vy);
    setup(); w = weapon(EMBER_SPEAR, EMBER_DAMAGE_IRON); equip(w);
    target(20); target(0); fixture.enemies[1].y += 35 * EMBER_Q;
    fixture.player.combo = 2; weapon_fire(&fixture, w);
    CHECK(fixture.enemies[1].hp < 100000);
    setup(); w = weapon(EMBER_SWORD, EMBER_DAMAGE_IRON); equip(w);
    target(20); target(0); fixture.enemies[1].y += 35 * EMBER_Q;
    fixture.player.combo = 2; weapon_fire(&fixture, w);
    CHECK(fixture.enemies[1].hp == 100000);
}
static void entity_rules(void)
{
    for (unsigned k = 0; k < EMBER_SUMMONS_COUNT; ++k) {
        setup(); target(20); summon(&fixture, k, 180, fixture.player.x, fixture.player.y);
        CHECK(fixture.summons[0].hp == ember_summons[k].hp);
        CHECK(fixture.summons[0].armor == ember_summons[k].armor +
            (ember_summons[k].inherit_armor ? fixture.attributes[EMBER_ARMOR] : 0));
        content_step(&fixture); CHECK(fixture.damage_total);
        row("summons", ember_summons[k].id);
    }
    for (unsigned k = 3; k < 15; ++k) {
        setup(); unsigned i = ember_sim_spawn(&fixture, k, 0,
            fixture.player.x + 10 * EMBER_Q, fixture.player.y);
        struct ember_enemy *e = &fixture.enemies[i];
        const struct ember_enemies_row *d = &ember_enemies[k];
        e->ai_timer = (uint32_t)d->attack_cooldown - 1;
        content_enemy(&fixture, i);
        switch (k) {
        case 3: CHECK(e->defense.front_block && e->defense.block_strength == d->block_percent); break;
        case 4: case 10:
            content_death(&fixture, i, 0, 0, 1);
            CHECK(fixture.shots[0].effect == (k == 4 ? 4 : 6)); break;
        case 5: CHECK(fixture.player.defense.status[EMBER_CHILL].frames); break;
        case 6: CHECK(fixture.player.defense.status[EMBER_SHOCK].frames); break;
        case 7: CHECK(fixture.player.defense.status[EMBER_BREAK_ARMOR].frames); break;
        case 8: CHECK(fixture.shots[0].pierce == d->pass_through); break;
        case 9: CHECK(fixture.shot_count == (unsigned)d->shot_count); break;
        case 11: CHECK(e->vx || e->vy); break;
        case 12:
            e->ai_timer = (uint32_t)d->charge_frames;
            content_enemy(&fixture, i); CHECK(e->vx || e->vy); break;
        case 13: CHECK(fixture.shots[0].damage_type == EMBER_DAMAGE_TRUE); break;
        case 14:
            e->ai_timer = (uint32_t)d->ground_interval - 1;
            content_enemy(&fixture, i); CHECK(fixture.shots[0].effect == 6); break;
        }
        e->defense.status[EMBER_CHILL].frames = 180;
        e->defense.status[EMBER_CHILL].stacks = 1;
        int slowed = enemy_speed(&fixture, e);
        e->defense.status[EMBER_CHILL] = (struct ember_status_state){0};
        CHECK(d->speed ? slowed < enemy_speed(&fixture, e) : slowed == 0);
    }
    setup(); unsigned i = ember_sim_spawn(&fixture, 0, 1,
        fixture.player.x + 40 * EMBER_Q, fixture.player.y);
    CHECK(enemy_speed(&fixture, &fixture.enemies[i]) > ember_enemies[0].speed);
    setup(); i = ember_sim_spawn(&fixture, 0, 2, fixture.player.x, fixture.player.y);
    CHECK(fixture.enemies[i].defense.temporary[6] == ember_affixes[1].shield);
    setup(); i = ember_sim_spawn(&fixture, 0, 3, fixture.player.x, fixture.player.y);
    fixture.enemies[i].alive = 0; content_death(&fixture, i, 0, 0, 1);
    CHECK(fixture.alive_count == 1u + (unsigned)ember_affixes[2].split_count);
    setup(); i = ember_sim_spawn(&fixture, 0, 5, fixture.player.x, fixture.player.y);
    int lamp = fixture.lamp_radius; content_enemy(&fixture, i);
    CHECK(fixture.lamp_radius == lamp * (100 - ember_affixes[4].value) / 100);
    setup(); i = ember_sim_spawn(&fixture, 9, 6, fixture.player.x, fixture.player.y);
    fixture.enemies[i].hp = 1;
    fixture.enemies[i].ai_timer = (uint32_t)(ember_enemies[9].attack_cooldown *
        100 / (100 + ember_affixes[5].value) - 1);
    content_enemy(&fixture, i); CHECK(fixture.shot_count);
    setup(); i = ember_sim_spawn(&fixture, 0, 7, fixture.player.x, fixture.player.y);
    CHECK(fixture.enemies[i].defense.temporary[ember_enemies[0].element_index] ==
        ember_affixes[6].value);
    setup(); i = ember_sim_spawn(&fixture, 0, 8, fixture.player.x, fixture.player.y);
    fixture.enemies[i].ai_timer = (uint32_t)ember_affixes[7].duration - 1;
    content_enemy(&fixture, i);
    CHECK(fixture.enemies[i].x != fixture.player.x || fixture.enemies[i].y != fixture.player.y);
    setup(); target(20);
    fixture.enemies[0].facing8 = EMBER_EAST;
    CHECK(!enemy_front(&fixture.enemies[0], fixture.player.x, fixture.player.y));
    fixture.enemies[0].facing8 = EMBER_WEST;
    CHECK(enemy_front(&fixture.enemies[0], fixture.player.x, fixture.player.y));
}
static void blessings(void)
{
    for (unsigned b = 0; b < EMBER_BLESSINGS_COUNT; ++b) {
        setup(); target(20); grid_build(&fixture); ember_sim_blessing(&fixture, b);
        struct ember_attack h = {.base = 100, .attack = 100, .share = {0,100,0,0,0,0}};
        switch (b) {
        case 0:
            fixture.attributes[EMBER_TIDE_DAMAGE] = 140;
            content_before_hit(&fixture, 0, 0, &h); CHECK(h.increased == 40); break;
        case 1:
            fixture.dash_buff = 120;
            content_before_hit(&fixture, 0, 0, &h); CHECK(h.increased == 40); break;
        case 2:
            fixture.pillars[0].lit = 1;
            fixture.pillars[0].x = fixture.enemies[0].x;
            fixture.pillars[0].y = fixture.enemies[0].y;
            CHECK(ember_sim_hit(&fixture, 0, &h).damage == 120); break;
        case 3:
            fixture.enemies[0].x += 300 * EMBER_Q;
            fixture.enemies[0].alive = 0; fixture.oil = 100;
            content_death(&fixture, 0, 0, 0, 10);
            CHECK(fixture.oil == 300); break;
        case 4:
            fixture.enemies[0].affix = 1;
            fixture.enemies[0].hp = 1;
            ember_sim_hit(&fixture, 0, &h);
            CHECK(fixture.pickup_count == 2);
            CHECK(fixture.pickups[0].kind || fixture.pickups[1].kind); break;
        case 5:
            fixture.player.defense.shield_max = 10;
            fixture.player.defense.since_hurt = 180;
            player_step(&fixture, 0, 0);
            CHECK(fixture.damage_total); break;
        case 6:
            energy_add(&fixture, 10); CHECK(fixture.player.charge == 14); break;
        case 7:
            ember_sim_status(&fixture, 0, EMBER_WET, 0);
            ember_sim_status(&fixture, 0, EMBER_IGNITE, 0);
            CHECK(fixture.damage_total >= 24); break;
        case 8:
            for (unsigned n = 0; n < 9; ++n) target(20);
            content_before_hit(&fixture, 0, 0, &h); CHECK(h.increased == 10); break;
        case 9:
            content_before_hit(&fixture, 0, 0, &h); CHECK(h.base == 200); break;
        case 10:
            ember_sim_pet(&fixture, 0, 3); pet_step(&fixture);
            CHECK(fixture.player.pet_timer == 40 && fixture.pet_skill_timer == 420); break;
        case 12:
            player_hurt_typed(&fixture, 20, 1,
                fixture.enemies[0].x, fixture.enemies[0].y, 0, 0);
            CHECK(fixture.damage_total > 0 && fixture.recoil_next == 120);
            CHECK(fixture.enemies[0].x > fixture.player.x + 20 * EMBER_Q); break;
        case 11:
            fixture.standing_frames = 60; content_step(&fixture);
            CHECK(fixture.player.defense.reduction[2] == 25); break;
        }
        row("blessings", ember_blessings[b].id);
    }
}
static void resonances(void)
{
    for (unsigned b = 0; b < EMBER_RESONANCES_COUNT; ++b) {
        setup(); target(20); target(50); grid_build(&fixture);
        ember_sim_resonance(&fixture, b);
        struct ember_attack h = {.base = 100, .attack = 100, .share = {0,100,0,0,0,0}};
        switch (b) {
        case 0:
            ember_sim_status(&fixture, 0, EMBER_WET, 0);
            ember_sim_status(&fixture, 0, EMBER_IGNITE, 0);
            CHECK(fixture.shots[0].effect == 11); break;
        case 1:
            fixture.enemies[0].defense.status[EMBER_BREAK_ARMOR].stacks = 3;
            h.flags = EMBER_DOT; content_before_hit(&fixture, 0, 0, &h);
            CHECK(h.increased == 15); break;
        case 2:
            fixture.enemies[1].burn = 180;
            ember_sim_status(&fixture, 0, EMBER_SHOCK, 0);
            CHECK(fixture.enemies[0].hp < 100000); break;
        case 3:
            fixture.enemies[0].alive = 0; fixture.enemies[0].burn = 180;
            fixture.enemies[0].defense.status[EMBER_CORRODE].frames = 180;
            content_death(&fixture, 0, 0, 0, 10);
            CHECK(fixture.shots[0].effect == 2); break;
        case 4:
            ember_sim_status(&fixture, 0, EMBER_WET, 0);
            CHECK(fixture.enemies[0].defense.rust == 50); break;
        case 5:
            for (unsigned n = 0; n < 4; ++n) target(60 + (int)n * 15);
            for (unsigned n = 0; n < 6; ++n) ember_sim_status(&fixture, n, EMBER_WET, 0);
            ember_sim_status(&fixture, 0, EMBER_SHOCK, 0);
            CHECK(fixture.enemies[5].hp < 100000); break;
        case 6:
            fixture.enemies[0].alive = 0; fixture.enemies[0].defense.frozen = 30;
            content_death(&fixture, 0, 0, 0, 10);
            CHECK(fixture.shots[0].effect == 3); break;
        case 7:
            fixture.attributes[EMBER_ARMOR] = 100;
            h.share[1] = 0; h.share[3] = 100;
            content_before_hit(&fixture, 0, 0, &h); CHECK(h.increased == 10); break;
        case 8:
            fixture.player.hp = fixture.player.max_hp;
            heal(&fixture, 10); CHECK(fixture.player.defense.temporary[6] == 10); break;
        case 9:
            fixture.previous_light = 0; fixture.in_light = 1;
            content_step(&fixture); CHECK(fixture.damage_total);
            CHECK(fixture.events.item[0].damage_type == EMBER_DAMAGE_FIRE); break;
        }
        row("resonances", ember_resonances[b].id);
    }
}
static void contracts(void)
{
    for (unsigned c = 0; c < EMBER_CONTRACTS_COUNT; ++c) {
        setup();
        if (c == 5) ember_sim_pet(&fixture, 0, 255);
        ember_sim_contract(&fixture, c, c);
        switch (c) {
        case 0:
            CHECK(fixture.player.max_hp == 208 && fixture.has_reward_relic); break;
        case 1: {
            unsigned e = ember_sim_spawn(&fixture, 0, 1, fixture.player.x, fixture.player.y);
            CHECK(fixture.enemies[e].second_affix == 2 && fixture.free_evolution); break;
        }
        case 2:
            CHECK(fixture.attributes[EMBER_FUEL_EFFICIENCY] == 50 &&
                fixture.guaranteed_resonance); break;
        case 3:
            fixture.player.hp = 100; heal(&fixture, 20);
            CHECK(fixture.player.hp == 110 && fixture.gold == 200 &&
                fixture.has_reward_inscription); break;
        case 4:
            CHECK(!fixture.attributes[EMBER_DASH_COUNT] && fixture.contract_cap_choice);
            ember_sim_reward_cap(&fixture, EMBER_CRIT);
            CHECK(fixture.cap_raise[EMBER_CRIT] == 20); break;
        case 5:
            CHECK(ember_sim_price(&fixture, 30) == 45 && fixture.pet_level == 5); break;
        }
        ember_sim_cleanse(&fixture, c); CHECK(!fixture.curses[c]);
        row("contracts", ember_contracts[c].id);
    }
    setup(); ember_sim_contract(&fixture, 2, 2);
    struct ember_altar_choice choices[3];
    ember_sim_altar_choices(&fixture, choices);
    for (unsigned i = 0; i < 3; ++i) CHECK(choices[i].kind == 1);
    CHECK(!fixture.guaranteed_resonance);
    ember_sim_resonance(&fixture, 0); ember_sim_resonance(&fixture, 1);
    CHECK(!ember_sim_contract_reward_available(&fixture, 2));
    setup(); fixture.player.relic_level[R_THORN] = 1;
    fixture.player.relic_level[R_LINING] = 1;
    ember_sim_blessing(&fixture, 12); ember_sim_blessing(&fixture, 11);
    CHECK(ember_sim_tag_count(&fixture, "on_hurt") == 3);
    row("cleansers", ember_cleansers[0].id);
}
static void builds(void)
{
    /* gdd 4.6.6: each named combination is equipped in the same invocation. */
    const unsigned chars[10] = {0,4,2,3,5,1,7,6,1,0};
    const unsigned categories[10] = {8,8,2,5,6,4,6,3,4,8};
    const unsigned elements[10] = {1,1,2,3,3,0,0,4,0,1};
    const unsigned branches[10] = {1,2,2,2,2,2,0,2,1,0};
    const unsigned items[10][3] = {
        {R_COAL,R_LAMP,R_MIRROR},{R_LENS,R_BONE,R_CORE},{R_FROST,R_ICE,R_MIRROR},
        {R_FEATHER,R_RIFT,R_QUIVER},{R_NEEDLE,R_STAR,R_QUIVER},{R_ANVIL,R_IRON,R_HEART},
        {R_BADGE,R_MIRROR,R_IRON},{R_EYE,R_NIGHT,R_DARK_HEART},
        {R_FORGE,R_ANVIL,R_IRON},{R_TWINS,R_QUIVER,R_CORE}};
    for (unsigned b = 0; b < 10; ++b) {
        setup(); ember_sim_character(&fixture, chars[b]);
        unsigned w = weapon(categories[b], elements[b]); equip(w);
        for (unsigned i = 0; i < 3; ++i) fixture.player.relic_level[items[b][i]] = 1;
        ember_sim_attributes(&fixture);
        fixture.player.inscription[w][0] = (uint8_t)(b == 0 ? 14 : b == 1 ? 11 :
            b == 3 ? 12 : b == 4 ? 4 : b == 8 ? 15 : b == 9 ? 17 : 0);
        if (b == 7) ember_sim_contract(&fixture, 0, 3);
        unsigned sub = weapon(b == 3 ? EMBER_GREATSWORD : EMBER_HAMMER,
            (b == 3 || b == 4) ? EMBER_DAMAGE_WATER : EMBER_DAMAGE_IRON);
        if (sub == w) sub = weapon(EMBER_SWORD, EMBER_DAMAGE_IRON);
        fixture.player.sub_weapon = (uint8_t)sub;
        fixture.player.weapon_level[sub] = 5;
        if (b == 1) fixture.player.inscription[w][1] = 5;
        if (b == 2) fixture.player.relic_level[R_FORGE] = 1;
        if (b == 3) fixture.player.relic_level[R_TIDE] = 1;
        if (b == 5) {
            fixture.player.relic_level[R_THORN] = 1;
            fixture.player.relic_level[R_LINING] = 1;
            fixture.player.relic_level[R_DARK_HEART] = 1;
            fixture.player.sub_weapon = (uint8_t)weapon(EMBER_BLADES, EMBER_DAMAGE_SHADOW);
            fixture.player.weapon_level[sub] = 0;
            fixture.player.weapon_level[fixture.player.sub_weapon] = 1;
        }
        if (b == 6) {
            fixture.player.inscription[w][0] = 18;
            ember_sim_pet(&fixture, 0, 10);
        }
        if (b == 7) {
            fixture.player.relic_level[R_BUCKLE] = 1;
            ember_sim_blessing(&fixture, 1);
        }
        if (b == 8) fixture.player.inscription[w][1] = 14;
        if (b == 9) fixture.player.inscription[sub][0] = 17;
        const unsigned resonance_ids[] = {255,255,4,255,5,8,7,255,1,255};
        if (resonance_ids[b] != 255) {
            CHECK(ember_sim_resonance_ready(&fixture, resonance_ids[b]));
            ember_sim_resonance(&fixture, resonance_ids[b]);
        }
        ember_sim_attributes(&fixture);
        if (branches[b]) {
            CHECK(ember_sim_evolution_ready(&fixture, w, branches[b]));
            ember_sim_evolve(&fixture, w, branches[b]);
        }
        target(25); target(60); grid_build(&fixture);
        if (b == 1 || b == 8)
            for (unsigned n = 0; n < 3; ++n) ember_sim_status(&fixture, 0, EMBER_IGNITE, 0);
        if (b == 3) {
            fixture.previous_input = EMBER_RIGHT;
            for (unsigned n = 0; n < 1440; ++n) {
                fixture.player.x += n & 1 ? -EMBER_Q : EMBER_Q;
                content_step(&fixture);
            }
        }
        if (b == 6) content_skill(&fixture, 0);
        if (b == 7) fixture.enemies[0].facing8 = EMBER_EAST;
        fixture.charge_frames = 30;
        weapon_fire(&fixture, w);
        for (unsigned f = 0; f < 30; ++f) shots_step(&fixture);
        CHECK(fixture.damage_total > 0);
        if (b == 0) CHECK(light_zone_at(&fixture, fixture.enemies[0].x, fixture.enemies[0].y));
        if (b == 1) CHECK(fixture.enemies[0].defense.status[EMBER_IGNITE].stacks <= 1);
        if (b == 2) {
            weapon_fire(&fixture, w); weapon_fire(&fixture, w);
            CHECK(fixture.enemies[0].defense.frozen);
            unsigned before = fixture.damage_total;
            weapon_fire(&fixture, sub);
            /* The breaker passive can immediately apply chill again after shattering. */
            CHECK(fixture.trigger_peak && fixture.damage_total > before);
        }
        if (b == 3) {
            unsigned supers = 0;
            for (unsigned n = 0; n < 16; ++n) enemy_hit(&fixture, 0, 10, w, 0, 0);
            for (unsigned n = 0; n < fixture.events.count; ++n)
                supers += fixture.events.item[n].tier == 2;
            CHECK(supers);
        }
        if (b == 5) {
            fixture.player.hp = fixture.player.max_hp;
            heal(&fixture, 10); CHECK(fixture.player.defense.temporary[6] == 10);
        }
        if (b == 6) CHECK(fixture.summons[0].life && player_in_light_zone(&fixture));
        if (b == 7) CHECK(!fixture.in_light && fixture.lamp_disabled && fixture.curses[0]);
        if (b == 9) {
            fixture.weapon_timer[w] = fixture.weapon_timer[sub] = 0;
            weapons_step(&fixture, EMBER_J);
            CHECK(fixture.weapon_timer[w] && fixture.weapon_timer[sub]);
        }
        printf("BUILD,%u,damage=%u\n", b, fixture.damage_total);
    }
}
static void interface_rules(void)
{
    const int x[8] = {0,1,1,1,0,-1,-1,-1};
    const int y[8] = {1,1,0,-1,-1,-1,0,1};
    for (unsigned d = 0; d < 8; ++d) {
        setup(); unsigned t = target(20);
        fixture.enemies[t].x = fixture.player.x + x[d] * 100 * EMBER_Q;
        fixture.enemies[t].y = fixture.player.y + y[d] * 100 * EMBER_Q;
        ember_sim_step(&fixture, EMBER_J);
        CHECK(fixture.player.facing8 == d);
        CHECK(fixture.player.facing_frame == (d < 5 ? d : 8 - d));
        CHECK(fixture.player.flip_x == (d >= 5));
    }
    setup(); struct ember_shot *p = shot(&fixture, 0, fixture.player.x,
        fixture.player.y, 10, 4, 10);
    p->vx = 0; p->vy = -EMBER_Q;
    shots_step(&fixture); CHECK(p->dir16 == 4);
    setup(); unsigned e = ember_sim_spawn(&fixture, 0, 3,
        fixture.player.x + 20 * EMBER_Q, fixture.player.y);
    struct ember_attack h = {.base=1000,.attack=100,.share={100,0,0,0,0,0}};
    ember_sim_hit(&fixture, e, &h);
    CHECK(fixture.alive_count == 3 && fixture.player.kills == 1);
    CHECK(!fixture.enemies[e].alive && !fixture.enemies[e].retiring);
    CHECK(fixture.pickup_count == 1);
}
static void dark_projectile_snapshot(void)
{
    for (unsigned dark = 0; dark < 2; ++dark) {
        setup(); unsigned e = target(dark ? 400 : 40);
        enemy_projectile(&fixture, &fixture.enemies[e], 0, 100, EMBER_DAMAGE_TRUE, 0);
        struct ember_shot *p = &fixture.shots[0];
        CHECK(p->enemy_increased == (dark ? 20 : 0));
        p->x = fixture.player.x; p->y = fixture.player.y; p->vx = p->vy = 0;
        p->damage = 10;
        fixture.lamp_disabled = !dark;
        int hp = fixture.player.hp;
        shots_step(&fixture);
        CHECK(hp - fixture.player.hp == (dark ? 12 : 10));
    }
    setup(); target(20); target(32); fixture.enemies[0].affix = 4;
    fixture.lamp_disabled = 1; grid_build(&fixture);
    struct ember_shot *reflected = shot(&fixture, 0, fixture.enemies[0].x,
        fixture.enemies[0].y, 100, 20, 10);
    reflected->weapon = 0;
    shots_step(&fixture);
    CHECK(reflected->alive && reflected->hostile && reflected->enemy_increased == 20);
    CHECK(fixture.enemies[1].hp == 100000 && fixture.damage_total == 0);
    reflected->homing = reflected->follow = reflected->pet = 1;
    reflected->x = fixture.player.x + 100 * EMBER_Q;
    reflected->vx = reflected->vy = 0;
    shots_step(&fixture);
    CHECK(reflected->alive && reflected->x == fixture.player.x + 100 * EMBER_Q);
    reflected->x = fixture.player.x; reflected->y = fixture.player.y;
    reflected->vx = reflected->vy = 0;
    fixture.lamp_disabled = 0;
    int hp_before = fixture.player.hp;
    shots_step(&fixture);
    CHECK(!reflected->alive && hp_before - fixture.player.hp == 100);
    setup(); CHECK(!player_in_light_zone(&fixture));
    CHECK(!enemy_in_dark(&fixture, fixture.player.x, fixture.player.y));
    fixture.pillars[0].x = fixture.player.x; fixture.pillars[0].y = fixture.player.y;
    fixture.pillars[0].lit = 1;
    CHECK(player_in_light_zone(&fixture));
    fixture.stealth = 60; CHECK(!player_in_light_zone(&fixture));
    setup(); target(40); grid_build(&fixture);
    weapon_fire(&fixture, 0); CHECK(fixture.player.action_ticks == 0);
    ++fixture.player.action_ticks; weapon_fire(&fixture, 0);
    CHECK(!fixture.player.action_ticks);
}
static void vulnerability_and_dots(void)
{
    setup(); target(20);
    fixture.enemies[0].defense.vulnerability = 10;
    fixture.enemies[0].hunter_mark = fixture.enemies[0].owl_mark = 120;
    struct ember_attack h = {.base=100,.attack=100,.increased=50,.share={0,100,0,0,0,0}};
    CHECK(ember_sim_hit(&fixture, 0, &h).damage == 232);
    CHECK(fixture.enemies[0].defense.vulnerability == 10);
    CHECK(ember_sim_hit(&fixture, 0, &h).damage == 232);
    struct ember_defense d; ember_defense_init(&d, 1000);
    int32_t hp = 1000;
    h = (struct ember_attack){.base=100,.attack=100,.share={50,50,0,0,0,0}};
    h.element_more[EMBER_DAMAGE_FIRE] = 25;
    struct ember_damage_result r = ember_damage(&fixture.combat_rng, &h, &d, &hp);
    CHECK(r.part[EMBER_DAMAGE_IRON] == 50 && r.part[EMBER_DAMAGE_FIRE] == 62);
    setup(); target(20); grid_build(&fixture);
    unsigned w = weapon(EMBER_CODEX, EMBER_DAMAGE_WATER); equip(w);
    fixture.attributes[EMBER_CRIT] = 100;
    weapon_fire(&fixture, w); fixture.events.count = 0; shots_step(&fixture);
    CHECK(fixture.events.item[0].damage_type == EMBER_DAMAGE_WATER);
    CHECK(!fixture.events.item[0].tier);
    fixture.dot_can_crit = 1; fixture.shots[0].tick = 0;
    fixture.events.count = 0; shots_step(&fixture);
    CHECK(fixture.events.item[0].tier == 1);
    setup(); target(20); ember_sim_pet(&fixture, 4, 7);
    fixture.attributes[EMBER_ATTACK] = 10000;
    struct ember_shot *ground = shot(&fixture, 2, fixture.player.x,
        fixture.player.y, 8, 60, 120);
    ground->effect = 10; ground_effect(&fixture, ground);
    CHECK(fixture.events.item[0].damage_type == EMBER_DAMAGE_FIRE);
    CHECK(fixture.events.item[0].value == 8);
}
static void skill_and_evolution_modifiers(void)
{
    unsigned damage[2];
    for (unsigned equipped = 0; equipped < 2; ++equipped) {
        setup(); target(20);
        if (equipped) fixture.player.relic_level[R_CORE] = 1;
        fixture.attributes[EMBER_CRIT] = 0;
        skill_hit(&fixture, 0, EMBER_DAMAGE_FIRE, 100, EMBER_STATUS_COUNT);
        damage[equipped] = fixture.damage_total;
    }
    CHECK(damage[0] == 100 && damage[1] == 125);
    for (unsigned equipped = 0; equipped < 2; ++equipped) {
        setup(); target(20); grid_build(&fixture);
        unsigned w = weapon(EMBER_STAFF, EMBER_DAMAGE_FIRE); equip(w);
        fixture.player.evolution[w] = 2;
        if (equipped) fixture.player.relic_level[R_LENS] = 1;
        CHECK((ember_sim_weapon_tags(&fixture, w) & TAG_SINGLE) &&
            !(ember_sim_weapon_tags(&fixture, w) & TAG_AREA));
        fixture.attributes[EMBER_CRIT] = 0;
        enemy_hit(&fixture, 0, 100, w, 0, 0);
        damage[equipped] = fixture.damage_total;
    }
    CHECK(damage[0] == 100 && damage[1] == 125);
}
static void inherited_area_tags(void)
{
    setup(); target(20); fixture.player.relic_level[R_LENS] = 1;
    inherited_area(&fixture, fixture.player.x, fixture.player.y, 100, 100, 0);
    CHECK(fixture.damage_total == 100);
    inherited_hit(&fixture, 0, 100, 0); CHECK(fixture.damage_total == 225);
    setup(); target(20); fixture.player.relic_level[R_MIRROR] = 1;
    inherited_area(&fixture, fixture.player.x, fixture.player.y, 100, 100, 0);
    CHECK(fixture.damage_total == 110);
}
static void target_lifetimes(void)
{
    setup(); target(20); target(40);
    struct ember_shot *p = shot(&fixture, 0, fixture.enemies[0].x,
        fixture.enemies[0].y, 10, 4, 10);
    p->weapon = 0; p->hit_bits[0] = 1;
    fixture.hourglass_seen[0] = 1; fixture.hourglass_count = 1;
    fixture.enemies[0].alive = 0; --fixture.alive_count;
    unsigned e = ember_sim_spawn(&fixture, 0, 0, p->x, p->y);
    CHECK(e == 0 && !fixture.hourglass_seen[0] && !(p->hit_bits[0] & 1));
    grid_build(&fixture); int hp = fixture.enemies[e].hp;
    shots_step(&fixture); CHECK(fixture.enemies[e].hp < hp);
    setup(); ember_sim_character(&fixture, 4); target(20); fixture.enemies[0].hp = 1;
    fixture.fuse_target = 0; fixture.fuse_stacks = 4;
    enemy_hit(&fixture, 0, 100, fixture.player.main_weapon, 0, 0);
    CHECK(fixture.fuse_target == -1 && !fixture.fuse_stacks);
}
static void healing_windows(void)
{
    setup(); target(20); fixture.player.hp = 100;
    fixture.player.relic_level[R_BELT] = 1;
    for (unsigned i = 0; i < 7; ++i)
        player_hit_effects(&fixture, 0, (struct ember_damage_result){.damage=1}, TAG_MELEE);
    CHECK(fixture.player.hp == 105);
    fixture.combat_frame = 59;
    player_hit_effects(&fixture, 0, (struct ember_damage_result){.damage=1}, TAG_MELEE);
    CHECK(fixture.player.hp == 105);
    fixture.combat_frame = 60;
    player_hit_effects(&fixture, 0, (struct ember_damage_result){.damage=1}, TAG_MELEE);
    CHECK(fixture.player.hp == 106);
    setup(); fixture.player.hp = 100; fixture.curses[3] = 1;
    heal(&fixture, 1); CHECK(fixture.player.hp == 100);
    heal(&fixture, 1); CHECK(fixture.player.hp == 101);
}
static void split_depth(void)
{
    for (unsigned bonus = 0; bonus < 2; ++bonus) {
        setup(); fixture.trigger_bonus = (uint8_t)bonus;
        unsigned w = weapon(EMBER_STAFF, EMBER_DAMAGE_FIRE); equip(w);
        fixture.player.inscription[w][0] = 7;
        for (unsigned i = 0; i < 5; ++i) target(20 + (int)i * 20);
        grid_build(&fixture); weapon_fire(&fixture, w);
        for (unsigned tick = 0; tick < 60; ++tick) shots_step(&fixture);
        CHECK(fixture.trigger_peak == 3 + bonus);
        for (unsigned i = 0; i < EMBER_SHOTS; ++i)
            CHECK(fixture.shots[i].depth <= 3 + bonus);
    }
}
static struct ember_sim twin;
static void determinism(void)
{
    for (unsigned c = 0; c < EMBER_CHARACTERS_COUNT; ++c) {
        setup(); ember_sim_character(&fixture, c); ember_sim_pet(&fixture, c % 6, 255);
        fixture.player.charge = 100;
        ember_sim_spawn(&fixture, 18 + c % 3, 0,
            fixture.player.x + 80 * EMBER_Q, fixture.player.y);
        target(20);
        twin = fixture;
        for (unsigned f = 0; f < 180; ++f) {
            uint16_t input = (f % 45 < 30 ? EMBER_J : 0) |
                (f < 90 ? EMBER_RIGHT : EMBER_DOWN);
            if (!f) input |= EMBER_K | EMBER_U;
            if (f == 30) input |= EMBER_L;
            ember_sim_step(&fixture, input); ember_sim_step(&twin, input);
            CHECK(!memcmp(&fixture, &twin, sizeof(fixture)));
        }
    }
    puts("DETERMINISM,8 characters,180 ticks each,raw state equal");
}
int main(void)
{
    weapons(); evolutions(); relics(); relic_rules(); inscriptions(); characters(); pets(); pet_runes();
    enemies(); class_shapes(); entity_rules(); blessings(); resonances(); contracts(); builds(); interface_rules(); dark_projectile_snapshot(); vulnerability_and_dots(); skill_and_evolution_modifiers(); inherited_area_tags(); target_lifetimes(); healing_windows(); split_depth(); determinism();
    printf("PASS E4 assertions=%u\n", assertions);
    return 0;
}
