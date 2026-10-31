/* File: host_test.c
 * Spec: Task T-NETN; SoC 7.2/7.4; eth-spec 2.4/2.6.
 * Description: Production B3N network, inference and monitor event tests without RTL.
 * Clock domain: none (host); mock only MMIO, IRQ locking, cache and CPU counters.
 */
#define _GNU_SOURCE
#include "runtime.h"
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

struct demo_state demo;
static struct { uintptr_t address; uint32_t value; } cells[512];
static unsigned int cell_count;
static jmp_buf failure;
static const char *failed;
static unsigned int invalidations;
static uint64_t now;
static char serial[512];
static unsigned int serial_length;

static void allowed(uintptr_t address)
{
    uintptr_t base = address & ~(uintptr_t)0xfffu;
    assert(base == EDRV32_NPU_BASE || base == EDRV32_ETH_BASE ||
           base == EDRV32_MEM_XBAR_BASE ||
           (address >= EDRV32_PLIC_BASE && address < EDRV32_PLIC_BASE + 0x210000u));
}

uint32_t mmio_read32(uintptr_t address)
{
    allowed(address);
    for (unsigned int i = 0; i < cell_count; ++i) {
        if (cells[i].address == address) {
            return cells[i].value;
        }
    }
    return 0;
}

void mmio_write32(uintptr_t address, uint32_t value)
{
    allowed(address);
    for (unsigned int i = 0; i < cell_count; ++i) {
        if (cells[i].address == address) {
            cells[i].value = value;
            return;
        }
    }
    assert(cell_count < 512);
    cells[cell_count].address = address;
    cells[cell_count++].value = value;
}

uint32_t demo_irq_lock(void) { return 0; }
void demo_irq_unlock(uint32_t old) { (void)old; }
uint64_t clint_time(void) { now += 1000000; return now; }
void clint_set_compare(uint64_t deadline) { assert(deadline > now); }
uint32_t demo_npu_cpu_cycles(void) { static uint32_t cycles; return cycles += 123; }
void cache_clean(uintptr_t address, uint32_t bytes) { (void)address; (void)bytes; }
void cache_invalidate(uintptr_t address, uint32_t bytes)
{
    assert(address == demo_cached(DEMO_OUTPUT_BASE) ||
           address == demo_cached(DEMO_OUTPUT_BASE + DEMO_OUTPUT_SPACING));
    assert(bytes == DEMO_OUTPUT_BYTES);
    ++invalidations;
}
void uart_putc(uint8_t byte)
{
    assert(serial_length + 1 < sizeof serial);
    serial[serial_length++] = (char)byte;
    serial[serial_length] = 0;
}
void uart_puts(const char *text) { while (*text) { uart_putc((uint8_t)*text++); } }
void info_number(const char *key, uint64_t value) { (void)key; (void)value; }
void info_hex(const char *key, uint32_t value) { (void)key; (void)value; }
void info_text(const char *key, const char *value) { (void)key; (void)value; }
_Noreturn void demo_fail(const char *reason, enum engine_id engine)
{
    (void)engine;
    failed = reason;
    longjmp(failure, 1);
}

static void notify(unsigned int window, uint32_t bytes)
{
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_WIN_BYTES_OFFSET(window), bytes);
    struct engine_event event = {0};
    event.irq = EDRV32_ETH_IRQ_STAT_RX_NOTIFY0_MASK << window;
    demo_network_event(&event, NULL);
    demo_network_receive();
}

static void tx_complete(void)
{
    struct engine_event event = {0};
    event.done_count = demo.tx_done + demo.tx_count;
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_DONE_COUNT_OFFSET, event.done_count);
    demo_network_event(&event, NULL);
}

static void model_test(void)
{
    uint32_t header[] = {0x4d4e4445u, 1, 1, 64, 32,
                        DEMO_WORK_BASE, DEMO_INPUT_BASE, DEMO_OUTPUT_BASE};
    memcpy(demo_uncached(DEMO_MODEL_WINDOW), header, sizeof header);
    memset(demo_uncached(DEMO_MODEL_WINDOW + 0x1000), 0x12, 64);
    memset(demo_uncached(DEMO_MODEL_WINDOW + 0x100000), 0x34, 32);
    notify(2, 128);
    assert(*(uint8_t *)demo_uncached(DEMO_DESC_BASE) == 0x12);
    assert(*(uint8_t *)demo_uncached(DEMO_MODEL_BASE) == 0x34);
    assert(mmio_read32(EDRV32_NPU_BASE + EDRV32_NPU_DESC_COUNT_OFFSET) == 1);
    assert(eth_window_bytes(2) == 0);
    if (!setjmp(failure)) {
        notify(2, 127);
        assert(0);
    }
    assert(strcmp(failed, "Model bytes") == 0);
    header[0] = 0;
    memcpy(demo_uncached(DEMO_MODEL_WINDOW), header, sizeof header);
    if (!setjmp(failure)) {
        notify(2, 128);
        assert(0);
    }
    assert(strcmp(failed, "EDNM magic/version") == 0);
}

