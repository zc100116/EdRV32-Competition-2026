/* sched.c — showcase 4.5.2 host acceptance: wall step max includes IRQ wait. */
#include "sched.h"
#include "port.h"
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
static uint64_t now;
static unsigned calls;
static uint64_t deadline;
static unsigned fairness,gui_calls;
static uint64_t gui_at;
static volatile uint32_t flag;
static jmp_buf finished;
struct sched_task *test_gui;
uint64_t sched_port_time(void) { return now; }
uint32_t sched_port_lock(void) { return 0; }
void sched_port_unlock(uint32_t s) { (void)s; }
void sched_port_compare(uint64_t d) { deadline=d; }
void sched_port_wait(void) { if(fairness) now=deadline; else now+=20; flag=1; }
static void step(struct sched_task *task)
{
    sched_take(task);
    if(calls==3) longjmp(finished,1);
    now+=calls==0 ? 5 : calls==1 ? 17 : 9;
    if(calls==1) { flag=0; sched_wait_flag(&flag); }
    ++calls; sched_signal(task,1);
}
static void app_slice(struct sched_task *task)
{
    sched_take(task); now+=100; sched_wake_at(task,now);
    extern struct sched_task *test_gui;
    sched_defer_for(task,test_gui,now,1000);
}
static void gui_slice(struct sched_task *task)
{
    sched_take(task);
    if(gui_calls) assert(now-gui_at<=33000);
    gui_at=now;
    if(++gui_calls==4) longjmp(finished,1);
    sched_wake_at(task,now+33000);
}
int main(void)
{
    struct sched_task task={"test",step,0,1,UINT64_MAX,0,0}; sched_add(&task);
    if(!setjmp(finished)) sched_run();
    assert(task.busy_ticks==31 && task.max_step_ticks==37 && sched_idle_ticks()==20);
    puts("PASS scheduler busy=31 max_step=37 idle=20");
    task.events=0; task.wake_at=UINT64_MAX;
    fairness=1; now=0;
    struct sched_task app={"app",app_slice,1,0,0,0,0};
    struct sched_task gui={"GUI",gui_slice,2,0,0,0,0};
    test_gui=&gui;
    gui.wake_at=UINT64_MAX;
    app_slice(&app);
    assert(app.wake_at==now);
    puts("PASS static GUI: application slice is not deferred");
    gui.wake_at=0;
    sched_add(&app); sched_add(&gui);
    if(!setjmp(finished)) sched_run();
    assert(gui_calls==4);
    puts("PASS 1 ms application yield: continuous slices allow GUI every 33 ms");
}
