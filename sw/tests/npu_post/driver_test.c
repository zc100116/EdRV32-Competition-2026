/* driver_test.c — npu-spec 4, SoC 7.4.4/5.
 * Observe MMIO/cache ordering and complete cache-line ranges, including zero candidates.
 * Clock domain: host CPU.
 */
#include "npu.h"
#include <assert.h>
#include <stdio.h>
static unsigned released;
static unsigned writes;
static unsigned invalidations;
static uint32_t count;
static uint32_t selected;
static const uint32_t offsets[] = {EDRV32_NPU_POST_CTRL_OFFSET,
    EDRV32_NPU_POST_INT8_TH0_OFFSET, EDRV32_NPU_POST_INT8_TH1_OFFSET,
    EDRV32_NPU_POST_INT8_TH2_OFFSET, EDRV32_NPU_POST_PROB_TH_OFFSET};
static const uint32_t values[] = {1, 103, 105, 103, 4194304};
uint32_t mmio_read32(uintptr_t address)
{
    if (address == EDRV32_NPU_BASE + EDRV32_NPU_POST_COUNT_OFFSET) return count;
    assert(address == EDRV32_NPU_BASE + EDRV32_NPU_POST_STATUS_OFFSET);
    return 1;
}
void mmio_write32(uintptr_t address, uint32_t value)
{
    if (writes < 5) {
        assert(address == EDRV32_NPU_BASE + offsets[writes]);
        assert(value == values[writes]);
    } else if (address == EDRV32_NPU_BASE + EDRV32_NPU_POST_BASE_OFFSET) {
        assert(released);
        selected = value;
    } else if (address == EDRV32_NPU_BASE + EDRV32_NPU_DOORBELL_OFFSET) {
        assert(released && selected == 0x05200000u && value == 1);
    }
    ++writes;
}
void engine_dma_clean(uintptr_t address, uint32_t bytes)
{
    assert(address == EDRV32_DDR_BASE + 0x05200000u && bytes == 120960);
    released = 1;
}
void engine_dma_invalidate(uintptr_t address, uint32_t bytes)
{
    assert(address == EDRV32_DDR_BASE + selected);
    assert(bytes == ((count * 24 + 31) & ~31u));
    ++invalidations;
}
int main(void)
{
    npu_post_configure();
    npu_post_start(0x04000000, 0x05000000, 0x05200000);
    assert(writes == 9 && npu_post_status() == 1);
    for (count = 1; count <= 5040; ++count) assert(npu_post_acquire(selected) == count);
    count = 0;
    assert(npu_post_acquire(selected) == 0 && invalidations == 5040);
    puts("PASS POST defaults, clean before DOORBELL, invalidate 1..5040 counts and zero");
}
