/* File: main.c; ember_isles tech 2. Board entry on display clock.
 * Clock domain: clk_sys and display vsync.
 */
#include "game.h"
#include "plat.h"
int main(void)
{
    ember_game_init();
    for (unsigned frame = 1;; ++frame) {
        ember_game_frame(frame);
        plat_wait_vsync();
    }
}
