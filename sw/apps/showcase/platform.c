/* File: platform.c
 * Design: showcase 4.1/4.2; CPU 5; SoC 7.3/7.4.
 * Description: Trap-contained ID probes, IRQ routing and cached system clock.
 * Clock domain: clk_sys, media IRQs from clk_mem.
 */
#include "platform.h"
#include "board/serial.h"
#include "app.h"
#include "runtime.h"
#include "lvgl/showcase_lvgl.h"
#include "port.h"
#include "clint.h"
#include "eth_monitor.h"
#include "eth.h"
#include "board/input.h"
#include "virtual_input_uart.h"
#include "gpio.h"
#include "plic.h"
#include "sysctrl.h"
#include "uart.h"
#include "board/board.h"
#include "board/vision_hooks.h"
#include "board/vision/pipeline_exec.h"
static uint32_t system_hz;
static uint32_t hardware;
static volatile uint32_t probing;
static volatile uint32_t probe_missing;
static volatile uint32_t frames;
static unsigned input_source,input_sequence;
static uint64_t input_tick;
static uint16_t input_keys;
uint64_t platform_input_tick(void) { return input_tick; }
unsigned platform_input_sequence(void) { return input_sequence; }
void platform_input_received(unsigned source)
{
    struct virtual_input_state input = virtual_input_get();
    showcase_input_virtual(input, platform_ticks());
    uint16_t keys=input.keys;
    input_source=source;
    if(keys!=input_keys) {
        input_keys=keys; input_tick=platform_ticks(); ++input_sequence;
    }
}
unsigned platform_input_source(void) { return input_source; }
static uint32_t milliseconds;
static uint64_t millisecond_base;
static volatile uint32_t rnd_done;
static unsigned rnd_owner;
static const struct rnd_batch *rnd_gui_pending, *rnd_pipe_pending;
static void rnd_dispatch(void)
{
    if (rnd_owner) return;
    const struct rnd_batch *batch;
    if (rnd_gui_pending) {
        batch = rnd_gui_pending; rnd_gui_pending = NULL; rnd_owner = 1;
    } else if (rnd_pipe_pending) {
        batch = rnd_pipe_pending; rnd_pipe_pending = NULL; rnd_owner = 2;
    } else return;
    rnd_submit(batch);
}
void board_pipe_rnd_submit(const struct rnd_batch *batch)
{
    rnd_pipe_pending = batch; rnd_dispatch();
}
static uint64_t rnd_elapsed;
static uint64_t rnd_irq_tick;
static rnd_callback app_rnd_callback;
static engine_irq_callback app_disp_callback;
static void *app_context;

