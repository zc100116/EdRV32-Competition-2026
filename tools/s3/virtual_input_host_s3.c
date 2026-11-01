/* File: virtual_input_host_s3.c
 * Spec: sys-subsys 2.5/2.6; Task T-S3IN.
 * Description: Real S3 ISR/input sampling with 16-byte UART at 115200 8N1.
 * Clock domain: deterministic host microseconds.
 */
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "s3_platform.h"
#include "virtual_input.h"
#include "virtual_input_uart.h"
#include "uart.h"
#include "plic.h"
#include "eth_monitor.h"
#include "sysctrl.h"

extern void s3_interrupt(void);
unsigned host_cause = 0x8000000bu;
static uint8_t fifo[16];
static unsigned head;
static unsigned count;
static unsigned dropped;
static unsigned receives;
static uint32_t enabled;
static uint32_t threshold;
static uint32_t irq_enable;
static unsigned interrupts;
static uint64_t now;
static jmp_buf stopped;
static char output[256];
static unsigned output_count;

static void dispatch(void)
{
    if (interrupts && (enabled & (1u << EDRV32_PLIC_SOURCE_UART0)) &&
        (irq_enable & UART_IRQ_RX_THRESH) && threshold && count >= threshold) {
        interrupts = 0;
        ++receives;
        s3_interrupt();
        interrupts = 1;
    }
}
uint32_t virtual_input_lock(void)
{
    uint32_t saved = interrupts ? 8u : 0;
    interrupts = 0;
    return saved;
}
void virtual_input_unlock(uint32_t saved)
{
    interrupts = !!(saved & 8u);
    dispatch();
}
uint32_t mmio_read32(uintptr_t address)
{
    if (address == EDRV32_UART0_BASE + UART_STATUS) return count ? 0 : UART_STATUS_RX_EMPTY;
    if (address == EDRV32_PLIC_BASE + PLIC_ENABLE) return enabled;
    if (address == EDRV32_SYSCTRL_BASE + SYSCTRL_CLK_SYS_HZ) return 1000000;
    assert(!"unexpected MMIO read");
    return 0;
}
void mmio_write32(uintptr_t address, uint32_t value)
{
    if (address == EDRV32_UART0_BASE + UART_RX_THRESH) threshold = value;
    else if (address == EDRV32_UART0_BASE + UART_IRQ_EN) irq_enable = value;
    else assert(!"unexpected MMIO write");
}
void plic_set_enable(uint32_t value) { enabled = value; }
void plic_set_threshold(unsigned value) { assert(value == 0); }
void plic_set_priority(unsigned source, unsigned priority)
{ assert(source == EDRV32_PLIC_SOURCE_UART0 && priority == 1); }
unsigned plic_claim(void) { return EDRV32_PLIC_SOURCE_UART0; }
void plic_complete(unsigned source) { assert(source == EDRV32_PLIC_SOURCE_UART0); }
void uart_init(void) { }
uint8_t uart_getc(void)
{
    assert(count);
    uint8_t byte = fifo[head];
    head = (head + 1) % sizeof fifo;
    --count;
    return byte;
}
void uart_putc(uint8_t byte) { output[output_count++] = (char)byte; }
void uart_puts(const char *text) { while (*text) uart_putc((uint8_t)*text++); }
uint16_t gpio_read(void) { return 0xffff; }
uint64_t clint_time(void) { return now; }
void host_stopped(void) { longjmp(stopped, 1); }
struct engine_event engine_poll(enum engine_id engine)
{ (void)engine; return (struct engine_event){.status = EDRV32_DISP_STATUS_IDLE_MASK}; }
void engine_control(enum engine_id engine, uint32_t control) { (void)engine; (void)control; }
void engine_irq_clear(enum engine_id engine, uint32_t irq) { (void)engine; (void)irq; }
void engine_irq_handle(unsigned source) { (void)source; assert(!"unexpected media IRQ"); }
void engine_irq_register(enum engine_id engine, uint32_t mask, unsigned priority,
                         engine_irq_callback callback, void *context)
{
    (void)engine; (void)mask; (void)priority; (void)callback; (void)context;
    enabled |= 1u << EDRV32_PLIC_SOURCE_DISP;
}
void rnd_irq_register(unsigned priority, rnd_callback callback, void *context)
{
    (void)priority; (void)callback; (void)context;
    enabled |= 1u << EDRV32_PLIC_SOURCE_RND;
}
void rnd_irq_handle(void) { assert(!"unexpected RND IRQ"); }
void eth_monitor_board_init(uint32_t frequency) { assert(frequency == 1000000); }
uint32_t eth_monitor_board_tick(void) { return 0; }
void eth_monitor_board_set_receive(void (*receive)(uint32_t)) { (void)receive; }
void eth_window_configure(unsigned window, uint32_t base, uint32_t bytes)
{ (void)window; (void)base; (void)bytes; }

