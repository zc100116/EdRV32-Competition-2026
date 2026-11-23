/* File: main.c
 * Spec: gpu-soc-testplan ST-13; visual soc-testplan SC-06, BIOS load.
 * Description: After real ETH BIOS loading, validate the 64 KiB RX window regression.
 * Clock domain: clk_sys software; Ethernet RX/TX clocks external.
 */
#include "../gpu_drivers/test.h"
#include "regs/eth_regs.h"

static void write_eth(uint32_t offset, uint32_t value)
{
    mmio_write32(EDRV32_ETH_BASE + offset, value);
}
static uint32_t read_eth(uint32_t offset)
{
    return mmio_read32(EDRV32_ETH_BASE + offset);
}
int main(void)
{
    test_init();
    test_equal("ETH loader DDR segment", 0x1234abcdu,
               *(volatile uint32_t *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + 0x200000u));
    /* Reset the loader's ETH state before reproducing the visual SC-06 setup. */
    write_eth(EDRV32_ETH_CTRL_OFFSET, EDRV32_ETH_CTRL_SOFT_RST_MASK);
    while ((read_eth(EDRV32_ETH_STATUS_OFFSET) & EDRV32_ETH_STATUS_IDLE_MASK) == 0u) {
    }
    write_eth(EDRV32_ETH_MAC_LO_OFFSET, 0x00000001u);
    write_eth(EDRV32_ETH_MAC_HI_OFFSET, 0x0200u);
    write_eth(EDRV32_ETH_IP_ADDR_OFFSET, 0xc0a80164u);
    write_eth(EDRV32_ETH_RX_PORT_OFFSET, 9000u);
    write_eth(EDRV32_ETH_TX_DST_MAC_LO_OFFSET, 0x00000002u);
    write_eth(EDRV32_ETH_TX_DST_MAC_HI_OFFSET, 0x0200u);
    write_eth(EDRV32_ETH_TX_DST_IP_OFFSET, 0xc0a80101u);
    write_eth(EDRV32_ETH_TX_PORT_OFFSET, (9000u << 16) | 9001u);
    write_eth(EDRV32_ETH_WIN_BASE_OFFSET(2), 0x09000000u);
    write_eth(EDRV32_ETH_WIN_SIZE_OFFSET(2), 65536u);
    write_eth(EDRV32_ETH_IRQ_EN_OFFSET, EDRV32_ETH_IRQ_EN_RX_NOTIFY2_MASK);
    plic_set_priority(EDRV32_PLIC_SOURCE_ETH, 1u);
    plic_set_enable(1u << EDRV32_PLIC_SOURCE_ETH);
    plic_set_threshold(0u);
    write_eth(EDRV32_ETH_CTRL_OFFSET, EDRV32_ETH_CTRL_ENABLE_MASK);
    test_external(13u);
    while ((plic_pending() & (1u << EDRV32_PLIC_SOURCE_ETH)) == 0u) {
    }
    unsigned int source = plic_claim();
    test_equal("ETH PLIC source", EDRV32_PLIC_SOURCE_ETH, source);
    test_equal("ETH notify", EDRV32_ETH_IRQ_STAT_RX_NOTIFY2_MASK,
               read_eth(EDRV32_ETH_IRQ_STAT_OFFSET));
    write_eth(EDRV32_ETH_IRQ_STAT_OFFSET, EDRV32_ETH_IRQ_STAT_RX_NOTIFY2_MASK);
    plic_complete(source);
    test_equal("ETH RX bytes", 65536u, read_eth(EDRV32_ETH_WIN_BYTES_OFFSET(2)));
    for (uint32_t i = 0; i < 65536u; ++i) {
        uint8_t actual = ((volatile uint8_t *)(uintptr_t)
                          (EDRV32_DDR_UNCACHED_BASE + 0x09000000u))[i];
        test_equal("ETH RX data", (uint8_t)(i * 73u + 19u), actual);
    }
    test_equal("accepted", 64u, read_eth(EDRV32_ETH_PERF_OFFSET(1)));
    test_equal("checksum drop", 1u, read_eth(EDRV32_ETH_PERF_OFFSET(4)));
    test_equal("port drop", 1u, read_eth(EDRV32_ETH_PERF_OFFSET(5)));
    test_equal("ARP reply", 1u, read_eth(EDRV32_ETH_PERF_OFFSET(8)));
    uart_puts("PASS ST-13 ETH load and receive\r\n");
    test_finish(0u);
}
