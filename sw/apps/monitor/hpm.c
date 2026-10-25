/* File: hpm.c
 * Spec: cpu-spec 5 (CSR map), 7.1 (event codes).
 * Description: Eight 64-bit counters sample events 1--8 and 9--16 in two runs.
 *              CY, IR and HPM share a single mcountinhibit measurement window.
 * Clock domain: clk_sys.
 */
#include "monitor.h"

const char *const monitor_hpm_names[16] = {
    "HPM 01 dual retire", "HPM 02 single retire", "HPM 03 zero retire",
    "HPM 04 branches", "HPM 05 pair RAW", "HPM 06 pair structural",
    "HPM 07 pair slot1 type", "HPM 08 pair missing slot1", "HPM 09 load-use stall",
    "HPM 10 divide stall", "HPM 11 device wait", "HPM 12 frontend empty",
    "HPM 13 I-cache miss", "HPM 14 D-cache miss", "HPM 15 dirty writeback",
    "HPM 16 branch mispredict"
};

#define CSR_WRITE(csr, value) __asm__ volatile ("csrw " #csr ", %0" :: "r"(value) : "memory")
#define CSR_READ(csr, value) __asm__ volatile ("csrr %0, " #csr : "=r"(value) :: "memory")
#define HPM_INHIBIT 0x7fdu

void monitor_hpm_stop(void)
{
    CSR_WRITE(mcountinhibit, HPM_INHIBIT);
}

void monitor_hpm_start(void)
{
    CSR_WRITE(mcountinhibit, 0u);
}

void monitor_hpm_release(void)
{
    /* Keep HPM frozen outside the benchmark; the normal cycle clock resumes. */
    CSR_WRITE(mcountinhibit, HPM_INHIBIT & ~5u);
}

#define SET_COUNTER(index, event) do { \
    CSR_WRITE(mhpmevent##index, event); \
    CSR_WRITE(mhpmcounter##index, 0u); \
    CSR_WRITE(mhpmcounter##index##h, 0u); \
} while (0)

void monitor_hpm_prepare(unsigned int round)
{
    unsigned int first = round * 8u + 1u;
    monitor_hpm_stop();
    SET_COUNTER(3, first);
    SET_COUNTER(4, first + 1u);
    SET_COUNTER(5, first + 2u);
    SET_COUNTER(6, first + 3u);
    SET_COUNTER(7, first + 4u);
    SET_COUNTER(8, first + 5u);
    SET_COUNTER(9, first + 6u);
    SET_COUNTER(10, first + 7u);
    CSR_WRITE(mcycle, 0u);
    CSR_WRITE(mcycleh, 0u);
    CSR_WRITE(minstret, 0u);
    CSR_WRITE(minstreth, 0u);
}

#define READ_COUNTER(low_csr, high_csr, destination) do { \
    uint32_t low; \
    uint32_t high; \
    CSR_READ(low_csr, low); \
    CSR_READ(high_csr, high); \
    destination = ((uint64_t)high << 32) | low; \
} while (0)

void monitor_hpm_read(uint64_t *events, uint64_t *instructions)
{
    /* Frozen counters need no high/low retry sequence. */
    READ_COUNTER(mhpmcounter3, mhpmcounter3h, events[0]);
    READ_COUNTER(mhpmcounter4, mhpmcounter4h, events[1]);
    READ_COUNTER(mhpmcounter5, mhpmcounter5h, events[2]);
    READ_COUNTER(mhpmcounter6, mhpmcounter6h, events[3]);
    READ_COUNTER(mhpmcounter7, mhpmcounter7h, events[4]);
    READ_COUNTER(mhpmcounter8, mhpmcounter8h, events[5]);
    READ_COUNTER(mhpmcounter9, mhpmcounter9h, events[6]);
    READ_COUNTER(mhpmcounter10, mhpmcounter10h, events[7]);
    READ_COUNTER(minstret, minstreth, *instructions);
}
