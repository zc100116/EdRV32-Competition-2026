/* File: sched.c
 * Design: 2026-11-02-showcase-software 4.1.
 * Description: Three cooperative services; atomic readiness-to-WFI transition.
 * Clock domain: clk_sys or host test clock.
 */
#include "sched.h"
#include "port.h"
#include <stddef.h>
static struct sched_task *tasks[3];
static unsigned count;
static uint64_t idle_ticks;
void sched_add(struct sched_task *task)
{
    tasks[count++] = task;
}
void sched_signal(struct sched_task *task, uint32_t events)
{
    uint32_t state = sched_port_lock();
    task->events |= events;
    sched_port_unlock(state);
}
void sched_wake_at(struct sched_task *task, uint64_t mtime)
{
    uint32_t state = sched_port_lock();
    task->wake_at = mtime;
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
uint64_t sched_idle_ticks(void)
{
    return idle_ticks;
}
void sched_wait_flag(volatile uint32_t *flag)
{
    uint32_t state = sched_port_lock();
    while (!*flag) {
        uint64_t begin = sched_port_time();
        sched_port_wait();
        idle_ticks += sched_port_time() - begin;
        /* Service the pending IRQ, then recheck with MIE masked. */
        sched_port_unlock(state);
        state = sched_port_lock();
    }
    sched_port_unlock(state);
}
void sched_run(void)
{
    for (;;) {
        uint32_t state = sched_port_lock();
        uint64_t now = sched_port_time();
        uint64_t deadline = UINT64_MAX;
        struct sched_task *ready = NULL;
        for (unsigned i = 0; i < count; ++i) {
            struct sched_task *task = tasks[i];
            if ((task->events || now >= task->wake_at) &&
                (!ready || task->priority < ready->priority)) ready = task;
            if (task->wake_at < deadline) deadline = task->wake_at;
        }
        if (ready) {
            if (now >= ready->wake_at) ready->wake_at = UINT64_MAX;
            sched_port_unlock(state);
            uint64_t begin = sched_port_time();
            uint64_t idle_before = idle_ticks;
            ready->step(ready);
            uint64_t elapsed = sched_port_time() - begin;
            ready->busy_ticks += elapsed - (idle_ticks - idle_before);
            if (elapsed > ready->max_step_ticks) ready->max_step_ticks = elapsed;
        } else {
            sched_port_compare(deadline);
            /* IRQs remain masked from readiness check through WFI. A pending,
             * locally enabled interrupt wakes this CPU even when MIE is zero.
             */
            uint64_t begin = sched_port_time();
            sched_port_wait();
            idle_ticks += sched_port_time() - begin;
            sched_port_unlock(state);
        }
    }
}
