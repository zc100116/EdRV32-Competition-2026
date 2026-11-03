/* network.c — showcase 4.5.4; sole ETH transmitter, EDSC and EDTM coexist.
 * Notification snapshots are handled in communication context, clk_sys. */
#include "board.h"
#include "games.h"
#include "ddr_map.h"
#include "protocol.h"
#include "vision_hooks.h"
#include "../runtime.h"
#include "../platform.h"
#include "../ui/ui_data.h"
#include "eth_monitor.h"
#include "eth.h"
#include "virtual_input.h"
#include <stdlib.h>
#include <string.h>
#define MESSAGE_BASE SHOWCASE_MESSAGE_BASE
#define TX_DESC SHOWCASE_TX_DESC
#define TX_DATA SHOWCASE_TX_DATA
#define MONITOR_RING SHOWCASE_MONITOR_RING
#define MONITOR_CAPACITY 1024u
struct message { struct message *next; unsigned bytes; uint8_t data[1024]; };
static struct message *head,*tail;
static unsigned tx_echo;
static unsigned tx_active,tx_done,tx_count,tx_bytes,sequence,produced,consumed;
unsigned board_tx_bytes,board_tx_packets,board_echo_count,board_echo_replies;
char board_udp_text[1001];
static struct edsc protocol;

static void *uncached(uint32_t physical)
{ return (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE+physical); }
int board_eth_send(uint32_t descriptors,uint32_t count)
{
    if(tx_active) return 0;
    struct engine_event e=engine_poll(ENGINE_ETH);
    if(!(e.status&EDRV32_ETH_STATUS_IDLE_MASK)) return 0;
    tx_active=1; tx_done=e.done_count; tx_count=count; tx_bytes=0;
    /* Descriptors stay owned by the caller until the hardware completes. */
    const struct eth_tx_descriptor *d=uncached(descriptors);
    for(unsigned i=0;i<count;++i) tx_bytes+=d[i].word[1];
    eth_monitor_peer_configure(); eth_send(descriptors,count); return 1;
}
static void enqueue(const uint8_t *data,unsigned bytes)
{
    if(bytes>=12 && data[4]==0x83 && data[5]==0) ++board_echo_count;
    struct message *m=malloc(sizeof(*m));
    if(!m) { platform_puts("EDSC reply allocation failed\r\n"); platform_stop(); }
    m->next=0; m->bytes=bytes; memcpy(m->data,data,bytes);
    if(tail) tail->next=m; else head=m;
    tail=m;
}
static unsigned reserve(unsigned kind,uint32_t total,uint32_t *base)
{
    uint32_t capacity;
    if(kind==1) { *base=SHOWCASE_MODEL_BASE; capacity=SHOWCASE_MODEL_BYTES; }
    else if(kind==2) { *base=SHOWCASE_IMAGE_BASE; capacity=SHOWCASE_IMAGE_BYTES; }
    else { *base=board_game_destination(); capacity=board_game_available(); }
    if(total>capacity) return 3;
    eth_window_configure(0,*base,total); return 0;
}
static unsigned complete(unsigned kind,uint32_t base,uint32_t bytes,uint32_t *index)
{
    if(kind==3) return board_game_append(bytes,index);
    if(kind==2 && bytes!=1280*720*2) return 2;
    unsigned status=vision_bulk_done(kind,base,bytes);
    return status ? status : 4;
}
void board_bulk_complete(unsigned kind) { edsc_finish(&protocol,kind); }
void board_network_init(void)
{
    eth_monitor_local_init(platform_clock_hz());
    eth_window_configure(0,0,0); eth_window_configure(1,0,0);
    eth_window_configure(3,MESSAGE_BASE,1024);
    engine_control(ENGINE_ETH,EDRV32_ETH_CTRL_ENABLE_MASK);
    protocol.ops=(struct edsc_ops){reserve,complete,vision_camera,enqueue};
}
extern void board_memory_sample(const struct mem_xbar_stats *memory);
void board_network_step(void)
{
    struct engine_event e=engine_poll(ENGINE_ETH);
    if(e.error || (e.irq&EDRV32_ETH_IRQ_STAT_ERROR_MASK)) {
        platform_puts("ETH error "); platform_put_hex(e.error); platform_stop(); }
    if(tx_active && e.done_count-tx_done>=tx_count) {
        board_tx_packets+=engine_perf(ENGINE_ETH,10); board_tx_bytes+=tx_bytes;
        if(tx_echo) ++board_echo_replies;
        tx_echo=0; tx_active=0;
    }
    if(e.irq&EDRV32_ETH_IRQ_STAT_RX_NOTIFY2_MASK) {
        virtual_input_network(uncached(VIRTUAL_INPUT_BASE));
        eth_window_configure(2,VIRTUAL_INPUT_BASE,VIRTUAL_INPUT_BYTES);
    }
    if(e.irq&EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK) {
        unsigned bytes=eth_window_bytes(3);
        const uint8_t *data=uncached(MESSAGE_BASE);
        unsigned n=bytes>1000 ? 1000 : bytes;
        memcpy(board_udp_text,data,n); board_udp_text[n]=0;
        edsc_message(&protocol,data,bytes);
        eth_window_configure(3,MESSAGE_BASE,1024);
    }
    if(e.irq&EDRV32_ETH_IRQ_STAT_RX_NOTIFY0_MASK) {
        unsigned bytes=eth_window_bytes(0); eth_window_configure(0,0,0);
        edsc_bulk(&protocol,bytes);
    }
    engine_irq_clear(ENGINE_ETH,e.irq);
    static uint64_t next_monitor;
    uint64_t now=platform_ticks();
    if(now>=next_monitor) {
        struct eth_monitor r={.sequence=sequence++,.time=now,.system_hz=platform_clock_hz()};
        mem_xbar_snapshot(&r.memory); board_memory_sample(&r.memory);
        r.eth[0]=engine_perf(ENGINE_ETH,2); r.eth[1]=board_tx_bytes;
        if(eth_monitor_peer_known() && produced-consumed<MONITOR_CAPACITY) {
            eth_monitor_pack(uncached(MONITOR_RING+
                (produced%MONITOR_CAPACITY)*ETH_MONITOR_BYTES),&r); ++produced;
        }
        next_monitor=now+platform_clock_hz()/100;
    }
    if(tx_active || !eth_monitor_peer_known()) return;
    if(head) {
        struct message *m=head;
        memcpy(uncached(TX_DATA),m->data,m->bytes);
        eth_tx_descriptor_pack(uncached(TX_DESC),TX_DATA,m->bytes,3,1,0);
        if(board_eth_send(TX_DESC,1)) {
            tx_echo=m->bytes>=12 && m->data[4]==0x83 && m->data[5]==0;
            head=m->next; if(!head) tail=0; free(m);
        }
    } else if(produced-consumed>=16) {
        for(unsigned i=0;i<16;++i) memcpy((uint8_t *)uncached(TX_DATA)+i*ETH_MONITOR_BYTES,
            uncached(MONITOR_RING+((consumed+i)%MONITOR_CAPACITY)*ETH_MONITOR_BYTES),
            ETH_MONITOR_BYTES);
        eth_tx_descriptor_pack(uncached(TX_DESC),TX_DATA,16*ETH_MONITOR_BYTES,3,1,0);
        if(board_eth_send(TX_DESC,1)) consumed+=16;
    }
}
void ui_data_debug_echo(void)
{
    /* The PC supplies ECHO payloads; this button starts a fresh observed series. */
    board_echo_count=board_echo_replies=0;
}
