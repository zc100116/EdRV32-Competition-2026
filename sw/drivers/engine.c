/* File: engine.c
 * Spec: SoC 6.1, 7.1–7.4; mem-subsys 4.1
 * Description: B2 engine operations; caller owns buffer lifetime and valid configuration.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "engine.h"
#include "plic.h"
#include "cache.h"

struct engine_registers {
    uintptr_t base;
    uint32_t control;
    uint32_t status;
    uint32_t irq_enable;
    uint32_t irq_status;
    uint32_t error;
    uint32_t done;
    uint32_t perf[16];
    unsigned int source;
};
static const struct engine_registers registers[] = {
    { EDRV32_VIN_BASE, EDRV32_VIN_CTRL_OFFSET, EDRV32_VIN_STATUS_OFFSET,
      EDRV32_VIN_IRQ_EN_OFFSET, EDRV32_VIN_IRQ_STAT_OFFSET,
      EDRV32_VIN_ERR_CODE_OFFSET, EDRV32_VIN_DONE_COUNT_OFFSET,
      { EDRV32_VIN_PERF_OFFSET(0), EDRV32_VIN_PERF_OFFSET(1),
        EDRV32_VIN_PERF_OFFSET(2), EDRV32_VIN_PERF_OFFSET(3),
        EDRV32_VIN_PERF_OFFSET(4), EDRV32_VIN_PERF_OFFSET(5),
        EDRV32_VIN_PERF_OFFSET(6), EDRV32_VIN_PERF_OFFSET(7),
        EDRV32_VIN_PERF_OFFSET(8), EDRV32_VIN_PERF_OFFSET(9),
        EDRV32_VIN_PERF_OFFSET(10), EDRV32_VIN_PERF_OFFSET(11),
        EDRV32_VIN_PERF_OFFSET(12), EDRV32_VIN_PERF_OFFSET(13),
        EDRV32_VIN_PERF_OFFSET(14), EDRV32_VIN_PERF_OFFSET(15) },
      EDRV32_PLIC_SOURCE_VIN },
    { EDRV32_PIX_BASE, EDRV32_PIX_CTRL_OFFSET, EDRV32_PIX_STATUS_OFFSET,
      EDRV32_PIX_IRQ_EN_OFFSET, EDRV32_PIX_IRQ_STAT_OFFSET,
      EDRV32_PIX_ERR_CODE_OFFSET, EDRV32_PIX_DONE_COUNT_OFFSET,
      { EDRV32_PIX_PERF_OFFSET(0), EDRV32_PIX_PERF_OFFSET(1),
        EDRV32_PIX_PERF_OFFSET(2), EDRV32_PIX_PERF_OFFSET(3),
        EDRV32_PIX_PERF_OFFSET(4), EDRV32_PIX_PERF_OFFSET(5),
        EDRV32_PIX_PERF_OFFSET(6), EDRV32_PIX_PERF_OFFSET(7),
        EDRV32_PIX_PERF_OFFSET(8), EDRV32_PIX_PERF_OFFSET(9),
        EDRV32_PIX_PERF_OFFSET(10), EDRV32_PIX_PERF_OFFSET(11),
        EDRV32_PIX_PERF_OFFSET(12), EDRV32_PIX_PERF_OFFSET(13),
        EDRV32_PIX_PERF_OFFSET(14), EDRV32_PIX_PERF_OFFSET(15) },
      EDRV32_PLIC_SOURCE_PIX },
    { EDRV32_GEO_BASE, EDRV32_GEO_CTRL_OFFSET, EDRV32_GEO_STATUS_OFFSET,
      EDRV32_GEO_IRQ_EN_OFFSET, EDRV32_GEO_IRQ_STAT_OFFSET,
      EDRV32_GEO_ERR_CODE_OFFSET, EDRV32_GEO_DONE_COUNT_OFFSET,
      { EDRV32_GEO_PERF_OFFSET(0), EDRV32_GEO_PERF_OFFSET(1),
        EDRV32_GEO_PERF_OFFSET(2), EDRV32_GEO_PERF_OFFSET(3),
        EDRV32_GEO_PERF_OFFSET(4), EDRV32_GEO_PERF_OFFSET(5),
        EDRV32_GEO_PERF_OFFSET(6), EDRV32_GEO_PERF_OFFSET(7),
        EDRV32_GEO_PERF_OFFSET(8), EDRV32_GEO_PERF_OFFSET(9),
        EDRV32_GEO_PERF_OFFSET(10), EDRV32_GEO_PERF_OFFSET(11),
        EDRV32_GEO_PERF_OFFSET(12), EDRV32_GEO_PERF_OFFSET(13),
        EDRV32_GEO_PERF_OFFSET(14), EDRV32_GEO_PERF_OFFSET(15) },
      EDRV32_PLIC_SOURCE_GEO },
    { EDRV32_DISP_BASE, EDRV32_DISP_CTRL_OFFSET, EDRV32_DISP_STATUS_OFFSET,
      EDRV32_DISP_IRQ_EN_OFFSET, EDRV32_DISP_IRQ_STAT_OFFSET,
      EDRV32_DISP_ERR_CODE_OFFSET, EDRV32_DISP_DONE_COUNT_OFFSET,
      { EDRV32_DISP_PERF_OFFSET(0), EDRV32_DISP_PERF_OFFSET(1),
        EDRV32_DISP_PERF_OFFSET(2), EDRV32_DISP_PERF_OFFSET(3),
        EDRV32_DISP_PERF_OFFSET(4), EDRV32_DISP_PERF_OFFSET(5),
        EDRV32_DISP_PERF_OFFSET(6), EDRV32_DISP_PERF_OFFSET(7),
        EDRV32_DISP_PERF_OFFSET(8), EDRV32_DISP_PERF_OFFSET(9),
        EDRV32_DISP_PERF_OFFSET(10), EDRV32_DISP_PERF_OFFSET(11),
        EDRV32_DISP_PERF_OFFSET(12), EDRV32_DISP_PERF_OFFSET(13),
        EDRV32_DISP_PERF_OFFSET(14), EDRV32_DISP_PERF_OFFSET(15) },
      EDRV32_PLIC_SOURCE_DISP },
    { EDRV32_NPU_BASE, EDRV32_NPU_CTRL_OFFSET, EDRV32_NPU_STATUS_OFFSET,
      EDRV32_NPU_IRQ_EN_OFFSET, EDRV32_NPU_IRQ_STAT_OFFSET,
      EDRV32_NPU_ERR_CODE_OFFSET, EDRV32_NPU_DONE_COUNT_OFFSET,
      { EDRV32_NPU_PERF_OFFSET(0), EDRV32_NPU_PERF_OFFSET(1),
        EDRV32_NPU_PERF_OFFSET(2), EDRV32_NPU_PERF_OFFSET(3),
        EDRV32_NPU_PERF_OFFSET(4), EDRV32_NPU_PERF_OFFSET(5),
        EDRV32_NPU_PERF_OFFSET(6), EDRV32_NPU_PERF_OFFSET(7),
        EDRV32_NPU_PERF_OFFSET(8), EDRV32_NPU_PERF_OFFSET(9),
        EDRV32_NPU_PERF_OFFSET(10), EDRV32_NPU_PERF_OFFSET(11),
        EDRV32_NPU_PERF_OFFSET(12), EDRV32_NPU_PERF_OFFSET(13),
        EDRV32_NPU_PERF_OFFSET(14), EDRV32_NPU_PERF_OFFSET(15) },
      EDRV32_PLIC_SOURCE_NPU },
    { EDRV32_ETH_BASE, EDRV32_ETH_CTRL_OFFSET, EDRV32_ETH_STATUS_OFFSET,
      EDRV32_ETH_IRQ_EN_OFFSET, EDRV32_ETH_IRQ_STAT_OFFSET,
      EDRV32_ETH_ERR_CODE_OFFSET, EDRV32_ETH_DONE_COUNT_OFFSET,
      { EDRV32_ETH_PERF_OFFSET(0), EDRV32_ETH_PERF_OFFSET(1),
        EDRV32_ETH_PERF_OFFSET(2), EDRV32_ETH_PERF_OFFSET(3),
        EDRV32_ETH_PERF_OFFSET(4), EDRV32_ETH_PERF_OFFSET(5),
        EDRV32_ETH_PERF_OFFSET(6), EDRV32_ETH_PERF_OFFSET(7),
        EDRV32_ETH_PERF_OFFSET(8), EDRV32_ETH_PERF_OFFSET(9),
        EDRV32_ETH_PERF_OFFSET(10), EDRV32_ETH_PERF_OFFSET(11),
        EDRV32_ETH_PERF_OFFSET(12), EDRV32_ETH_PERF_OFFSET(13),
        EDRV32_ETH_PERF_OFFSET(14), EDRV32_ETH_PERF_OFFSET(15) },
      EDRV32_PLIC_SOURCE_ETH },
    { EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_CTRL_OFFSET, EDRV32_MEM_XBAR_STATUS_OFFSET,
      EDRV32_MEM_XBAR_IRQ_EN_OFFSET, EDRV32_MEM_XBAR_IRQ_STAT_OFFSET,
      EDRV32_MEM_XBAR_ERR_CODE_OFFSET, EDRV32_MEM_XBAR_DONE_COUNT_OFFSET,
      { EDRV32_MEM_XBAR_PERF_OFFSET(0), EDRV32_MEM_XBAR_PERF_OFFSET(1),
        EDRV32_MEM_XBAR_PERF_OFFSET(2), EDRV32_MEM_XBAR_PERF_OFFSET(3),
        EDRV32_MEM_XBAR_PERF_OFFSET(4), EDRV32_MEM_XBAR_PERF_OFFSET(5),
        EDRV32_MEM_XBAR_PERF_OFFSET(6), EDRV32_MEM_XBAR_PERF_OFFSET(7),
        EDRV32_MEM_XBAR_PERF_OFFSET(8), EDRV32_MEM_XBAR_PERF_OFFSET(9),
        EDRV32_MEM_XBAR_PERF_OFFSET(10), EDRV32_MEM_XBAR_PERF_OFFSET(11),
        EDRV32_MEM_XBAR_PERF_OFFSET(12), EDRV32_MEM_XBAR_PERF_OFFSET(13),
        EDRV32_MEM_XBAR_PERF_OFFSET(14), EDRV32_MEM_XBAR_PERF_OFFSET(15) },
      EDRV32_PLIC_SOURCE_MEM_XBAR },
};
struct irq_registration {
    enum engine_id engine;
    engine_irq_callback callback;
    void *context;
};
static struct irq_registration registration[16];

/* SoC 7.1: forward the specified control command without implicit reset/recovery. */
void engine_control(enum engine_id engine, uint32_t control)
{
    const struct engine_registers *r = &registers[engine];
    mmio_write32(r->base + r->control, control);
}

