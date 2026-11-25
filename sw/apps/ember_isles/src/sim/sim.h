/* File: sim.h
 * Spec: ember_isles tech 2-3; gdd 2-5 and E3 systems.
 * Description: Read-only presentation contract for the deterministic combat state.
 * Clock domain: fixed 60 Hz simulation.
 */
#ifndef EMBER_SIM_H
#define EMBER_SIM_H
#include "core/core.h"
#include "combat.h"
#include "meta/meta.h"
/* Presentation contract frozen for ART-3:
 * facing8: 0 down, 1 down-right, 2 right, 3 up-right, 4 up, 5 up-left,
 * 6 left, 7 down-left. Moving uses movement; attacking/charging uses aim.
 * facing_frame indexes five drawn frames [down, down-right, right, up-right, up];
 * flip_x mirrors the three left directions. E3 facing is derived from facing8.
 * Shot dir16: 0 right, counterclockwise in screen space in steps of 22.5 degrees.
 */
enum ember_direction { EMBER_SOUTH, EMBER_SOUTHEAST, EMBER_EAST, EMBER_NORTHEAST,
    EMBER_NORTH, EMBER_NORTHWEST, EMBER_WEST, EMBER_SOUTHWEST };
enum ember_phase { EMBER_MENU, EMBER_PLAY, EMBER_UPGRADE, EMBER_WON, EMBER_LOST };
enum ember_enemy_presentation_action {
    EMBER_ENEMY_IDLE, EMBER_ENEMY_WALK, EMBER_ENEMY_HIT, EMBER_ENEMY_DEATH,
    EMBER_ENEMY_ATTACK, EMBER_ENEMY_SUMMON, EMBER_ENEMY_SHIELD,
    EMBER_ENEMY_TIDE_SWEEP_COLUMN, EMBER_ENEMY_TIDE_EBB,
    EMBER_ENEMY_TIDE_VORTEX, EMBER_ENEMY_TIDE_BLACKTIDE
};
struct ember_enemy {
    ember_fixed x, y, vx, vy;
    int32_t hp, shield;
    uint16_t burn, timer, flash;
    uint8_t alive, kind, affix, mode, retiring;
    uint8_t burn_weapon, burn_pet;
    uint16_t marked, hunter_mark, owl_mark, taunted, attacking, facing_lock;
    uint32_t ai_timer;
    uint32_t action_ticks;
    uint8_t presentation_action; /* Read-only action clock; no combat timing effects. */
    uint8_t stage, facing, second_affix, capturable, real_shadow, illusion, extra_affixes;
    uint8_t facing8, facing_frame, flip_x, in_dark;
    uint16_t burn_tick, burn_fraction;
    uint32_t wave;
    struct ember_defense defense;
};
struct ember_shot {
    ember_fixed x, y, vx, vy, z, vz, previous_x, previous_y;
    uint8_t dir16, effect, damage_type, hit_flags, returning, depth, homing, repeat_slot, dot_type;
    uint32_t hit_bits[(EMBER_ENEMIES + 31) / 32];
    int32_t damage, initial_damage, enemy_increased, speed;
    uint16_t passed;
    uint16_t life, radius, tick, trigger_radius, delay;
    uint8_t alive, kind, hostile, pierce;
    uint8_t weapon, follow, pet, enemy_kind, room;
    int16_t last_hit;
    ember_fixed origin_x, origin_y;
};
struct ember_player {
    ember_fixed x, y;
    int32_t hp, max_hp, armor, speed;
    uint32_t xp, next_xp, level, kills;
    uint16_t cooldown_a, cooldown_b, charge, dash, invulnerable, flash;
    uint8_t dash_charges;
    uint8_t facing, character, facing8, facing_frame, flip_x;
    uint8_t main_weapon, sub_weapon, pet_weapon, action, action_frame, combo;
    uint8_t cast_skill; /* Frozen at action start: 0 K, 1 L, 2 U; presentation only. */
    uint16_t action_time, pet_timer, cooldown_k;
    /* Simulation ticks since this action began. Reset to zero on each attack,
     * cast, hurt, dash and interaction, including consecutive same-kind actions.
     * Presentation chooses its animation frame from action_ticks, not global time.
     */
    uint32_t action_ticks;
    int16_t hand_x, hand_y;
    struct ember_defense defense;
    uint8_t weapon_level[50], relic_level[38], inscription[50][2], evolution[50];
    uint8_t pet_inscription[12], pet_weapon_level[12];
};
/* IDs are zero-based CSV row indices; inscriptions store one plus that index.
 * Choice kind: 0 weapon, 1 relic, 2 inscription, 3 evolution, 4 pet upgrade,
 * 5 resource filler (GDD 6); slot is the target weapon index for runes/evolution.
 * Shot kind: 0 bolt, 1 ring, 2 ground, 3 pot, 4 seed, 5 burst, 6 hostile.
 * Affix: 0 none, 1 haste, 2 ward. Facing: 0 right, 1 down, 2 left, 3 up.
 */
