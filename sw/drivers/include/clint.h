/* File: clint.h
 * Spec: sys-subsys-spec 4.1
 * Description: CLINT register offsets, fields and software interface.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_CLINT_H
#define EDRV32_CLINT_H
#include "mmio.h"

#define CLINT_MSIP 0x000u
#define CLINT_MTIMECMP_LO 0x4000u
#define CLINT_MTIMECMP_HI 0x4004u
#define CLINT_MTIME_LO 0xbff8u
#define CLINT_MTIME_HI 0xbffcu

#define CLINT_MSIP_PENDING 0x1u

uint64_t clint_time(void);
void clint_set_compare(uint64_t value);
void clint_set_software_irq(unsigned int pending);
#endif
