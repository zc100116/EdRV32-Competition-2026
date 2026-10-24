/* ============================================================================
 * File        : edrv32_mmio.h
 * Author      : Edward ZC
 * Description : Ordered 32-bit MMIO access helpers for EdRV32 software.
 * Notes       : RV32 only; callers must use naturally aligned addresses.
 * ========================================================================== */
#ifndef EDRV32_MMIO_H
#define EDRV32_MMIO_H

static inline void edrv32_mmio_write32(unsigned int address,
                                       unsigned int value)
{
    *(volatile unsigned int *)address = value;
    __asm__ __volatile__("" ::: "memory");
}

static inline unsigned int edrv32_mmio_read32(unsigned int address)
{
    unsigned int value;

    value = *(volatile unsigned int *)address;
    __asm__ __volatile__("" ::: "memory");
    return value;
}

static inline void edrv32_mmio_fence(void)
{
    __asm__ __volatile__("fence iorw, iorw" ::: "memory");
}

#endif /* EDRV32_MMIO_H */
