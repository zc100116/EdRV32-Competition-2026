/* File: e4_table_test.c; tech 6 E4 CSV-only numeric change demonstration. */
#include "../src/sim/sim.c"
static struct ember_sim state;
int main(void)
{
    ember_sim_init(&state, 11);
    ember_sim_character(&state, EMBER_DATA_CHARACTERS_SMITH);
    content_skill(&state, 1);
    content_step(&state);
    printf("ironwall=%d\n", state.player.defense.reduction[1]);
    return 0;
}
