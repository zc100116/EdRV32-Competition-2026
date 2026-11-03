/* sched.c — showcase 4.5.2 host acceptance: wall step max includes IRQ wait. */
#include "sched.h"
#include "port.h"
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
static uint64_t now;
static unsigned calls;
static volatile uint32_t flag;
static jmp_buf finished;
uint64_t sched_port_time(void) { return now; }
uint32_t sched_port_lock(void) { return 0; }
void sched_port_unlock(uint32_t s) { (void)s; }
void sched_port_compare(uint64_t d) { (void)d; }
void sched_port_wait(void) { now+=20; flag=1; }
static void step(struct sched_task *task)
{
    sched_take(task);
    if(calls==3) longjmp(finished,1);
    now+=calls==0 ? 5 : calls==1 ? 17 : 9;
    if(calls==1) { flag=0; sched_wait_flag(&flag); }
    ++calls; sched_signal(task,1);
}
int main(void)
{
    struct sched_task task={"test",step,0,1,UINT64_MAX,0,0}; sched_add(&task);
    if(!setjmp(finished)) sched_run();
    assert(task.busy_ticks==31 && task.max_step_ticks==37 && sched_idle_ticks()==20);
    puts("PASS scheduler busy=31 max_step=37 idle=20");
}
