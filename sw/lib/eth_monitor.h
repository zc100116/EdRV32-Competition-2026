/* File: eth_monitor.h
 * Spec: design 2026-10-29-b2-software 3.4–3.5a; eth-spec 2.4/2.6.
 * Description: Shared demo endpoint and EDTM v1 wire record.
 * Clock domain: clk_sys; memory statistics count clk_mem cycles.
 */
#ifndef EDRV32_ETH_MONITOR_H
#define EDRV32_ETH_MONITOR_H
#include "mem_xbar.h"
#define ETH_MONITOR_BYTES 320u
struct eth_monitor {
    uint32_t sequence;
    uint32_t scene;
    uint64_t time;
    struct mem_xbar_stats memory;
    uint32_t vin[4];
    uint32_t disp[2];
    uint32_t npu[4];
    uint32_t eth[2];
    uint32_t idle_cycles;
    uint32_t system_hz;
    uint32_t video_skips;
};
void eth_monitor_pack(uint8_t out[ETH_MONITOR_BYTES], const struct eth_monitor *record);
/* Reset PHY for 10 ms, settle for 100 ms and configure the demo local endpoint. */
void eth_monitor_local_init(uint32_t clock_hz);
int eth_monitor_peer_known(void);
void eth_monitor_peer_configure(void);
/* Capture the shared timestamp, DDR snapshot and CPU clock fields. */
void eth_monitor_snapshot(struct eth_monitor *record, uint32_t clock_hz);
/* B3R/B3N: caller owns CLINT, invokes tick at 100 Hz and reports nonzero ETH errors. */
/* One application callback runs before the monitor acknowledges RX notifications. */
void eth_monitor_board_set_receive(void (*receive)(uint32_t irq));
void eth_monitor_board_init(uint32_t clock_hz);
uint32_t eth_monitor_board_tick(void);
#endif
