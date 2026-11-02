/* File: runtime.h
 * Design: showcase 4.1/4.2.
 * Description: Core service tasks and GUI completion handoff.
 * Clock domain: clk_sys.
 */
#ifndef SHOWCASE_RUNTIME_H
#define SHOWCASE_RUNTIME_H
#include "sched.h"
extern struct sched_task communication_task;
extern struct sched_task application_task;
extern struct sched_task gui_task;
void showcase_input_event(void);
void showcase_input_dispatch(void);
void showcase_input_sample(uint32_t keys);
void showcase_cpu_report_init(void);
void showcase_cpu_report(void);
void showcase_gui_disp_event(uint32_t irq);
void showcase_communication_step(struct sched_task *task);
void showcase_gui_restore(void);
void showcase_gui_step(struct sched_task *task);
uint32_t showcase_gui_frames(void);
uint8_t showcase_gui_paused(void);
uint8_t showcase_launcher_active(void);
int showcase_network_link(void);
uint32_t showcase_network_tx_packets(void);
#endif
