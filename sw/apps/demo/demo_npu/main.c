/* File: main.c
 * Spec: Task T-NETN; SoC 7.2/7.4; npu-spec 2.4; eth-spec 2.4/2.6.
 * Description: B3N SRAM application and NPU/ETH/timer interrupt dispatch.
 * Clock domain: clk_sys; no VIN/PIX/GEO/DISP/RND accesses.
 */
#include "runtime.h"

struct demo_state demo;

uint32_t demo_npu_cpu_cycles(void)
{
    uint32_t cycles;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(cycles));
    return cycles;
}

_Noreturn void demo_fail(const char *reason, enum engine_id engine)
{
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    struct engine_event event = engine_poll(engine);
    info_text("DEMO ERROR", reason);
    info_hex("IRQ_STAT", event.irq);
    info_hex("STATUS", event.status);
    info_hex("ERR_CODE", event.error);
    info_hex("DONE_COUNT", event.done_count);
    info_text("DEMO stopped", "reset to restart");
    for (;;) {
        __asm__ volatile ("wfi");
    }
}

static void __attribute__((interrupt("machine"), aligned(4))) demo_interrupt(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (demo.sleeping) {
        demo.idle_cycles += (uint32_t)(clint_time() - demo.sleep_start);
        demo.sleeping = 0;
    }
    if (cause == 0x80000007u) {
        demo_monitor_tick();
    } else if (cause == 0x8000000bu) {
        engine_irq_dispatch();
    } else {
        info_hex("mcause", cause);
        demo_fail("CPU trap", ENGINE_NPU);
    }
}

int main(void)
{
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    demo.clock_hz = sysctrl_read(SYSCTRL_CLK_SYS_HZ);
    demo.scene = 1;
    demo.output = DEMO_ETHERNET;
    demo.sample_hz = 100;
    demo.active_npu = -1;
    demo.tx_surface = -1;
    demo.tx_check_buffer = -1;
    uart_init();
    uart_set_baud(demo.clock_hz, 115200);
    info_text("Demo", "demo_npu network image inference");
    system_info();
    info_hex("SYS ID", sysctrl_read(SYSCTRL_ID));
    info_hex("MEM_XBAR ID", mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_ID_OFFSET));
    info_hex("NPU ID", mmio_read32(EDRV32_NPU_BASE + EDRV32_NPU_ID_OFFSET));
    info_hex("ETH ID", mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_ID_OFFSET));
    uintptr_t handler = (uintptr_t)demo_interrupt;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(handler) : "memory");
    plic_set_enable(0);
    plic_set_threshold(0);
    demo_npu_init();
    demo_network_init();
    struct mem_xbar_stats initial;
    mem_xbar_snapshot(&initial);
    demo.deadline = clint_time() + demo.clock_hz / demo.sample_hz;
    clint_set_compare(demo.deadline);
    __asm__ volatile ("csrw mie, %0" :: "r"((1u << 7) | (1u << 11)) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    for (;;) {
        demo_network_service();
        demo_network_receive();
        demo_npu_service();
        demo_monitor_send();
        uint32_t lock = demo_irq_lock();
        if (!demo.received && demo.inference[0].state != BUFFER_READY &&
            demo.inference[1].state != BUFFER_READY) {
            demo.sleep_start = clint_time();
            demo.sleeping = 1;
            __asm__ volatile ("wfi" ::: "memory");
        }
        demo_irq_unlock(lock);
    }
}
