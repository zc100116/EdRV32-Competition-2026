/* sched_freertos.c — D7/card 93 preemptive scheduler comparison; clk_sys.
 * Tasks retain the common event/deadline interface. CLINT wakes absolute
 * deadlines even while NES/CoreMark suppress the periodic kernel tick.
 */
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "sched.h"
#include "sched_policy.h"
#include "port.h"
#include "platform.h"
#include "runtime.h"
#include "clint.h"
#include "virtual_input_uart.h"
#include <stddef.h>

static struct service {
    struct sched_task *task;
    TaskHandle_t handle;
    unsigned waiting;
    unsigned kernel_depth;
} services[3];
static unsigned count, started, initialized, exclusive;
const uintptr_t sched_mtime_low = EDRV32_CLINT_BASE + CLINT_MTIME_LO;
static SemaphoreHandle_t shared, rnd;
static void (*initialize_services)(void);
volatile uint32_t sched_interrupt_active;
volatile uint32_t sched_kernel_entry, sched_restore_entry;
volatile uint32_t sched_kernel_cycles, sched_interrupt_cycles;
volatile uint32_t sched_switch_count, sched_switch_requested;
static uint64_t idle_ticks, run_since, next_tick;
static uint32_t run_interrupts;
static struct sched_task *running;
static unsigned running_idle;
static TaskHandle_t previous_handle;
static unsigned trap_scheduled;
static uint32_t excluded_cycles;
static struct service *running_service;
static unsigned idle_kernel_depth, external_profile, irq_kernel_depth;
static uint32_t irq_kernel_begin;
static uint64_t measure_time;
static uint32_t measure_kernel, measure_switches;

/* Match the kernel's nesting counter while preserving the caller's MIE.
 * API critical exits must not enable IRQs inside an application MMIO lock. */