static void arrive(uint8_t byte)
{
    now += 87;
    if (count == sizeof fifo) ++dropped;
    else {
        fifo[(head + count) % sizeof fifo] = byte;
        ++count;
    }
    dispatch();
}
static void frame(unsigned x, unsigned y, unsigned mouse, unsigned keys)
{
    const uint8_t bytes[] = {0x1b, 'V', keys, keys >> 8, x, x >> 8, y, y >> 8, mouse, 0};
    for (unsigned i = 0; i < sizeof bytes; ++i) arrive(bytes[i]);
}
static void expect(unsigned keys, unsigned x, unsigned y, unsigned mouse, const char *scenario)
{
    unsigned actual = s3_input();
    struct virtual_input_state input = virtual_input_get();
    if (actual != keys || input.x != (int)x || input.y != (int)y || input.mouse != mouse) {
        fprintf(stderr, "FAIL %s: keys expected=%u actual=%u pointer=%d,%d/%u "
                "expected=%u,%u/%u time=%llu dropped=%u\n", scenario, keys, actual,
                input.x, input.y, input.mouse, x, y, mouse, (unsigned long long)now, dropped);
        exit(1);
    }
}
int main(void)
{
    s3_platform_init();
    /* Two frames overflow the old polling path; the next header completes its
     * partial frame, exposing coordinate bytes d/w as legacy menu commands. */
    frame(100, 119, 0, 0);
    frame(97, 112, 0, 0);
    (void)s3_input();
    now += 100000; /* Slow LVGL frame, independent of serial reception. */
    frame(100, 119, 0, 0);
    expect(0, 100, 119, 0, "payload d/w must not launch or move selection");
    assert((enabled & (1u << EDRV32_PLIC_SOURCE_DISP)) &&
           (enabled & (1u << EDRV32_PLIC_SOURCE_RND)));
    for (unsigned i = 0; i < 100; ++i) {
        frame(100, 119, 1, VI_RIGHT);
        frame(97, 112, 2, VI_LEFT);
        frame(100, 119, 0, 0);
        now += 100000;
        expect(0, 100, 119, 0, "continuous absolute frames across slow LVGL samples");
    }
    frame(100, 119, 1, VI_RIGHT);
    expect(S3_KEY_RIGHT, 100, 119, 1, "left mouse and right key pressed");
    frame(97, 112, 2, VI_LEFT);
    expect(S3_KEY_LEFT, 97, 112, 2, "right mouse and left key pressed");
    frame(100, 119, 0, 0);
    expect(0, 100, 119, 0, "mouse and keys released");
    for (unsigned split = 1; split < 10; ++split) {
        frame(100, 119, 3, VI_A | VI_START);
        expect(S3_KEY_JUMP | S3_KEY_PAUSE, 100, 119, 3, "buttons pressed");
        const uint8_t bytes[] = {0x1b, 'V', 0, 0, 97, 0, 112, 0, 0, 0};
        for (unsigned i = 0; i < split; ++i) arrive(bytes[i]);
        expect(S3_KEY_JUMP | S3_KEY_PAUSE, 100, 119, 3, "partial release");
        for (unsigned i = split; i < sizeof bytes; ++i) arrive(bytes[i]);
        expect(0, 97, 112, 0, "completed release");
    }
    uint32_t saved = virtual_input_lock();
    frame(100, 119, 1, 0);
    virtual_input_unlock(saved);
    expect(0, 100, 119, 1, "buffered full frame");
    arrive('a'); arrive('d'); arrive('w'); arrive('p');
    expect(15, 100, 119, 1, "legacy characters delivered once");
    expect(0, 100, 119, 1, "legacy bits consumed");
    assert(dropped == 0);
    host_cause = 2;
    if (!setjmp(stopped)) { s3_interrupt(); assert(!"exception returned"); }
    assert(strcmp(output, "S3 CPU mcause=0x00000002 mepc=0x00001234\r\n") == 0);
    printf("PASS S3 input: slow frames, a/d/w/p payload, 9 splits, mouse/key release, "
           "legacy, exception; FIFO dropped=%u interrupts=%u\n", dropped, receives);
    return 0;
}