/* SoC 7.1: capture error information before any RW1C acknowledgement. */
struct engine_event engine_poll(enum engine_id engine)
{
    const struct engine_registers *r = &registers[engine];
    struct engine_event event;
    event.irq = mmio_read32(r->base + r->irq_status);
    event.status = mmio_read32(r->base + r->status);
    event.error = mmio_read32(r->base + r->error);
    event.done_count = mmio_read32(r->base + r->done);
    return event;
}

/* SoC 7.1: acknowledge the captured peripheral flags before PLIC completion. */
void engine_irq_clear(enum engine_id engine, uint32_t mask)
{
    const struct engine_registers *r = &registers[engine];
    mmio_write32(r->base + r->irq_status, mask);
}

/* SoC 7.1: module-specific counter meanings are preserved. */
uint32_t engine_perf(enum engine_id engine, unsigned int counter)
{
    const struct engine_registers *r = &registers[engine];
    return mmio_read32(r->base + r->perf[counter]);
}

/* SoC 6.1: caller registers each enabled source before enabling machine external IRQs. */
void engine_irq_register(enum engine_id engine, uint32_t mask, unsigned int priority,
                         engine_irq_callback callback, void *context)
{
    const struct engine_registers *r = &registers[engine];
    registration[r->source] = (struct irq_registration){engine, callback, context};
    mmio_write32(r->base + r->irq_enable, mask);
    plic_set_priority(r->source, priority);
    plic_set_enable(mmio_read32(EDRV32_PLIC_BASE + PLIC_ENABLE) | (1u << r->source));
}

