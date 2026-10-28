/* File: uart_input.h
 * Spec: edrv32-soc-spec 7.5(3a), 7.5(4).
 * Description: Shared Enter-terminated UART input with caller-owned line state.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_UART_INPUT_H
#define EDRV32_UART_INPUT_H
#include <stdint.h>

struct uart_input {
    uint8_t previous_cr;
};

static inline int uart_input_is_enter(uint8_t character)
{
    return character == '\r' || character == '\n';
}

uint8_t uart_input_getc(struct uart_input *input);
uint8_t uart_read_selection(struct uart_input *input);
void uart_input_binary_begin(struct uart_input *input);
#endif
