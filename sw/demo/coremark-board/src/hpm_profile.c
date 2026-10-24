#include "core_portme.h"
#include "hpm_profile.h"

/* Forty physical counters; each pass assigns consecutive event IDs. */
#define HPM_SLOTS(X) \
    X(0, 0x323, 0xb03, 0xb83) \
    X(1, 0x324, 0xb04, 0xb84) \
    X(2, 0x325, 0xb05, 0xb85) \
    X(3, 0x326, 0xb06, 0xb86) \
    X(4, 0x327, 0xb07, 0xb87) \
    X(5, 0x328, 0xb08, 0xb88) \
    X(6, 0x329, 0xb09, 0xb89) \
    X(7, 0x32a, 0xb0a, 0xb8a) \
    X(8, 0x32b, 0xb0b, 0xb8b) \
    X(9, 0x32c, 0xb0c, 0xb8c) \
    X(10, 0x32d, 0xb0d, 0xb8d) \
    X(11, 0x32e, 0xb0e, 0xb8e) \
    X(12, 0x32f, 0xb0f, 0xb8f) \
    X(13, 0x330, 0xb10, 0xb90) \
    X(14, 0x331, 0xb11, 0xb91) \
    X(15, 0x332, 0xb12, 0xb92) \
    X(16, 0x333, 0xb13, 0xb93) \
    X(17, 0x334, 0xb14, 0xb94) \
    X(18, 0x335, 0xb15, 0xb95) \
    X(19, 0x336, 0xb16, 0xb96) \
    X(20, 0x337, 0xb17, 0xb97) \
    X(21, 0x338, 0xb18, 0xb98) \
    X(22, 0x339, 0xb19, 0xb99) \
    X(23, 0x33a, 0xb1a, 0xb9a) \
    X(24, 0x33b, 0xb1b, 0xb9b) \
    X(25, 0x33c, 0xb1c, 0xb9c) \
    X(26, 0x33d, 0xb1d, 0xb9d) \
    X(27, 0x33e, 0xb1e, 0xb9e) \
    X(28, 0x33f, 0xb1f, 0xb9f) \
    X(29, 0x7e0, 0x7c0, 0x7d0) \
    X(30, 0x7e1, 0x7c1, 0x7d1) \
    X(31, 0x7e2, 0x7c2, 0x7d2) \
    X(32, 0x7e3, 0x7c3, 0x7d3) \
    X(33, 0x7e4, 0x7c4, 0x7d4) \
    X(34, 0x7e5, 0x7c5, 0x7d5) \
    X(35, 0x7e6, 0x7c6, 0x7d6) \
    X(36, 0x7e7, 0x7c7, 0x7d7) \
    X(37, 0x7e8, 0x7c8, 0x7d8) \
    X(38, 0x7e9, 0x7c9, 0x7d9) \
    X(39, 0x7ea, 0x7ca, 0x7da)

#define WRITE_CSR(csr, value) \
    __asm__ __volatile__("csrw " #csr ", %0" :: "r"((unsigned int)(value)) : "memory")
#define READ_CSR(csr, value) \
    __asm__ __volatile__("csrr %0, " #csr : "=r"(value) :: "memory")

static unsigned int round_r;
static unsigned int first_event_r;
static unsigned int last_event_r;
static unsigned int event_low_r[HPM_COUNTER_COUNT];
static unsigned int event_high_r[HPM_COUNTER_COUNT];

void hpm_prepare(unsigned int round)
{
    round_r = round + 1u;
    first_event_r = round == 0u ? 1u : (round == 1u ? 41u : 81u);
    last_event_r = round == 0u ? 40u : (round == 1u ? 80u : 98u);

    /* Only programmable HPM counters are inhibited. mcycle/minstret run. */
    WRITE_CSR(0x320, 0xfffffff8u);
    WRITE_CSR(0x7f0, 0x7ffu);
#define CONFIGURE(slot, event_csr, low_csr, high_csr) \
    do { \
        unsigned int event_id = first_event_r + (slot); \
        if (event_id > last_event_r) \
            event_id = 0u; \
        WRITE_CSR(event_csr, event_id); \
        WRITE_CSR(low_csr, 0u); \
        WRITE_CSR(high_csr, 0u); \
    } while (0);
    HPM_SLOTS(CONFIGURE)
#undef CONFIGURE
}

void hpm_capture(void)
{
#define CAPTURE(slot, event_csr, low_csr, high_csr) \
    READ_CSR(low_csr, event_low_r[slot]); \
    READ_CSR(high_csr, event_high_r[slot]);
    HPM_SLOTS(CAPTURE)
#undef CAPTURE
}

void hpm_report(unsigned int cycles, unsigned int instret)
{
    unsigned int slot;
    unsigned int count = last_event_r - first_event_r + 1u;
    unsigned int attribution_sum = 0u;

    ee_printf("HPM_BEGIN round=%u events=%u-%u\n",
              round_r, first_event_r, last_event_r);
    ee_printf("HPM cycles=%u instret=%u\n", cycles, instret);
    for (slot = 0u; slot < count; slot++) {
        ee_printf("HPM slot=%u event=%u value=0x%08x%08x\n",
                  slot, first_event_r + slot,
                  event_high_r[slot], event_low_r[slot]);
        if (round_r == 2u && slot < 16u)
            attribution_sum += event_low_r[slot];
    }
    if (round_r == 2u)
        ee_printf("HPM attribution_41_56_sum=%u\n", attribution_sum);
    ee_printf("HPM_END round=%u\n", round_r);
}
