/* File: e4b_table_test.c; gdd 2.4 CSV-only tuning of the six E4b rules.
 * Clock domain: fixed 60 Hz; included sim operations expose actual applied values.
 */
#include "../src/sim/sim.c"
static struct ember_sim state;
static void reset(unsigned character)
{
    ember_sim_init(&state, 11);
    ember_sim_character(&state, character);
    ember_sim_spawn(&state, 0, 0, state.player.x + 40 * EMBER_Q, state.player.y);
    state.enemies[0].hp = state.enemies[0].defense.max_hp = 10000;
}
int main(void)
{
    reset(EMBER_DATA_CHARACTERS_NAMELESS);
    content_skill(&state, 0);
    printf("lock=%u ", state.enemies[0].facing_lock);
    reset(EMBER_DATA_CHARACTERS_SEER);
    content_skill(&state, 0); ground_effect(&state, &state.shots[0]);
    printf("gate=%d/%u ", ember_slow_percent(&state.enemies[0].defense),
        state.enemies[0].defense.slow[EMBER_SLOW_GATE].frames);
    state.shots[0].effect = 3; state.shots[0].tick = 0;
    ground_effect(&state, &state.shots[0]);
    printf("abyss=%u ", state.enemies[0].defense.slow[EMBER_SLOW_ABYSS].frames);
    reset(EMBER_DATA_CHARACTERS_KEEPER);
    state.hourglass_pending = state.player.relic_level[R_HOURGLASS] = 1;
    int normal = ember_characters[state.player.character].skill_l_cooldown *
        (100 - state.attributes[EMBER_COOLDOWN]) / 100;
    player_step(&state, EMBER_L, EMBER_L);
    printf("discount=%d ", normal - state.player.cooldown_b);
    reset(EMBER_DATA_CHARACTERS_LAMPLIGHTER);
    summon(&state, 1, 180, state.player.x, state.player.y);
    content_skill(&state, 1); content_skill(&state, 1);
    printf("damage=%d armor=%d\n", state.summons[0].damage, state.summons[0].armor);
    return 0;
}
