/* File: virtual_input.h
 * Spec: Task T-VIN1 input state protocol.
 * Description: Complete virtual controller and absolute pointer state.
 * Clock domain: clk_sys, or host test caller.
 */
#ifndef EDRV32_VIRTUAL_INPUT_H
#define EDRV32_VIRTUAL_INPUT_H
#include <stdint.h>
#define VIRTUAL_INPUT_WINDOW 2u
#define VIRTUAL_INPUT_BASE 0x0a010000u
#define VIRTUAL_INPUT_BYTES 8u
enum virtual_key {
    VI_UP = 1u << 0, VI_DOWN = 1u << 1, VI_LEFT = 1u << 2, VI_RIGHT = 1u << 3,
    VI_A = 1u << 4, VI_B = 1u << 5, VI_SELECT = 1u << 6, VI_START = 1u << 7,
    VI_ENTER = 1u << 8, VI_ESC = 1u << 9, VI_NEXT = 1u << 10, VI_PREV = 1u << 11
};
struct virtual_input_state {
    uint16_t keys;
    int16_t x;
    int16_t y;
    uint8_t mouse; /* bits 0/1/2: left/right/middle */
    uint8_t active;
    uint8_t wheel; /* wire byte 7: cumulative modulo-256, down is positive */
};
/* Returns the legacy character, or -1 when consumed by ESC V + state. */
int virtual_input_serial(uint8_t byte);
/* Called after RX NOTIFY: read the latest eight bytes from the uncached window. */
void virtual_input_network(const volatile uint8_t *frame);
struct virtual_input_state virtual_input_get(void);
/* Accumulated signed modulo-256 deltas; each consumer drains once per read. */
int16_t virtual_input_take_wheel(void);
#endif
