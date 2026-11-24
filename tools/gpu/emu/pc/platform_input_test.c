/* platform_input_test.c — Ember Isles tech 1/3: separate keyboard and pointer.
 * Checks the legacy wire protocol and both platform input contracts.
 * Clock domain: deterministic host test.
 */
#include "plat.h"
#include "pc_soc.h"
#include "virtual_input.h"
#include <assert.h>
#include <stdio.h>
uint32_t pc_frontend_keys(void) { return PLAT_DOWN | PLAT_SELECT | PLAT_START; }
uint32_t pc_frontend_millis(void) { return 0; }
uint32_t pc_frontend_wait(void) { return 800; }
void pc_frontend_audio(const int16_t *samples, uint32_t frames)
{
    (void)samples;
    (void)frames;
}
int main(void)
{
    const uint16_t wire[] = {VI_UP, VI_LEFT, VI_DOWN, VI_RIGHT, VI_A, VI_B,
        VI_L, VI_U, VI_Q, VI_F, VI_SELECT, VI_ESC, VI_ENTER};
    for (unsigned i = 0; i < sizeof(wire) / sizeof(*wire); ++i)
        assert(virtual_input_game_keys(wire[i]) == (1u << i));
    assert(virtual_input_game_keys(VI_START | VI_NEXT | VI_PREV) == 0);
    const uint8_t frame[] = {0xff, 0xff, 0xff, 4, 0xcf, 2, 3, 7};
    assert(virtual_input_serial(0x1b) == -1);
    assert(virtual_input_serial('V') == -1);
    for (unsigned i = 0; i < sizeof(frame); ++i)
        assert(virtual_input_serial(frame[i]) == -1);
    struct virtual_input_state input = virtual_input_get();
    assert(input.keys == 0xffff && input.x == 1279 && input.y == 719);
    assert(input.mouse == 3 && input.wheel == 7 && input.active);
    assert(virtual_input_game_keys(input.keys) == 0x1fff);
    const uint8_t released[8] = {0};
    virtual_input_network(released);
    assert(!virtual_input_get().keys && !virtual_input_get().mouse);
    struct plat_pointer_state pointer = {639, 359, 3};
    pc_soc_game_input(0x1fff, pointer);
    assert(plat_game_keys() == 0x1fff);
    assert(plat_pointer().x == 639 && plat_pointer().y == 359 && plat_pointer().buttons == 3);
    assert(plat_keys() == (PLAT_DOWN | PLAT_SELECT | PLAT_START));
    pc_soc_game_input(0, (struct plat_pointer_state){0});
    assert(!plat_game_keys() && !plat_pointer().buttons);
    puts("PASS 13 game keys, legacy controller/wire, pointer and release");
    return 0;
}
