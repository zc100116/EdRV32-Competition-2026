/* File: board.c
 * Spec: PC design 4.4; gpu-soc 6-8; S-0b board mapping.
 * Description: Board frame/input clock, DDR pool, UART logs and IRQ dispatch.
 * Clock domain: clk_sys; display frames arrive through PLIC.
 */
#include "plat.h"
#include "mmio.h"
#include "plic.h"
#include "uart.h"
#include "gpio.h"
#include "clint.h"
#include "es8156.h"
#include "eth.h"
#include "virtual_input.h"
#include "regs/disp_gpu_regs.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
static uint8_t pool[64 * 1024 * 1024] __attribute__((aligned(4096)));
static size_t allocated;
static plat_irq_handler handlers[16];
static void *contexts[16];
static uint64_t started;
static volatile uint32_t frames;
void plat_irq_register(unsigned source, plat_irq_handler handler, void *context)
{
    handlers[source] = handler;
    contexts[source] = context;
}
void plat_irq_dispatch(void)
{
    unsigned source;
    while ((source = plic_claim()) != 0) {
        handlers[source](contexts[source]);
        plic_complete(source);
    }
}
static void __attribute__((interrupt("machine"), aligned(4))) interrupt_entry(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (cause != 0x8000000bu) {
        plat_printf("CPU trap mcause=%u\n", cause);
        abort();
    }
    plat_irq_dispatch();
}
static void display_irq(void *context)
{
    (void)context;
    uint32_t irq = mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_IRQ_STAT_OFFSET);
    if (irq & EDRV32_DISP_GPU_IRQ_STAT_FRAME_MASK) ++frames;
    if (irq & EDRV32_DISP_GPU_IRQ_STAT_ERROR_MASK) {
        plat_printf("DISP error %u\n",
            mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_ERR_CODE_OFFSET));
        abort();
    }
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_IRQ_STAT_OFFSET, irq);
}
static void network_irq(void *context)
{
    (void)context;
    uint32_t irq = mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_IRQ_STAT_OFFSET);
    if (irq & EDRV32_ETH_IRQ_STAT_ERROR_MASK) {
        plat_printf("ETH error %u\n",
            mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_ERR_CODE_OFFSET));
        abort();
    }
    if (irq & EDRV32_ETH_IRQ_STAT_RX_NOTIFY2_MASK)
        virtual_input_network((const volatile uint8_t *)(uintptr_t)
                              (EDRV32_DDR_UNCACHED_BASE + VIRTUAL_INPUT_BASE));
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_IRQ_STAT_OFFSET, irq);
}
void plat_init(void)
{
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    uart_init();
    started = clint_time();
    if (es8156_init()) { uart_puts("ES8156 I2C NACK\n"); abort(); }
    plic_set_enable(0);
    plic_set_threshold(0);
    plat_irq_register(EDRV32_PLIC_SOURCE_DISP, display_irq, NULL);
    plat_irq_register(EDRV32_PLIC_SOURCE_ETH, network_irq, NULL);
    plic_set_priority(EDRV32_PLIC_SOURCE_DISP, 1);
    plic_set_priority(EDRV32_PLIC_SOURCE_ETH, 1);
    plic_set_enable((1u << EDRV32_PLIC_SOURCE_DISP) | (1u << EDRV32_PLIC_SOURCE_ETH));
    mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_GPU_IRQ_EN_OFFSET,
                 EDRV32_DISP_GPU_IRQ_EN_FRAME_MASK | EDRV32_DISP_GPU_IRQ_EN_ERROR_MASK);
    const struct eth_endpoint local = {{0x02, 0x45, 0x44, 0x52, 0x56, 0x32},
                                      {192, 168, 1, 10}, 5000};
    eth_phy_reset(1);
    uint64_t until = clint_time() + EDRV32_CLK_SYS_HZ / 100;
    while (clint_time() < until) {}
    eth_phy_reset(0);
    until = clint_time() + EDRV32_CLK_SYS_HZ / 10;
    while (clint_time() < until) {}
    eth_local_configure(&local);
    eth_window_configure(VIRTUAL_INPUT_WINDOW, VIRTUAL_INPUT_BASE, VIRTUAL_INPUT_BYTES);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_IRQ_EN_OFFSET,
                 EDRV32_ETH_IRQ_EN_RX_NOTIFY2_MASK | EDRV32_ETH_IRQ_EN_ERROR_MASK);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_CTRL_OFFSET, EDRV32_ETH_CTRL_ENABLE_MASK);
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uintptr_t)interrupt_entry) : "memory");
    __asm__ volatile ("csrw mie, %0" :: "r"(0x800u) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
}
void plat_wait_vsync(void)
{
    uint32_t previous = frames;
    while (frames == previous) __asm__ volatile ("wfi");
}
uint32_t plat_keys(void)
{
    uint32_t state;
    __asm__ volatile ("csrrci %0, mstatus, 8" : "=r"(state) :: "memory");
    uint32_t keys = virtual_input_get().keys &
        (VI_UP | VI_DOWN | VI_LEFT | VI_RIGHT | VI_A | VI_B | VI_START | VI_SELECT);
    if (state & 8) __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    unsigned buttons = (~gpio_read()) & 15;
    if (buttons & 1) keys |= PLAT_RIGHT;
    if (buttons & 2) keys |= PLAT_LEFT;
    if (buttons & 4) keys |= PLAT_A;
    if (buttons & 8) keys |= PLAT_START;
    return keys;
}
uint32_t plat_game_keys(void)
{
    uint32_t saved;
    __asm__ volatile ("csrrci %0, mstatus, 8" : "=r"(saved) :: "memory");
    uint16_t keys = virtual_input_get().keys;
    if (saved & 8) __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    unsigned buttons = (~gpio_read()) & 15;
    if (buttons & 1) keys |= VI_RIGHT;
    if (buttons & 2) keys |= VI_LEFT;
    if (buttons & 4) keys |= VI_A;
    if (buttons & 8) keys |= VI_ENTER;
    return virtual_input_game_keys(keys);
}
struct plat_pointer_state plat_pointer(void)
{
    uint32_t saved;
    __asm__ volatile ("csrrci %0, mstatus, 8" : "=r"(saved) :: "memory");
    struct virtual_input_state input = virtual_input_get();
    if (saved & 8) __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    return (struct plat_pointer_state){input.x / 2, input.y / 2, input.mouse};
}
uint32_t plat_millis(void)
{
    return (uint32_t)((clint_time() - started) / (EDRV32_CLK_SYS_HZ / 1000));
}
int plat_printf(const char *format, ...)
{
    char buffer[256];
    va_list args;
    va_start(args, format);
    int result = vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    uart_puts(buffer);
    return result;
}
void *plat_dma_alloc(size_t bytes, size_t alignment)
{
    allocated = (allocated + alignment - 1) & ~(alignment - 1);
    if (bytes > sizeof(pool) - allocated) {
        uart_puts("Board DDR pool exhausted\n"); abort();
    }
    void *result = pool + allocated;
    allocated += bytes;
    return result;
}
/* newlib's failure exit reaches the UART and stops the CPU. */
_Noreturn void _exit(int status)
{
    plat_printf("Exit %d\n", status);
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    for (;;) __asm__ volatile ("wfi");
}
