/* File: uart_input.c
 * Spec: edrv32-soc-spec 7.5(3a), 7.5(4).
 * Description: Treat CR, LF and CR LF as one Enter, and confirm single-character selections.
 * Clock domain: clk_sys.
 */
#include "uart_input.h"
#include "uart.h"

uint8_t uart_input_getc(struct uart_input *input)
{
    for (;;) {
        uint8_t character = uart_getc();
        if (character == '\n' && input->previous_cr) {
            input->previous_cr = 0u;
            continue;
        }
        input->previous_cr = character == '\r';
        return character;
    }
}

uint8_t uart_read_selection(struct uart_input *input)
{
    uint8_t selection = uart_input_getc(input);
    if (uart_input_is_enter(selection)) {
        return 0u;
    }
    int extra = 0;
    while (!uart_input_is_enter(uart_input_getc(input))) {
        extra = 1;
    }
    return extra ? 0u : selection;
}

void uart_input_binary_begin(struct uart_input *input)
{
    /* The host waits for the ready line before sending any binary bytes.
     * After ready has drained, a queued byte following CR is the optional LF.
     */
    if (input->previous_cr &&
        (mmio_read32(EDRV32_UART0_BASE + UART_STATUS) & UART_STATUS_RX_EMPTY) == 0u) {
        (void)uart_getc();
    }
    input->previous_cr = 0u;
}
