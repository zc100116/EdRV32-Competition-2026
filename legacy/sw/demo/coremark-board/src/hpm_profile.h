#ifndef EDRV32_COREMARK_HPM_PROFILE_H
#define EDRV32_COREMARK_HPM_PROFILE_H

#define HPM_COUNTER_COUNT 40u
#define HPM_ROUND_COUNT 3u

void hpm_prepare(unsigned int round);
void hpm_capture(void);
void hpm_report(unsigned int cycles, unsigned int instret);

#endif
