/* File: sim.h
 * Spec: ember_isles tech 2-3; gdd 2-5 and E2 scope.
 * Description: Read-only presentation contract for the deterministic combat state.
 * Clock domain: fixed 60 Hz simulation.
 */
#ifndef EMBER_SIM_H
#define EMBER_SIM_H
#include "core/core.h"
enum ember_phase { EMBER_MENU, EMBER_PLAY, EMBER_UPGRADE, EMBER_WON, EMBER_LOST };
struct ember_enemy {
    ember_fixed x, y, vx, vy;
    int32_t hp, shield;
    uint16_t burn, timer, flash;
    uint8_t alive, kind, affix, mode;
};
struct ember_shot {
    ember_fixed x, y, vx, vy, z, vz;
    int32_t damage;
    uint16_t life, radius, tick;
    uint8_t alive, kind, hostile, pierce;
};
struct ember_player {
    ember_fixed x, y;
    int32_t hp, max_hp, armor, speed;
    uint32_t xp, next_xp, level, kills;
    uint16_t cooldown_a, cooldown_b, charge, dash, invulnerable, flash;
    uint8_t facing;
    uint8_t weapon_level[4], relic_level[6], inscription[4][2];
};
struct ember_sim {
    enum ember_phase phase;
    uint32_t frame, combat_frame, wave, wave_frame, rest, spawned, alive_count;
    uint32_t shot_count, damage_total, rng_seed;
    uint8_t previous_input, selected, choices[3];
    struct ember_rng spawn_rng, combat_rng, loot_rng;
    struct ember_player player;
    struct ember_enemy enemies[EMBER_ENEMIES];
    struct ember_shot shots[EMBER_SHOTS];
    struct ember_events events;
    uint16_t weapon_timer[4];
};
void ember_sim_init(struct ember_sim *sim, uint32_t seed);
void ember_sim_step(struct ember_sim *sim, uint8_t input);
/* Decimal field-by-field summary used verbatim by PC and Spike. */
void ember_sim_summary(const struct ember_sim *sim, char *text, size_t bytes);
#endif