#define EMBER_OBSTACLES 32
#define EMBER_PICKUPS (3 * EMBER_ENEMIES + 62)
#define EMBER_GRID_COLUMNS 120
#define EMBER_GRID_ROWS 68
struct ember_obstacle { ember_fixed x, y; uint16_t radius; };
struct ember_choice { uint8_t kind, id, slot; };
enum ember_drop_kind { EMBER_DROP_XP, EMBER_DROP_RELIC, EMBER_DROP_GOLD, EMBER_DROP_EMBER,
    EMBER_DROP_WEAPON, EMBER_DROP_PET_WEAPON, EMBER_DROP_INSCRIPTION, EMBER_DROP_WORLD,
    EMBER_DROP_CLEANSE };
struct ember_pickup { ember_fixed x, y; uint32_t xp; uint8_t alive, kind, id, slot, room; };
enum ember_attribute {
    EMBER_MAX_HP, EMBER_ARMOR, EMBER_SPEED, EMBER_ATTACK, EMBER_ATTACK_SPEED,
    EMBER_CRIT, EMBER_CRIT_DAMAGE, EMBER_AREA, EMBER_PROJECTILES,
    EMBER_PROJECTILE_SPEED, EMBER_DURATION, EMBER_COOLDOWN, EMBER_PIERCE,
    EMBER_KNOCKBACK, EMBER_REGEN, EMBER_DODGE, EMBER_SHIELD, EMBER_TENACITY,
    EMBER_DASH_COUNT, EMBER_DASH_COOLDOWN, EMBER_STATUS_CHANCE,
    EMBER_STATUS_STRENGTH, EMBER_STATUS_DURATION, EMBER_PICKUP, EMBER_XP,
    EMBER_GOLD, EMBER_LUCK, EMBER_HEALING, EMBER_AURA, EMBER_THREAT,
    EMBER_EMBER_DAMAGE, EMBER_TIDE_DAMAGE, EMBER_IRON_DAMAGE, EMBER_STAR_DAMAGE,
    EMBER_SHADOW_DAMAGE, EMBER_LAMP_RADIUS, EMBER_FUEL_EFFICIENCY,
    EMBER_LIGHT_EFFECT, EMBER_FIRE_RESIST, EMBER_TIDE_RESIST, EMBER_STAR_RESIST,
    EMBER_SHADOW_RESIST, EMBER_ALL_RESIST, EMBER_REDUCTION, EMBER_ATTRIBUTE_COUNT
};
enum ember_item_kind { EMBER_ITEM_WEAPON, EMBER_ITEM_RELIC, EMBER_ITEM_INSCRIPTION,
    EMBER_ITEM_EVOLUTION, EMBER_ITEM_PET_LEVEL, EMBER_ITEM_RESOURCE, EMBER_ITEM_PET_WEAPON,
    EMBER_ITEM_PET_WEAPON_LEVEL, EMBER_ITEM_BLESSING, EMBER_ITEM_RESONANCE,
    EMBER_ITEM_GOLD, EMBER_ITEM_WORLD, EMBER_ITEM_PET, EMBER_ITEM_CLEANSE,
    EMBER_ITEM_REFRESH, EMBER_ITEM_CURSE, EMBER_ITEM_CONTRACT, EMBER_ITEM_CAP };
enum ember_panel { EMBER_PANEL_NONE, EMBER_PANEL_SHOP, EMBER_PANEL_ALTAR,
    EMBER_PANEL_CURSE, EMBER_PANEL_REWARD, EMBER_PANEL_CAP, EMBER_PANEL_REPLACE,
    EMBER_PANEL_HIDDEN, EMBER_PANEL_CLEANSE };
enum ember_room_reward { EMBER_REWARD_WEAPON, EMBER_REWARD_RELIC, EMBER_REWARD_ALTAR,
    EMBER_REWARD_GOLD, EMBER_REWARD_PET, EMBER_REWARD_SHOP, EMBER_REWARD_RIFT,
    EMBER_REWARD_SIDE, EMBER_REWARD_LEGENDARY, EMBER_REWARD_WORLD, EMBER_REWARD_NONE = 255 };
