/* File: main.c
 * Spec: soc-testplan SC-07; b2-software 3.4a, 3.5, 3.5a.
 * Description: Send an EDVF header and an in-place full Surface, then 16 EDTM snapshots.
 * Clock domain: clk_sys software.
 */
#include "common.h"
int main(void)
{
    init();
    configure_eth();
    video_descriptors();
    eth_send(TX_DESC, 2u);
    while (read_reg(EDRV32_ETH_BASE, EDRV32_ETH_DONE_COUNT_OFFSET) != 2u) {
    }
    for (unsigned int record = 0; record < 16; record++) {
        volatile uint32_t *item = ddr(TX_BASE + 0x4000u + record * 320u);
        volatile uint32_t *audit = ddr(TX_BASE + 0x2000u + record * 49u * 4u);
        for (unsigned int i = 0; i < 80; i++) item[i] = 0u;
        write_reg(EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_STAT_CTRL_OFFSET,
                  EDRV32_MEM_XBAR_STAT_CTRL_SNAPSHOT_MASK |
                  EDRV32_MEM_XBAR_STAT_CTRL_CLEAR_MASK);
        item[0] = 0x4d544445u;
        item[1] = 0x00010001u;
        item[2] = record;
        item[3] = 1u;
        uint64_t time = clint_time();
        item[4] = (uint32_t)time;
        item[5] = (uint32_t)(time >> 32);
        item[6] = read_reg(EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_WINDOW_CYC_OFFSET);
        item[7] = read_reg(EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_DS_BUSY_OFFSET);
        item[8] = read_reg(EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_DIR_SWITCH_OFFSET);
        for (unsigned int port = 0; port < 7; port++) {
            uint32_t offsets[] = {
                EDRV32_MEM_XBAR_RD_TXN_OFFSET(port), EDRV32_MEM_XBAR_RD_BEAT_OFFSET(port),
                EDRV32_MEM_XBAR_WR_TXN_OFFSET(port), EDRV32_MEM_XBAR_WR_BEAT_OFFSET(port),
                EDRV32_MEM_XBAR_WAIT_SUM_OFFSET(port), EDRV32_MEM_XBAR_WAIT_MAX_OFFSET(port),
                EDRV32_MEM_XBAR_URG_CNT_OFFSET(port)
            };
            for (unsigned int field = 0; field < 7; field++) {
                item[9 + port * 7 + field] = read_reg(EDRV32_MEM_XBAR_BASE, offsets[field]);
                audit[port * 7 + field] = read_reg(EDRV32_MEM_XBAR_BASE, offsets[field]);
            }
        }
        item[71] = EDRV32_CLK_SYS_HZ;
        item[72] = 150000000u;
    }
    volatile uint32_t *descriptor = ddr(TX_DESC);
    descriptor[EDRV32_ETH_TX_DESC_SRC_ADDR_OFFSET / 4u] = TX_BASE + 0x4000u;
    descriptor[EDRV32_ETH_TX_DESC_LEN_OFFSET / 4u] = 16u * 320u;
    descriptor[EDRV32_ETH_TX_DESC_WIN_OFFSET / 4u] = 3u | EDRV32_ETH_TX_DESC_NOTIFY_MASK;
    descriptor[EDRV32_ETH_TX_DESC_OFFSET_OFFSET / 4u] = 0u;
    eth_send(TX_DESC, 1u);
    while (read_reg(EDRV32_ETH_BASE, EDRV32_ETH_DONE_COUNT_OFFSET) != 3u) {
    }
    command(99u, 0u);
    finish(0u);
}
