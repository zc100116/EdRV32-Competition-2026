/* File: aud.h
 * Spec: aud-spec 2.1-2.2, 4-6; visual SoC 7.4.
 * Description: DDR ring producer and LOW interrupt refill service.
 * Clock domain: clk_sys CPU; registers in clk_mem, playback in clk_aud.
 */
#ifndef EDRV32_AUD_H
#define EDRV32_AUD_H
#include <stdint.h>
#include "gpu_soc_map.h"
#include "regs/aud_regs.h"

struct aud_ring {
    uint32_t *samples; /* DDR CPU alias, 512 B aligned. */
    uint32_t bytes; /* 512 B multiple. */
    uint32_t write_offset;
};
struct aud_event { uint32_t irq; uint32_t error; uint32_t underruns; };
/* Refill callback writes at most the free space reported by aud_space(). */
typedef void (*aud_refill)(struct aud_ring *ring, const struct aud_event *event, void *context);
/* Initialize only while disabled, after the previous disable has drained RD_PTR to zero. */
void aud_init(struct aud_ring *ring, uint32_t *samples, uint32_t bytes, uint32_t low_level);
uint32_t aud_space(const struct aud_ring *ring);
/* frames is a multiple of 8; caller reserves at least 32 B between WR_PTR and RD_PTR. */
void aud_write(struct aud_ring *ring, const uint32_t *samples, uint32_t frames);
void aud_enable(unsigned int enable);
uint32_t aud_underruns(void);
struct aud_event aud_status(void);
void aud_irq_register(unsigned int priority, aud_refill refill, void *context);
/* Application handles PLIC claim/complete for source 8. */
struct aud_event aud_irq_handle(struct aud_ring *ring);
#endif
