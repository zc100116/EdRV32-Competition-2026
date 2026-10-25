/* File: plic.h
 * Spec: sys-subsys-spec 4.2
 * Description: PLIC register offsets, fields and software interface.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_PLIC_H
#define EDRV32_PLIC_H
#include "mmio.h"

#define PLIC_PRIORITY 0x000u
#define PLIC_PENDING 0x1000u
#define PLIC_ENABLE 0x2000u
#define PLIC_THRESHOLD 0x200000u
#define PLIC_CLAIM 0x200004u

#define PLIC_PRIORITY_MASK 0x7u
#define PLIC_THRESHOLD_MASK 0x7u
#define PLIC_SOURCE_MASK 0xfffeu
#define PLIC_SOURCE_COUNT 0xfu

void plic_set_priority(unsigned int source, unsigned int priority);
void plic_set_enable(uint32_t sources);
void plic_set_threshold(unsigned int threshold);
uint32_t plic_pending(void);
unsigned int plic_claim(void);
void plic_complete(unsigned int source);
#endif
