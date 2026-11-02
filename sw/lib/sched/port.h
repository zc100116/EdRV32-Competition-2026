/* File: port.h
 * Design: showcase 4.1; CPU 5 (WFI ignores global MIE).
 * Description: Internal scheduler port and synchronous LVGL idle accounting.
 * Clock domain: clk_sys or deterministic host clock.
 */
#ifndef SHOWCASE_SCHED_PORT_H
#define SHOWCASE_SCHED_PORT_H
#include <stdint.h>
uint64_t sched_port_time(void);
uint32_t sched_port_lock(void);
void sched_port_unlock(uint32_t state);
void sched_port_compare(uint64_t deadline);
void sched_port_wait(void);
void sched_wait_flag(volatile uint32_t *flag);
#endif
