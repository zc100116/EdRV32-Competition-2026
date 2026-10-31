/* File: session.h
 * Spec: edrv32-soc-spec 6.1, 7.5(3a).
 * Description: Shared little-endian load session parsing and byte-count comparison.
 * Clock domain: clk_sys (also compiled by host tests).
 */
#ifndef EDRV32_BOOT_SESSION_H
#define EDRV32_BOOT_SESSION_H
#include "boot.h"

#define BOOT_MAX_SEGMENTS 16u
#define BOOT_ETH_SRAM_OFFSET 0x1000u

struct boot_segment {
    uint32_t address;
    uint32_t length;
};
struct boot_session {
    uint32_t count;
    uint32_t entry;
    struct boot_segment segments[BOOT_MAX_SEGMENTS];
};

static inline uint32_t boot_word(const volatile uint8_t *bytes)
{
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static inline int boot_session_parse(struct boot_session *session,
                                     const volatile uint8_t *bytes)
{
    session->count = boot_word(bytes);
    session->entry = boot_word(bytes + 4u);
    if (session->count < 1u || session->count > BOOT_MAX_SEGMENTS ||
        !boot_run_address(session->entry)) return 0;
    for (uint32_t i = 0u; i < session->count; ++i) {
        struct boot_segment *segment = &session->segments[i];
        segment->address = boot_word(bytes + 8u + 8u * i);
        segment->length = boot_word(bytes + 12u + 8u * i);
        if (!boot_load_range(segment->address, segment->length)) return 0;
    }
    return 1;
}

static inline void boot_session_bytes(const struct boot_session *session,
                                      uint32_t *ddr, uint32_t *stage)
{
    *ddr = 0u;
    *stage = 8u + 8u * session->count;
    for (uint32_t i = 0u; i < session->count; ++i) {
        const struct boot_segment *segment = &session->segments[i];
        if (segment->address >= EDRV32_DDR_BASE) *ddr += segment->length;
        else *stage += segment->length;
    }
}

static inline int boot_session_complete(const struct boot_session *session,
                                        uint32_t ddr_bytes, uint32_t stage_bytes)
{
    uint32_t ddr;
    uint32_t stage;
    boot_session_bytes(session, &ddr, &stage);
    return ddr == ddr_bytes && stage == stage_bytes;
}
#endif
