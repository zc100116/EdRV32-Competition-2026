/* File: core.h
 * Spec: ember_isles tech 2-3; deterministic arithmetic, pools and replay.
 * Description: Integer simulation primitives shared by PC and RV32.
 * Clock domain: fixed 60 Hz simulation.
 */
#ifndef EMBER_CORE_H
#define EMBER_CORE_H
#include <stdint.h>
#include <stddef.h>
#define EMBER_Q 65536
#define EMBER_REPLAY_FRAMES 60000
#define EMBER_DEMO_FRAMES 10800
#define EMBER_ENEMIES 1500
#define EMBER_SHOTS 3000
#define EMBER_EVENTS 256
#define EMBER_PARTICLES 8000
#define EMBER_UP 1u
#define EMBER_LEFT 2u
#define EMBER_DOWN 4u
#define EMBER_RIGHT 8u
#define EMBER_J 16u
#define EMBER_K 32u
#define EMBER_L 64u
#define EMBER_U 128u
#define EMBER_SWAP 256u
#define EMBER_INTERACT 512u
#define EMBER_DASH 1024u
#define EMBER_SELECT 2048u
#define EMBER_START 4096u
#define EMBER_A EMBER_J
#define EMBER_B EMBER_L
typedef int32_t ember_fixed;
struct ember_rng { uint32_t state; };
struct ember_replay { uint32_t seed; uint32_t count; uint16_t input[EMBER_REPLAY_FRAMES]; };
enum ember_event_kind {
    EMBER_EVENT_SHOT, EMBER_EVENT_HIT, EMBER_EVENT_KILL, EMBER_EVENT_DASH,
    EMBER_EVENT_SEED, EMBER_EVENT_ULTIMATE, EMBER_EVENT_LEVELUP, EMBER_EVENT_CHOOSE,
    EMBER_EVENT_HURT, EMBER_EVENT_VICTORY, EMBER_EVENT_PICKUP, EMBER_EVENT_WEAPON_CHANGE,
    EMBER_EVENT_COUNT
};
enum ember_pickup_type { EMBER_PICKUP_XP, EMBER_PICKUP_GOLD, EMBER_PICKUP_EMBER,
                         EMBER_PICKUP_ITEM };
enum ember_weapon_slot { EMBER_WEAPON_SLOT_MAIN, EMBER_WEAPON_SLOT_SUB,
                         EMBER_WEAPON_SLOT_PET };
/* PICKUP: subtype is ember_pickup_type; value is quantity (item: CSV ID).
 * x/y is the pickup position. WEAPON_CHANGE: subtype is ember_weapon_slot,
 * value is the new weapon CSV ID (255: native pet attack); x/y is the player.
 * tier, damage_type and outcome retain their damage-event meanings.
 * outcome: 0 hit, 1 dodge, 2 block; damage_type uses sim/combat.h ordering. */
struct ember_event {
    uint16_t kind;
    uint32_t value;
    ember_fixed x;
    ember_fixed y;
    uint8_t tier, damage_type, outcome, subtype;
};
struct ember_events { unsigned count; struct ember_event item[EMBER_EVENTS]; };
uint32_t ember_random(struct ember_rng *rng);
ember_fixed ember_mul(ember_fixed a, ember_fixed b);
ember_fixed ember_sin(uint16_t angle);
ember_fixed ember_cos(uint16_t angle);
int ember_pool_take(uint8_t *alive, unsigned count);
void ember_event_push(struct ember_events *events, unsigned kind, unsigned value,
                      ember_fixed x, ember_fixed y);
void ember_replay_load(struct ember_replay *replay, const char *path);
void ember_replay_save(const struct ember_replay *replay, const char *path);
#endif
