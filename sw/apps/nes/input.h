/* File: input.h
 * Spec: sys-subsys 2.5/2.6; Task T-NESKEY.
 * Description: UART interrupt ownership and atomic controller snapshots.
 * Clock domain: clk_sys.
 */
#ifndef NES_INPUT_H
#define NES_INPUT_H
#include <stdint.h>
void nes_uart_receive(void);
void nes_uart_start(void);
void nes_input_init(void);
uint32_t nes_input_lock(void);
void nes_input_unlock(uint32_t state);
#endif
