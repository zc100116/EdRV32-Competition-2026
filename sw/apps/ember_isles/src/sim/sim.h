/* File: sim.h
 * Spec: ember_isles tech 2-3; gdd 2-5 and E3 systems.
 * Description: Read-only presentation contract for the deterministic combat state.
 * Clock domain: fixed 60 Hz simulation.
 */
#ifndef EMBER_SIM_H
#define EMBER_SIM_H
#include "core/core.h"
#include "combat.h"
enum ember_phase { EMBER_MENU, EMBER_PLAY, EMBER_UPGRADE, EMBER_WON, EMBER_LOST };
struct ember_enemy {
    ember_fixed x, y, vx, vy;
    int32_t hp, shield;
    uint16_t burn, timer, flash;
    uint8_t alive, kind, affix, mode;
    uint8_t burn_weapon;
    uint16_t burn_tick, burn_fraction;
    uint32_t wave;
    struct ember_defense defense;
};
struct ember_shot {
    ember_fixed x, y, vx, vy, z, vz;
    int32_t damage;
    uint16_t life, radius, tick;
    uint8_t alive, kind, hostile, pierce;
    uint8_t weapon, follow, pet;
    int16_t last_hit;
};
struct ember_player {
    ember_fixed x, y;
    int32_t hp, max_hp, armor, speed;
    uint32_t xp, next_xp, level, kills;
    uint16_t cooldown_a, cooldown_b, charge, dash, invulnerable, flash;
    uint8_t facing;
    uint8_t main_weapon, sub_weapon, pet_weapon, action, action_frame, combo;
    uint16_t action_time, pet_timer, cooldown_k;
    int16_t hand_x, hand_y;
    struct ember_defense defense;
    uint8_t weapon_level[4], relic_level[6], inscription[4][2];
};
/* IDs are zero-based CSV row indices; inscriptions store one plus that index.
 * Choice kind: 0 weapon, 1 relic, 2 inscription; slot is its weapon index.
 * Shot kind: 0 bolt, 1 ring, 2 ground, 3 pot, 4 seed, 5 burst, 6 hostile.
 * Affix: 0 none, 1 haste, 2 ward. Facing: 0 right, 1 down, 2 left, 3 up.
 */
#define EMBER_OBSTACLES 32
#define EMBER_GRID_COLUMNS 80
#define EMBER_GRID_ROWS 45
struct ember_obstacle { ember_fixed x, y; uint16_t radius; };
struct ember_choice { uint8_t kind, id, slot; };
struct ember_pickup { ember_fixed x, y; uint32_t xp; uint8_t alive; };
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
struct ember_sim {
    enum ember_phase phase;
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
    uint16_t weapon_timer[4];
    int32_t attributes[EMBER_ATTRIBUTE_COUNT], cap_raise[EMBER_ATTRIBUTE_COUNT];
    int32_t oil, oil_fraction, lamp_radius;
    uint8_t in_light, lamp_disabled, trigger_bonus, dot_can_crit, dual_wield;
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
    } weapon_system[4];
    struct { ember_fixed x, y; int32_t damage; uint16_t cooldown; uint8_t category; } pet;
    struct ember_pickup pickups[EMBER_ENEMIES];
    uint32_t pickup_count;
    ember_fixed dash_vx, dash_vy;
    /* 32-pixel spatial buckets; linked indices retain stable pool ordering. */
    int16_t grid[EMBER_GRID_COLUMNS * EMBER_GRID_ROWS], next_enemy[EMBER_ENEMIES];
};
void ember_sim_init(struct ember_sim *sim, uint32_t seed);
enum ember_action { EMBER_IDLE, EMBER_MOVE, EMBER_DASHING, EMBER_HURT, EMBER_DEAD,
                    EMBER_INTERACTING, EMBER_CAST, EMBER_ATTACKING };
enum ember_weapon_category { EMBER_SWORD, EMBER_GREATSWORD, EMBER_SPEAR, EMBER_BLADES,
    EMBER_HAMMER, EMBER_BOW, EMBER_CROSSBOW, EMBER_GUN, EMBER_STAFF, EMBER_CODEX };
void ember_sim_step(struct ember_sim *sim, uint16_t input);
struct ember_damage_result ember_sim_hit(struct ember_sim *sim, unsigned enemy,
                                         const struct ember_attack *hit);
void ember_sim_status(struct ember_sim *sim, unsigned enemy, unsigned status,
                       unsigned depth);
void ember_sim_attributes(struct ember_sim *sim);
/* Decimal field-by-field summary used verbatim by PC and Spike. */
void ember_sim_summary(const struct ember_sim *sim, char *text, size_t bytes);
#endif
