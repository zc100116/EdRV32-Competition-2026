/* fabric.c — SoC 6.4.1 / P5b 9.3; preserve all SNAPSHOT|CLEAR intervals.
 * Telemetry and benchmark share cumulative totals instead of stealing windows.
 * Clock domain: clk_sys cooperative foreground.
 */
#include "fabric.h"
static struct board_fabric_totals totals;
void board_fabric_sample(const struct mem_xbar_stats *sample)
{
    totals.cycles += sample->window_cycles;
    for (unsigned p = 0; p < 2; ++p) {
        const struct mem_xbar_port_stats *s = &sample->port[p == 0 ? 4 : 0];
        totals.port[p][0] += s->rd_txn;
        totals.port[p][1] += s->wr_txn;
        totals.port[p][2] += s->rd_beat;
        totals.port[p][3] += s->wr_beat;
        totals.port[p][4] += s->wait_sum;
    }
}
struct board_fabric_totals board_fabric_totals(void) { return totals; }
