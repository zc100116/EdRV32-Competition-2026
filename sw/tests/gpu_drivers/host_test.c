/* File: host_test.c
 * Spec: GPU 2.2, 2.9, 5; AUD 2.2, 4; visual SoC 7.4.
 * Description: Test actual drivers against mapped MMIO with observable cache/I2C hooks.
 * Clock domain: host; no RTL simulation.
 */
#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include "gpu.h"
#include "aud.h"
#include "es8156.h"
#include "i2c.h"
#include "plic.h"
#include "cache.h"

static uint32_t cache_clean_count;
static uint32_t cache_invalidate_count;
static uintptr_t last_address;
static uint32_t last_bytes;
static uint32_t i2c_index;
static uint32_t low_callbacks;
static const uint16_t codec[] = {
    0x1000, 0x003c, 0x0005, 0x001c, 0x0204, 0x0301, 0x0400, 0x0508, 0x0600,
    0x082b, 0x1300, 0x202a, 0x213c, 0x2202, 0x2407, 0x233a, 0x0a01, 0x0b01,
    0x14bd, 0x0121, 0x0d14, 0x1800, 0x082f, 0x2520, 0x0002, 0x0003, 0x1130
};
void cache_clean(uintptr_t address, uint32_t bytes)
{
    cache_clean_count++;
    last_address = address;
    last_bytes = bytes;
}
void cache_invalidate(uintptr_t address, uint32_t bytes)
{
    cache_invalidate_count++;
    last_address = address;
    last_bytes = bytes;
}
void cache_clean_invalidate(uintptr_t address, uint32_t bytes)
{
    (void)address;
    (void)bytes;
    abort();
}
void cache_clean_all(void) { abort(); }
void plic_set_priority(unsigned int source, unsigned int priority)
{
    assert((source == EDRV32_PLIC_SOURCE_GPU || source == EDRV32_PLIC_SOURCE_AUD) &&
           priority == 1u);
}
void plic_set_enable(uint32_t value) { (void)value; }
void i2c_init(unsigned int port, uint32_t clock, uint32_t scl)
{
    assert(port == 0u && clock == EDRV32_CLK_SYS_HZ && scl == 100000u);
}
int i2c_command(uint32_t value)
{
    unsigned int index = i2c_index / 3u;
    uint32_t expected;
    assert(index < sizeof(codec) / sizeof(codec[0]));
    switch (i2c_index % 3u) {
    case 0: expected = I2C_CMD_START | 0x12u; break;
    case 1: expected = codec[index] >> 8; break;
    default: expected = I2C_CMD_STOP | (codec[index] & 255u); break;
    }
    assert(value == expected);
    i2c_index++;
    return 0;
}
static void map(uintptr_t address, size_t bytes)
{
    assert(mmap((void *)address, bytes, PROT_READ | PROT_WRITE,
                MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) == (void *)address);
}
static void refill(struct aud_ring *ring, const struct aud_event *event, void *context)
{
    (void)ring;
    (void)context;
    assert(event->error == 0u);
    low_callbacks++;
}
int main(void)
{
    map(EDRV32_MEDIA_APB_BASE, 65536u);
    map(EDRV32_DDR_BASE, 65536u);
    map(EDRV32_PLIC_BASE, 65536u);
    struct gpu_command *commands = (void *)(uintptr_t)EDRV32_DDR_BASE;
    gpu_resolve(commands, &(struct gpu_resolve_args){
        .base = 0x100000u, .stride = 1280u, .y0 = 180u, .x1 = 640u, .y1 = 360u
    });
    assert(commands->word[0] == 0x40u && commands->word[2] == 0x100000u);
    assert(commands->word[3] == 1280u && commands->word[4] == 0x00b40000u);
    assert(commands->word[5] == 0x01680280u && commands->word[7] == 0u);
    struct gpu_range source = {EDRV32_DDR_BASE + 512u, 64u};
    struct gpu_range result = {EDRV32_DDR_BASE + 1024u, 32u};
    struct gpu_batch batch = {commands, 1u, &source, 1u, &result, 1u};
    gpu_submit(&batch);
    assert(cache_clean_count == 2u && last_address == source.address && last_bytes == 64u);
    assert(mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_DESC_BASE_OFFSET) == 0u);
    assert(mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_DESC_COUNT_OFFSET) == 1u);
    assert(mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_DOORBELL_OFFSET) == 1u);
    mmio_write32(EDRV32_GPU_BASE + EDRV32_GPU_STATUS_OFFSET, EDRV32_GPU_STATUS_IDLE_MASK);
    mmio_write32(EDRV32_GPU_BASE + EDRV32_GPU_IRQ_STAT_OFFSET, EDRV32_GPU_IRQ_STAT_ERROR_MASK);
    mmio_write32(EDRV32_GPU_BASE + EDRV32_GPU_ERR_CODE_OFFSET, 2u);
    struct gpu_event event = gpu_wait();
    assert(event.error == 2u && cache_invalidate_count == 1u && last_bytes == 32u);
    assert(last_address == result.address);
    assert(gpu_hit_object(0x05012345u) == 0x12345u && gpu_hit_target(0x05012345u) == 5u);
    assert(gpu_free_object(0x00123456u) == 0x123456u);
    assert(gpu_physical((void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + 512u)) == 512u);

    struct aud_ring ring;
    uint32_t samples[16];
    for (uint32_t i = 0; i < 16u; ++i) samples[i] = 0x10001000u + i;
    aud_init(&ring, (void *)(uintptr_t)(EDRV32_DDR_BASE + 4096u), 512u, 128u);
    assert(aud_space(&ring) == 480u);
    ring.write_offset = 480u;
    cache_clean_count = 0u;
    aud_write(&ring, samples, 16u);
    assert(ring.write_offset == 32u && cache_clean_count == 2u);
    for (uint32_t i = 0; i < 8u; ++i) {
        assert(ring.samples[120u+i] == samples[i]);
        assert(ring.samples[i] == samples[8u+i]);
    }
    assert(mmio_read32(EDRV32_AUD_BASE + EDRV32_AUD_WR_PTR_OFFSET) == 32u);
    aud_irq_register(1u, refill, NULL);
    mmio_write32(EDRV32_AUD_BASE + EDRV32_AUD_IRQ_STAT_OFFSET,
                 EDRV32_AUD_IRQ_STAT_RX_NOTIFY0_MASK);
    assert(aud_irq_handle(&ring).irq == EDRV32_AUD_IRQ_STAT_RX_NOTIFY0_MASK);
    assert(low_callbacks == 1u);
    assert(es8156_init() == 0 && i2c_index == 81u);
    puts("PASS GPU/AUD cache, ring wrap, error propagation and ES8156 sequence");
    return 0;
}
