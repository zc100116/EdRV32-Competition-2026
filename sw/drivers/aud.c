/* File: aud.c
 * Spec: aud-spec 2.1-2.2, 4-6; visual SoC 7.4.
 * Description: Ring wrap, cache publication and LOW interrupt refill.
 * Clock domain: clk_sys CPU; registers in clk_mem, playback in clk_aud.
 */
#include "aud.h"
#include "cache.h"
#include "plic.h"

static aud_refill refill_callback;
static void *refill_context;

static uint32_t read_reg(uint32_t offset)
{
    return *(volatile uint32_t *)(uintptr_t)(EDRV32_AUD_BASE + offset);
}

static void write_reg(uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(uintptr_t)(EDRV32_AUD_BASE + offset) = value;
}

void aud_init(struct aud_ring *ring, uint32_t *samples, uint32_t bytes, uint32_t low_level)
{
    uintptr_t address = (uintptr_t)samples;
    *ring = (struct aud_ring){samples, bytes, 0u};
    write_reg(EDRV32_AUD_RING_BASE_OFFSET,
              (uint32_t)(address - (address >= EDRV32_DDR_UNCACHED_BASE ?
                                   EDRV32_DDR_UNCACHED_BASE : EDRV32_DDR_BASE)));
    write_reg(EDRV32_AUD_RING_SIZE_OFFSET, bytes);
    write_reg(EDRV32_AUD_WR_PTR_OFFSET, 0u);
    write_reg(EDRV32_AUD_LOW_LEVEL_OFFSET, low_level);
}

uint32_t aud_space(const struct aud_ring *ring)
{
    uint32_t rd = read_reg(EDRV32_AUD_RD_PTR_OFFSET);
    return (rd + ring->bytes - ring->write_offset - 32u) % ring->bytes;
}

void aud_write(struct aud_ring *ring, const uint32_t *samples, uint32_t frames)
{
    uint32_t bytes = frames * 4u;
    uint32_t first = ring->bytes - ring->write_offset;
    if (first > bytes) {
        first = bytes;
    }
    for (uint32_t i = 0; i < first / 4u; ++i) {
        ring->samples[ring->write_offset / 4u + i] = samples[i];
    }
    for (uint32_t i = 0; i < (bytes - first) / 4u; ++i) {
        ring->samples[i] = samples[first / 4u + i];
    }
    /* SoC 7.4: publish both sides of a wrapped write before advancing WR_PTR. */
    if ((uintptr_t)ring->samples < EDRV32_DDR_UNCACHED_BASE) {
        cache_clean((uintptr_t)ring->samples + ring->write_offset, first);
        if (bytes != first) {
            cache_clean((uintptr_t)ring->samples, bytes - first);
        }
    }
    ring->write_offset = (ring->write_offset + bytes) % ring->bytes;
    write_reg(EDRV32_AUD_WR_PTR_OFFSET, ring->write_offset);
}

void aud_enable(unsigned int enable)
{
    write_reg(EDRV32_AUD_CTRL_OFFSET, enable ? EDRV32_AUD_CTRL_ENABLE_MASK : 0u);
}

uint32_t aud_underruns(void)
{
    return read_reg(EDRV32_AUD_UNDERRUN_CNT_OFFSET);
}

struct aud_event aud_status(void)
{
    return (struct aud_event){read_reg(EDRV32_AUD_IRQ_STAT_OFFSET),
                             read_reg(EDRV32_AUD_ERR_CODE_OFFSET), aud_underruns()};
}

void aud_irq_register(unsigned int priority, aud_refill refill, void *context)
{
    refill_callback = refill;
    refill_context = context;
    /* Generated common bit8 is named RX_NOTIFY0; AUD assigns it LOW (aud-spec 4). */
    write_reg(EDRV32_AUD_IRQ_EN_OFFSET,
              EDRV32_AUD_IRQ_EN_RX_NOTIFY0_MASK | EDRV32_AUD_IRQ_EN_ERROR_MASK);
    plic_set_priority(EDRV32_PLIC_SOURCE_AUD, priority);
    plic_set_enable(*(volatile uint32_t *)(uintptr_t)(EDRV32_PLIC_BASE + PLIC_ENABLE) |
                    (1u << EDRV32_PLIC_SOURCE_AUD));
}

struct aud_event aud_irq_handle(struct aud_ring *ring)
{
    struct aud_event event = aud_status();
    write_reg(EDRV32_AUD_IRQ_STAT_OFFSET, event.irq);
    if ((event.irq & EDRV32_AUD_IRQ_STAT_ERROR_MASK) == 0u &&
        (event.irq & EDRV32_AUD_IRQ_STAT_RX_NOTIFY0_MASK) != 0u) {
        refill_callback(ring, &event, refill_context);
    }
    return event;
}
