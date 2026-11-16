/* sched_policy.h — T-VIS-RTOS; shared foreground state and measurements, clk_sys. */
#ifndef SHOWCASE_SCHED_POLICY_H
#define SHOWCASE_SCHED_POLICY_H
#include <stdint.h>
#include "port.h"
#define sched_report_format snprintf
uint32_t sched_critical_enter(void);
void sched_critical_leave(uint32_t state);
void sched_shared_enter(void);
unsigned sched_shared_release(void);
void sched_shared_restore(unsigned depth);
void sched_shared_leave(unsigned *guard);
static inline unsigned sched_shared_guard(void) { sched_shared_enter(); return 0; }
#define SHOWCASE_SHARED() \
    unsigned shared_guard __attribute__((cleanup(sched_shared_leave))) = sched_shared_guard()
void sched_initialize(void (*initialize)(void));
void sched_gui_service(void);
void sched_gui_barrier(void);
static inline uint64_t sched_counter_value(volatile uint64_t *counter)
{
    uint32_t state = sched_port_lock();
    uint64_t value = *counter;
    sched_port_unlock(state);
    return value;
}
void sched_rnd_prepare(void);
void sched_rnd_wait(volatile uint32_t *flag);
void sched_rnd_complete(void);
void sched_exclusive(unsigned active);
struct sched_measurement { unsigned switches, kernel; };
struct sched_measurement sched_measure(void);
void sched_measure_reset(void);
#define SCHED_REPORT_MEASURE() struct sched_measurement sched_m = sched_measure()
#define SCHED_REPORT_FORMAT " ctxsw=%u kern=%u.%u%%"
#define SCHED_REPORT_VALUES , sched_m.switches, sched_m.kernel / 10, sched_m.kernel % 10
#endif
