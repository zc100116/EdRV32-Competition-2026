/* File: input_release.c
 * Spec: sys-subsys 2.5/2.6; Task T-NESKEY acceptance.
 * Description: Exercise real NES UART/parser/merge with a 16-byte receive FIFO.
 * Clock domain: deterministic host microseconds; UART 115200 8N1.
 */
#include <assert.h>
#include <stdio.h>
#include "nes_port.h"
#include "virtual_input.h"
#include "input.h"
#include "uart.h"
#include "plic.h"
#include "eth.h"
#include "sysctrl.h"

/* Pre-interrupt baseline main.c keeps its polling path and never calls init. */
extern void nes_uart_start(void) __attribute__((weak));
extern int nes_application_main(void);
unsigned char nes_rom_slot[1];
unsigned nes_frame_limit;
int nes_skip_render;
static uint64_t now;
static uint8_t fifo[16];
static unsigned head;
static unsigned count;
static unsigned dropped;
static uint32_t threshold = 1;
static uint32_t irq_enable;
static uint32_t plic_enable;
static unsigned interrupts_enabled;
static unsigned receives;

static void dispatch(void)
{
    if (interrupts_enabled && (plic_enable & (1u << EDRV32_PLIC_SOURCE_UART0)) &&
            (irq_enable & UART_IRQ_RX_THRESH) && threshold && count >= threshold) {
        ++receives;
        virtual_input_uart_receive();
    }
}

uint32_t virtual_input_lock(void)
{
    uint32_t previous = interrupts_enabled ? 8u : 0;
    interrupts_enabled = 0;
    return previous;
}
void virtual_input_unlock(uint32_t state)
{
    interrupts_enabled = !!(state & 8u);
    dispatch();
}
void nes_input_init(void)
{
    nes_uart_start();
    interrupts_enabled = 1;
    dispatch();
}
uint32_t mmio_read32(uintptr_t address)
{
    if (address == EDRV32_PLIC_BASE + PLIC_ENABLE) return plic_enable;
    if (address == EDRV32_UART0_BASE + UART_STATUS)
        return count ? 0 : UART_STATUS_RX_EMPTY;
    if (address == EDRV32_SYSCTRL_BASE + SYSCTRL_CLK_SYS_HZ)
        return 1000000;
    assert(!"unexpected MMIO read");
    return 0;
}
void mmio_write32(uintptr_t address, uint32_t value)
{
    if (address == EDRV32_UART0_BASE + UART_RX_THRESH) threshold = value;
    else if (address == EDRV32_UART0_BASE + UART_IRQ_EN) irq_enable = value;
    else assert(!"unexpected MMIO write");
}
void plic_set_threshold(unsigned value) { assert(value == 0); }
void plic_set_priority(unsigned source, unsigned priority)
{ assert(source == EDRV32_PLIC_SOURCE_UART0 && priority == 1); }
void plic_set_enable(uint32_t sources) { plic_enable = sources; }
uint64_t clint_time(void) { return now; }
uint16_t gpio_read(void) { return 0xffff; }
void uart_init(void) { }
uint8_t uart_getc(void)
{
    assert(count);
    uint8_t byte = fifo[head];
    head = (head + 1) % sizeof fifo;
    --count;
    return byte;
}
struct engine_event engine_poll(enum engine_id engine)
{ assert(engine == ENGINE_ETH); return (struct engine_event){0}; }
void engine_irq_clear(enum engine_id engine, uint32_t irq) { (void)engine; (void)irq; }
void engine_control(enum engine_id engine, uint32_t control) { (void)engine; (void)control; }
void eth_monitor_local_init(uint32_t frequency) { assert(frequency == 1000000); }
void eth_window_configure(unsigned window, uint32_t base, uint32_t size)
{ (void)window; (void)base; (void)size; }

static void arrive(uint8_t byte)
{
    now += 87; /* ceil(10 bits / 115200 baud), only the model timebase is rounded. */
    if (count == sizeof fifo) ++dropped;
    else {
        fifo[(head + count) % sizeof fifo] = byte;
        ++count;
    }
    dispatch();
}
static void frame(unsigned keys)
{
    const uint8_t bytes[10] = {0x1b, 'V', keys, keys >> 8, 0, 0, 0, 0, 0, 0};
    for (unsigned i = 0; i < sizeof bytes; ++i) arrive(bytes[i]);
}
static void expect(unsigned expected, const char *scenario)
{
    unsigned actual = nes_buttons();
    if (actual != expected) {
        fprintf(stderr, "FAIL %s: expected=%u actual=%u time=%llu dropped=%u\n",
                scenario, expected, actual, (unsigned long long)now, dropped);
        assert(actual == expected);
    }
}
void nes_run(void)
{
    frame(VI_RIGHT);
    now = 18519; /* One emulated frame at 54 fps, independent of 18 fps display. */
    expect(0x80, "initial right press");
    now = 20000;
    frame(VI_RIGHT); /* Existing tool's 20 ms held-state transmission. */
    frame(0);        /* Key release immediately after a repeat: 20 bytes between polls. */
    now = 37038;
    expect(0, "repeat then release within one NES frame");
    assert(dropped == 0);

    /* Frame boundaries can fall at every serial byte, including ESC and V. */
    for (unsigned split = 1; split < 10; ++split) {
        frame(VI_RIGHT);
        expect(0x80, "split setup press");
        const uint8_t released[10] = {0x1b, 'V', 0, 0, 0, 0, 0, 0, 0, 0};
        for (unsigned i = 0; i < split; ++i) arrive(released[i]);
        expect(0x80, "incomplete release keeps previous state");
        for (unsigned i = split; i < sizeof released; ++i) arrive(released[i]);
        expect(0, "completed split release");
    }
    frame(VI_RIGHT);
    frame(0);
    expect(0, "short tap entirely between polls");
    uint64_t previous = now;
    frame(VI_RIGHT);
    now = previous + 20000;
    frame(VI_RIGHT);
    now = previous + 40000;
    frame(0);
    now = previous + 55556;
    expect(0, "18 fps polling gap with three input frames");
    uint32_t saved = virtual_input_lock();
    frame(VI_RIGHT); /* A complete frame buffered before the interrupt is serviced. */
    virtual_input_unlock(saved);
    expect(0x80, "drain buffered complete frame");
    frame(0);
    expect(0, "release after buffered press");
    for (unsigned i = 0; i < 100; ++i) frame(VI_RIGHT);
    frame(0);
    expect(0, "continuous frames, final release wins");
    assert(dropped == 0);
    arrive('d');
    expect(0x80, "legacy 100 ms pulse");
    now += 100001;
    expect(0, "legacy pulse expires");
    puts("PASS NES release: repeat/release, 9 splits, short tap, 18 fps gap,");
    puts("buffered frame, 101 continuous frames, legacy pulse");
    printf("FIFO dropped=%u UART receive interrupts=%u\n", dropped, receives);
}
int main(void) { return nes_application_main(); }
