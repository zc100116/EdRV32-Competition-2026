/* File: main.c
 * Spec: gpu-soc-testplan ST-12; aud-spec 2, 4-6.
 * Description: Stream sine-left/square-right samples, refill on PLIC LOW interrupts.
 * Clock domain: clk_sys software; observed I2S clk_aud and I2C0 port 0.
 */
#include "../gpu_drivers/test.h"
#include "aud.h"
#include "es8156.h"

static struct aud_ring ring;
static volatile uint32_t supplied;
static volatile uint32_t low_count;
static const int16_t sine[32] = {
    0, 1951, 3827, 5556, 7071, 8315, 9239, 9808,
    10000, 9808, 9239, 8315, 7071, 5556, 3827, 1951,
    0, -1951, -3827, -5556, -7071, -8315, -9239, -9808,
    -10000, -9808, -9239, -8315, -7071, -5556, -3827, -1951
};

static void produce(uint32_t count)
{
    uint32_t samples[96];
    for (uint32_t i = 0; i < count; ++i) {
        uint32_t index = supplied + i;
        int16_t square = (index & 16u) == 0u ? 10000 : -10000;
        samples[i] = (uint16_t)sine[index & 31u] | ((uint32_t)(uint16_t)square << 16);
    }
    aud_write(&ring, samples, count);
    supplied += count;
}

static void refill(struct aud_ring *buffer, const struct aud_event *event, void *context)
{
    (void)event;
    (void)context;
    ++low_count;
    if (supplied < 256u) {
        uint32_t count = 256u - supplied;
        if (count > 64u) {
            count = 64u;
        }
        test_equal("audio ring free space", 1u, aud_space(buffer) >= count * 4u);
        produce(count);
    }
}

static void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void)
{
    unsigned int source = plic_claim();
    test_equal("AUD PLIC source", EDRV32_PLIC_SOURCE_AUD, source);
    struct aud_event event = aud_irq_handle(&ring);
    test_equal("AUD error", 0u, event.error);
    plic_complete(source);
}

int main(void)
{
    test_init();
    test_equal("ES8156 ACK", 0u, (uint32_t)es8156_init());
    aud_init(&ring, (uint32_t *)(uintptr_t)(EDRV32_DDR_BASE + 0x10000u), 512u, 128u);
    produce(96u);
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uintptr_t)trap_handler));
    aud_irq_register(1u, refill, 0);
    plic_set_threshold(0u);
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 11));
    __asm__ volatile ("csrsi mstatus, 8");
    aud_enable(1u);
    /* Bench confirms 256 exact I2S sample frames and 27 codec writes. */
    test_external(12u);
    __asm__ volatile ("csrci mstatus, 8");
    test_equal("all samples supplied", 256u, supplied);
    test_equal("LOW interrupts", 1u, low_count >= 3u);
    aud_enable(0u);
    uart_puts("PASS ST-12 audio\r\n");
    test_finish(0u);
}
