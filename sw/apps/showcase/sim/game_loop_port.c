/* game_loop_port.c — R4 §3.3 host application-clock adapter.
 * Host GUI timer stands in for the board application task; rules remain shared.
 */
#include "theme.h"
#include "game_loop.h"
#include <stdint.h>
#include <stdio.h>
static lv_timer_t *application;
static void tick(lv_timer_t *t) { (void)t; game_loop_step(); }
uint64_t platform_ticks(void) { return (uint64_t)lv_tick_get()*1000; }
uint32_t platform_clock_hz(void) { return 1000000; }
void platform_puts(const char *text) { fputs(text,stdout); }
uint32_t sched_port_lock(void) { return 0; }
void sched_port_unlock(uint32_t lock) { (void)lock; }
void app_wake_at(uint64_t deadline)
{
    (void)deadline;
    if (!application) application = lv_timer_create(tick,16,NULL);
}
