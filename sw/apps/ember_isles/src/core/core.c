/* File: core.c
 * Spec: ember_isles tech 2-3.
 * Description: Q16.16 lookup trigonometry, independent xorshift streams and pools.
 * Clock domain: fixed 60 Hz simulation.
 */
#include "core.h"
#include <stdio.h>
#include <stdlib.h>
#include "sine.inc"
uint32_t ember_random(struct ember_rng *rng)
{
    uint32_t x = rng->state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rng->state = x;
    return x;
}
ember_fixed ember_mul(ember_fixed a, ember_fixed b)
{
    return (ember_fixed)((int64_t)a * b / EMBER_Q);
}
ember_fixed ember_sin(uint16_t angle) { return ember_sine[angle >> 8]; }
ember_fixed ember_cos(uint16_t angle) { return ember_sin((uint16_t)(angle + 16384u)); }
int ember_pool_take(uint8_t *alive, unsigned count)
{
    for (unsigned i = 0; i < count; ++i) {
        if (!alive[i]) { alive[i] = 1; return (int)i; }
    }
    fputs("ember entity pool exhausted\n", stderr);
    abort();
}
void ember_event_push(struct ember_events *events, unsigned kind, unsigned value,
                      ember_fixed x, ember_fixed y)
{
    if (events->count == EMBER_EVENTS) {
        fputs("ember event pool exhausted\n", stderr);
        abort();
    }
    events->item[events->count++] = (struct ember_event){.kind = (uint16_t)kind, .value = value, .x = x, .y = y, .source_weapon = 255};
}

void ember_run_config_default(struct ember_run_config *config)
{
    *config = (struct ember_run_config){.sub_weapon = 255, .pet = 255,
        .pet_weapon = 255, .talents = {0,255,255,255}};
}
