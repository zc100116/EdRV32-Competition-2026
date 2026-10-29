/* File: engine.h
 * Spec: edrv32-soc-spec 6.1, 7.1–7.4
 * Description: B2 media engine software interface.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_ENGINE_H
#define EDRV32_ENGINE_H
#include <stdint.h>
#include <stddef.h>
#include "mmio.h"
#include "regs/vin_regs.h"
#include "regs/pix_regs.h"
#include "regs/geo_regs.h"
#include "regs/disp_regs.h"
#include "regs/npu_regs.h"
#include "regs/eth_regs.h"
#include "regs/mem_xbar_regs.h"
#include "regs/perf_mon_regs.h"

enum engine_id {
    ENGINE_VIN, ENGINE_PIX, ENGINE_GEO, ENGINE_DISP, ENGINE_NPU,
    ENGINE_ETH, ENGINE_MEM_XBAR, ENGINE_PERF_MON
};
struct engine_event {
    uint32_t irq;
    uint32_t status;
    uint32_t error;
    uint32_t done_count;
};
typedef void (*engine_irq_callback)(const struct engine_event *event, void *context);
/* SoC 7.1: write the engine CTRL word (generated CTRL masks). */
void engine_control(enum engine_id engine, uint32_t control);
/* SoC 7.1: read status, sticky IRQ, error code and completion count without clearing. */
struct engine_event engine_poll(enum engine_id engine);
/* SoC 7.1: acknowledge exactly the caller's RW1C IRQ mask. */
void engine_irq_clear(enum engine_id engine, uint32_t mask);
/* SoC 7.1: read the module-defined performance counter. */
uint32_t engine_perf(enum engine_id engine, unsigned int counter);
/* SoC 6.1: register callback, set engine IRQ mask and enable its PLIC source at priority. */
void engine_irq_register(enum engine_id engine, uint32_t mask, unsigned int priority,
                         engine_irq_callback callback, void *context);
/* SoC 6.1: service an already claimed source, snapshot/clear IRQ then invoke callback. */
void engine_irq_handle(unsigned int source);
/* SoC 6.1: claim one pending PLIC source, service it, then complete; 0 means none. */
unsigned int engine_irq_dispatch(void);
/* SoC 7.3: map a Surface physical address to its slot in an equally spaced ring. */
unsigned int surface_ring_slot(uint32_t base, uint32_t ring_base, uint32_t slot_bytes);
/* SoC 7.4: clean a CPU cached range before DMA reads (BSP interface). */
void engine_dma_clean(uintptr_t cached_address, uint32_t bytes);
/* SoC 7.4: invalidate a CPU cached range after DMA writes (BSP interface). */
void engine_dma_invalidate(uintptr_t cached_address, uint32_t bytes);
#endif
