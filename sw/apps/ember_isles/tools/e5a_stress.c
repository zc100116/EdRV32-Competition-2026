/* File: e5a_stress.c
 * Spec: tech 2/4; E5a reproducible real simulation stress configuration.
 * Description: Fill real enemy/projectile pools, then run ordinary collision ticks.
 * Clock domain: fixed 60 Hz diagnostic, outside the two game modes.
 */
#include "sim/sim.h"
#include "data.h"
#include <stdio.h>
#include <time.h>
#include <assert.h>
static struct ember_sim simulation;
int main(void)
{
    const struct ember_stress_row *c = &ember_stress[0];
    struct ember_sim *s = &simulation;
    ember_sim_stress(s);
    assert(s->alive_count == EMBER_ENEMIES);
    assert(s->shot_count == EMBER_SHOTS);
    printf("RUN,mode=%u,stage=%u,seed=%u,diagnostic=stress\n",
        s->config.mode, s->config.stage, s->rng_seed);
    printf("STRESS,frame,combat,phase,enemies,shots,hits,kills,damage,hp,microseconds\n");
    printf("STRESS,0,0,1,%u,%u,0,0,0,%d,0\n", s->alive_count, s->shot_count, s->player.hp);
    unsigned hits = 0;
    for (int frame = 1; frame <= c->frames; ++frame) {
        clock_t begin = clock();
        uint16_t input = s->phase == EMBER_UPGRADE && !(s->previous_input & EMBER_J) ?
            EMBER_J : 0;
        ember_sim_step(s, input);
        clock_t elapsed = clock() - begin;
        for (unsigned i = 0; i < s->events.count; ++i)
            hits += s->events.item[i].kind == EMBER_EVENT_HIT;
        unsigned enemies = 0, shots = 0;
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i) enemies += !!s->enemies[i].alive;
        for (unsigned i = 0; i < EMBER_SHOTS; ++i) shots += !!s->shots[i].alive;
        assert(enemies == s->alive_count && shots == s->shot_count);
        assert(s->phase == EMBER_PLAY || s->phase == EMBER_UPGRADE);
        printf("STRESS,%d,%u,%u,%u,%u,%u,%u,%u,%d,%lu\n", frame,
            s->combat_frame, s->phase, s->alive_count, s->shot_count, hits, s->player.kills,
            s->damage_total, s->player.hp,
            (unsigned long)((uint64_t)elapsed * 1000000u / CLOCKS_PER_SEC));
        if (frame % 60 == 0) {
            char summary[2048];
            ember_sim_summary(s, summary, sizeof(summary));
            printf("STATE,%s\n", summary);
        }
    }
    printf("END,%d,%u,%u,%u,%u\n", c->frames, s->phase, s->wave, s->config.mode, s->config.stage);
    assert(hits && s->damage_total && s->combat_frame);
    return 0;
}
