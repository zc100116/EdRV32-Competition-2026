/* network.c — showcase 4.5.4; sole ETH transmitter, EDSC and EDTM coexist.
 * Notification snapshots are handled in communication context, clk_sys. */
#include "board.h"
#include "games.h"
#include "ddr_map.h"
#include "protocol.h"
#include "records.h"
#include "state.h"
#include "../ui/detection.h"
#include "vision_hooks.h"
#include "../runtime.h"
#include "../platform.h"
#include "../ui/ui_data.h"
#include "eth_monitor.h"
#include "eth.h"
#include "uart.h"
#include <stdio.h>
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
    else if(kind==2) {
        *base=vision_upload_base(); capacity=SHOWCASE_IMAGE_BYTES;
        if(!*base) return 3;
    }
    else { *base=board_game_destination(); capacity=board_game_available(); }
    if(total>capacity) return 3;
    if(kind==1) vision_model_receiving();
    if(kind==2) vision_image_receiving(protocol.seq);
    eth_window_configure(0,*base,total); return 0;
}
static unsigned complete(unsigned kind,uint32_t base,uint32_t bytes,uint32_t *index)
{
    if(kind==3) return board_game_append(bytes,index);
    unsigned status=vision_bulk_done(kind,base,bytes);
    if(status) board_session_fail(status);
    return status ? status : EDSC_PENDING;
}
void board_bulk_complete(unsigned kind)
{ edsc_finish(&protocol,kind,kind==2 ? vision_frame() : 0); }
void board_bulk_cancel(void) { edsc_cancel(&protocol); }
unsigned board_peer(void) { return protocol.peer; }
uint32_t board_image_request(void) { return vision_request(); }
static void state(uint8_t p[56])
{
    uint8_t vision[56] = {0}; vision_state(vision);
    const struct board_state snapshot = {.session=ui_data_session(),
        .error=board_session_error(), .boxes=vision[3],
        .detection=ui_data_detection_config(), .process=ui_data_process_config(),
        .request=record_u32(vision+44), .frame=record_u32(vision+48),
        .image_status=vision[52]};
    board_state_encode(p,&snapshot);
}
static ui_app_t app_target;
static ui_state_t state_target;
static unsigned command(unsigned type,const uint8_t *p,unsigned bytes,uint32_t seq)
{
    (void)seq;
    ui_session_t s=ui_data_session();
    if(type==4) {
        app_target=(ui_app_t)p[0];
        if(p[0]==UI_APP_GAME && p[1]==0) {
            unsigned count; ui_data_games(&count);
            if(record_u16(p+2)>=count) return 2;
        }
        if(p[1] && s.app!=app_target) return 5;
        if(p[1]==1 && s.state!=UI_STATE_RUNNING) return 5;
        if(p[1]==2 && s.state!=UI_STATE_PAUSED) return 5;
        if(p[1]==3 && s.state!=UI_STATE_FAILED) return 5;
        state_target=p[1]==1 ? UI_STATE_PAUSED :
            app_target==UI_APP_NONE ? UI_STATE_IDLE : UI_STATE_RUNNING;
        if(p[1]==0) ui_data_app_open(app_target,record_u16(p+2));
        else if(p[1]==3) ui_data_app_retry();
        else ui_data_app_pause(p[1]==1);
        ui_show_app(app_target,record_u16(p+2));
        return EDSC_PENDING;
    }
    if(type==5) {
        if(s.app!=UI_APP_IMAGE || s.state!=UI_STATE_RUNNING || protocol.active) return 5;
        vision_image_info(record_u16(p),record_u16(p+2),p+8,bytes-8);
    } else if(type==6) {
        ui_process_config_t c={.enabled=record_u32(p),.brightness=(int16_t)record_u16(p+4),
            .contrast=record_u16(p+6),.gamma_tenths=record_u16(p+8),
            .stage1=p[10],.stage2=p[11],.threshold=p[12],.original=p[13],
            .angle=(int16_t)record_u16(p+14),.scale_percent=record_u16(p+16),
            .translate_x=(int16_t)record_u16(p+18),.translate_y=(int16_t)record_u16(p+20)};
        ui_data_process_set(&c);
        return s.app==UI_APP_PROCESS && s.state==UI_STATE_RUNNING ? EDSC_PENDING : 0;
    } else if(type==7) {
        ui_data_detection_threshold(p[0]);
        for(unsigned i=0;i<80;++i)
            ui_data_detection_class(i,(record_u32(p+4+4*(i/32))>>(i%32))&1);
        vision_detection_changed(); platform_gui_wake();
        return (s.app==UI_APP_CAMERA || s.app==UI_APP_IMAGE) &&
            s.state==UI_STATE_RUNNING ? EDSC_PENDING : 0;
    }
    platform_gui_wake();
    return 0;
}
static unsigned progress(unsigned type)
{
    ui_session_t s=ui_data_session();
    if(type==6) {
        if(s.app!=UI_APP_PROCESS || s.state!=UI_STATE_RUNNING) return 0;
        return vision_process_applied() ? 0 : EDSC_PENDING;
    }
    if(type==7) {
        if((s.app!=UI_APP_CAMERA && s.app!=UI_APP_IMAGE) || s.state!=UI_STATE_RUNNING)
            return 0;
        return vision_detection_applied() ? 0 : EDSC_PENDING;
    }
    if(board_session_target()!=app_target) return 6;
    if(s.state==UI_STATE_FAILED) return board_session_error();
    if(s.app!=app_target) return EDSC_PENDING;
    return s.state==state_target ? 0 : EDSC_PENDING;
}
static void cancel(unsigned kind)
{
    eth_window_configure(0,0,0);
    if(kind==1 || kind==2) vision_cancel(kind);
}
void ui_data_image_step(int direction)
{
    uint8_t snapshot[56]; state(snapshot);
    if(snapshot[52]!=UI_IMAGE_RECEIVING && snapshot[52]!=UI_IMAGE_DETECTING)
        edsc_image_step(&protocol,direction);
}
void board_network_init(void)
{
    eth_monitor_local_init(platform_clock_hz());
    eth_window_configure(0,0,0); eth_window_configure(1,0,0);
    eth_window_configure(3,MESSAGE_BASE,1024);
    engine_control(ENGINE_ETH,EDRV32_ETH_CTRL_ENABLE_MASK);
    protocol.ops=(struct edsc_ops){reserve,complete,enqueue,state,command,progress,cancel};
    protocol.build=BUILD_COMMIT;
}
extern void board_memory_sample(const struct mem_xbar_stats *memory);
void board_network_step(void)
{
    static uint32_t peer_ip,peer_port;
    static char peer_report[80];
    uint32_t ip=mmio_read32(EDRV32_ETH_BASE+EDRV32_ETH_PEER_IP_OFFSET);
    uint32_t port=mmio_read32(EDRV32_ETH_BASE+EDRV32_ETH_PEER_PORT_OFFSET);
    if(port && (ip!=peer_ip || port!=peer_port)) {
        peer_ip=ip; peer_port=port;
        snprintf(peer_report,sizeof(peer_report),
            "ETH peer IP: 0x%08lx\r\nETH peer port: %lu\r\n",
            (unsigned long)ip,(unsigned long)port);
        platform_puts(peer_report);
    }

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
        platform_input_received(2);
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
    edsc_poll(&protocol,platform_ticks(),platform_clock_hz());
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
