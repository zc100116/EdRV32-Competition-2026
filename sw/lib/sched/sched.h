/* File: sched.h
 * Design: 2026-11-02-showcase-software 4.1.
 * Description: Cooperative tasks, interrupt events and absolute CLINT deadlines.
 * Clock domain: clk_sys, or host test clock.
 */
#ifndef SHOWCASE_SCHED_H
#define SHOWCASE_SCHED_H
#include <stdint.h>
struct sched_task {
    const char *name;
    void (*step)(struct sched_task *task);
    uint8_t priority;
    volatile uint32_t events;
    uint64_t wake_at;
    uint64_t busy_ticks;
    uint64_t max_step_ticks;
};
void sched_add(struct sched_task *task);
void sched_signal(struct sched_task *task, uint32_t events);
void sched_wake_at(struct sched_task *task, uint64_t mtime);
uint32_t sched_take(struct sched_task *task);
/* Cooperatively defer an already-due application slice while GUI is active. */
void sched_defer_ready(struct sched_task *task,uint64_t now,uint64_t delay);
void sched_run(void);
uint64_t sched_idle_ticks(void);
#endif
