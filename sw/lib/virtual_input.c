/* File: virtual_input.c
 * Spec: Task T-VIN1 input state protocol.
 * Description: Serial framing and notified network data replace the complete state.
 * Clock domain: clk_sys, or host test caller.
 */
#include "virtual_input.h"
#include "plat/plat.h"
static volatile struct virtual_input_state state;
static uint8_t serial_frame[VIRTUAL_INPUT_BYTES];
static unsigned serial_position;
static unsigned revision;
unsigned virtual_input_revision(void) { return revision; }
static int16_t wheel_pending;

uint16_t virtual_input_game_keys(uint16_t keys)
{
    return ((keys & VI_UP) ? PLAT_KEY_W : 0) |
        ((keys & VI_LEFT) ? PLAT_KEY_A : 0) |
        ((keys & VI_DOWN) ? PLAT_KEY_S : 0) |
        ((keys & VI_RIGHT) ? PLAT_KEY_D : 0) |
        ((keys & VI_A) ? PLAT_KEY_J : 0) |
        ((keys & VI_B) ? PLAT_KEY_K : 0) |
        ((keys & VI_L) ? PLAT_KEY_L : 0) |
        ((keys & VI_U) ? PLAT_KEY_U : 0) |
        ((keys & VI_Q) ? PLAT_KEY_Q : 0) |
        ((keys & VI_F) ? PLAT_KEY_F : 0) |
        ((keys & VI_SELECT) ? PLAT_KEY_SPACE : 0) |
        ((keys & VI_ESC) ? PLAT_KEY_ESC : 0) |
        ((keys & VI_ENTER) ? PLAT_KEY_ENTER : 0);
}

void virtual_input_network(const volatile uint8_t *frame)
{
    ++revision;
    wheel_pending += (int8_t)(uint8_t)(frame[7] - state.wheel);
    state = (struct virtual_input_state) {
        .keys = (uint16_t)(frame[0] | (uint16_t)frame[1] << 8),
        .x = (int16_t)(frame[2] | (uint16_t)frame[3] << 8),
        .y = (int16_t)(frame[4] | (uint16_t)frame[5] << 8),
        .mouse = frame[6],
        .wheel = frame[7],
        .active = 1
    };
}

int virtual_input_serial(uint8_t byte)
{
    if (serial_position == 0) {
        if (byte != 0x1b) return byte;
        serial_position = 1;
    } else if (serial_position == 1) {
        /* ESC introduces only the specified V command; unknown commands are consumed. */
        serial_position = byte == 'V' ? 2 : 0;
    } else {
        serial_frame[serial_position++ - 2] = byte;
        if (serial_position == VIRTUAL_INPUT_BYTES + 2) {
            virtual_input_network(serial_frame);
            serial_position = 0;
        }
    }
    return -1;
}

struct virtual_input_state virtual_input_get(void)
{
    return state;
}

int16_t virtual_input_take_wheel(void)
{
    int16_t value = wheel_pending;
    wheel_pending = 0;
    return value;
}