enum ember_room_kind { EMBER_ROOM_MAIN, EMBER_ROOM_SIDE, EMBER_ROOM_HIDDEN };
struct ember_point { ember_fixed x, y; };
struct ember_ground_weapon {
    ember_fixed x, y;
    uint8_t alive, kind, id, level, evolution, inscription[2], room;
};
struct ember_sim {
    enum ember_phase phase;
    struct ember_run_config config;
    struct ember_codex discoveries;
    uint32_t boss_kills, bosses_defeated, hidden_rooms, pillars_lit;
    uint32_t stage_frame;
    uint16_t ordinary_count[21];
    struct { uint8_t kind, affix, divisor; uint32_t wave;
        ember_fixed x, y; } spawn_queue[EMBER_ENEMIES];
    uint32_t queued_spawns;
    uint16_t wave_scheduled[30], wave_live[30], wave_wait[30];
    uint8_t wave_finished[30], altars_used, rift_doors[2];
    struct ember_rng map_rng;
    uint8_t panel, option_count, panel_selected, panel_return, transaction_result;
    struct ember_choice options[EMBER_ATTRIBUTE_COUNT], pending_item;
    int32_t option_prices[EMBER_ATTRIBUTE_COUNT], pending_price;
    int16_t pending_pickup, pending_ground, pending_shop;
    struct ember_ground_weapon ground[62];
    struct ember_choice shop_stock[3], altar_stock[3];
    uint8_t altar_count, altar_generated;
    uint8_t shop_sold[3];
    uint32_t shop_refreshes;
    uint8_t altars_available, shop_available, rifts_available, stage_clear;
    uint8_t rifts_count, rifts_used, chosen_curse, chosen_rift, room_serial;
    uint8_t room_kind, island, room_wave, room_cleared, room_lit, room_reward;
    uint8_t side_left, side_completed, hidden_count, hidden_active, cleanse_tokens;
    uint8_t room_wave_pending;
    struct {
        struct ember_point point;
        uint8_t island, clue, found, visited, obstacle_index;
        int32_t hp;
    } hidden[2];
    struct ember_point altar, merchant, rifts[2], exit, doors[3], hazard_point, lighthouse;
    uint8_t door_rewards[10][3], rift_islands[2];
    struct ember_point hidden_exit, hidden_return_position;
    uint8_t hidden_return_serial, hidden_return_pillars;
    unsigned hidden_return_obstacles;
    uint8_t hazard_phase, region;
    uint32_t hazard_cycle;
    struct { uint32_t enemies, shots, pickups, summons; } peaks[3];
    uint32_t frame, combat_frame, wave, wave_frame, rest, spawned, alive_count;
    uint32_t shot_count, damage_total, rng_seed;
    uint16_t previous_input;
    uint8_t selected, paused;
    struct ember_choice choices[3];
    struct ember_rng spawn_rng, combat_rng, loot_rng;
    struct ember_player player;
    struct ember_enemy enemies[EMBER_ENEMIES];
    struct ember_shot shots[EMBER_SHOTS];
    struct ember_events events;
    ember_fixed world_width, world_height;
    ember_fixed safe_left, safe_top, safe_right, safe_bottom;
    struct ember_obstacle obstacles[EMBER_OBSTACLES];
    unsigned obstacle_count;
    uint16_t weapon_timer[50];
    uint32_t charge_frames;
    uint16_t attack_count[50], hit_count[50], arrow_count[50];
    uint8_t blessings[13], resonances[10], curses[6];
    uint8_t pet_kind, pet_level, flame_dash, next_crit;
    uint32_t moving_frames, standing_frames;
    ember_fixed previous_player_x, previous_player_y;
    uint16_t skill_time, ultimate_time, pet_skill_timer;
    uint16_t pet_attack_count, pet_hit_count;
    uint16_t dash_buff, stealth, pet_skill_time;
    int16_t marked_target, fuse_target;
    uint8_t fuse_stacks, free_evolution, guaranteed_resonance, contract_cap_choice;
    uint8_t tide_shield, loaded, saved_pillars, previous_light, boss_blackout;
    int32_t contract_caps[EMBER_ATTRIBUTE_COUNT];
    int32_t saved_oil, energy_fraction, leech_fraction, healing_fraction;
    uint8_t reward_relic, has_reward_relic, reward_inscription, has_reward_inscription;
    uint32_t gold;
    struct { ember_fixed x, y; int32_t hp, armor, damage, base_armor, base_damage; uint16_t life, timer;
        uint8_t kind, room; } summons[8];
    uint32_t belt_frames[5], thorn_next, recoil_next;
    uint8_t belt_first, belt_count;
    uint8_t hourglass_seen[EMBER_ENEMIES], hourglass_count, hourglass_pending;
    int32_t attributes[EMBER_ATTRIBUTE_COUNT], cap_raise[EMBER_ATTRIBUTE_COUNT];
    int32_t oil, oil_fraction, lamp_radius;
    /* in_light is player light-zone membership; each enemy has its own in_dark.
     * The portable lamp is visibility only, excluded from player light zones. */
    uint8_t in_light, lamp_disabled, trigger_bonus, dot_can_crit, dual_wield, pillar_count;
    int32_t tag_damage[32];
    uint8_t trigger_peak;
    struct { ember_fixed x, y; uint8_t lit; } pillars[8];
    struct ember_weapon_system {
        uint8_t category, offhand, rarity;
        int32_t share[EMBER_DAMAGE_TYPES], conversion, added[EMBER_DAMAGE_TYPES];
        int32_t increased, more[4], penetration;
        uint32_t tags;
        uint16_t status_mask;
        uint8_t offhand_attribute;
        int32_t offhand_flat;
    } weapon_system[50];
    struct { ember_fixed x, y; int32_t damage; uint16_t cooldown; uint8_t category; } pet;
    struct ember_pickup pickups[EMBER_PICKUPS];
    uint32_t pickup_count;
    ember_fixed dash_vx, dash_vy;
    /* 32-pixel spatial buckets; linked indices retain stable pool ordering. */
    int16_t grid[EMBER_GRID_COLUMNS * EMBER_GRID_ROWS], next_enemy[EMBER_ENEMIES];
};
void ember_sim_init(struct ember_sim *sim, uint32_t seed);
void ember_sim_stress(struct ember_sim *sim);
void ember_sim_begin(struct ember_sim *sim, uint32_t seed, const struct ember_run_config *config);
enum ember_action { EMBER_IDLE, EMBER_MOVE, EMBER_DASHING, EMBER_HURT, EMBER_DEAD,
                    EMBER_INTERACTING, EMBER_CAST, EMBER_ATTACKING, EMBER_CHARGING };
