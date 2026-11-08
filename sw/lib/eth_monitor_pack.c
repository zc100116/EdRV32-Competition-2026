/* File: eth_monitor_pack.c
 * Spec: design 2026-10-29-b2-software 3.5/3.5a.
 * Description: Original demo little-endian EDTM type-1 serialization.
 * Clock domain: none (pure software).
 */
#include "eth_monitor.h"

static void put16(uint8_t *out, uint16_t value)
{
    out[0] = (uint8_t)value;
    out[1] = (uint8_t)(value >> 8);
}

static void put32(uint8_t *out, uint32_t value)
{
    put16(out, (uint16_t)value);
    put16(out + 2, (uint16_t)(value >> 16));
}

static void put64(uint8_t *out, uint64_t value)
{
    put32(out, (uint32_t)value);
    put32(out + 4, (uint32_t)(value >> 32));
}

void eth_monitor_pack(uint8_t out[ETH_MONITOR_BYTES], const struct eth_monitor *r)
{
    for (unsigned int i = 0; i < ETH_MONITOR_BYTES; ++i) {
        out[i] = 0;
    }
    out[0] = 'E'; out[1] = 'D'; out[2] = 'T'; out[3] = 'M';
    put16(out + 4, 1);
    put16(out + 6, 1);
    put32(out + 8, r->sequence);
    put32(out + 12, r->scene);
    put64(out + 16, r->time);
    put32(out + 24, r->memory.window_cycles);
    put32(out + 28, r->memory.downstream_busy);
    put32(out + 32, r->memory.direction_switches);
    for (unsigned int p = 0; p < 7; ++p) {
        const struct mem_xbar_port_stats *s = &r->memory.port[p];
        uint8_t *port = out + 36 + p * 28;
        put32(port, s->rd_txn);
        put32(port + 4, s->rd_beat);
        put32(port + 8, s->wr_txn);
        put32(port + 12, s->wr_beat);
        put32(port + 16, s->wait_sum);
        put32(port + 20, s->wait_max);
        put32(port + 24, s->urgent);
    }
    for (unsigned int i = 0; i < 4; ++i) {
        put32(out + 232 + i * 4, r->vin[i]);
        put32(out + 256 + i * 4, r->npu[i]);
    }
    for (unsigned int i = 0; i < 2; ++i) {
        put32(out + 248 + i * 4, r->disp[i]);
        put32(out + 272 + i * 4, r->eth[i]);
    }
    put32(out + 280, r->idle_cycles);
    put32(out + 284, r->system_hz);
    put32(out + 288, 180000000u);
    put32(out + 292, r->video_skips);
}

