/* File: e5a_upgrade_test.c
 * Spec: GDD 6: levels 10/20/30 guarantee rare choices when eligible.
 * Description: Verify all guarantee levels and the specified resource-only pool.
 * Clock domain: deterministic host verification of simulation upgrade decisions.
 */
#include "sim/sim.c"
#include <assert.h>
static struct ember_sim simulation;
int main(void)
{
    struct ember_sim *s = &simulation;
    const unsigned levels[] = {10, 20, 30};
    for (unsigned n = 0; n < 3; ++n)
        for (unsigned seed = 1; seed <= 32; ++seed) {
            ember_sim_init(s, seed);
            s->player.level = levels[n] - 1;
            s->player.xp = s->player.next_xp;
            upgrade_offer(s);
            assert(s->phase == EMBER_UPGRADE && s->player.level == levels[n]);
            const struct ember_choice *c = &s->choices[0];
            assert(c->kind <= 2);
            assert((c->kind == 0 ? ember_weapons[c->id].grade :
                c->kind == 1 ? ember_relics[c->id].grade :
                ember_inscriptions[c->id].grade) >= 2);
        }
    ember_sim_init(s, 1);
    s->player.level = 9;
    s->player.xp = s->player.next_xp;
    for (unsigned w = 0; w < 2; ++w) {
        s->player.weapon_level[w] = 5;
        s->player.evolution[w] = 1;
        s->player.inscription[w][0] = (uint8_t)(1 + 2 * w);
        s->player.inscription[w][1] = (uint8_t)(2 + 2 * w);
    }
    for (unsigned r = 0; r < 6; ++r) s->player.relic_level[r] = 1;
    upgrade_offer(s);
    unsigned resources = 0;
    for (unsigned i = 0; i < 3; ++i) {
        assert(s->choices[i].kind == 5);
        resources |= 1u << s->choices[i].id;
    }
    assert(resources == 7);
    puts("PASS E5a: 96 rare guarantees; exhausted level-10 pool retains "
         "all three resource fillers");
    return 0;
}
