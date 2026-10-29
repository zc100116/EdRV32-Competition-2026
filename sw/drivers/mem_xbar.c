/* File: mem_xbar.c
 * Spec: mem-subsys-spec 4.1
 * Description: B2 engine operations; caller owns buffer lifetime and valid configuration.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "mem_xbar.h"

/* MEM 4.1: snapshot before clear gives contiguous measurement windows. */
void mem_xbar_snapshot(struct mem_xbar_stats *stats)
{
    mmio_write32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_STAT_CTRL_OFFSET,
                 EDRV32_MEM_XBAR_STAT_CTRL_SNAPSHOT_MASK | EDRV32_MEM_XBAR_STAT_CTRL_CLEAR_MASK);
    stats->window_cycles = mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_WINDOW_CYC_OFFSET);
    stats->downstream_busy = mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_DS_BUSY_OFFSET);
    stats->direction_switches =
        mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_DIR_SWITCH_OFFSET);
    for (unsigned int port = 0; port < 7u; ++port) {
        stats->port[port].rd_txn =
            mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_RD_TXN_OFFSET(port));
        stats->port[port].rd_beat =
            mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_RD_BEAT_OFFSET(port));
        stats->port[port].wr_txn =
            mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_WR_TXN_OFFSET(port));
        stats->port[port].wr_beat =
            mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_WR_BEAT_OFFSET(port));
        stats->port[port].wait_sum =
            mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_WAIT_SUM_OFFSET(port));
        stats->port[port].wait_max =
            mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_WAIT_MAX_OFFSET(port));
        stats->port[port].urgent =
            mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_URG_CNT_OFFSET(port));
    }
}

/* MEM 4.1: P2/P6 rates can be adjusted between arbitration decisions. */
void mem_xbar_rate(unsigned int port, uint32_t rate)
{
    mmio_write32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_RATE_OFFSET(port), rate);
}

/* MEM 4.1: read before clearing ERROR, which also clears these details. */
void mem_xbar_error(uint32_t *port, uint32_t *address, uint32_t *type)
{
    *port = mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_ERR_PORT_OFFSET);
    *address = mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_ERR_ADDR_OFFSET);
    *type = mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_ERR_TYPE_OFFSET);
}
