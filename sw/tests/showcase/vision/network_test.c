/* network_test.c — P5c 10.3 / eth-spec 4.1; real vision and network services.
 * Hardware model ignores DOORBELL when an RX write wins the submission race.
 * Host clock; production protocol, cancellation, TX ownership and post slices.
 */
#ifndef NETWORK_INTEGRATION
#define NETWORK_INTEGRATION
#endif
#define BUILD_COMMIT "p5c-test"
#include "runtime_test.c"
#include "../../../apps/showcase/board/network.c"
static uint32_t network_irq, receive_bytes;
static unsigned tx_busy, rx_busy, ignore_next, ignored, rings, states, hellos, image_sends;
static uint32_t hardware_desc, hardware_count;
static struct eth_tx_descriptor held[3];
static uint32_t wire_seq;
ui_session_t ui_data_session(void) { return (ui_session_t){UI_APP_PIPELINE, UI_STATE_RUNNING,0,1}; }
unsigned board_session_error(void) { return 0; }
ui_app_t board_session_target(void) { return UI_APP_PIPELINE; }
void ui_data_app_open(ui_app_t app, unsigned arg) { (void)app; (void)arg; }
void ui_data_app_retry(void) {}
void ui_data_app_pause(bool paused) { vision_pause(paused); }
void ui_show_app(ui_app_t app, unsigned arg) { (void)app; (void)arg; }
const ui_game_t *ui_data_games(unsigned *count) { *count=0; return NULL; }
uint32_t board_game_destination(void) { return 0; }
unsigned board_game_available(void) { return 0; }
unsigned board_game_append(unsigned bytes,uint32_t *index)
{ (void)bytes; (void)index; return 0; }
void platform_put_hex(uint32_t value) { (void)value; }
void platform_input_received(unsigned source) { (void)source; }
void virtual_input_network(const volatile uint8_t *data) { (void)data; }
void board_memory_sample(const struct mem_xbar_stats *memory) { (void)memory; }
void mem_xbar_snapshot(struct mem_xbar_stats *memory) { memset(memory,0,sizeof *memory); }
void eth_monitor_pack(uint8_t out[ETH_MONITOR_BYTES],const struct eth_monitor *r)
{ (void)r; memset(out,0,ETH_MONITOR_BYTES); }
void eth_monitor_local_init(uint32_t hz) { (void)hz; }
int eth_monitor_peer_known(void) { return 1; }
void eth_monitor_peer_configure(void) {}
unsigned engine_perf(enum engine_id engine,unsigned counter)
{ (void)engine; (void)counter; return 0; }
void engine_irq_clear(enum engine_id engine,uint32_t flags)
{ assert(engine==ENGINE_ETH); network_irq &= ~flags; }
struct engine_event engine_poll(enum engine_id engine)
{
    if(engine==ENGINE_ETH) return (struct engine_event){.status=tx_busy||rx_busy ? 1 : 2,
        .irq=network_irq,.done_count=done_count};
    if(engine==ENGINE_DISP) return (struct engine_event){.status=
        display_enabled||display_scanned ? 1 : 2};
    return (struct engine_event){.status=2};
}
void eth_send(uint32_t descriptors,uint32_t count)
{
    ++rings;
    if(ignore_next) {
        ignore_next=0; ++ignored; rx_busy=1;
        return; /* RX became BUSY between STATUS read and DOORBELL write. */
    }
    assert(!tx_busy && !rx_busy && count<=3);
    hardware_desc=descriptors; hardware_count=count;
    memcpy(held,physical(descriptors),count*sizeof *held);
    tx_busy=1;
    if(descriptors==VISION_TX_DESCRIPTORS) ++image_sends;
    else {
        const uint8_t *p=physical(held[0].word[0]);
        if(!memcmp(p,"EDSC",4)) {
            if(record_u16(p+4)==0x85) ++states;
            if(record_u16(p+4)==0x84) ++hellos;
        }
    }
}
void eth_window_configure(unsigned window,uint32_t base,uint32_t bytes)
{ (void)window; (void)base; (void)bytes; }
uint32_t eth_window_bytes(unsigned window)
{ return window==3 ? receive_bytes : VISION_IMAGE_BYTES; }
static void complete_tx(void)
{
    if(!tx_busy) return;
    assert(!memcmp(held,physical(hardware_desc),hardware_count*sizeof *held));
    done_count+=hardware_count; tx_busy=0; network_irq|=EDRV32_ETH_IRQ_STAT_DONE_MASK;
}
static void pump(void)
{
    rx_busy=0;
    board_network_step(); vision_service(); complete_tx();
}
static void message(unsigned type,const uint8_t *payload,unsigned length)
{
    uint8_t *p=physical(SHOWCASE_MESSAGE_BASE);
    memcpy(p,"EDSC",4); p[4]=type; p[5]=0; p[6]=length; p[7]=length>>8;
    record_put32(p+8,++wire_seq); memcpy(p+12,payload,length);
    receive_bytes=length+12; network_irq|=EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK;
    board_network_step();
}
static void new_image(void)
{
    const uint8_t info[]={1,0,1,0,5,0,0,0,'a','.','p','n','g'};
    message(5,info,sizeof info);
    uint8_t bulk[8]={2}; record_put32(bulk+4,VISION_IMAGE_BYTES);
    message(1,bulk,sizeof bulk);
    assert(protocol.active); /* protocol owns the new request */
    network_irq|=EDRV32_ETH_IRQ_STAT_RX_NOTIFY0_MASK;
    board_network_step();
}
static void wait_npu(unsigned before)
{
    for(unsigned i=0;npu_runs==before;++i) {
        assert(i<5000); pump();
        if(memory_starts && npu_runs==before)
            event(ENGINE_VIN,EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK);
    }
}
static void finish_image(void)
{
    event(ENGINE_NPU,EDRV32_NPU_IRQ_STAT_DONE_MASK);
    for(unsigned i=0;protocol.active;++i) { assert(i<6000); pump(); }
    for(unsigned i=0;i<20;++i) pump();
    assert(ui_data_vision().image_status==UI_IMAGE_DONE);
    display_frame(); display_frame();
}
static void liveness(void)
{
    unsigned old_states=states, old_hellos=hellos;
    ticks+=platform_clock_hz();
    uint8_t *p=physical(SHOWCASE_MESSAGE_BASE); p[0]=0;
    receive_bytes=1; network_irq|=EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK;
    board_network_step();
    for(unsigned i=0;i<30;++i) pump();
    assert(states>old_states && hellos>old_hellos);
    assert(!tx_active);
}
int main(void)
{
    assert(mmap((void *)(uintptr_t)EDRV32_NPU_BASE,4096,PROT_READ|PROT_WRITE,
        MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED,-1,0)!=MAP_FAILED);
    /* Keep runtime fixture helpers available without executing its standalone suite. */
    (void)camera_test; (void)parallel_test; (void)interrupt_restart_test;
    (void)image_test; (void)cancel_test;
    (void)process_test; (void)model_test; (void)matrix_test;
    (void)window_reopened; (void)reopened_base; (void)reopened_bytes; (void)accept_send;
    (void)bulk_completions;
    assert(mmap((void *)(uintptr_t)EDRV32_DDR_BASE,0x02000000,PROT_READ|PROT_WRITE,
        MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED,-1,0)!=MAP_FAILED);
    assert(mmap((void *)(uintptr_t)(EDRV32_DDR_BASE+VISION_POST_BASE),VISION_OUTPUT_BYTES,
        PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED,-1,0)!=MAP_FAILED);
    assert(mmap((void *)(uintptr_t)EDRV32_DDR_UNCACHED_BASE,0x0b000000,PROT_READ|PROT_WRITE,
        MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED,-1,0)!=MAP_FAILED);
    assert(mmap((void *)(uintptr_t)EDRV32_ETH_BASE,4096,PROT_READ|PROT_WRITE,
        MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED,-1,0)!=MAP_FAILED);
    vision_init(); ui_data_chain_preset(8); board_network_init(); vision_app_image.enter(); drain();
    memset(physical(VISION_OUTPUT_BASE),0x80,VISION_OUTPUT_BYTES);
    protocol.peer=1;
    for(unsigned scenario=0;scenario<4;++scenario) {
        fprintf(stderr,"scenario %u\n",scenario);
        unsigned before=npu_runs;
        ignore_next=1;
        new_image(); wait_npu(before);
        if(scenario==1) { /* CANCEL while result descriptors remain hardware-owned. */
            unsigned sends=image_sends;
            event(ENGINE_NPU,EDRV32_NPU_IRQ_STAT_DONE_MASK);
            for(unsigned i=0;image_sends==sends;++i) {
                assert(i<6000); board_network_step(); vision_service();
                if(hardware_desc!=VISION_TX_DESCRIPTORS) complete_tx();
            }
            assert(tx_busy);
        }
        if(scenario==3) { /* New IMAGE_INFO without CANCEL fails explicitly, stays live. */
            const uint8_t info[]={1,0,1,0,5,0,0,0,'b','.','p','n','g'};
            message(5,info,sizeof info); assert(protocol.active);
            finish_image();
            before=npu_runs; new_image(); wait_npu(before); finish_image();
        } else {
            message(8,(const uint8_t *)"",0); assert(!protocol.active);
            if(scenario!=2) {
                if(scenario!=1) event(ENGINE_NPU,EDRV32_NPU_IRQ_STAT_DONE_MASK);
                for(unsigned i=0;i<1500;++i) pump();
            }
            before=npu_runs;
            new_image(); /* scenario 2: immediate INFO+BEGIN while cancelled NPU runs. */
            if(scenario==2) event(ENGINE_NPU,EDRV32_NPU_IRQ_STAT_DONE_MASK);
            wait_npu(before); finish_image();
        }
        ignore_next=1; /* Repeat the real doorbell race during each scenario's replies. */
        liveness();
    }
    assert(ignored==8 && board_eth_rering==8 && rings>8);
    puts("PASS ignored RX-busy DOORBELL, four CANCEL/new-image timings, STATE/HELLO and later images");
}
