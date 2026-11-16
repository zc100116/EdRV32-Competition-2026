/* tower_loop.c — R4 §3.3.2; deterministic deadline, catch-up and snapshot contract.
 * Host clock and scheduler ports stand in for application task services.
 */
#include "game_loop.h"
#include <assert.h>
#include <stdio.h>
static uint64_t now, wake;
static unsigned locked, calls, reports, report_steps, report_late, report_draws;
static int buffers[3];
uint64_t platform_ticks(void) { return now; }
uint32_t platform_clock_hz(void) { return 60000; }
void app_wake_at(uint64_t deadline) { wake = deadline; }
uint32_t sched_port_lock(void) { assert(!locked); locked = 1; return 0; }
void sched_port_unlock(uint32_t state) { (void)state; assert(locked); locked = 0; }
static void step(void *context) { (void)context; assert(!locked); ++calls; }
static void snapshot(void *context, void *destination)
{
    (void)context;
    assert(!locked);
    *(int *)destination = (int)calls;
}
static void report(void *context, unsigned draws, unsigned steps,
                   unsigned late, unsigned mean_us)
{
    (void)context;
    assert(!locked && mean_us == 0);
    ++reports; report_steps = steps; report_late = late; report_draws = draws;
}
int main(void)
{
    game_loop_config config = {step,snapshot,report,NULL,
        {&buffers[0],&buffers[1],&buffers[2]},sizeof(int)};
    game_loop_start(&config);
    assert(wake == 0);
    int value;
    game_loop_step();
    assert(calls == 1 && wake == 1000 && game_loop_read(&value) && value == 1);
    assert(!game_loop_read(&value));
    now = 3500;
    game_loop_step();
    assert(calls == 4 && wake == 4000 && game_loop_read(&value) && value == 4);
    game_loop_drawn();
    now = 10000;
    game_loop_step();
    assert(calls == 7 && wake == 11000 && game_loop_read(&value) && value == 7);
    now = 60000;
    game_loop_step();
    assert(calls == 10 && wake == 61000);
    assert(reports == 1 && report_steps == 10 && report_late == 57 && report_draws == 1);
    game_loop_stop();
    now = 70000;
    game_loop_step();
    assert(calls == 10);
    puts("PASS tower loop: 60 Hz deadlines, two catch-ups, discarded time, counters,"
         " triple snapshots outside locks and stop");
}
