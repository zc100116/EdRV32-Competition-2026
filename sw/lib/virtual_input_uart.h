/* File: virtual_input_uart.h
 * Spec: sys-subsys 2.5/2.6; Tasks T-NESKEY/T-S3IN.
 * Description: Shared UART reception and foreground snapshot critical sections.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_VIRTUAL_INPUT_UART_H
#define EDRV32_VIRTUAL_INPUT_UART_H
#include <stdint.h>
/* Caller disables interrupts and owns mtvec/mie and the PLIC threshold. */
void virtual_input_uart_start(void (*character)(int));
void virtual_input_uart_receive(void);
void virtual_input_uart_set_raw(void (*receive)(unsigned));
uint32_t virtual_input_lock(void);
void virtual_input_unlock(uint32_t state);
#endif
