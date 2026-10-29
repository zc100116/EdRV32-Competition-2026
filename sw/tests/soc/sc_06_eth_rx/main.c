/* File: main.c
 * Spec: soc-testplan SC-06; eth 2.2-2.5.
 * Description: Receive 64 KiB, observe NOTIFY through PLIC and check exact bytes/drop counters.
 * Clock domain: clk_sys software.
 */
#include "common.h"
int main(void)
{
    init();
    configure_eth();
    command(4u, 0u);
    wait_irq(EDRV32_PLIC_SOURCE_ETH, 1u);
    equal("WIN2_BYTES", 65536u, read_reg(EDRV32_ETH_BASE, EDRV32_ETH_WIN_BYTES_OFFSET(2)));
    for (unsigned int position = 0; position < 65536u; position++) {
        uint8_t actual = ((volatile uint8_t *)ddr(RX_BASE))[position];
        if (actual != (uint8_t)(position * 73u + 19u)) {
            uart_puts("RX byte position=");
            print_hex(position);
            equal("WIN2 data", (uint8_t)(position * 73u + 19u), actual);
        }
    }
    equal("NOTIFY2 event", EDRV32_ETH_IRQ_STAT_RX_NOTIFY2_MASK,
          events[EDRV32_PLIC_SOURCE_ETH]);
    equal("accepted packets", 64u, read_reg(EDRV32_ETH_BASE, EDRV32_ETH_PERF_OFFSET(1)));
    equal("checksum drop", 1u, read_reg(EDRV32_ETH_BASE, EDRV32_ETH_PERF_OFFSET(4)));
    equal("port drop", 1u, read_reg(EDRV32_ETH_BASE, EDRV32_ETH_PERF_OFFSET(5)));
    equal("ARP replies", 1u, read_reg(EDRV32_ETH_BASE, EDRV32_ETH_PERF_OFFSET(8)));
    command(99u, 0u);
    finish(0u);
}
