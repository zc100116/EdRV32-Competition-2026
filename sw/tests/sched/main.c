/* File: main.c
 * Design: showcase 4.1; CPU 5 WFI wake semantics.
 * Description: Priority, atomic events, deadlines, idle accounting and IRQ/WFI race.
 * Clock domain: deterministic host clock.
 */
#include "sched.h"
#include "port.h"
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
static uint64_t now;
static uint64_t compare;
static uint32_t enabled = 8;
static unsigned sequence;
static unsigned waits;
static jmp_buf done;
static struct sched_task high;
static struct sched_task low;
uint64_t sched_port_time(void) { return now; }
uint32_t sched_port_lock(void)
{
    uint32_t old = enabled;
    enabled = 0;
    return old;
}
void sched_port_unlock(uint32_t old) { enabled = old; }
void sched_port_compare(uint64_t deadline) { compare = deadline; }
void sched_port_wait(void)
{
    assert(enabled == 0);
    ++waits;
    if (waits == 1) {
        assert(compare == 100);
        now = 50;
        sched_signal(&low, 2);
    } else if (waits == 2) {
        assert(compare == 100);
        now = compare;
    } else if (waits == 3) {
        assert(compare == UINT64_MAX);
        /* IRQ arrives after the final readiness check but before WFI.
         * The CPU wakes on pending IRQ with MIE masked; ISR then sets event.
         */
        now += 7;
        sched_signal(&low, 4);
    } else {
        assert(sequence == 5);
        assert(high.busy_ticks == 10);
        assert(low.busy_ticks == 21);
        assert(sched_idle_ticks() == 86);
        longjmp(done, 1);
    }
}
static void step_high(struct sched_task *task)
{
    assert(sequence++ == 0);
    assert(sched_take(task) == 3);
    assert(sched_take(task) == 0);
    now += 10;
}
static void step_low(struct sched_task *task)
{
    unsigned stage = sequence++;
    assert(stage >= 1 && stage <= 4);
    if (stage == 1) {
        assert(sched_take(task) == 1);
        now += 6;
        sched_wake_at(task, 100);
    } else if (stage == 2) {
        assert(now == 50 && task->wake_at == 100);
        assert(sched_take(task) == 2);
        now += 5;
    } else if (stage == 3) {
        assert(now == 100);
        assert(sched_take(task) == 0);
        now += 5;
    } else {
        assert(sched_take(task) == 4);
        now += 5;
    }
}
int main(void)
{
    high = (struct sched_task){"high", step_high, 0, 0, UINT64_MAX, 0};
    low = (struct sched_task){"low", step_low, 2, 0, UINT64_MAX, 0};
    sched_add(&low);
    sched_add(&high);
    sched_signal(&low, 1);
    sched_signal(&high, 1);
    sched_signal(&high, 2);
    if (!setjmp(done)) sched_run();
    puts("PASS sched priority events timer idle IRQ-before-WFI");
    return 0;
}
