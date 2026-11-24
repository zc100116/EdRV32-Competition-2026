/* File: combat.h; gdd 2.2a, 2.3, 4.2. Deterministic damage and status records.
 * Clock domain: fixed 60 Hz simulation. Values are integer percentages unless Q16 noted.
 */
#ifndef EMBER_COMBAT_H
#define EMBER_COMBAT_H
#include "core/core.h"
enum ember_damage_type { EMBER_DAMAGE_IRON, EMBER_DAMAGE_FIRE, EMBER_DAMAGE_WATER,
                         EMBER_DAMAGE_STAR,
                         EMBER_DAMAGE_SHADOW, EMBER_DAMAGE_TRUE, EMBER_DAMAGE_TYPES };
enum ember_status { EMBER_IGNITE, EMBER_WET, EMBER_CHILL, EMBER_SHOCK,
                    EMBER_BREAK_ARMOR, EMBER_STUN, EMBER_CORRODE, EMBER_BLIND,
                    EMBER_STATUS_COUNT };
enum ember_hit_flags { EMBER_DOT = 1, EMBER_DOT_CRIT = 2, EMBER_UNDODGEABLE = 4,
                       EMBER_IGNORE_BLOCK = 8, EMBER_FRONT = 16, EMBER_CHARGED = 32,
                       EMBER_FORCE_CRIT = 64 };
enum ember_slow_source { EMBER_SLOW_GATE, EMBER_SLOW_ABYSS, EMBER_SLOW_VINE,
    EMBER_SLOW_WEB, EMBER_SLOW_VORTEX, EMBER_SLOW_COUNT };
struct ember_slow_state { uint16_t frames; int32_t percent; };
struct ember_status_state { uint16_t frames, tick; uint8_t stacks; };
struct ember_defense {
    int32_t armor, resistance[4], all_resistance, resistance_cap[4];
    int32_t dodge, tenacity, vulnerability, reduction[4], reduction_cap;
    int32_t block_chance, block_strength;
    uint8_t front_block, active_block, immune_pierce, immune_break, rank, weakness;
    uint16_t invulnerable, hurt_frames, since_hurt, shield_delay;
    int32_t permanent_shield, shield_max, shield_recovery;
    int32_t temporary[EMBER_DAMAGE_TYPES + 1]; /* index 6: mixed non-true */
    uint16_t shield_frames[EMBER_DAMAGE_TYPES + 1];
    int32_t posture, posture_max, max_hp, break_bonus, rust;
    uint16_t broken, frozen;
    struct ember_status_state status[EMBER_STATUS_COUNT];
    struct ember_slow_state slow[EMBER_SLOW_COUNT];
};
struct ember_attack {
    int32_t base, flat, attack, increased, more[4], crit, crit_damage;
    int32_t penetration, share[EMBER_DAMAGE_TYPES], conversion, added[EMBER_DAMAGE_TYPES];
    int32_t element_more[EMBER_DAMAGE_TYPES], element_increased[EMBER_DAMAGE_TYPES];
    int32_t posture, status_strength, leech;
    uint8_t flags, depth, source_weapon;
};
struct ember_damage_result {
    int32_t damage, absorbed, part[EMBER_DAMAGE_TYPES], before_defense;
    uint8_t crit, dodged, blocked, dominant;
};
struct ember_damage_result ember_damage(struct ember_rng *rng, const struct ember_attack *hit,
                                        struct ember_defense *target, int32_t *hp);
void ember_defense_init(struct ember_defense *target, int32_t max_hp);
void ember_defense_step(struct ember_defense *target);
void ember_slow_apply(struct ember_defense *target, unsigned source, int percent, int duration);
int ember_slow_percent(const struct ember_defense *target);
/* Returns a bitset of linked reactions; callers execute damage through the same hit path. */
unsigned ember_status_apply(struct ember_defense *target, unsigned status, int duration,
                            int strength);
int32_t ember_attribute_value(unsigned id, int32_t base, int32_t flat, int32_t increased,
                              const int32_t more[4], int32_t cap_raise);
#endif
