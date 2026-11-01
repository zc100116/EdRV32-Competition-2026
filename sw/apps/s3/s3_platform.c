/* File: s3_platform.c
 * Spec: SoC 3.5/7.3/7.4; RND 5.4; DISP 5.3; Task B3-3b.
 * Description: One interrupt owner for both S3 applications, frame handoff and input.
 * Clock domain: clk_sys CPU, media interrupts from clk_mem.
 */
#include "s3_platform.h"
#include "clint.h"
#include "eth_monitor.h"
#include "eth.h"
#include "virtual_input.h"
#include "virtual_input_uart.h"
#include "gpio.h"
#include "plic.h"
#include "sysctrl.h"
#include "uart.h"

static volatile uint32_t serial_keys;
static volatile uint32_t frames;
static volatile uint32_t switches[2];
static volatile uint32_t rnd_complete;
static uint32_t submitted_frame;
static uint16_t scroll_x;
static uint16_t scroll_y;
static uint64_t rnd_elapsed_ticks;
static volatile uint64_t rnd_irq_tick;

void s3_puts(const char *text)
{
    uart_puts(text);
}

void s3_put_u32(uint32_t value)
{
    char digits[10];
    unsigned int count = 0;
    do {
        digits[count++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value);
    while (count) {
        uart_putc((uint8_t)digits[--count]);
    }
}

void s3_put_hex(uint32_t value)
{
    static const char digits[] = "0123456789abcdef";
    s3_puts("0x");
    for (int shift = 28; shift >= 0; shift -= 4) {
        uart_putc((uint8_t)digits[(value >> shift) & 15u]);
    }
}

_Noreturn void s3_stop(void)
{
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    for (;;) {
        __asm__ volatile ("wfi");
    }
}

static void rnd_event(const struct rnd_result *result, void *context)
{
    (void)context;
    if (result->error) {
        s3_puts("RND ERR_CODE=");
        s3_put_hex(result->error);
        s3_puts(" CUR_DESC=");
        s3_put_hex(result->cur_desc);
        s3_puts("\r\n");
        s3_stop();
    }
    rnd_complete = 1;
}

static void disp_event(const struct engine_event *event, void *context)
{
    (void)context;
    if (event->irq & EDRV32_DISP_IRQ_STAT_ERROR_MASK) {
        s3_puts("DISP ERR_CODE=");
        s3_put_hex(event->error);
        s3_puts("\r\n");
        s3_stop();
    }
    if (event->irq & EDRV32_DISP_IRQ_STAT_FRAME_MASK) {
        ++frames;
    }
    if (event->irq & EDRV32_DISP_IRQ_STAT_SWITCH_MASK) {
        ++switches[DISP_L0];
    }
    if (event->irq & EDRV32_DISP_IRQ_STAT_SWITCH1_MASK) {
        ++switches[DISP_L1];
    }
}

static void __attribute__((interrupt("machine"), aligned(4))) s3_interrupt(void)
{
    uint64_t entered = s3_ticks();
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (cause == 0x80000007u) {
        if (eth_monitor_board_tick()) {
            s3_stop();
        }
    } else if (cause == 0x8000000bu) {
        unsigned int source = plic_claim();
        if (source == EDRV32_PLIC_SOURCE_RND) {
            rnd_irq_tick = entered;
            rnd_irq_handle();
        } else if (source == EDRV32_PLIC_SOURCE_UART0) {
            virtual_input_uart_receive();
        } else if (source != EDRV32_PLIC_SOURCE_NONE) {
            /* Remaining media source is DISP; registration is owned here. */
            engine_irq_handle(source);
        }
        if (source != EDRV32_PLIC_SOURCE_NONE) {
            plic_complete(source);
        }
    } else {
        uint32_t pc;
        __asm__ volatile ("csrr %0, mepc" : "=r"(pc));
        s3_puts("S3 CPU mcause=");
        s3_put_hex(cause);
        s3_puts(" mepc=");
        s3_put_hex(pc);
        s3_puts("\r\n");
        s3_stop();
    }
}

static void virtual_receive(uint32_t irq)
{
    if (irq & EDRV32_ETH_IRQ_STAT_RX_NOTIFY2_MASK) {
        virtual_input_network((const volatile uint8_t *)(uintptr_t)
            (EDRV32_DDR_UNCACHED_BASE + VIRTUAL_INPUT_BASE));
    }
}

static void s3_character(int character)
{
    switch (character) {
    case 'a': serial_keys |= S3_KEY_LEFT; break;
    case 'd': serial_keys |= S3_KEY_RIGHT; break;
    case 'w': serial_keys |= S3_KEY_JUMP; break;
    case 'p': serial_keys |= S3_KEY_PAUSE; break;
    default: break;
    }
}

struct virtual_input_state s3_virtual_input(void)
{
    uint32_t saved = virtual_input_lock();
    struct virtual_input_state input = virtual_input_get();
    virtual_input_unlock(saved);
    return input;
}

void s3_platform_init(void)
{
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    uart_init();
    /* BIOS may own a Surface: stop its scan before any application draws. */
    s3_display_stop();
    plic_set_enable(0);
    plic_set_threshold(0);
    engine_irq_clear(ENGINE_DISP, engine_poll(ENGINE_DISP).irq);
    rnd_irq_register(1, rnd_event, NULL);
    engine_irq_register(ENGINE_DISP,
        EDRV32_DISP_IRQ_EN_FRAME_MASK | EDRV32_DISP_IRQ_EN_ERROR_MASK |
        EDRV32_DISP_IRQ_EN_SWITCH_MASK | EDRV32_DISP_IRQ_EN_SWITCH1_MASK,
        1, disp_event, NULL);
    virtual_input_uart_start(s3_character);
    eth_monitor_board_init(s3_clock_hz());
    eth_window_configure(VIRTUAL_INPUT_WINDOW, VIRTUAL_INPUT_BASE, VIRTUAL_INPUT_BYTES);
    eth_monitor_board_set_receive(virtual_receive);
    uintptr_t handler = (uintptr_t)s3_interrupt;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(handler) : "memory");
    __asm__ volatile ("csrw mie, %0" :: "r"(0x880u) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
}

uint64_t s3_ticks(void)
{
    return clint_time();
}

uint32_t s3_clock_hz(void)
{
    return sysctrl_read(SYSCTRL_CLK_SYS_HZ);
}

uint32_t s3_milliseconds(void)
{
    return (uint32_t)(s3_ticks() / (s3_clock_hz() / 1000u));
}

uint32_t s3_input(void)
{
    uint32_t keys = (~gpio_read()) & 15u;
    uint32_t saved = virtual_input_lock();
    keys |= serial_keys;
    serial_keys = 0;
    uint16_t virtual_keys = virtual_input_get().keys;
    virtual_input_unlock(saved);
    if (virtual_keys & VI_LEFT) keys |= S3_KEY_LEFT;
    if (virtual_keys & VI_RIGHT) keys |= S3_KEY_RIGHT;
    if (virtual_keys & VI_A) keys |= S3_KEY_JUMP;
    if (virtual_keys & VI_START) keys |= S3_KEY_PAUSE;
    return keys;
}

uint32_t s3_frame_count(void)
{
    return frames;
}

void s3_wait_frame(void)
{
    uint32_t previous = frames;
    /* Spin with interrupts enabled: WFI after a completed test can miss a wakeup. */
    while (frames == previous) {
    }
}

void s3_rnd_run(const struct rnd_batch *batch)
{
    uint64_t start = s3_ticks();
    rnd_complete = 0;
    rnd_submit(batch);
    while (!rnd_complete) {
    }
    rnd_elapsed_ticks = s3_ticks() - start;
}

uint64_t s3_rnd_elapsed_ticks(void) { return rnd_elapsed_ticks; }

struct s3_rnd_timing s3_rnd_last_timing(void)
{
    const struct rnd_timing *t = rnd_last_timing();
    return (struct s3_rnd_timing) {
        t->clean_ticks, rnd_irq_tick - t->doorbell_tick, t->finish_ticks, t->cache_ops
    };
}

#define CSR_WRITE(csr, value) __asm__ volatile ("csrw " #csr ", %0" :: "r"(value) : "memory")
#define CSR_READ(csr, value) __asm__ volatile ("csrr %0, " #csr : "=r"(value) :: "memory")
#define SET_COUNTER(index, event) do { \
    CSR_WRITE(mhpmevent##index, event); \
    CSR_WRITE(mhpmcounter##index, 0u); \
    CSR_WRITE(mhpmcounter##index##h, 0u); \
} while (0)
#define READ_COUNTER(low_csr, high_csr, destination) do { \
    uint32_t low; \
    uint32_t high; \
    CSR_READ(low_csr, low); \
    CSR_READ(high_csr, high); \
    destination = ((uint64_t)high << 32) | low; \
} while (0)

void s3_cpu_begin(void)
{
    CSR_WRITE(mcountinhibit, 0x7fdu);
    SET_COUNTER(3, 9u);
    SET_COUNTER(4, 10u);
    SET_COUNTER(5, 11u);
    SET_COUNTER(6, 12u);
    SET_COUNTER(7, 13u);
    SET_COUNTER(8, 14u);
    SET_COUNTER(9, 15u);
    SET_COUNTER(10, 16u);
    CSR_WRITE(mcycle, 0u);
    CSR_WRITE(mcycleh, 0u);
    CSR_WRITE(minstret, 0u);
    CSR_WRITE(minstreth, 0u);
    CSR_WRITE(mcountinhibit, 0u);
}

void s3_cpu_end(struct s3_cpu_counters *c)
{
    /* Freeze CY/IR/HPM together; no high/low retry is needed while frozen. */
    CSR_WRITE(mcountinhibit, 0x7fdu);
    READ_COUNTER(mcycle, mcycleh, c->cycles);
    READ_COUNTER(minstret, minstreth, c->instructions);
    READ_COUNTER(mhpmcounter3, mhpmcounter3h, c->events[0]);
    READ_COUNTER(mhpmcounter4, mhpmcounter4h, c->events[1]);
    READ_COUNTER(mhpmcounter5, mhpmcounter5h, c->events[2]);
    READ_COUNTER(mhpmcounter6, mhpmcounter6h, c->events[3]);
    READ_COUNTER(mhpmcounter7, mhpmcounter7h, c->events[4]);
    READ_COUNTER(mhpmcounter8, mhpmcounter8h, c->events[5]);
    READ_COUNTER(mhpmcounter9, mhpmcounter9h, c->events[6]);
    READ_COUNTER(mhpmcounter10, mhpmcounter10h, c->events[7]);
    CSR_WRITE(mcountinhibit, 0x7f8u);
}

void s3_display_stop(void)
{
    engine_control(ENGINE_DISP, 0);
    while (!(engine_poll(ENGINE_DISP).status & EDRV32_DISP_STATUS_IDLE_MASK)) {
    }
}

void s3_display_scroll(uint16_t x, uint16_t y)
{
    scroll_x = x;
    scroll_y = y;
}

void s3_display_begin(const void *l0, uint32_t l0_stride,
                      const void *l1, uint32_t l1_stride)
{
    s3_display_stop();
    uint32_t interrupt_state = virtual_input_lock();
    /* The stopped scan can leave an unserviced last FRAME. It belongs to the
     * previous owner, rather than the first frame of this new configuration.
     */
    engine_irq_clear(ENGINE_DISP, EDRV32_DISP_IRQ_STAT_FRAME_MASK |
        EDRV32_DISP_IRQ_STAT_SWITCH_MASK | EDRV32_DISP_IRQ_STAT_SWITCH1_MASK);
    uint32_t initial_frame = frames;
    scroll_x = 0;
    scroll_y = 0;
    disp_l0_scroll(0, 0);
    disp_l1_geometry(0, 0, 1280, 720, 255);
    disp_submit(DISP_L0, rnd_physical(l0), l0_stride);
    disp_layer_enable(DISP_L0, 1);
    if (l1 != NULL) {
        disp_submit(DISP_L1, rnd_physical(l1), l1_stride);
    }
    disp_layer_enable(DISP_L1, l1 != NULL);
    engine_control(ENGINE_DISP, EDRV32_DISP_CTRL_ENABLE_MASK);
    virtual_input_unlock(interrupt_state);
    /* DISP v0.3: first enabled frame has FRAME, without a Surface release. */
    while (frames == initial_frame) {
    }
    submitted_frame = frames - 1u;
}

void s3_display_present(const void *l0, uint32_t l0_stride,
                        const void *l1, uint32_t l1_stride)
{
    if (frames == submitted_frame) {
        s3_wait_frame();
    }
    uint32_t previous_l0 = switches[DISP_L0];
    uint32_t previous_l1 = switches[DISP_L1];
    submitted_frame = frames;
    disp_l0_scroll(scroll_x, scroll_y);
    if (l0 != NULL) {
        disp_submit(DISP_L0, rnd_physical(l0), l0_stride);
    }
    if (l1 != NULL) {
        disp_submit(DISP_L1, rnd_physical(l1), l1_stride);
    }
    while ((l0 != NULL && switches[DISP_L0] == previous_l0) ||
           (l1 != NULL && switches[DISP_L1] == previous_l1)) {
    }
}

/* SoC 6.1/7.4: caller stops using the cached DDR alias before this transfer. */
void *s3_uncached(void *storage)
{
    return (void *)((uintptr_t)storage - EDRV32_DDR_BASE + EDRV32_DDR_UNCACHED_BASE);
}