void platform_gui_wake(void) { sched_signal(&gui_task, 0x100); }
bool platform_serial_ready(void)
{
    return !(mmio_read32(EDRV32_UART0_BASE + UART_STATUS) & UART_STATUS_TX_FULL);
}
void platform_serial_byte(unsigned char byte)
{
    mmio_write32(EDRV32_UART0_BASE + UART_TXDATA, byte);
}
void platform_puts(const char *text) { board_serial_write(text); }
void platform_put_u32(uint32_t value)
{
    char digits[10];
    unsigned count = 0;
    do {
        digits[count++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value);
    while (count) {
        char text[2] = {digits[--count], 0};
        platform_puts(text);
    }
}
void platform_put_hex(uint32_t value)
{
    static const char digits[] = "0123456789abcdef";
    platform_puts("0x");
    for (int shift = 28; shift >= 0; shift -= 4) {
        char text[2] = {digits[(value >> shift) & 15u], 0};
        platform_puts(text);
    }
}
_Noreturn void platform_stop(void)
{
    board_serial_finish();
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    for (;;) __asm__ volatile ("wfi");
}
uint64_t platform_ticks(void) { return clint_time(); }
uint32_t platform_clock_hz(void) { return system_hz; }
uint32_t platform_hardware(void) { return hardware; }
uint32_t platform_frames(void) { return frames; }
uint32_t platform_milliseconds(void)
{
    /* Scheduler calls at least every 10 ms for telemetry. Delta fits RV32;
     * retaining the remainder avoids drift and survives the low-word rollover.
     */
    uint64_t now = platform_ticks();
    uint32_t delta = (uint32_t)(now - millisecond_base);
    uint32_t elapsed = delta / (system_hz / 1000u);
    milliseconds += elapsed;
    millisecond_base += (uint64_t)elapsed * (system_hz / 1000u);
    return milliseconds;
}
uint64_t sched_port_time(void) { return platform_ticks(); }
uint32_t sched_port_lock(void) { return virtual_input_lock(); }
void sched_port_unlock(uint32_t state) { virtual_input_unlock(state); }
void sched_port_compare(uint64_t deadline) { clint_set_compare(board_prof_deadline(deadline)); }
void sched_port_wait(void) { __asm__ volatile ("wfi" ::: "memory"); }
void *platform_uncached(void *storage)
{
    return (void *)((uintptr_t)storage - EDRV32_DDR_BASE + EDRV32_DDR_UNCACHED_BASE);
}
struct virtual_input_state platform_virtual_input(void)
{
    return showcase_input_view(showcase_input_current_owner());
}
static uint32_t sample_keys(void)
{
    uint32_t keys = (~gpio_read()) & 15u;
    uint16_t virtual_keys = platform_virtual_input().keys;
    if (virtual_keys & (VI_LEFT | VI_PREV)) keys |= PLATFORM_LEFT;
    if (virtual_keys & (VI_RIGHT | VI_NEXT)) keys |= PLATFORM_RIGHT;
    if (virtual_keys & (VI_A | VI_ENTER)) keys |= PLATFORM_ENTER;
    if (virtual_keys & VI_ESC) keys |= PLATFORM_BACK;
    return keys;
}

static volatile uint64_t rnd_cycles,npu_cycles;
uint64_t board_rnd_cycles(void) { return rnd_cycles; }
uint64_t board_npu_cycles(void) { return npu_cycles; }
static void vision_event(const struct engine_event *event,void *context)
{
    if((uintptr_t)context==ENGINE_NPU && (event->irq&EDRV32_NPU_IRQ_STAT_DONE_MASK))
        npu_cycles+=engine_perf(ENGINE_NPU,0);
    vision_irq(event,context);
    sched_signal(&application_task,0x100);
}
static void rnd_event(const struct rnd_result *result, void *context)
{
    (void)context;
    rnd_irq_tick = platform_ticks();
    uint32_t perf[6]; rnd_read_perf(perf); rnd_cycles+=perf[0];
    if (result->error) {
        platform_puts("RND ERR_CODE=");
        platform_put_hex(result->error);
        platform_puts(" CUR_DESC=");
        platform_put_hex(result->cur_desc);
        platform_puts("\r\n");
        platform_stop();
    }
    unsigned owner = rnd_owner;
    rnd_owner = 0;
    if (owner == 2) pipe_rnd_done();
    else rnd_done = 1;
    rnd_dispatch();
    if (owner != 2 && app_rnd_callback) app_rnd_callback(result, app_context);
    if (showcase_gui_paused()) sched_signal(&application_task, PLATFORM_RND);
}
static void disp_event(const struct engine_event *event, void *context)
{
    (void)context;
    if (event->error) {
        platform_puts("DISP ERR_CODE="); platform_put_hex(event->error);
        platform_puts("\r\n"); platform_stop();
    }
    vision_display_irq(event->irq);
    if (event->irq & EDRV32_DISP_IRQ_STAT_SWITCH1_MASK)
        vision_gui_presented(platform_ticks());
    sched_signal(&application_task, 0x100);
    uint32_t events = 0;
    if (event->irq & EDRV32_DISP_IRQ_STAT_FRAME_MASK) {
        ++frames;
        events |= PLATFORM_FRAME;
    }
    if (event->irq & EDRV32_DISP_IRQ_STAT_SWITCH_MASK) events |= PLATFORM_SWITCH;
    if (event->irq & EDRV32_DISP_IRQ_STAT_SWITCH1_MASK) events |= PLATFORM_SWITCH1;
    if (app_disp_callback) app_disp_callback(event, app_context);
    if (showcase_gui_paused()) sched_signal(&application_task, events);
    else showcase_gui_disp_event(event->irq);
}
void platform_media_callbacks(rnd_callback rnd, engine_irq_callback disp, void *context)
{
    uint32_t state = virtual_input_lock();
    app_rnd_callback = rnd;
    app_disp_callback = disp;
    app_context = context;
    rnd_irq_register(1, rnd_event, NULL);
    engine_irq_register(ENGINE_DISP, EDRV32_DISP_IRQ_EN_ERROR_MASK |
        EDRV32_DISP_IRQ_EN_FRAME_MASK | EDRV32_DISP_IRQ_EN_SWITCH_MASK |
        EDRV32_DISP_IRQ_EN_SWITCH1_MASK, 1, disp_event, NULL);
    virtual_input_unlock(state);
}
static void __attribute__((interrupt("machine"), aligned(4))) interrupt_entry(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (cause == 5 && probing) {
        uint32_t pc;
        probe_missing = 1;
        __asm__ volatile ("csrr %0, mepc" : "=r"(pc));
        pc += 4;
        __asm__ volatile ("csrw mepc, %0" :: "r"(pc));
    } else if (cause == 0x80000007u) {
        uint32_t pc; __asm__ volatile ("csrr %0, mepc" : "=r"(pc));
        board_prof_sample(pc);
        clint_set_compare(board_prof_deadline(UINT64_MAX));
    } else if (cause == 0x8000000bu) {
        unsigned source = plic_claim();
        if (source == EDRV32_PLIC_SOURCE_RND) rnd_irq_handle();
        else if (source == EDRV32_PLIC_SOURCE_DISP) engine_irq_handle(source);
        else if (source == EDRV32_PLIC_SOURCE_UART0) {
            mmio_write32(EDRV32_UART0_BASE + UART_IRQ_EN, 0);
            sched_signal(&communication_task, 1);
        } else if (source == EDRV32_PLIC_SOURCE_ETH) {
            mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_IRQ_EN_OFFSET, 0);
            sched_signal(&communication_task, 2);
        } else if (source == EDRV32_PLIC_SOURCE_GPIO0) {
            gpio_irq_clear(gpio_irq_status());
            sched_signal(&communication_task, 4);
        }
        else if(source==EDRV32_PLIC_SOURCE_VIN || source==EDRV32_PLIC_SOURCE_NPU ||
                source==EDRV32_PLIC_SOURCE_PIX || source==EDRV32_PLIC_SOURCE_GEO)
            engine_irq_handle(source);
        if (source != EDRV32_PLIC_SOURCE_NONE) plic_complete(source);
    } else {
        uint32_t pc;
        __asm__ volatile ("csrr %0, mepc" : "=r"(pc));
        platform_puts("showcase CPU mcause="); platform_put_hex(cause);
        platform_puts(" mepc="); platform_put_hex(pc);
        platform_puts("\r\n"); platform_stop();
    }
}
static uint32_t probe(uintptr_t address)
{
    uint32_t value;
    probe_missing = 0;
    probing = 1;
    __asm__ volatile ("lw %0, 0(%1)" : "=r"(value) : "r"(address) : "memory");
    probing = 0;
    (void)value;
    return !probe_missing;
}
static uint32_t eth_irq_mask(void)
{
    return EDRV32_ETH_IRQ_EN_DONE_MASK | EDRV32_ETH_IRQ_EN_ERROR_MASK |
           EDRV32_ETH_IRQ_EN_RX_NOTIFY0_MASK | EDRV32_ETH_IRQ_EN_RX_NOTIFY2_MASK |
           EDRV32_ETH_IRQ_EN_RX_NOTIFY3_MASK;
}
static unsigned phy_address;
static unsigned phy_phase;
static uint16_t phy_id1;
static int network_link = -1;


