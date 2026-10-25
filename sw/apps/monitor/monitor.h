/* File: monitor.h
 * Spec: edrv32-soc-spec 7.5; cpu-spec 7.1.
 * Description: CoreMark reporting, HPM windows and menu peripheral operations.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_MONITOR_H
#define EDRV32_MONITOR_H
#include "coremark.h"
#include "info.h"

#define MONITOR_DEFAULT_ITERATIONS 10u
#define MONITOR_HPM_ROUNDS 2u

extern const char *const monitor_hpm_names[16];
void monitor_core_init(core_results *result, uint32_t iterations);
int monitor_core_crc(const core_results *result);
void monitor_coremark(uint32_t iterations, uint32_t clock_hz);
void monitor_metrics(const uint64_t cycles[2], uint64_t instructions, const uint64_t events[16]);
void monitor_hpm_prepare(unsigned int round);
void monitor_hpm_start(void);
void monitor_hpm_stop(void);
void monitor_hpm_read(uint64_t *events, uint64_t *instructions);
void monitor_hpm_release(void);
void monitor_peripherals(uint32_t clock_hz);
#endif
