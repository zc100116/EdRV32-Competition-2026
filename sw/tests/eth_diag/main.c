/* File: main.c
 * Spec: eth-spec 2.2, 2.4–2.7, 4.1–4.3; Task T-ETHDIAG.
 * Description: Scan PHYs, inspect link/delays and broadcast DDR-backed UDP diagnostics.
 * Clock domain: clk_sys CPU; ETH registers/DMA in clk_mem; PHY via MDIO.
 */
#include "eth.h"
#include "uart.h"
#include "clint.h"
#include "sysctrl.h"

/* Match the demo's command window and use separate aligned DDR TX storage. */
#define COMMAND_BASE 0x0a000000u
#define COMMAND_SIZE 0x00010000u
#define TX_DESCRIPTOR 0x0a100000u
#define TX_DATA 0x0a100800u

static unsigned int phy;
static unsigned int delay_next;
static uint32_t clock_hz;

static char *decimal(char *out, uint32_t value)
{
    char reverse[10];
    unsigned int n = 0;
    do {
        reverse[n++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value);
    while (n) *out++ = reverse[--n];
    *out = '\0';
    return out;
}

static void number(uint32_t value)
{
    char text[11];
    decimal(text, value);
    uart_puts(text);
}

static void hex(uint32_t value)
{
    uart_puts("0x");
    for (unsigned int n = 0; n < 8; ++n) {
        uart_putc((uint8_t)"0123456789abcdef"[(value >> (28u - 4u * n)) & 15u]);
    }
}

static uint32_t reg_read(uint32_t offset)
{
    return mmio_read32(EDRV32_ETH_BASE + offset);
}

static void line_hex(const char *name, uint32_t value)
{
    uart_puts(name);
    uart_puts("=");
    hex(value);
    uart_puts("\r\n");
}

static void wait_ticks(uint32_t ticks)
{
    uint64_t until = clint_time() + ticks;
    while (clint_time() < until) __asm__ volatile ("nop");
}

static void phy_reset(void)
{
    /* Same 10 ms assertion / 100 ms release interval as eth_monitor_local_init. */
    eth_phy_reset(1);
    wait_ticks(clock_hz / 100u);
    eth_phy_reset(0);
    wait_ticks(clock_hz / 10u);
    uart_puts("PHY reset\r\n");
}

static void scan(void)
{
    unsigned int found = 0;
    for (unsigned int address = 0; address < 32; ++address) {
        uint16_t id1 = eth_mdio_read(address, 2);
        uint16_t id2 = eth_mdio_read(address, 3);
        uint32_t id = ((uint32_t)id1 << 16) | id2;
        if (id != 0u && id != 0xffffffffu) {
            uart_puts("PHY addr=");
            number(address);
            uart_puts(" PHYID1=");
            hex(id1);
            uart_puts(" PHYID2=");
            hex(id2);
            uart_puts("\r\n");
            if (!found) phy = address;
            found = 1;
        }
    }
    if (!found) uart_puts("MDIO no response; PHY addr=0\r\n");
}

static uint16_t read_page(unsigned int page, unsigned int reg)
{
    eth_mdio_write(phy, 0x1f, (uint16_t)page);
    uint16_t value = eth_mdio_read(phy, reg);
    eth_mdio_write(phy, 0x1f, 0);
    return value;
}

static void delays(void)
{
    uint16_t tx = read_page(0xd08, 0x11);
    uint16_t rx = read_page(0xd08, 0x15);
    line_hex("D08.11", tx);
    line_hex("D08.15", rx);
    uart_puts("TXDLY=");
    number((tx >> 8) & 1u);
    uart_puts(" RXDLY=");
    number((rx >> 3) & 1u);
    uart_puts("\r\n");
}

static void phy_dump(void)
{
    eth_mdio_write(phy, 0x1f, 0);
    line_hex("BMCR", eth_mdio_read(phy, 0));
    line_hex("BMSR.1", eth_mdio_read(phy, 1));
    line_hex("BMSR.2", eth_mdio_read(phy, 1));
    line_hex("ANAR", eth_mdio_read(phy, 4));
    line_hex("ANLPAR", eth_mdio_read(phy, 5));
    line_hex("1000BASE-T status", eth_mdio_read(phy, 10));
    line_hex("PHYSR", read_page(0xa43, 0x1a));
    delays();
}

static void status(void)
{
    uint16_t physr = read_page(0xa43, 0x1a);
    unsigned int speed = (physr >> 4) & 3u;
    uart_puts("link=");
    number((physr >> 2) & 1u);
    uart_puts(" speed=");
    if (speed == 3u) uart_puts("reserved");
    else number(speed == 2u ? 1000u : (speed == 1u ? 100u : 10u));
    uart_puts(" duplex=");
    uart_puts((physr & 8u) ? "full\r\n" : "half\r\n");
    for (unsigned int i = 0; i <= 8; ++i) {
        uart_puts("PERF");
        number(i);
        uart_puts("=");
        number(reg_read(EDRV32_ETH_PERF_OFFSET(i)));
        uart_puts("\r\n");
    }
    uint32_t ip = reg_read(EDRV32_ETH_PEER_IP_OFFSET);
    uart_puts("PEER=");
    for (unsigned int i = 0; i < 4; ++i) {
        if (i) uart_putc('.');
        number((ip >> (24u - 8u * i)) & 255u);
    }
    uart_putc(':');
    number(reg_read(EDRV32_ETH_PEER_PORT_OFFSET));
    uart_puts("\r\n");
    line_hex("STATUS", reg_read(EDRV32_ETH_STATUS_OFFSET));
    line_hex("IRQ_STAT", reg_read(EDRV32_ETH_IRQ_STAT_OFFSET));
    line_hex("ERR_CODE", reg_read(EDRV32_ETH_ERR_CODE_OFFSET));
}

static void cycle_delays(void)
{
    unsigned int combination = delay_next;
    delay_next = (delay_next + 1u) & 3u;
    eth_mdio_write(phy, 0x1f, 0xd08);
    uint16_t tx = eth_mdio_read(phy, 0x11);
    uint16_t rx = eth_mdio_read(phy, 0x15);
    eth_mdio_write(phy, 0x11, (uint16_t)((tx & ~0x100u) | ((combination >> 1) << 8)));
    eth_mdio_write(phy, 0x15, (uint16_t)((rx & ~8u) | ((combination & 1u) << 3)));
    eth_mdio_write(phy, 0x1f, 0);
    eth_mdio_write(phy, 0, eth_mdio_read(phy, 0) | 0x8000u);
    /* BMCR reset is self-clearing; do not access paged registers until complete. */
    while (eth_mdio_read(phy, 0) & 0x8000u) { }
    uart_puts("Delay combination=");
    number(combination);
    uart_puts("\r\n");
    delays();
}

static void broadcast(uint32_t sequence)
{
    /* ETH 2.6: preserve descriptor/data ownership while a previous TX is busy. */
    if (reg_read(EDRV32_ETH_STATUS_OFFSET) & EDRV32_ETH_STATUS_BUSY_MASK) {
        uart_puts("TX busy\r\n");
        return;
    }
    char message[32] = "EDRV32 DIAG ";
    char *end = decimal(message + 12, sequence);
    uint32_t length = (uint32_t)(end - message);
    uint8_t *data = (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + TX_DATA);
    for (uint32_t i = 0; i < length; ++i) data[i] = (uint8_t)message[i];
    struct eth_tx_descriptor *descriptor =
        (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + TX_DESCRIPTOR);
    eth_tx_descriptor_pack(descriptor, TX_DATA, length, 3, 1, 0);
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    eth_send(TX_DESCRIPTOR, 1);
    uart_puts("TX sequence=");
    number(sequence);
    uart_puts("\r\n");
}

int main(void)
{
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    clock_hz = sysctrl_read(SYSCTRL_CLK_SYS_HZ);
    uart_init();
    uart_puts("EDRV32 ETH diagnostic\r\n");
    phy_reset();
    scan();
    phy_dump();
    const struct eth_endpoint local = {{0x02, 0x45, 0x44, 0x52, 0x56, 0x32},
                                      {192, 168, 1, 10}, 5000};
    const struct eth_endpoint peer = {{255, 255, 255, 255, 255, 255},
                                     {255, 255, 255, 255}, 6000};
    eth_local_configure(&local);
    eth_window_configure(3, COMMAND_BASE, COMMAND_SIZE);
    eth_peer_configure(&peer, 5000);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_CTRL_OFFSET, EDRV32_ETH_CTRL_ENABLE_MASK);
    uart_puts("Commands: d=delays r=PHY reset s=status\r\n");
    uint32_t sequence = 0;
    uint64_t next = clint_time() + clock_hz;
    for (;;) {
        uint32_t command = mmio_read32(EDRV32_UART0_BASE + UART_RXDATA);
        if (command & UART_RXDATA_VALID) {
            switch ((uint8_t)command) {
            case 'd': cycle_delays(); break;
            case 'r': phy_reset(); phy_dump(); break;
            case 's': status(); break;
            default: break;
            }
        }
        if (clint_time() >= next) {
            next += clock_hz;
            status();
            broadcast(sequence++);
        }
    }
}
