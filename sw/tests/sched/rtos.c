/* rtos.c — card 93; deterministic host checks of the scheduler adapter.
 * Mock only kernel/hardware boundaries; exercise real IRQ/deadline/accounting code.
 */
#include <assert.h>
#include <stdio.h>
#include <setjmp.h>
#include "../../lib/sched/freertos/sched_freertos.c"
static uint64_t clock_now, compare_at;
size_t xCriticalNesting;
static uint32_t irq_state = 8;
uint32_t virtual_input_lock(void)
{ uint32_t old = irq_state; irq_state = 0; return old; }
void virtual_input_unlock(uint32_t old) { irq_state |= old & 8; }
TaskHandle_t volatile pxCurrentTCB;
static unsigned ticks, switches, notifications, semaphore_gives, mutex_depth, rnd_token;
struct sched_task application_task, communication_task, gui_task;
uint64_t sched_port_time(void) { return clock_now; }
uint32_t sched_port_lock(void) { return 0; }
void sched_port_unlock(uint32_t state) { (void)state; }
uint32_t platform_clock_hz(void) { return 1000000; }
void clint_set_compare(uint64_t value) { compare_at = value; }
uint64_t board_prof_deadline(uint64_t value) { return value; }
void board_prof_sample(uint32_t pc) { (void)pc; }
void platform_puts(const char *text) { (void)text; }
void platform_put_hex(uint32_t value) { (void)value; }
_Noreturn void platform_stop(void) { assert(0); __builtin_unreachable(); }
BaseType_t xTaskIncrementTick(void) { ++ticks; return pdFALSE; }
void vTaskSwitchContext(void) { ++switches; }
TaskHandle_t xTaskGetCurrentTaskHandle(void) { return pxCurrentTCB; }
void vTaskGenericNotifyGiveFromISR(TaskHandle_t task, UBaseType_t index, BaseType_t *wake)
{
    (void)task; (void)index;
    ++notifications; *wake = pdTRUE;
}
BaseType_t xTaskGenericNotify(TaskHandle_t task, UBaseType_t index, uint32_t value,
                             eNotifyAction action, uint32_t *before)
{
    (void)task; (void)index; (void)value; (void)action; (void)before;
    ++notifications; return pdTRUE;
}
BaseType_t xQueueGiveFromISR(QueueHandle_t queue, BaseType_t *wake)
{
    (void)queue;
    ++semaphore_gives; ++rnd_token; *wake = pdTRUE; return pdTRUE;
}
TaskHandle_t xQueueGetMutexHolder(QueueHandle_t queue)
{ (void)queue; return mutex_depth ? pxCurrentTCB : NULL; }
BaseType_t xQueueTakeMutexRecursive(QueueHandle_t queue, TickType_t wait)
{ (void)queue; assert(wait == portMAX_DELAY); ++mutex_depth; return pdTRUE; }
BaseType_t xQueueGiveMutexRecursive(QueueHandle_t queue)
{ (void)queue; --mutex_depth; return pdTRUE; }
BaseType_t xQueueSemaphoreTake(QueueHandle_t queue, TickType_t wait)
{
    (void)queue;
    if (wait == portMAX_DELAY) assert(mutex_depth == 0 && rnd_token == 1);
    if (!rnd_token) return pdFALSE;
    --rnd_token; return pdTRUE;
}
void showcase_external_interrupt(void)
{
    /* Device work plus the FromISR API: kernel and IRQ have distinct charges. */
    clock_now += 10;
    sched_kernel_enter(); clock_now += 5; sched_kernel_leave();
    sched_signal(&application_task, 4);
    sched_rnd_complete();
    clock_now += 10;
}
static jmp_buf stopped;
static unsigned gui_steps, gui_requests;
static void initialize_test(void) {}
static void gui_step_test(struct sched_task *task)
{ ++gui_steps; (void)sched_take(task); }
void sched_gui_service(void) { ++gui_requests; }
uint32_t ulTaskGenericNotifyTake(UBaseType_t index, BaseType_t clear, TickType_t wait)
{
    (void)index; (void)clear;
    assert(wait == portMAX_DELAY);
    longjmp(stopped, 1);
}
int main(void)
{
    sched_add(&application_task); sched_add(&gui_task); sched_add(&communication_task);
    for (unsigned i = 0; i < 3; ++i) {
        services[i].handle = (TaskHandle_t)(uintptr_t)(i + 1);
        services[i].task->wake_at = UINT64_MAX;
    }
    started = 1;
    uint32_t outer = sched_critical_enter();
    assert(xCriticalNesting == 1 && irq_state == 0);
    uint32_t inner = sched_critical_enter();
    /* Model a kernel critical exit inside the application's critical section. */
    ++xCriticalNesting; --xCriticalNesting;
    if (!xCriticalNesting) irq_state = 8;
    assert(irq_state == 0);
    sched_critical_leave(inner);
    assert(xCriticalNesting == 1 && irq_state == 0);
    sched_critical_leave(outer);
    assert(xCriticalNesting == 0 && irq_state == 8);
    irq_state = 0; sched_interrupt_active = 1;
    outer = sched_critical_enter(); sched_critical_leave(outer);
    assert(xCriticalNesting == 0 && irq_state == 0);
    sched_interrupt_active = 0; irq_state = 8;
    pxCurrentTCB = services[0].handle;
    sched_trace_in();
    /* Nested API time is kernel time; a blocked API keeps its task-local depth. */
    clock_now = 10; sched_kernel_enter();
    clock_now = 15; sched_kernel_enter();
    clock_now = 20; sched_kernel_leave();
    clock_now = 30; sched_trace_out();
    pxCurrentTCB = services[1].handle; sched_trace_in();
    clock_now = 50; sched_trace_out();
    pxCurrentTCB = services[0].handle; sched_trace_in();
    clock_now = 60; sched_kernel_leave();
    clock_now = 70; sched_trace_out();
    assert(application_task.busy_ticks == 20 && gui_task.busy_ticks == 20);
    assert(sched_kernel_cycles == 30 && sched_switch_count == 3);
    /* Exclusive NES freezes periodic ticks while absolute deadlines still wake. */
    services[2].waiting = 1; communication_task.wake_at = 100;
    next_tick = 80; sched_exclusive(1);
    assert(compare_at == 100);
    clock_now = 100; sched_kernel_entry = 100;
    sched_trap_dispatch(0x80000007u, 0);
    assert(ticks == 0 && notifications == 1 && switches == 1);
    assert(compare_at == UINT64_MAX && services[2].waiting == 0);
    sched_trap_finish();
    /* CoreMark suppresses service timers as well as the periodic kernel tick. */
    services[2].waiting = 1; communication_task.wake_at = 110;
    sched_exclusive(2); assert(compare_at == UINT64_MAX);
    sched_exclusive(0); assert(compare_at == 110 && next_tick == 1100);
    clock_now = 1200; sched_kernel_entry = 1200;
    sched_trap_dispatch(0x80000007u, 0); sched_trap_finish();
    assert(ticks == 1 && next_tick == 2200);
    /* External interrupts defer switching until all ISR work is complete. */
    unsigned before = switches;
    clock_now = 1300; sched_kernel_entry = 1300;
    uint32_t kernel_before = sched_kernel_cycles;
    sched_trap_dispatch(0x8000000bu, 0);
    assert(switches == before + 1 && semaphore_gives == 1);
    assert(application_task.events == 4 && excluded_cycles == 25);
    sched_trap_finish();
    assert(sched_kernel_cycles - kernel_before == 5);
    /* A completion before the wait is retained; CPU ownership is released. */
    sched_rnd_prepare(); assert(rnd_token == 0);
    sched_rnd_complete();
    mutex_depth = 2;
    sched_rnd_wait(NULL);
    assert(rnd_token == 0 && mutex_depth == 2);
    sched_measure_reset();
    clock_now += 1000000;
    sched_switch_count += 100;
    sched_kernel_cycles += 10000;
    struct sched_measurement measured = sched_measure();
    assert(measured.switches == 100 && measured.kernel == 10);
    /* RPC-only wakes service the queue without creating a GUI/app wake loop. */
    gui_task.step = gui_step_test;
    initialize_services = initialize_test;
    pxCurrentTCB = services[1].handle; sched_trace_in();
    mutex_depth = 0; gui_task.events = 0x400; gui_task.wake_at = UINT64_MAX;
    if (!setjmp(stopped)) task_entry(&gui_task);
    assert(gui_steps == 0 && gui_requests == 1);
    /* The same RPC wake still runs LVGL when its actual deadline has arrived. */
    gui_task.events = 0x400; gui_task.wake_at = clock_now;
    if (!setjmp(stopped)) task_entry(&gui_task);
    assert(gui_steps == 1 && gui_requests == 1);
    puts("PASS RTOS accounting, tick suppression, deadlines and ISR semaphore wake");
    return 0;
}
