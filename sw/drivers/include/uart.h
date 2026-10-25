/* File: uart.h
 * Spec: sys-subsys-spec 4.3
 * Description: UART register offsets, fields and software interface.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_UART_H
#define EDRV32_UART_H
#include "mmio.h"

#define UART_ID 0x000u
#define UART_CTRL 0x004u
#define UART_STATUS 0x008u
#define UART_IRQ_EN 0x00cu
#define UART_IRQ_STAT 0x010u
#define UART_BAUD_DIV 0x014u
#define UART_RX_THRESH 0x018u
#define UART_TXDATA 0x020u
#define UART_RXDATA 0x024u

#define UART_CTRL_TX_EN 0x1u
#define UART_CTRL_RX_EN 0x2u
#define UART_CTRL_TX_CLR 0x4u
#define UART_CTRL_RX_CLR 0x8u
#define UART_STATUS_TX_EMPTY 0x1u
#define UART_STATUS_TX_FULL 0x2u
#define UART_STATUS_RX_EMPTY 0x4u
#define UART_STATUS_RX_FULL 0x8u
#define UART_STATUS_TX_BUSY 0x10u
#define UART_STATUS_TX_LEVEL_SHIFT 0x8u
#define UART_STATUS_TX_LEVEL_MASK 0x1f00u
#define UART_STATUS_RX_LEVEL_SHIFT 0x10u
#define UART_STATUS_RX_LEVEL_MASK 0x1f0000u
#define UART_IRQ_RX_THRESH 0x1u
#define UART_IRQ_TX_EMPTY 0x2u
#define UART_IRQ_RX_OVERRUN 0x4u
#define UART_IRQ_FRAME_ERR 0x8u
#define UART_BAUD_DIV_MASK 0xffffffu
#define UART_BAUD_DIV_MIN 0x80u
#define UART_RX_THRESH_MASK 0x1fu
#define UART_DATA_MASK 0xffu
#define UART_RXDATA_VALID 0x100u

void uart_init(void);
void uart_set_baud(uint32_t clock_hz, uint32_t baud);
void uart_putc(uint8_t value);
uint8_t uart_getc(void);
void uart_puts(const char *text);
void uart_drain(void);
#endif