int showcase_network_link(void) { return network_link; }
uint32_t showcase_network_tx_packets(void)
{
    extern unsigned board_tx_packets;
    return board_tx_packets;
}
static void mdio_start(unsigned reg)
{
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_MDIO_CMD_OFFSET,
                 (phy_address << EDRV32_ETH_MDIO_CMD_PHY_POS) | reg);
}
static void network_status_step(void)
{
    uint32_t value = mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_MDIO_STAT_OFFSET);
    if (value & EDRV32_ETH_MDIO_STAT_BUSY_MASK) return;
    uint16_t data = (uint16_t)(value >> EDRV32_ETH_MDIO_STAT_RDATA_POS);
    switch (phy_phase) {
    case 0: mdio_start(2); phy_phase = 1; break;
    case 1: phy_id1 = data; mdio_start(3); phy_phase = 2; break;
    case 2:
        if (phy_id1 != 0 && phy_id1 != 0xffffu && data != 0 && data != 0xffffu) {
            network_link = 0;
            mdio_start(1);
            phy_phase = 3;
        } else if (++phy_address < 32) {
            mdio_start(2);
            phy_phase = 1;
        } else phy_phase = 5;
        break;
    case 3:
        /* BMSR link latches low: discard first read, use the second. */
        mdio_start(1);
        phy_phase = 4;
        break;
    case 4:
        network_link = (data & 4u) != 0;
        mdio_start(1);
        phy_phase = 3;
        break;
    default: break;
    }
}
void showcase_communication_step(struct sched_task *task)
{
    uint32_t events = sched_take(task);
    (void)platform_milliseconds();
    if (events & 1) {
        while (!(mmio_read32(EDRV32_UART0_BASE + UART_STATUS) & UART_STATUS_RX_EMPTY)) {
            unsigned byte = mmio_read32(EDRV32_UART0_BASE + UART_RXDATA) & UART_DATA_MASK;
            if (board_uart_active()) board_uart_byte((unsigned)byte);
            else board_serial_character(byte);
        }
        mmio_write32(EDRV32_UART0_BASE + UART_IRQ_EN, UART_IRQ_RX_THRESH);
    }
    if (hardware & APP_HW_ETH) {
        board_network_step();
        network_status_step();
        mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_IRQ_EN_OFFSET, eth_irq_mask());
    }
    showcase_input_expire(platform_ticks(), system_hz * 3ull / 10);
    showcase_input_sample(sample_keys());
    showcase_input_event();
    showcase_cpu_report();
    board_serial_drain(false);
    sched_wake_at(task, platform_ticks() + system_hz / 100u);
}
void platform_init(void)
{
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    uart_init();
    system_hz = sysctrl_read(SYSCTRL_CLK_SYS_HZ);
    millisecond_base = platform_ticks();
    uintptr_t entry = (uintptr_t)interrupt_entry;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(entry) : "memory");
    if (!probe(EDRV32_DISP_BASE + EDRV32_DISP_ID_OFFSET)) {
        platform_puts("showcase missing DISP\r\n");
        platform_stop();
    }
    if (probe(EDRV32_RND_BASE + EDRV32_RND_ID_OFFSET)) hardware |= APP_HW_RND;
    if (probe(EDRV32_NPU_BASE + EDRV32_NPU_ID_OFFSET)) hardware |= APP_HW_NPU;
    if (probe(EDRV32_VIN_BASE + EDRV32_VIN_ID_OFFSET)) hardware |= APP_HW_VIN;
    if (probe(EDRV32_PIX_BASE + EDRV32_PIX_ID_OFFSET)) hardware |= APP_HW_PIX;
    if (probe(EDRV32_GEO_BASE + EDRV32_GEO_ID_OFFSET)) hardware |= APP_HW_GEO;
    if (probe(EDRV32_ETH_BASE + EDRV32_ETH_ID_OFFSET)) hardware |= APP_HW_ETH;
    engine_control(ENGINE_DISP, 0);
    plic_set_enable(0);
    plic_set_threshold(0);
    engine_irq_clear(ENGINE_DISP, engine_poll(ENGINE_DISP).irq);
    platform_media_callbacks(NULL, NULL, NULL);
    plic_set_priority(EDRV32_PLIC_SOURCE_UART0, 1);
    plic_set_enable(mmio_read32(EDRV32_PLIC_BASE + PLIC_ENABLE) |
                    (1u << EDRV32_PLIC_SOURCE_UART0));
    mmio_write32(EDRV32_UART0_BASE + UART_IRQ_EN, UART_IRQ_RX_THRESH);
    gpio_set_edges(15, 15);
    gpio_irq_clear(15);
    plic_set_priority(EDRV32_PLIC_SOURCE_GPIO0, 1);
    plic_set_enable(mmio_read32(EDRV32_PLIC_BASE + PLIC_ENABLE) |
                    (1u << EDRV32_PLIC_SOURCE_GPIO0));
    if (hardware & APP_HW_ETH) {
        board_network_init();
        eth_window_configure(VIRTUAL_INPUT_WINDOW, VIRTUAL_INPUT_BASE, VIRTUAL_INPUT_BYTES);

        plic_set_priority(EDRV32_PLIC_SOURCE_ETH, 1);
        plic_set_enable(mmio_read32(EDRV32_PLIC_BASE + PLIC_ENABLE) |
                        (1u << EDRV32_PLIC_SOURCE_ETH));
        mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_IRQ_EN_OFFSET, eth_irq_mask());
    }
    const enum engine_id engines[]={ENGINE_VIN,ENGINE_NPU,ENGINE_PIX,ENGINE_GEO};
    const unsigned bits[]={APP_HW_VIN,APP_HW_NPU,APP_HW_PIX,APP_HW_GEO};
    const uint32_t masks[]={EDRV32_VIN_IRQ_EN_ERROR_MASK|EDRV32_VIN_IRQ_EN_FRAME_MASK|
        EDRV32_VIN_IRQ_EN_CH1_FRAME_MASK|EDRV32_VIN_IRQ_EN_CH2_FRAME_MASK,EDRV32_NPU_IRQ_EN_ERROR_MASK|EDRV32_NPU_IRQ_EN_DONE_MASK,
        EDRV32_PIX_IRQ_EN_ERROR_MASK,EDRV32_GEO_IRQ_EN_ERROR_MASK|EDRV32_GEO_IRQ_EN_DONE_MASK};
    for(unsigned i=0;i<4;++i) if(hardware&bits[i])
        engine_irq_register(engines[i],masks[i],1,vision_event,(void *)(uintptr_t)engines[i]);
    clint_set_compare(UINT64_MAX);
    __asm__ volatile ("csrw mie, %0" :: "r"(0x880u) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
}
void showcase_rnd_run(const struct rnd_batch *batch)
{
    uint64_t begin = platform_ticks();
    uint32_t lock = sched_port_lock();
    rnd_done = 0;
    rnd_gui_pending = batch; rnd_dispatch();
    sched_port_unlock(lock);
    sched_wait_flag(&rnd_done);
    rnd_elapsed = platform_ticks() - begin;
}
uint64_t showcase_rnd_elapsed_ticks(void) { return rnd_elapsed; }
struct showcase_rnd_timing showcase_rnd_last_timing(void)
{
    const struct rnd_timing *t = rnd_last_timing();
    return (struct showcase_rnd_timing){
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

void showcase_cpu_begin(void)
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

void showcase_cpu_end(struct showcase_cpu_counters *c)
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


int platform_display_idle(void)
{
    return (engine_poll(ENGINE_DISP).status & EDRV32_DISP_STATUS_IDLE_MASK) != 0;
}
