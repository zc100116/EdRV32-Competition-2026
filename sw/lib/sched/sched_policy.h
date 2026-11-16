/* sched_policy.h — D7/card 93; cooperative hooks erase at compile time, clk_sys. */
#ifndef SHOWCASE_SCHED_POLICY_H
#define SHOWCASE_SCHED_POLICY_H
#include <stdint.h>
#include "port.h"
#define sched_report_format lv_snprintf
static inline void sched_initialize(void (*initialize)(void)) { initialize(); }
static inline void sched_gui_service(void) {}
static inline void sched_gui_barrier(void) {}
static inline uint64_t sched_counter_value(volatile uint64_t *counter) { return *counter; }
static inline void sched_rnd_prepare(void) {}
static inline void sched_rnd_wait(volatile uint32_t *flag) { sched_wait_flag(flag); }
static inline void sched_rnd_complete(void) {}
static inline void sched_exclusive(unsigned active) { (void)active; }
static inline void sched_measure_reset(void) {}
#define SCHED_REPORT_MEASURE()
#define SCHED_REPORT_FORMAT ""
#define SCHED_REPORT_VALUES
#endif
