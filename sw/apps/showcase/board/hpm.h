/* hpm.h — CPU 7.1; frozen two-round CoreMark counters, clk_sys. */
#ifndef SHOWCASE_HPM_H
#define SHOWCASE_HPM_H
#include <stdint.h>
void board_hpm_prepare(unsigned round);
void board_hpm_start(void);
void board_hpm_stop(void);
void board_hpm_read(uint64_t *cycles,uint64_t *instructions,uint64_t counters[8]);
void board_hpm_release(void);
#endif
