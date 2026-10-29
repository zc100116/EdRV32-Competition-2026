/* File: host_runtime.c
 * Spec: rnd 4–6, DISP 4.2/5.3; Task B3-3a.
 * Description: Check actual driver ownership/cache sequencing against mapped register words.
 * Clock domain: host; no RTL or SoC simulation.
 */
#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <sys/mman.h>
#include "rnd.h"
#include "disp.h"
#include "plic.h"

static unsigned int cleaned;
static unsigned int invalidated;
static unsigned int callbacks;
static const uintptr_t command_address = 0x90001000;
static const struct rnd_range sources[] = {{(void *)0x90002000, 96}, {(void *)0x90003000, 64}};
static const struct rnd_range targets[] = {{(void *)0x90004000, 160}};

static void map_registers(uintptr_t address, size_t bytes)
{
    void *mapped = mmap((void *)address, bytes, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    assert(mapped == (void *)address);
}

/* These stubs check only BSP calls: no cache hardware is modeled. */
void cache_clean(uintptr_t address, uint32_t bytes)
{
    assert(mmio_read32(EDRV32_RND_BASE + EDRV32_RND_DOORBELL_OFFSET) == 0);
    if (cleaned == 0) {
        assert(address == command_address && bytes == 128);
    } else {
        assert(address == (uintptr_t)sources[cleaned - 1].address);
        assert(bytes == sources[cleaned - 1].bytes);
    }
    ++cleaned;
}

void cache_invalidate(uintptr_t address, uint32_t bytes)
{
    assert(!(mmio_read32(EDRV32_RND_BASE + EDRV32_RND_STATUS_OFFSET) &
             EDRV32_RND_STATUS_BUSY_MASK));
    assert(address == (uintptr_t)targets[0].address && bytes == targets[0].bytes);
    ++invalidated;
}

static void callback(const struct rnd_result *result, void *context)
{
    assert(context == &callbacks);
    assert(result->irq == EDRV32_RND_IRQ_STAT_ERROR_MASK);
    assert(result->error == 3 && result->cur_desc == 1);
    assert(invalidated == 1);
    assert(mmio_read32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET) == result->irq);
    ++callbacks;
}

static void submit(void)
{
    cleaned = 0;
    invalidated = 0;
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_DOORBELL_OFFSET, 0);
    const struct rnd_batch batch = {(const struct rnd_command *)command_address, 2,
                                    sources, 2, targets, 1};
    rnd_submit(&batch);
    assert(cleaned == 3);
    assert(mmio_read32(EDRV32_RND_BASE + EDRV32_RND_DESC_BASE_OFFSET) == 0x10001000);
    assert(mmio_read32(EDRV32_RND_BASE + EDRV32_RND_DESC_COUNT_OFFSET) == 2);
    assert(mmio_read32(EDRV32_RND_BASE + EDRV32_RND_DOORBELL_OFFSET) == 1);
}

int main(void)
{
    map_registers(EDRV32_RND_BASE, 0x2000);
    map_registers(EDRV32_PLIC_BASE, PLIC_CLAIM + 0x1000);
    assert(rnd_physical((void *)0x91234560) == 0x11234560);
    assert(rnd_physical((void *)0xd1234560) == 0x11234560);
    submit();
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET, EDRV32_RND_IRQ_STAT_DONE_MASK);
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_CUR_DESC_OFFSET, 2);
    struct rnd_result result = rnd_wait();
    assert(result.error == 0 && result.cur_desc == 2);
    assert(result.irq == EDRV32_RND_IRQ_STAT_DONE_MASK && invalidated == 1);

    /* Error is captured before RW1C; the fake word records the acknowledgement write. */
    submit();
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET, EDRV32_RND_IRQ_STAT_ERROR_MASK);
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_ERR_CODE_OFFSET, 2);
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_CUR_DESC_OFFSET, 1);
    result = rnd_wait();
    assert(result.error == 2 && result.cur_desc == 1 && invalidated == 1);

    submit();
    mmio_write32(EDRV32_PLIC_BASE + PLIC_ENABLE, 1u << EDRV32_PLIC_SOURCE_DISP);
    rnd_irq_register(3, callback, &callbacks);
    assert(mmio_read32(EDRV32_PLIC_BASE + PLIC_ENABLE) ==
           ((1u << EDRV32_PLIC_SOURCE_DISP) | (1u << EDRV32_PLIC_SOURCE_RND)));
    assert(mmio_read32(EDRV32_PLIC_BASE + PLIC_PRIORITY +
                       4u * EDRV32_PLIC_SOURCE_RND) == 3);
    assert(mmio_read32(EDRV32_RND_BASE + EDRV32_RND_IRQ_EN_OFFSET) == 3);
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_ERR_CODE_OFFSET, 3);
    rnd_irq_handle();
    assert(callbacks == 1 && invalidated == 1);

    submit();
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET, 0);
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_ERR_CODE_OFFSET, 0);
    result = rnd_abort();
    assert(mmio_read32(EDRV32_RND_BASE + EDRV32_RND_CTRL_OFFSET) ==
           EDRV32_RND_CTRL_ABORT_MASK);
    assert(result.error == 0 && result.irq == 0 && invalidated == 1);

    disp_submit(DISP_L0, 0x100000, 2592);
    disp_submit(DISP_L1, 0x200000, 5120);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_NEXT_BASE_OFFSET) == 0x100000);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_STRIDE_OFFSET) == 2592);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_L1_NEXT_BASE_OFFSET) == 0x200000);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_L1_STRIDE_OFFSET) == 5120);
    disp_layer_enable(DISP_L0, 1);
    disp_layer_enable(DISP_L1, 1);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_LAYER_CTRL_OFFSET) == 3);
    disp_layer_enable(DISP_L1, 0);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_LAYER_CTRL_OFFSET) == 1);
    disp_l0_scroll(19, 7);
    disp_l1_geometry(16, 25, 320, 160, 127);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_L0_SCROLL_OFFSET) == 0x00070013);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_L1_POS_OFFSET) == 0x00190010);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_L1_SIZE_OFFSET) == 0x00a00140);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_L1_OPA_OFFSET) == 127);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_CUR_BASE_OFFSET, 0x300000);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_L1_CUR_BASE_OFFSET, 0x400000);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_REL_BASE_OFFSET, 0x500000);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_L1_REL_BASE_OFFSET, 0x600000);
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_IRQ_STAT_OFFSET,
                 EDRV32_DISP_IRQ_STAT_SWITCH1_MASK);
    assert(disp_current(DISP_L0) == 0x300000 && disp_current(DISP_L1) == 0x400000);
    assert(disp_released(DISP_L0) == 0x500000 && disp_released(DISP_L1) == 0x600000);
    assert(!disp_switched(DISP_L0) && disp_switched(DISP_L1));
    puts("PASS RND cache/submit/poll/error/IRQ/abort and DISP two-layer registers");
    return 0;
}
