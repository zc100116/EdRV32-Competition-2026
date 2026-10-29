/* File: eth.c
 * Spec: eth-spec 2.1, 2.3–2.7, 4.2
 * Description: B2 engine operations; caller owns buffer lifetime and valid configuration.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "eth.h"

_Static_assert(sizeof(struct eth_tx_descriptor) == EDRV32_ETH_TX_DESC_SIZE, "ETH TX size");

/* ETH 2.1: first octet occupies the most significant register byte. */
uint32_t eth_ipv4_pack(const uint8_t ip[4])
{
    return ((uint32_t)ip[0] << 24) | ((uint32_t)ip[1] << 16) |
           ((uint32_t)ip[2] << 8) | ip[3];
}

/* ETH 2.1: use endpoint byte arrays in human-readable/network order. */
void eth_local_configure(const struct eth_endpoint *local)
{
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_MAC_HI_OFFSET,
                 ((uint32_t)local->mac[0] << 8) | local->mac[1]);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_MAC_LO_OFFSET, eth_ipv4_pack(local->mac + 2));
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_IP_ADDR_OFFSET, eth_ipv4_pack(local->ip));
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_RX_PORT_OFFSET, local->port);
}

/* ETH 4.2: transmit endpoint is stable for the complete descriptor list. */
void eth_peer_configure(const struct eth_endpoint *peer, uint16_t source_port)
{
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_TX_DST_MAC_HI_OFFSET,
                 ((uint32_t)peer->mac[0] << 8) | peer->mac[1]);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_TX_DST_MAC_LO_OFFSET,
                 eth_ipv4_pack(peer->mac + 2));
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_TX_DST_IP_OFFSET, eth_ipv4_pack(peer->ip));
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_TX_PORT_OFFSET,
                 ((uint32_t)source_port << EDRV32_ETH_TX_PORT_TX_SRC_PORT_POS) | peer->port);
}

/* ETH 2.4: software starts a new block with a zero committed-byte count. */
void eth_window_configure(unsigned int window, uint32_t base, uint32_t size)
{
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_WIN_BASE_OFFSET(window), base);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_WIN_SIZE_OFFSET(window), size);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_WIN_BYTES_OFFSET(window), 0u);
}

/* ETH 2.4: cumulative byte count includes repeated writes and wraps at 32 bits. */
uint32_t eth_window_bytes(unsigned int window)
{
    return mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_WIN_BYTES_OFFSET(window));
}

/* ETH 2.6: ignored bits are zero, while source and length follow generated field masks. */
void eth_tx_descriptor_pack(struct eth_tx_descriptor *descriptor, uint32_t source,
                            uint32_t bytes, unsigned int window, unsigned int notify,
                            uint32_t offset)
{
    for (unsigned int i = 0; i < EDRV32_ETH_TX_DESC_SIZE / sizeof(uint32_t); ++i) {
        descriptor->word[i] = 0u;
    }
    descriptor->word[EDRV32_ETH_TX_DESC_SRC_ADDR_OFFSET / sizeof(uint32_t)] =
        source & EDRV32_ETH_TX_DESC_SRC_ADDR_MASK;
    descriptor->word[EDRV32_ETH_TX_DESC_LEN_OFFSET / sizeof(uint32_t)] =
        bytes & EDRV32_ETH_TX_DESC_LEN_MASK;
    descriptor->word[EDRV32_ETH_TX_DESC_WIN_OFFSET / sizeof(uint32_t)] =
        (window & EDRV32_ETH_TX_DESC_WIN_MASK) |
        ((notify << EDRV32_ETH_TX_DESC_NOTIFY_POS) & EDRV32_ETH_TX_DESC_NOTIFY_MASK);
    descriptor->word[EDRV32_ETH_TX_DESC_OFFSET_OFFSET / sizeof(uint32_t)] = offset;
}

/* ETH 2.3: application header is network order although block contents may be little-endian. */
void eth_header_pack(uint8_t header[8], unsigned int window, unsigned int notify,
                     uint32_t offset)
{
    for (unsigned int i = 0; i < EDRV32_ETH_APP_HEADER_SIZE; ++i) {
        header[i] = 0u;
    }
    header[EDRV32_ETH_APP_HEADER_WIN_OFFSET] = window & EDRV32_ETH_APP_HEADER_WIN_MASK;
    header[EDRV32_ETH_APP_HEADER_FLAGS_OFFSET] =
        (notify << EDRV32_ETH_APP_HEADER_NOTIFY_POS) & EDRV32_ETH_APP_HEADER_NOTIFY_MASK;
    for (unsigned int i = 0; i < sizeof(offset); ++i) {
        header[EDRV32_ETH_APP_HEADER_OFFSET_OFFSET + i] = (uint8_t)(offset >> (24u - 8u * i));
    }
}

/* ETH 2.6: hardware performs packetization, UDP/IP headers, FCS and terminal NOTIFY. */
void eth_send(uint32_t descriptors, uint32_t count)
{
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_DESC_BASE_OFFSET, descriptors);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_DESC_COUNT_OFFSET, count);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_DOORBELL_OFFSET, 1u);
}

/* ETH 2.7: assertion is active high in PHY_CTRL, inverted at the PHY reset pin. */
void eth_phy_reset(unsigned int asserted)
{
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_PHY_CTRL_OFFSET,
                 asserted << EDRV32_ETH_PHY_CTRL_PHY_RST_POS);
}

/* ETH 2.7: BUSY is the hardware completion handshake, without software timeout/retry. */
static uint32_t mdio_wait(void)
{
    uint32_t status;
    do {
        status = mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_MDIO_STAT_OFFSET);
    } while ((status & EDRV32_ETH_MDIO_STAT_BUSY_MASK) != 0u);
    return status;
}

/* ETH 2.7: command writes must be separated by BUSY completion. */
void eth_mdio_write(unsigned int phy, unsigned int reg, uint16_t value)
{
    (void)mdio_wait();
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_MDIO_CMD_OFFSET,
                 (phy << EDRV32_ETH_MDIO_CMD_PHY_POS) | reg |
                 EDRV32_ETH_MDIO_CMD_WRITE_MASK |
                 ((uint32_t)value << EDRV32_ETH_MDIO_CMD_WDATA_POS));
    (void)mdio_wait();
}

/* ETH 2.7: return exactly the Clause 22 read data exposed by the controller. */
uint16_t eth_mdio_read(unsigned int phy, unsigned int reg)
{
    (void)mdio_wait();
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_MDIO_CMD_OFFSET,
                 (phy << EDRV32_ETH_MDIO_CMD_PHY_POS) | reg);
    return (uint16_t)(mdio_wait() >> EDRV32_ETH_MDIO_STAT_RDATA_POS);
}