static void frame_test(unsigned int window)
{
    notify(window, DEMO_IMAGE_BYTES);
    assert(demo.active_npu == (int)window);
    assert(mmio_read32(EDRV32_NPU_BASE + EDRV32_NPU_INPUT_BASE_OFFSET) ==
           DEMO_INPUT_BASE + window * DEMO_INPUT_SPACING);
    assert(mmio_read32(EDRV32_NPU_BASE + EDRV32_NPU_OUTPUT_BASE_OFFSET) ==
           DEMO_OUTPUT_BASE + window * DEMO_OUTPUT_SPACING);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_IRQ_STAT_OFFSET,
                 EDRV32_NPU_IRQ_STAT_DONE_MASK);
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_PERF_OFFSET(0), 789);
    engine_irq_handle(EDRV32_PLIC_SOURCE_NPU);
    assert(demo.inference_cycles == 789);
    demo_npu_service();
    assert(demo.post_cycles == 123 && demo.detection_count == 0);
    assert(demo.tx_count == 3 && demo.tx_active);
    const struct eth_tx_descriptor *tx = demo_uncached(DEMO_TX_DESCRIPTORS);
    assert(tx[0].word[0] == DEMO_INPUT_BASE + window * DEMO_INPUT_SPACING);
    assert(tx[0].word[1] == DEMO_INPUT_BYTES && tx[0].word[2] == 0);
    assert(tx[1].word[0] == DEMO_OUTPUT_BASE + window * DEMO_OUTPUT_SPACING);
    assert(tx[1].word[1] == DEMO_OUTPUT_BYTES && tx[1].word[2] == 1);
    assert(tx[2].word[0] == DEMO_TX_DETECTIONS);
    assert(tx[2].word[1] == 16 && tx[2].word[2] == 0x102);
    assert(!memcmp(demo_uncached(DEMO_TX_DETECTIONS), "EDDT", 4));
    assert(demo_read32((uint8_t *)demo_uncached(DEMO_TX_DETECTIONS) + 8) == window);
    assert(eth_window_bytes(window) == DEMO_IMAGE_BYTES);
    assert(demo.inference[window].state == BUFFER_PROCESSING);
    struct engine_event partial = {0};
    partial.done_count = demo.tx_done + 1;
    demo_network_event(&partial, NULL);
    assert(demo.tx_active && eth_window_bytes(window) == DEMO_IMAGE_BYTES);
    tx_complete();
    assert(!demo.tx_active && !demo.checking);
    assert(demo.inference[window].state == BUFFER_FREE);
    assert(eth_window_bytes(window) == 0);
}

int main(void)
{
    size_t bytes = 0x0b000000u;
    assert(mmap((void *)(uintptr_t)EDRV32_DDR_UNCACHED_BASE, bytes,
                PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) !=
           MAP_FAILED);
    assert(mmap((void *)(uintptr_t)EDRV32_DDR_BASE, bytes,
                PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) !=
           MAP_FAILED);
    memset((void *)demo_cached(DEMO_OUTPUT_BASE), 0x80, DEMO_OUTPUT_BYTES);
    memset((void *)demo_cached(DEMO_OUTPUT_BASE + DEMO_OUTPUT_SPACING), 0x80,
           DEMO_OUTPUT_BYTES);
    demo.clock_hz = 100000000;
    demo.sample_hz = 100;
    demo.scene = 1;
    demo.tx_surface = demo.tx_check_buffer = demo.active_npu = -1;
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_STATUS_OFFSET, EDRV32_ETH_STATUS_IDLE_MASK);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_PORT_OFFSET, 6000);
    demo_npu_init();
    demo_network_init();
    for (unsigned int window = 0; window < 4; ++window) {
        assert(mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_WIN_SIZE_OFFSET(window)) ==
               (window < 2 ? DEMO_WINDOW_SIZE : window == 2 ?
                DEMO_MODEL_WINDOW_SIZE : DEMO_COMMAND_WINDOW_SIZE));
    }
    model_test();
    frame_test(0);
    frame_test(1);
    assert(invalidations == 2);
    assert(strstr(serial, "frame_id=0 NPU_PERF0=789 post_cpu_cycles=123 detections=0"));
    assert(strstr(serial, "frame_id=1 NPU_PERF0=789 post_cpu_cycles=123 detections=0"));
    notify(3, 1);
    assert(eth_window_bytes(3) == 0);
    demo_monitor_tick();
    const uint8_t *record = demo_uncached(DEMO_MONITOR_RING);
    assert(!memcmp(record, "EDTM", 4));
    for (unsigned int offset = 232; offset < 256; offset += 4) {
        assert(demo_read32(record + offset) == 0);
    }
    assert(demo_read32(record + 256) == 2);
    demo.monitor_flush = 1;
    demo_monitor_send();
    assert(demo.tx_count == 1);
    tx_complete();
    if (!setjmp(failure)) { notify(0, DEMO_INPUT_BYTES - 1); assert(0); }
    assert(!strcmp(failed, "RGB565 image length"));
    struct engine_event error = {0};
    error.error = 1;
    if (!setjmp(failure)) { demo_network_event(&error, NULL); assert(0); }
    assert(!strcmp(failed, "ETH"));
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_ERR_CODE_OFFSET, 1);
    if (!setjmp(failure)) { engine_irq_handle(EDRV32_PLIC_SOURCE_NPU); assert(0); }
    assert(!strcmp(failed, "NPU"));
    puts("PASS demo_npu: EDNM, WIN0/1, CH2 then OUTPUT then EDDT, ownership, EDTM, errors");
    return 0;
}
