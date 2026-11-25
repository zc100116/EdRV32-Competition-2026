/* File: e5a_content_test.c; GDD 5/6, tech 3/6: E5a directed behavior verification.
 * Description: Real inventory, resources, panels, routes, clues, terrain, meta and saves.
 * Clock domain: deterministic directed 60 Hz tests; not normal-run victory evidence.
 */
#include "sim/sim.c"
#include <assert.h>
static struct ember_sim fixture, twin;
static struct ember_meta profile, loaded;
static void setup(unsigned mode)
{
    struct ember_run_config c;
    ember_run_config_default(&c);
    c.mode = (uint8_t)mode;
    ember_sim_begin(&fixture, 17, &c);
    ember_sim_step(&fixture, EMBER_START);
    fixture.rest = 100000;
    fixture.events.count = 0;
}
static void meta_test(void)
{
    ember_meta_init(&profile);
    assert(profile.characters == 43 && profile.unlocked[0] == 1);
    profile.fragments = 1000;
    assert(!ember_meta_unlock_character(&profile, 2));
    profile.bosses |= 1u << 18;
    assert(ember_meta_unlock_character(&profile, 2));
    unsigned balance = profile.fragments;
    assert(ember_meta_unlock_character(&profile, 2) && profile.fragments == balance);
    assert(!ember_meta_unlock_talent(&profile, 0, 4));
    assert(ember_meta_unlock_talent(&profile, 0, 2));
    assert(ember_meta_unlock_talent(&profile, 0, 3));
    assert(ember_meta_unlock_talent(&profile, 0, 4));
    assert(ember_meta_unlock_talent(&profile, 0, 5));
    assert(ember_meta_unlock_talent(&profile, 0, 7));
    balance = profile.fragments;
    assert(ember_meta_select_talent(&profile, 0, 3));
    assert(ember_meta_select_talent(&profile, 0, 5));
    assert(profile.fragments == balance);
    struct ember_run_config c;
    ember_meta_config(&profile, 0, 255, 0, &c);
    ember_sim_begin(&fixture, 1, &c);
    assert(fixture.player.max_hp == 260 && fixture.player.defense.permanent_shield == 20);
    assert(fixture.oil == 8000 && !fixture.gold && fixture.player.sub_weapon == 255);
    ember_sim_step(&fixture, EMBER_START);
    ember_sim_step(&fixture, EMBER_K);
    assert(fixture.player.cooldown_k == 216);
    assert(ember_meta_select_talent(&profile, 0, 2));
    assert(ember_meta_select_talent(&profile, 0, 4));
    ember_meta_config(&profile, 0, 255, 0, &c);
    ember_sim_begin(&fixture, 1, &c);
    assert(fixture.player.max_hp == 299 && fixture.gold == 40);
    profile.codex.enemies[18] = profile.codex.weapons[0] = profile.codex.pets[0] = 1;
    profile.codex.world[2] = 1;
    ember_meta_save(&profile, "build/ember_isles/e5a-save.txt");
    ember_meta_load(&loaded, "build/ember_isles/e5a-save.txt");
    assert(!memcmp(&profile, &loaded, sizeof(profile)));
    ember_sim_begin(&fixture, 3, &c);
    loaded.fragments = 0;
    memset(loaded.unlocked, 0, sizeof(loaded.unlocked));
    ember_sim_begin(&twin, 3, &c);
    for (unsigned i = 0; i < 600; ++i) {
        uint16_t input = i == 0 ? EMBER_START : EMBER_RIGHT | EMBER_J;
        ember_sim_step(&fixture, input); ember_sim_step(&twin, input);
        assert(!memcmp(&fixture, &twin, sizeof(fixture)));
    }
    ember_meta_init(&loaded);
    loaded.fragments = 1000;
    loaded.bosses = (1u << 18) | (1u << 19);
    loaded.hidden_rooms = 3; loaded.arena_pillars = 50;
    const unsigned weapon_b[8] = {1,9,13,33,32,44,16,24};
    for (unsigned character = 0; character < 8; ++character) {
        assert(ember_meta_unlock_character(&loaded, character));
        assert(ember_meta_unlock_talent(&loaded, character, 1));
        balance = loaded.fragments;
        assert(ember_meta_select_talent(&loaded, character, 1));
        ember_meta_config(&loaded, character, 255, 0, &c);
        ember_sim_begin(&fixture, 1, &c);
        assert(fixture.player.main_weapon == weapon_b[character]);
        assert(fixture.player.weapon_level[weapon_b[character]] == 1);
        assert(fixture.player.sub_weapon == 255 && loaded.fragments == balance);
        assert(ember_meta_select_talent(&loaded, character, 0));
        ember_meta_config(&loaded, character, 255, 0, &c);
        ember_sim_begin(&fixture, 1, &c);
        assert(fixture.player.main_weapon == ember_characters[character].initial_weapon);
    }
    assert(ember_meta_unlock_talent(&loaded, 1, 2));
    assert(ember_meta_unlock_talent(&loaded, 1, 4));
    assert(ember_meta_unlock_talent(&loaded, 1, 6));
    ember_meta_config(&loaded, 1, 255, 0, &c);
    ember_sim_begin(&fixture, 1, &c);
    player_hurt_resolved(&fixture, 100, 1, fixture.player.x, fixture.player.y,
        EMBER_DAMAGE_TRUE, 0, 0, 1);
    assert(fixture.player.defense.temporary[6] == 25);
    puts("PASS meta: four initial characters, achievement+currency, prerequisites, "
        "free selection,");
    puts("  exact talent effects, real save roundtrip and replay/profile isolation");
}
static void inventory_test(void)
{
    setup(EMBER_ROUTE);
    fixture.player.sub_weapon = 1; fixture.player.weapon_level[1] = 1;
    fixture.player.weapon_level[0] = 5; fixture.player.evolution[0] = 2;
    fixture.player.inscription[0][0] = 2; fixture.player.inscription[0][1] = 7;
    item_receive(&fixture, (struct ember_choice){EMBER_ITEM_WEAPON, 2, 255});
    assert(fixture.panel == EMBER_PANEL_REPLACE && fixture.option_count == 2);
    panel_step(&fixture, EMBER_J);
    assert(fixture.player.main_weapon == 2 && fixture.ground[0].alive);
    assert(fixture.ground[0].level == 5 && fixture.ground[0].evolution == 2);
    assert(fixture.ground[0].inscription[0] == 2 && fixture.ground[0].inscription[1] == 7);
    assert(inventory_owned(&fixture, EMBER_ITEM_WEAPON, 0));
    pending_reset(&fixture); fixture.pending_ground = 0;
    item_receive(&fixture, (struct ember_choice){EMBER_ITEM_WEAPON, 0, 255});
    panel_step(&fixture, EMBER_J);
    assert(fixture.player.main_weapon == 0 && fixture.player.weapon_level[0] == 5);
    assert(fixture.player.evolution[0] == 2 && fixture.player.inscription[0][1] == 7);
    assert(inventory_owned(&fixture, EMBER_ITEM_WEAPON, 2));
    stage_exit(&fixture);
    assert(!inventory_owned(&fixture, EMBER_ITEM_WEAPON, 2));
    assert(fixture.player.weapon_level[0] == 5 && fixture.config.stage == 1);
    fixture.gold = 100;
    for (unsigned i = 0; i < 6; ++i) fixture.player.relic_level[i] = 1;
    item_receive(&fixture, (struct ember_choice){EMBER_ITEM_RELIC, 19, 255});
    assert(fixture.option_count == 6);
    panel_step(&fixture, EMBER_J);
    assert(fixture.gold == 107 && !fixture.player.relic_level[0] && fixture.player.relic_level[19]);
    unsigned gold = fixture.gold;
    item_receive(&fixture, (struct ember_choice){EMBER_ITEM_INSCRIPTION, 16, 0});
    panel_step(&fixture, EMBER_J);
    assert(fixture.player.inscription[0][0] == 17 && fixture.gold == gold);
    assert(inventory_owned(&fixture, EMBER_ITEM_INSCRIPTION, 16));
    ember_sim_pet(&fixture, 0, 0); fixture.pet_level = 4;
    fixture.player.pet_weapon_level[0] = 3; fixture.player.pet_inscription[0] = 1;
    item_receive(&fixture, (struct ember_choice){EMBER_ITEM_PET_WEAPON, 1, 255});
    panel_step(&fixture, EMBER_J);
    assert(fixture.player.pet_weapon == 1 && fixture.pet_level == 4);
    unsigned ground = 0;
    for (unsigned i = 0; i < 62; ++i)
        if (fixture.ground[i].alive && fixture.ground[i].kind == EMBER_ITEM_PET_WEAPON) {
            assert(fixture.ground[i].id == 0 && fixture.ground[i].level == 3 &&
                fixture.ground[i].inscription[0] == 1); ++ground;
        }
    assert(ground == 1);
    item_receive(&fixture, (struct ember_choice){EMBER_ITEM_WEAPON, 3, 255});
    panel_step(&fixture, EMBER_INTERACT);
    assert(fixture.player.main_weapon == 0 && !fixture.player.weapon_level[3]);
    setup(EMBER_ROUTE);
    ember_sim_pet(&fixture, 0, 255);
    fixture.events.count = 0;
    fixture.choices[0] = (struct ember_choice){EMBER_ITEM_PET_WEAPON, 0, 255};
    fixture.selected = 0;
    upgrade_choose(&fixture);
    unsigned acquired = 0, changed = 0;
    for (unsigned i = 0; i < fixture.events.count; ++i) {
        acquired += fixture.events.item[i].kind == EMBER_EVENT_PICKUP;
        changed += fixture.events.item[i].kind == EMBER_EVENT_WEAPON_CHANGE;
    }
    assert(acquired == 1 && changed == 1 && fixture.player.pet_weapon == 0);
    puts("PASS inventory: global IDs, both weapon slots, pet weapons, dropped state,");
    puts("  stage cleanup, relic 25% refund, rune no-refund and abandon");
}
static void economy_test(void)
{
    setup(EMBER_ROUTE);
    drop_resource(&fixture, EMBER_DROP_XP, 0, 0, 7, 0, 0);
    drop_resource(&fixture, EMBER_DROP_XP, 0, 0, 11, 0, 0);
    drop_resource(&fixture, EMBER_DROP_GOLD, 0, 0, 9, 0, 0);
    pickups_step(&fixture, 2);
    assert(fixture.player.xp == 18 && fixture.gold == 9 && fixture.pickup_count == 0);
    assert(fixture.events.count == 2 && fixture.events.item[0].value == 18);
    fixture.events.count = 0; fixture.oil = 0;
    drop_resource(&fixture, EMBER_DROP_EMBER, 0, 0, 2, fixture.player.x, fixture.player.y);
    pickups_step(&fixture, 0);
    assert(fixture.oil == 600 && fixture.player.charge == 4);
    fixture.gold = 20;
    shop_stock(&fixture); shop_open(&fixture);
    fixture.panel_selected = fixture.option_count - 1;
    panel_step(&fixture, EMBER_J);
    assert(fixture.gold == 0 && fixture.shop_refreshes == 1);
    fixture.panel_selected = fixture.option_count - 1;
    struct ember_rng rng = fixture.loot_rng;
    panel_step(&fixture, EMBER_J);
    assert(fixture.transaction_result == 1 && fixture.loot_rng.state == rng.state);
    unsigned frame = fixture.combat_frame, stage_frame = fixture.stage_frame;
    struct ember_rng combat = fixture.combat_rng, spawn = fixture.spawn_rng, map = fixture.map_rng;
    ember_sim_step(&fixture, 0); ember_sim_step(&fixture, EMBER_DOWN); ember_sim_step(&fixture, 0);
    assert(fixture.combat_frame == frame && fixture.stage_frame == stage_frame);
    assert(fixture.loot_rng.state == rng.state && fixture.combat_rng.state == combat.state &&
        fixture.spawn_rng.state == spawn.state && fixture.map_rng.state == map.state);
    ember_sim_step(&fixture, EMBER_SELECT);
    assert(!fixture.panel && !fixture.paused);
    fixture.player.sub_weapon = 3; fixture.player.weapon_level[3] = 1;
    fixture.player.relic_level[19] = fixture.player.relic_level[15] = 1;
    assert(ember_sim_resonance_ready(&fixture, 0));
    fixture.guaranteed_resonance = 1; fixture.altars_available = 2;
    altar_open(&fixture);
    for (unsigned i = 0; i < 3; ++i) assert(fixture.options[i].kind == EMBER_ITEM_RESONANCE);
    panel_step(&fixture, EMBER_J);
    fixture.guaranteed_resonance = 1; altar_open(&fixture); panel_step(&fixture, EMBER_J);
    assert(!ember_sim_contract_reward_available(&fixture, 2));
    ember_sim_contract(&fixture, 0, 1);
    stage_exit(&fixture);
    assert(fixture.curses[0]);
    fixture.cleanse_tokens = 1;
    cleanse_open(&fixture); panel_step(&fixture, EMBER_J);
    assert(!fixture.curses[0] && !fixture.cleanse_tokens);
    puts("PASS economy: XP/gold/embers, aggregated events, refresh prices, pause/RNG,");
    puts("  two-resonance limit, contract persistence and rare cleansing");
}
static void modes_test(void)
{
    setup(EMBER_ROUTE);
    shot(&fixture, 0, fixture.player.x, fixture.player.y, 10, 4, 100);
    struct ember_shot *hostile = shot(&fixture, 0,
        fixture.player.x, fixture.player.y, 10, 4, 100);
    hostile->hostile = 1;
    modes_cleared(&fixture);
    assert(fixture.room_cleared && !fixture.shot_count);
    for (unsigned i = 0; i < EMBER_SHOTS; ++i) assert(!fixture.shots[i].alive);
    setup(EMBER_ROUTE);
    fixture.rest = 0; fixture.room_cleared = 1;
    fixture.player.x = fixture.lighthouse.x; fixture.player.y = fixture.lighthouse.y;
    assert(modes_interact(&fixture) && fixture.room_lit);
    fixture.island = 2; fixture.room_kind = EMBER_ROOM_MAIN;
    fixture.door_rewards[2][2] = EMBER_REWARD_SIDE;
    fixture.player.x = fixture.doors[2].x; fixture.player.y = fixture.doors[2].y;
    assert(modes_interact(&fixture) && fixture.room_kind == EMBER_ROOM_SIDE && fixture.island == 2);
    unsigned length = fixture.side_left;
    assert(length >= 1 && length <= 2);
    for (unsigned i = 0; i < length; ++i) {
        fixture.room_cleared = fixture.room_lit = 1;
        fixture.player.x = fixture.doors[0].x; fixture.player.y = fixture.doors[0].y;
        assert(modes_interact(&fixture));
    }
    assert(fixture.room_kind == EMBER_ROOM_MAIN && fixture.island == 3);
    for (unsigned clue = 0; clue < 3; ++clue) {
        setup(EMBER_ROUTE); fixture.rest = 100000;
        fixture.hidden_count = 1; fixture.hidden[0].island = 0;
        fixture.hidden[0].clue = (uint8_t)clue;
        fixture.hidden[0].point = (struct ember_point){fixture.player.x,fixture.player.y};
        fixture.hidden[0].found = fixture.hidden[0].visited = 0;
        world_setup(&fixture); room_rocks(&fixture);
        if (clue == 2) ember_sim_pet(&fixture, 0, 255);
        for (unsigned i = 0; i < 200 && !fixture.hidden[0].found; ++i)
            ember_sim_step(&fixture, clue ? 0 : EMBER_J);
        assert(fixture.hidden[0].found);
        fixture.room_cleared = 0;
        fixture.player.x = fixture.hidden[0].point.x;
        fixture.player.y = fixture.hidden[0].point.y;
        modes_interact(&fixture);
        assert(fixture.room_kind == EMBER_ROOM_MAIN);
        fixture.room_cleared = 1;
        fixture.player.x = fixture.hidden[0].point.x; fixture.player.y = fixture.hidden[0].point.y;
        assert(modes_interact(&fixture) && fixture.room_kind == EMBER_ROOM_HIDDEN);
        assert(fixture.panel == EMBER_PANEL_HIDDEN && fixture.hidden_rooms == 1);
        fixture.panel_selected = fixture.option_count - 1;
        panel_step(&fixture, EMBER_J);
        assert(fixture.discoveries.world[clue]);
        unsigned clock = fixture.combat_frame, stage_clock = fixture.stage_frame;
        unsigned wave = fixture.wave;
        int oil = fixture.oil, hp = fixture.player.hp;
        fixture.player.cooldown_k = 100;
        for (unsigned i = 0; i < 60; ++i) ember_sim_step(&fixture, EMBER_RIGHT);
        assert(fixture.combat_frame == clock + 60 && fixture.stage_frame == stage_clock + 60);
        assert(fixture.wave == wave && !fixture.alive_count && !fixture.queued_spawns);
        assert(fixture.oil < oil && fixture.player.cooldown_k == 40);
        assert(fixture.player.hp >= hp && !fixture.hazard_phase);
        fixture.player.x = fixture.hidden_exit.x; fixture.player.y = fixture.hidden_exit.y;
        assert(modes_interact(&fixture) && fixture.room_kind == EMBER_ROOM_MAIN);
        unsigned found = fixture.hidden_rooms;
        modes_interact(&fixture);
        assert(fixture.hidden_rooms == found);
    }
    setup(EMBER_ARENA);
    fixture.wave = 10; fixture.exit = (struct ember_point){fixture.player.x,fixture.player.y};
    fixture.wave_scheduled[9] = (uint16_t)ember_waves[9].count;
    arena_milestones(&fixture);
    modes_cleared(&fixture);
    assert(fixture.stage_clear && !fixture.shop_available);
    unsigned clock = fixture.stage_frame;
    fixture.combat_frame = 60;
    fixture.player.hp -= 100;
    int hp = fixture.player.hp;
    for (unsigned i = 0; i < 120; ++i) ember_sim_step(&fixture, 0);
    assert(fixture.player.hp == hp + 2 && fixture.stage_frame == clock);
    ember_sim_step(&fixture, EMBER_RIGHT);
    assert(fixture.stage_frame == clock);
    fixture.player.x = fixture.exit.x; fixture.player.y = fixture.exit.y;
    assert(modes_interact(&fixture) && fixture.phase == EMBER_WON &&
        fixture.config.stage == 0 && fixture.wave == 10);
    puts("PASS modes: branch adds 1-2 islands, forward return, lighthouse/bridges,");
    puts("  all three clues, hidden reward/one visit, boss rest and real coast exit");
}
static void terrain_and_species_test(void)
{
    for (unsigned stage = 0; stage < 3; ++stage) {
        struct ember_run_config c; ember_run_config_default(&c); c.stage = (uint8_t)stage;
        ember_sim_begin(&fixture, 1, &c); ember_sim_step(&fixture, EMBER_START);
        fixture.rest = 100000;
        fixture.player.x = stage ? fixture.world_width / 2 : 100 * EMBER_Q;
        fixture.player.y = fixture.world_height / 2;
        fixture.hazard_point = (struct ember_point){fixture.player.x,fixture.player.y};
        unsigned e = ember_sim_spawn(&fixture, stage ? 5 : 0, 0,
            fixture.player.x + 40 * EMBER_Q, fixture.player.y);
        fixture.stage_frame = (unsigned)ember_hazards[stage].warning - 1;
        int hp = fixture.player.hp, enemy_hp = fixture.enemies[e].hp;
        if (!stage) fixture.enemies[e].burn = 100;
        ember_sim_step(&fixture, 0);
        assert(fixture.hazard_phase == 2);
        if (!stage) assert(fixture.player.hp == hp && !fixture.enemies[e].burn &&
            ember_slow_percent(&fixture.player.defense) > 0);
        else {
            assert(fixture.player.hp < hp && fixture.enemies[e].hp < enemy_hp);
            if (stage == 1) assert(fixture.player.defense.status[EMBER_BLIND].frames &&
                fixture.enemies[e].defense.status[EMBER_BLIND].frames);
        }
    }
    setup(EMBER_ROUTE);
    ember_sim_spawn(&fixture, 0, 0, 0, 0);
    unsigned charger = ember_sim_spawn(&fixture, 1, 0, 0, 0);
    ember_sim_spawn(&fixture, 2, 0, 0, 0);
    fixture.spawn_queue[0].kind = 3; fixture.spawn_queue[0].wave = 1; fixture.queued_spawns = 1;
    queued_spawn_step(&fixture); assert(fixture.queued_spawns == 1);
    struct ember_attack hit = {.base=100000,.attack=100,.crit_damage=150,.share={100,0,0,0,0,0}};
    ember_sim_hit(&fixture, charger, &hit);
    queued_spawn_step(&fixture);
    assert(!fixture.queued_spawns && fixture.ordinary_count[3] == 1);
    unsigned elite = ember_sim_spawn(&fixture, 4, 3, 0, 0);
    ember_sim_hit(&fixture, elite, &hit);
    assert(fixture.queued_spawns == 3 && !fixture.ordinary_count[4]);
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
        if (fixture.enemies[i].alive && fixture.enemies[i].kind == 3)
            ember_sim_hit(&fixture, i, &hit);
    queued_spawn_step(&fixture);
    assert(!fixture.queued_spawns && fixture.ordinary_count[4] == 3);
    puts("PASS terrain: flood extinguish/slow, fog damage/blind, "
        "warned rock damage to both sides;");
    puts("  overlapping-wave and split queues retain species<=3, medium<=2");
}
static void difficulty_and_progress_test(void)
{
    struct ember_run_config c;
    ember_run_config_default(&c); c.difficulty = 8;
    ember_sim_begin(&fixture, 13, &c); ember_sim_step(&fixture, EMBER_START);
    fixture.rest = 100000;
    unsigned ordinary = ember_sim_spawn(&fixture, 0, 0, 0, 0);
    assert(fixture.enemies[ordinary].hp == 36 && !fixture.enemies[ordinary].defense.rank);
    assert(enemy_speed(&fixture, &fixture.enemies[ordinary]) == 71);
    unsigned elite = ember_sim_spawn(&fixture, 0, 1, 0, 0);
    assert(fixture.enemies[elite].second_affix == 2 && fixture.enemies[elite].defense.rank == 1);
    unsigned head = ember_sim_spawn(&fixture, 15, 0, 0, 0);
    assert(fixture.enemies[head].hp == 2160 && fixture.enemies[head].defense.temporary[6] == 432);
    assert(ember_sim_price(&fixture, 100) == 125);
    fixture.oil = 5000;
    for (unsigned i = 0; i < 60; ++i) ember_sim_step(&fixture, 0);
    assert(fixture.oil == 4850);
    int hp = fixture.player.hp;
    player_hurt_resolved(&fixture, 100, 1, fixture.player.x, fixture.player.y,
        EMBER_DAMAGE_IRON, 0, 0, 1);
    int enemy_damage = hp - fixture.player.hp;
    c.difficulty = 0; ember_sim_begin(&twin, 13, &c);
    hp = twin.player.hp;
    player_hurt_resolved(&twin, 100, 1, twin.player.x, twin.player.y,
        EMBER_DAMAGE_IRON, 0, 0, 1);
    assert(enemy_damage > hp - twin.player.hp);
    unsigned doubled = 0;
    for (unsigned seed = 1; seed <= 100 && !doubled; ++seed) {
        c.difficulty = 0; ember_sim_begin(&fixture, seed, &c);
        c.difficulty = 4; ember_sim_begin(&twin, seed, &c);
        fixture.wave = twin.wave = 1;
        enemy_spawn(&fixture); enemy_spawn(&twin);
        doubled = !fixture.enemies[0].affix && twin.enemies[0].affix;
    }
    assert(doubled);
    ember_meta_init(&profile); profile.fragments = 1000;
    setup(EMBER_ROUTE);
    fixture.hidden_rooms = 2; ember_meta_commit(&profile, &fixture);
    assert(!ember_meta_character_ready(&profile, 6));
    fixture.hidden_rooms = 1; ember_meta_commit(&profile, &fixture);
    assert(ember_meta_character_ready(&profile, 6));
    setup(EMBER_ARENA);
    fixture.pillars_lit = 49; ember_meta_commit(&profile, &fixture);
    assert(!ember_meta_character_ready(&profile, 7));
    fixture.pillars_lit = 1; ember_meta_commit(&profile, &fixture);
    assert(ember_meta_character_ready(&profile, 7));
    fixture.bosses_defeated = 1u << 19; fixture.boss_kills = 1;
    ember_meta_commit(&profile, &fixture);
    assert(ember_meta_character_ready(&profile, 4));
    fixture.phase = EMBER_WON; fixture.config.difficulty = 0;
    ember_meta_commit(&profile, &fixture); assert(profile.difficulty == 1);
    ember_meta_commit(&profile, &fixture); assert(profile.difficulty == 1);
    fixture.config.difficulty = 1;
    ember_meta_commit(&profile, &fixture); assert(profile.difficulty == 2);
    puts("PASS global difficulty: movement, HP, damage, elite chance, oil, extra affix,");
    puts("  prices, guardian shield; unlock progress and highest-tier completion");
}
int main(void)
{
    meta_test(); inventory_test(); economy_test(); modes_test(); terrain_and_species_test();
    difficulty_and_progress_test();
    return 0;
}