/* SoC 6.1, 7.1: only registered media sources are passed by the application's dispatcher. */
void engine_irq_handle(unsigned int source)
{
    const struct irq_registration *r = &registration[source];
    struct engine_event event = engine_poll(r->engine);
    /* MEM 4.1: error detail registers clear with ERROR; callback reads them first. */
    r->callback(&event, r->context);
    engine_irq_clear(r->engine, event.irq);
}

/* SoC 6.1: source zero is the specified no-pending-interrupt result. */
unsigned int engine_irq_dispatch(void)
{
    unsigned int source = plic_claim();
    if (source != EDRV32_PLIC_SOURCE_NONE) {
        engine_irq_handle(source);
        plic_complete(source);
    }
    return source;
}

/* SoC 7.3: caller supplies the containing ring and its allocation spacing. */
unsigned int surface_ring_slot(uint32_t base, uint32_t ring_base, uint32_t slot_bytes)
{
    return (base - ring_base) / slot_bytes;
}

/* SoC 7.4: use only BSP cache maintenance for CPU-to-engine transfers. */
void engine_dma_clean(uintptr_t cached_address, uint32_t bytes)
{
    cache_clean(cached_address, bytes);
}

/* SoC 7.4: call only after engine writes complete and before CPU cached reads. */
void engine_dma_invalidate(uintptr_t cached_address, uint32_t bytes)
{
    cache_invalidate(cached_address, bytes);
}