enum ember_weapon_category { EMBER_SWORD, EMBER_GREATSWORD, EMBER_SPEAR, EMBER_BLADES,
    EMBER_HAMMER, EMBER_BOW, EMBER_CROSSBOW, EMBER_GUN, EMBER_STAFF, EMBER_CODEX };
void ember_sim_step(struct ember_sim *sim, uint16_t input);
struct ember_damage_result ember_sim_hit(struct ember_sim *sim, unsigned enemy,
                                         const struct ember_attack *hit);
void ember_sim_status(struct ember_sim *sim, unsigned enemy, unsigned status,
                       unsigned depth);
void ember_sim_attributes(struct ember_sim *sim);
/* Content setup/actions for menus, altar, codex and E4 directed verification.
 * IDs index generated CSV rows. Evolution branch is 1 (A) or 2 (B).
 */
unsigned ember_sim_spawn(struct ember_sim *sim, unsigned kind, unsigned affix,
                          ember_fixed x, ember_fixed y);
void ember_sim_character(struct ember_sim *sim, unsigned character);
void ember_sim_pet(struct ember_sim *sim, unsigned kind, unsigned weapon);
/* Altar content choices: kind 0 blessing, 1 resonance; E5 owns placement and UI. */
struct ember_altar_choice { uint8_t kind, id; };
unsigned ember_sim_altar_choices(struct ember_sim *sim, struct ember_altar_choice choices[3]);
int ember_sim_contract_reward_available(const struct ember_sim *sim, unsigned reward);
void ember_sim_blessing(struct ember_sim *sim, unsigned id);
void ember_sim_resonance(struct ember_sim *sim, unsigned id);
void ember_sim_contract(struct ember_sim *sim, unsigned curse, unsigned reward);
void ember_sim_reward_cap(struct ember_sim *sim, unsigned attribute);
int32_t ember_sim_price(const struct ember_sim *sim, int32_t base);
void ember_sim_cleanse(struct ember_sim *sim, unsigned curse);
unsigned ember_sim_tag_count(const struct ember_sim *sim, const char *tag);
int ember_sim_resonance_ready(const struct ember_sim *sim, unsigned id);
int ember_sim_evolution_ready(const struct ember_sim *sim, unsigned weapon, unsigned branch);
uint32_t ember_sim_weapon_tags(const struct ember_sim *sim, unsigned weapon);
void ember_sim_evolve(struct ember_sim *sim, unsigned weapon, unsigned branch);
/* Decimal field-by-field summary used verbatim by PC and Spike. */
void ember_sim_summary(const struct ember_sim *sim, char *text, size_t bytes);
#endif
