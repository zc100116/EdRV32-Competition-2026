/* File: edrv32.h
 * Spec: CLAUDE.md 9.2; infra-plan I-07
 * Description: Bare-metal test exit and host console interfaces.
 *              The host observes symbols rather than MMIO register addresses.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_H
#define EDRV32_H
#include <stdint.h>
extern volatile uint64_t tohost;
extern volatile uint64_t fromhost;
_Noreturn void edrv32_exit(int status);
void edrv32_putchar(char value);
#endif
