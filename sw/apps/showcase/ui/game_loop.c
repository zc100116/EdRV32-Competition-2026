/* game_loop.c — R4 §3.3.2; fixed simulation deadlines, bounded catch-up.
 * Application task calls no LVGL. Snapshot copies occur outside IRQ locks.
 */
#include "game_loop.h"
#include "../platform.h"
#include "../apps.h"
#include <port.h>
#include <string.h>
static game_loop_config config;
static bool active;
static unsigned published, reading = 3, sequence, consumed, draws, steps, late;
static uint64_t deadline, report_at, spent;
void game_loop_start(const game_loop_config *next)
{
    config = *next;
    published = 0;
    reading = 3;
    sequence = consumed = draws = steps = late = 0;
    spent = 0;
    uint64_t now = platform_ticks();
    deadline = now;
    report_at = now+platform_clock_hz();
    uint32_t lock = sched_port_lock();
    active = true;
    sched_port_unlock(lock);
    app_wake_at(now);
}
void game_loop_stop(void)
{
    uint32_t lock = sched_port_lock();
    active = false;
    sched_port_unlock(lock);
}
static void publish(void)
{
    unsigned slot = 0;
    uint32_t lock = sched_port_lock();
    while (slot == published || slot == reading) ++slot;
    sched_port_unlock(lock);
    config.snapshot(config.context,config.buffers[slot]);
    lock = sched_port_lock();
    published = slot;
    ++sequence;
    sched_port_unlock(lock);
}
void game_loop_step(void)
{
    if (!active) return;
    uint64_t now = platform_ticks();
    uint64_t period = platform_clock_hz()/60;
    unsigned count = 0;
    /* One due step and at most two catch-up steps. */
    while (now >= deadline && count < 3) {
        uint64_t start = platform_ticks();
        config.step(config.context);
        spent += platform_ticks()-start;
        publish();
        ++steps;
        if (count) ++late;
        ++count;
        deadline += period;
        now = platform_ticks();
    }
    if (now >= deadline) {
        late += (unsigned)((now-deadline)/period+1);
        deadline = now+period;
    }
    if (now >= report_at) {
        uint32_t lock = sched_port_lock();
        unsigned painted = draws;
        draws = 0;
        sched_port_unlock(lock);
        config.report(config.context,painted,steps,late,
            (unsigned)(spent*1000000/platform_clock_hz()/steps));
        steps = late = 0;
        spent = 0;
        report_at = now+platform_clock_hz();
    }
    app_wake_at(deadline);
}
bool game_loop_read(void *destination)
{
    uint32_t lock = sched_port_lock();
    unsigned version = sequence;
    if (version == consumed) { sched_port_unlock(lock); return false; }
    unsigned slot = published;
    reading = slot;
    sched_port_unlock(lock);
    memcpy(destination,config.buffers[slot],config.bytes);
    lock = sched_port_lock();
    consumed = version;
    reading = 3;
    sched_port_unlock(lock);
    return true;
}
void game_loop_drawn(void)
{
    uint32_t lock = sched_port_lock();
    ++draws;
    sched_port_unlock(lock);
}
