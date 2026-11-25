/* File: e5a_grid_test.c
 * Spec: GDD 5; tech 2-3; E5a full arena collision grid.
 * Description: Exercise every bucket and real area damage at the far world edge.
 * Clock domain: fixed 60 Hz directed host verification.
 */
#include "sim/sim.c"
#include <assert.h>
static struct ember_sim simulation;
int main(void)
{
    struct ember_sim *s = &simulation;
    ember_sim_init(s, 20261125);
    assert(s->world_width == 3840 * EMBER_Q);
    assert(s->world_height == 2160 * EMBER_Q);
    assert(EMBER_GRID_COLUMNS == 120 && EMBER_GRID_ROWS == 68);
    unsigned target = ember_sim_spawn(s, 0, 0, 0, 0);
    for (unsigned y = 0; y < EMBER_GRID_ROWS; ++y)
        for (unsigned x = 0; x < EMBER_GRID_COLUMNS; ++x) {
            s->enemies[target].x = (int)(x * 32 + 8) * EMBER_Q;
            s->enemies[target].y = (int)(y * 32 + 8) * EMBER_Q;
            grid_build(s);
            assert(s->grid[y * EMBER_GRID_COLUMNS + x] == (int)target);
        }
    s->enemies[target].x = 3820 * EMBER_Q;
    s->enemies[target].y = 2140 * EMBER_Q;
    grid_build(s);
    int hp = s->enemies[target].hp;
    area_hit(s, s->enemies[target].x, s->enemies[target].y, 20, 1,
             s->player.main_weapon, 0, 0);
    assert(s->enemies[target].hp < hp);
    s->player.x = s->world_width;
    s->player.y = s->world_height;
    player_step(s, EMBER_RIGHT | EMBER_DOWN, 0);
    assert(s->player.x == s->world_width -
        ember_characters[s->player.character].boundary_margin * EMBER_Q);
    assert(s->player.y == s->world_height -
        ember_characters[s->player.character].boundary_margin * EMBER_Q);
    puts("PASS E5a: 8160 buckets, far-edge damage, 3840x2160 world boundary");
    return 0;
}
