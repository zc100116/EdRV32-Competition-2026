/* File: eth_monitor_board.c
 * Spec: design 2026-10-29-b2-software 3.5/3.5a; eth-spec 2.4/2.6.
 * Description: B3R/B3N WIN3 peer setup and the demo 100 Hz/16-record DDR monitor path.
 * Clock domain: clk_sys; CPU writes noncached DDR, ETH owns TX until DONE_COUNT.
 */
#include "eth_monitor.h"
#include "eth.h"
#include "clint.h"
#include "info.h"

/* Same reserved network region as demo; outside S3 and board_npu working storage. */
#define COMMAND_BASE 0x0a000000u
#define COMMAND_SIZE 0x00010000u
#define TX_DESCRIPTORS 0x0a100000u
#define TX_MONITOR 0x0a100800u
#define MONITOR_RING 0x0a102000u
#define MONITOR_CAPACITY 1024u

static void (*receive_callback)(uint32_t irq);

void eth_monitor_board_set_receive(void (*receive)(uint32_t irq))
{
    receive_callback = receive;
}

static uint32_t clock_hz;
static uint32_t sequence;
static uint32_t produced;
static uint32_t consumed;
static uint32_t tx_done;
static uint32_t tx_active;
static uint32_t previous_received;
static uint32_t sent_bytes;
static uint32_t previous_sent;

static void *uncached(uint32_t address)
{
    return (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + address);
}

void eth_monitor_board_init(uint32_t system_hz)
{
    clock_hz = system_hz;
    eth_monitor_local_init(clock_hz);
    eth_window_configure(3, COMMAND_BASE, COMMAND_SIZE);
    engine_control(ENGINE_ETH, EDRV32_ETH_CTRL_ENABLE_MASK);
    clint_set_compare(clint_time() + clock_hz / 100u);
}

uint32_t eth_monitor_board_tick(void)
{
    struct engine_event event = engine_poll(ENGINE_ETH);
    if (event.error || (event.irq & EDRV32_ETH_IRQ_STAT_ERROR_MASK)) {
        info_hex("ETH ERR_CODE", event.error);
        return 1u;
    }
    if (event.irq & EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK) {
        eth_window_configure(3, COMMAND_BASE, COMMAND_SIZE);
        info_hex("ETH peer IP", mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_IP_OFFSET));
        info_number("ETH peer port", mmio_read32(EDRV32_ETH_BASE +
                                               EDRV32_ETH_PEER_PORT_OFFSET));
    }
    if (receive_callback) receive_callback(event.irq);
    engine_irq_clear(ENGINE_ETH, event.irq);
    if (tx_active && event.done_count - tx_done == 1u) {
        sent_bytes += 16u * ETH_MONITOR_BYTES;
        tx_active = 0;
    }
    struct eth_monitor record;
    record.scene = 0;
    for (unsigned int i = 0; i < 4u; ++i) {
        record.vin[i] = 0;
        record.npu[i] = 0;
    }
    record.disp[0] = 0;
    record.disp[1] = 0;
    record.idle_cycles = 0;
    record.video_skips = 0;
    record.sequence = sequence++;
    eth_monitor_snapshot(&record, clock_hz);
    uint32_t received = engine_perf(ENGINE_ETH, 2);
    record.eth[0] = received - previous_received;
    record.eth[1] = sent_bytes - previous_sent;
    previous_received = received;
    previous_sent = sent_bytes;
    /* Demo policy: advance sequence and discard newest when peer unknown or ring full. */
    if (eth_monitor_peer_known() && produced - consumed < MONITOR_CAPACITY) {
        eth_monitor_pack(uncached(MONITOR_RING +
            (produced % MONITOR_CAPACITY) * ETH_MONITOR_BYTES), &record);
        ++produced;
    }
    if (!tx_active && eth_monitor_peer_known() && produced - consumed >= 16u &&
        (event.status & EDRV32_ETH_STATUS_IDLE_MASK)) {
        uint32_t *destination = uncached(TX_MONITOR);
        for (unsigned int i = 0; i < 16u; ++i) {
            const uint32_t *source = uncached(MONITOR_RING +
                ((consumed + i) % MONITOR_CAPACITY) * ETH_MONITOR_BYTES);
            for (unsigned int word = 0; word < ETH_MONITOR_BYTES / 4u; ++word) {
                destination[i * (ETH_MONITOR_BYTES / 4u) + word] = source[word];
            }
        }
        consumed += 16u;
        eth_tx_descriptor_pack(uncached(TX_DESCRIPTORS), TX_MONITOR,
                               16u * ETH_MONITOR_BYTES, 3, 1, 0);
        eth_monitor_peer_configure();
        tx_done = event.done_count;
        tx_active = 1;
        eth_send(TX_DESCRIPTORS, 1);
    }
    clint_set_compare(record.time + clock_hz / 100u);
    return 0u;
}
