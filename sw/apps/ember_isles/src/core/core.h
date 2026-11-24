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
#define EMBER_DOWN 2u
#define EMBER_LEFT 4u
#define EMBER_RIGHT 8u
#define EMBER_A 16u
#define EMBER_B 32u
#define EMBER_SELECT 64u
#define EMBER_START 128u
typedef int32_t ember_fixed;
struct ember_rng { uint32_t state; };
struct ember_replay { uint32_t seed; uint32_t count; uint8_t input[EMBER_REPLAY_FRAMES]; };
struct ember_event { uint16_t kind; uint16_t value; ember_fixed x; ember_fixed y; };
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