uint32_t sched_critical_enter(void)
{
    uint32_t state = virtual_input_lock();
    if (started && !sched_interrupt_active) ++xCriticalNesting;
    return state;
}
void sched_critical_leave(uint32_t state)
{
    if (started && !sched_interrupt_active) --xCriticalNesting;
    virtual_input_unlock(state);
}
uint32_t sched_cycle(void) { return (uint32_t)sched_port_time(); }
_Noreturn void sched_assert(const char *file, unsigned line)
{
    (void)sched_port_lock();
    platform_puts("FreeRTOS assertion "); platform_puts(file); platform_puts(":");
    platform_put_u32(line); platform_puts("\r\n"); platform_stop();
}
static struct service *service(struct sched_task *task)
{
    for (unsigned i = 0; i < count; ++i)
        if (services[i].task == task) return &services[i];
    return NULL;
}
static void arm_timer(void)
{
    uint64_t deadline = exclusive ? UINT64_MAX : next_tick;
    for (unsigned i = 0; i < count; ++i)
        if (exclusive != 2 && services[i].waiting && services[i].task->wake_at < deadline)
            deadline = services[i].task->wake_at;
    extern uint64_t board_prof_deadline(uint64_t deadline);
    clint_set_compare(board_prof_deadline(deadline));
}
void sched_add(struct sched_task *task) { services[count++].task = task; }
static void notify(struct sched_task *task)
{
    /* Boot collects events before the three kernel tasks exist. */
    if (!started) return;
    struct service *s = service(task);
    if (sched_interrupt_active) {
        BaseType_t wake = pdFALSE;
        vTaskNotifyGiveFromISR(s->handle, &wake);
        sched_switch_requested |= wake != pdFALSE;
    } else xTaskNotifyGive(s->handle);
}
void sched_signal(struct sched_task *task, uint32_t events)
{
    uint32_t state = sched_port_lock();
    task->events |= events;
    notify(task);
    sched_port_unlock(state);
}
void sched_wake_at(struct sched_task *task, uint64_t deadline)
{
    uint32_t state = sched_port_lock();
    task->wake_at = deadline;
    notify(task);
    sched_port_unlock(state);
}
uint32_t sched_take(struct sched_task *task)
{
    uint32_t state = sched_port_lock();
    uint32_t events = task->events;
    task->events = 0;
    sched_port_unlock(state);
    return events;
}
void sched_defer_ready(struct sched_task *task, uint64_t now, uint64_t delay)
{ (void)task; (void)now; (void)delay; }
void sched_defer_for(struct sched_task *task, const struct sched_task *gui,
                     uint64_t now, uint64_t delay)
{ (void)task; (void)gui; (void)now; (void)delay; }
void sched_shared_enter(void) { (void)xSemaphoreTakeRecursive(shared, portMAX_DELAY); }
void sched_shared_leave(unsigned *guard)
{
    (void)guard;
    (void)xSemaphoreGiveRecursive(shared);
}
unsigned sched_shared_release(void)
{
    unsigned depth = 0;
    while (xSemaphoreGetMutexHolder(shared) == xTaskGetCurrentTaskHandle()) {
        (void)xSemaphoreGiveRecursive(shared);
        ++depth;
    }
    return depth;
}
void sched_shared_restore(unsigned depth)
{
    while (depth--) sched_shared_enter();
}
void sched_initialize(void (*initialize)(void)) { initialize_services = initialize; }
static void account(void)
{
    uint64_t now = sched_port_time();
    uint32_t pending = sched_interrupt_active ? (uint32_t)now - sched_kernel_entry : 0;
    uint64_t elapsed = now - run_since -
        (uint32_t)(sched_interrupt_cycles - run_interrupts) - pending;
    unsigned depth = running_service ? running_service->kernel_depth : idle_kernel_depth;
    if (depth) sched_kernel_cycles += (uint32_t)elapsed;
    else if (running) running->busy_ticks += elapsed;
    else if (running_idle) idle_ticks += elapsed;
    run_since = now;
    run_interrupts = sched_interrupt_cycles + pending;
}
/* API trace hooks follow each task across a blocking context switch. */
void sched_kernel_enter(void)
{
    if (sched_interrupt_active) {
        if (external_profile && irq_kernel_depth++ == 0) irq_kernel_begin = sched_cycle();
        return;
    }
    if (!previous_handle) return;
    uint32_t state = sched_port_lock();
    account();
    if (running_service) ++running_service->kernel_depth;
    else ++idle_kernel_depth;
    sched_port_unlock(state);
}
void sched_kernel_leave(void)
{
    if (sched_interrupt_active) {
        if (external_profile && --irq_kernel_depth == 0)
            sched_kernel_cycles += sched_cycle() - irq_kernel_begin;
        return;
    }
    if (!previous_handle) return;
    uint32_t state = sched_port_lock();
    account();
    if (running_service) --running_service->kernel_depth;
    else --idle_kernel_depth;
    sched_port_unlock(state);
}
static void task_entry(void *argument)
{
    struct sched_task *task = argument;
    struct service *s = service(task);
    if (task == &gui_task) {
        initialize_services();
        initialized = 1;
        for (unsigned i = 0; i < count; ++i) notify(services[i].task);
    } else while (!initialized) ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    for (;;) {
        uint32_t state = sched_port_lock();
        uint64_t now = sched_port_time();
        unsigned ready = task->events || now >= task->wake_at;
        unsigned rpc_only = task == &gui_task && task->events == 0x400 &&
                            now < task->wake_at;
        if (now >= task->wake_at) task->wake_at = UINT64_MAX;
        s->waiting = !ready;
        arm_timer();
        sched_port_unlock(state);
        if (ready) {
            /* Serialize shared application state; priority inheritance lets a
             * preempted GUI/communication slice finish its borrowed pointers.
             * RND and GUI RPC release this mutex across their blocking wait. */
            sched_shared_enter();
            state = sched_port_lock();
            account();
            uint64_t begin = task->busy_ticks;
            sched_port_unlock(state);
            if (rpc_only) {
                /* A synchronous GUI call does not advance LVGL's timer.
                 * Otherwise an app's no-op GUI request and GUI's app signal
                 * would wake one another indefinitely before any deadline. */
                state = sched_port_lock();
                task->events &= ~0x400u;
                sched_port_unlock(state);
                sched_gui_service();
            } else task->step(task);
            state = sched_port_lock();
            account();
            uint64_t busy = task->busy_ticks - begin;
            if (busy > task->max_step_ticks) task->max_step_ticks = busy;
            sched_port_unlock(state);
            sched_shared_leave(NULL);
        } else ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    }
}
extern void showcase_rtos_trap(void);
void sched_run(void)
{
    (void)sched_port_lock();
    shared = xSemaphoreCreateRecursiveMutex();
    rnd = xSemaphoreCreateBinary();
    extern void sched_gui_queue_init(void);
    sched_gui_queue_init();
    for (unsigned i = 0; i < count; ++i) {
        struct sched_task *t = services[i].task;
        unsigned words = t == &communication_task ? 4096 : 8192;
        unsigned priority = t == &application_task ? 3 : t == &gui_task ? 2 : 1;
        (void)xTaskCreate(task_entry, t->name, words, t, priority, &services[i].handle);
    }
    started = 1;
    extern void sched_install_trap(void);
    sched_install_trap();
    vTaskStartScheduler();
    sched_assert(__FILE__, __LINE__);
}
void sched_rnd_prepare(void) { (void)xSemaphoreTake(rnd, 0); }
void sched_rnd_wait(volatile uint32_t *flag)
{
    (void)flag;
    unsigned depth = sched_shared_release();
    (void)xSemaphoreTake(rnd, portMAX_DELAY);
    sched_shared_restore(depth);
}
void sched_rnd_complete(void)
{
    BaseType_t wake = pdFALSE;
    (void)xSemaphoreGiveFromISR(rnd, &wake);
    sched_switch_requested |= wake != pdFALSE;
}
void vApplicationIdleHook(void) { sched_port_wait(); }
void sched_trace_out(void) { account(); }
void sched_trace_in(void)
{
    extern TaskHandle_t volatile pxCurrentTCB;
    TaskHandle_t handle = pxCurrentTCB;
    if (handle != previous_handle) ++sched_switch_count;
    previous_handle = handle;
    running = NULL;
    running_service = NULL;
    for (unsigned i = 0; i < count; ++i)
        if (services[i].handle == handle) {
            running = services[i].task;
            running_service = &services[i];
        }
    running_idle = !running;
    run_since = sched_port_time();
    run_interrupts = sched_interrupt_cycles;
}
uint64_t sched_idle_ticks(void)
{
    uint32_t state = sched_port_lock();
    uint64_t ticks = idle_ticks;
    if (running_idle) ticks += sched_port_time() - run_since -
        (uint32_t)(sched_interrupt_cycles - run_interrupts);
    sched_port_unlock(state);
    return ticks;
}
/* Called with task registers saved, on the dedicated ISR stack. */
extern void showcase_external_interrupt(void);
extern void board_prof_sample(uint32_t pc);
void sched_trap_dispatch(uint32_t cause, uint32_t pc)
{
    trap_scheduled = 0;
    excluded_cycles = 0;
    sched_interrupt_active = 1;
    if (cause == 0x80000007u) {
        uint64_t now = sched_port_time();
        if (!exclusive && now >= next_tick) {
            next_tick = now + platform_clock_hz() / configTICK_RATE_HZ;
            if (xTaskIncrementTick()) sched_switch_requested = 1;
        }
        for (unsigned i = 0; i < count; ++i) {
            struct service *s = &services[i];
            if (s->waiting && now >= s->task->wake_at) {
                s->waiting = 0;
                notify(s->task);
            }
        }
        board_prof_sample(pc);
        arm_timer();
    } else if (cause == 0x8000000bu) {
        uint32_t begin = sched_cycle();
        external_profile = 1;
        showcase_external_interrupt();
        external_profile = 0;
        excluded_cycles = sched_cycle() - begin;
    } else if (cause == 11) sched_switch_requested = 1;
    else {
        platform_puts("FreeRTOS CPU mcause="); platform_put_hex(cause);
        platform_puts(" mepc="); platform_put_hex(pc); platform_puts("\r\n"); platform_stop();
    }
    if (sched_switch_requested) {
        sched_switch_requested = 0;
        trap_scheduled = 1;
        vTaskSwitchContext();
    }
}
void sched_trap_finish(void)
{
    uint64_t resume = sched_port_time();
    uint32_t end = (uint32_t)resume;
    sched_restore_entry = end;
    sched_kernel_cycles += end - sched_kernel_entry - excluded_cycles;
    sched_interrupt_cycles += end - sched_kernel_entry;
    if (trap_scheduled) {
        run_since = resume;
        run_interrupts = sched_interrupt_cycles;
    }
    sched_interrupt_active = 0;
}
TaskHandle_t sched_gui_handle(void) { return service(&gui_task)->handle; }
void vPortSetupTimerInterrupt(void)
{
    next_tick = sched_port_time() + platform_clock_hz() / configTICK_RATE_HZ;
    arm_timer();
}
void sched_exclusive(unsigned active)
{
    uint32_t state = sched_port_lock();
    exclusive = active;
    if (!active) next_tick = sched_port_time() + platform_clock_hz() / configTICK_RATE_HZ;
    arm_timer();
    sched_port_unlock(state);
}

struct sched_measurement sched_measure(void)
{
    uint32_t state = sched_port_lock();
    account();
    uint64_t now = sched_port_time();
    uint64_t elapsed = now - measure_time;
    struct sched_measurement m = {
        (unsigned)((uint64_t)(sched_switch_count - measure_switches) *
                   platform_clock_hz() / elapsed),
        (unsigned)((uint64_t)(uint32_t)(sched_kernel_cycles - measure_kernel) * 1000 / elapsed)
    };
    measure_time = now;
    measure_kernel = sched_kernel_cycles;
    measure_switches = sched_switch_count;
    sched_port_unlock(state);
    return m;
}

void sched_measure_reset(void)
{
    uint32_t state = sched_port_lock();
    account();
    measure_time = sched_port_time();
    measure_kernel = sched_kernel_cycles;
    measure_switches = sched_switch_count;
    sched_port_unlock(state);
}
