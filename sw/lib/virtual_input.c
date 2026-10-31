/* File: virtual_input.c
 * Spec: Task T-VIN1 input state protocol.
 * Description: Serial framing and notified network data replace the complete state.
 * Clock domain: clk_sys, or host test caller.
 */
#include "virtual_input.h"
static struct virtual_input_state state;
static uint8_t serial_frame[VIRTUAL_INPUT_BYTES];
static unsigned serial_position;

void virtual_input_network(const volatile uint8_t *frame)
{
    state = (struct virtual_input_state) {
        .keys = (uint16_t)(frame[0] | (uint16_t)frame[1] << 8),
        .x = (int16_t)(frame[2] | (uint16_t)frame[3] << 8),
        .y = (int16_t)(frame[4] | (uint16_t)frame[5] << 8),
        .mouse = frame[6],
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
