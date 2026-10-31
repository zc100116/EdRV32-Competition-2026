/* File: eth.h
 * Spec: eth-spec 2.1, 2.3–2.7, 4.2
 * Description: B2 media engine software interface.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_ETH_H
#define EDRV32_ETH_H
#include "engine.h"
struct eth_endpoint {
    uint8_t mac[6];
    uint8_t ip[4];
    uint16_t port;
};
struct eth_tx_descriptor { uint32_t word[8]; };
/* ETH 2.1: pack four network-order octets into a register value. */
uint32_t eth_ipv4_pack(const uint8_t ip[4]);
/* ETH 2.1, 4.2: set local MAC, IP and UDP receive port while idle. */
void eth_local_configure(const struct eth_endpoint *local);
/* ETH 2.1, 4.2: set peer MAC/IP and local/remote UDP transmit ports while idle. */
void eth_peer_configure(const struct eth_endpoint *peer, uint16_t source_port);
/* ETH 2.4: configure one receive window (physical address) and clear its byte count. */
void eth_window_configure(unsigned int window, uint32_t base, uint32_t size);
/* ETH 2.4: read committed receive bytes; NOTIFY guarantees preceding writes completed. */
uint32_t eth_window_bytes(unsigned int window);
/* ETH 2.6: pack one 32-byte TX descriptor with reserved words zero. */
void eth_tx_descriptor_pack(struct eth_tx_descriptor *descriptor, uint32_t source,
                            uint32_t bytes, unsigned int window, unsigned int notify,
                            uint32_t offset);
/* ETH 2.3: pack the eight-byte application header in network byte order. */
void eth_header_pack(uint8_t header[8], unsigned int window, unsigned int notify,
                     uint32_t offset);
/* ETH 2.6: submit an already coherent physical descriptor list; keep source until DONE. */
void eth_send(uint32_t descriptors, uint32_t count);
/* Minimum UDP packet start interval in clk_mem cycles; zero selects line rate. */
void eth_set_tx_gap(uint32_t cycles);
/* ETH 2.7: assert (1) or release (0) PHY reset; caller supplies PHY manual timing. */
void eth_phy_reset(unsigned int asserted);
/* ETH 2.7: issue a blocking Clause 22 register write; no retry or timeout. */
void eth_mdio_write(unsigned int phy, unsigned int reg, uint16_t value);
/* ETH 2.7: issue a blocking Clause 22 register read; no retry or timeout. */
uint16_t eth_mdio_read(unsigned int phy, unsigned int reg);
#endif
