/* runtime_test.c — showcase 4.5.4/4.5.6; production pipeline ownership tests.
 * Mock the hardware/BOARD boundary only; real slices, CH2 and wire code, host clock.
 */
#define _GNU_SOURCE
#include "vision_hooks.h"
#include "memory.h"
#include "model.h"
#include "session.h"
#include "wire.h"
#include "../../../apps/showcase/ui/ui_data.h"
#include "vin.h"
#include "disp.h"
#include "geo_matrix.h"
#include "npu.h"
#include "pix.h"
#include "geo.h"
#include "ov5640.h"
#include "eth.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
static struct session model_session;
void board_session_fail(unsigned error)
{
    vision_app_camera.exit();
    session_fail(&model_session, error);
}
static void model_start(ui_app_t app, unsigned arg)
{
    (void)arg;
    if (app == UI_APP_CAMERA) vision_app_camera.enter();
    else vision_app_image.enter();
}
static void model_stop(ui_app_t app)
{
    (void)app;
    vision_app_camera.exit();
}
static bool model_ready(ui_app_t app, ui_state_t target)
{
    (void)app;
    return vision_ready(target);
}
static uint32_t hardware = APP_HW_VIN | APP_HW_NPU | APP_HW_ETH;
static uint64_t ticks;
static uint32_t busy[3];
static struct vin_frame frames[3];
static unsigned npu_runs, submitted, done_count, window_reopened;
static unsigned npu_configurations;
static uint32_t reopened_base, reopened_bytes;
static unsigned accept_send = 1;
static unsigned sensor_initializations;
static unsigned bulk_completions[3];
static uint32_t geo_descriptor;
static uint32_t display_current, display_next, display_released;
static unsigned display_enabled, display_scanned, display_frames, memory_starts;
static uint32_t memory_base;
static unsigned gamma_loads, pix_busy;
static struct pix_config last_pix;
void platform_gui_wake(void) {}
uint32_t showcase_gui_frames(void) { return display_frames; }
ui_system_t ui_data_system(void) { return (ui_system_t){0}; }
static unsigned invalidates;
void engine_dma_invalidate(uintptr_t address, uint32_t bytes)
{
    assert(address == EDRV32_DDR_BASE + VISION_OUTPUT_BASE && bytes == VISION_OUTPUT_BYTES);
    memcpy((void *)address, (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE+VISION_OUTPUT_BASE),bytes);
    ++invalidates;
}
uint32_t platform_frames(void) { return display_frames; }
void platform_put_u32(uint32_t value) { fprintf(stderr, "%u", value); }
void disp_submit(enum disp_layer layer, uint32_t base, uint32_t stride)
{ assert(layer == DISP_L0 && stride == VISION_STRIDE); display_next = base; }
void disp_layer_enable(enum disp_layer layer, unsigned enable)
{ assert(layer == DISP_L0); display_enabled = enable; }
uint32_t disp_current(enum disp_layer layer) { assert(layer == DISP_L0); return display_current; }
uint32_t disp_released(enum disp_layer layer)
{ assert(layer == DISP_L0); return display_released; }
void vin_memory_start(uint32_t base, uint32_t stride, unsigned width, unsigned height)
{
    assert(stride == VISION_STRIDE && width == 1280 && height == 720);
    memory_base = base; ++memory_starts;
}
uint64_t platform_ticks(void) { return ticks += 100; }
uint32_t platform_clock_hz(void) { return 125000000; }
uint32_t platform_hardware(void) { return hardware; }
void platform_puts(const char *s) { fputs(s, stderr); }
_Noreturn void platform_stop(void) { abort(); }
void app_wake_at(uint64_t deadline) { (void)deadline; }
uint32_t sched_port_lock(void) { return 0; }
void sched_port_unlock(uint32_t state) { (void)state; }
int ov5640_init(unsigned camera, uint32_t hz)
{
    assert(camera == 0 && hz == 125000000);
    ++sensor_initializations;
    return 0;
}
void engine_control(enum engine_id engine, uint32_t ctrl)
{
    (void)ctrl;
    if (engine == ENGINE_PIX || engine == ENGINE_GEO)
        assert((hardware & (APP_HW_PIX | APP_HW_GEO)) == (APP_HW_PIX | APP_HW_GEO));
}
struct engine_event engine_poll(enum engine_id engine)
{
    if (engine == ENGINE_PIX) return (struct engine_event){.status = pix_busy ? 1 : 2};
    if (engine == ENGINE_DISP) return (struct engine_event){.status =
        display_enabled || display_scanned ? 1 : 2};
    if (engine == ENGINE_PIX || engine == ENGINE_GEO) assert(hardware & APP_HW_GEO);
    return (struct engine_event){.status = 2, .done_count = done_count};
}
void vin_camera_size(unsigned camera, unsigned width, unsigned height)
{ assert(camera == 0 && width == 1280 && height == 720); }
void vin_channel_configure(unsigned channel, const struct vin_channel *c)
{ assert(channel == 0 || channel == 2); busy[channel] = c->busy_slots; }
void vin_channel_enable(unsigned channel, unsigned enabled)
{ assert(channel == 0 || channel == 2); assert(!enabled); }
void vin_slots_busy(unsigned channel, uint32_t slots) { busy[channel] = slots; }
struct vin_frame vin_frame_done(unsigned channel) { return frames[channel]; }
unsigned vin_frame_slot(uint32_t info)
{ return (info & EDRV32_VIN_CH_DONE_INFO_SLOT_MASK) >> EDRV32_VIN_CH_DONE_INFO_SLOT_POS; }
void npu_configure(const struct npu_config *c)
{ assert(c->count == 68); ++npu_configurations; }
void npu_start(uint32_t input, uint32_t output)
{
    assert(input >= VISION_INPUT_BASE && input < VISION_INPUT_BASE + 3*VISION_INPUT_SPACING);
    assert(output == VISION_OUTPUT_BASE);
    ++npu_runs;
}
void pix_configure(const struct pix_config *c) { last_pix = *c; assert(hardware & APP_HW_PIX); }
void pix_gamma_load(unsigned bank, const uint8_t values[256])
{
    assert(hardware & APP_HW_PIX);
    assert(bank <= 1 && bank != last_pix.gamma_bank && values[255] == 255);
    ++gamma_loads;
}
int32_t geo_q16(int32_t n, int32_t d) { return (int32_t)((int64_t)n * 65536 / d); }
void geo_descriptor_pack(struct geo_descriptor *d, const struct geo_config *c)
{
    assert(hardware & APP_HW_GEO);
    assert(c->src_width == 1280 && c->rect_height == 720);
    d->word[0] = c->src_base;
}
void geo_submit(uint32_t descriptors, uint32_t count)
{ assert(count == 1); geo_descriptor = descriptors; }
int board_eth_send(uint32_t descriptors, uint32_t count)
{
    assert(descriptors == VISION_TX_DESCRIPTORS && count == 3);
    if (!accept_send) return 0;
    ++submitted;
    return 1;
}
void board_bulk_complete(unsigned kind)
{ assert(kind == 1 || kind == 2); ++bulk_completions[kind]; }
void eth_window_configure(unsigned window, uint32_t base, uint32_t bytes)
{
    assert(window == 0);
    ++window_reopened;
    reopened_base = base;
    reopened_bytes = bytes;
}
void eth_tx_descriptor_pack(struct eth_tx_descriptor *d, uint32_t source,
                            uint32_t bytes, unsigned window, unsigned notify, uint32_t offset)
{
    memset(d, 0, sizeof *d);
    d->word[0] = source;
    d->word[1] = bytes;
    d->word[2] = window | (notify << 8);
    d->word[3] = offset;
}
static void *physical(uint32_t address)
{ return (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + address); }
static void event(enum engine_id engine, uint32_t flags)
{
    const struct engine_event e = {.irq = flags};
    vision_irq(&e, (void *)(uintptr_t)engine);
}
static void display_frame(void);
static void drain(void)
{
    unsigned steps = 0;
    while (vision_service()) assert(++steps < 50000);
}
static void camera(unsigned slot, unsigned frame_id)
{
    frames[0] = (struct vin_frame){slot << EDRV32_VIN_CH_DONE_INFO_SLOT_POS, frame_id};
    frames[2] = (struct vin_frame){slot << EDRV32_VIN_CH_DONE_INFO_SLOT_POS, frame_id};
    event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_FRAME_MASK | EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK);
    unsigned before = npu_runs;
    vision_service();
    assert(npu_runs == before + 1);
    assert(busy[0] & (1u << slot));
    event(ENGINE_NPU, EDRV32_NPU_IRQ_STAT_DONE_MASK);
    drain();
}
static void display_frame(void)
{
    uint32_t flags = EDRV32_DISP_IRQ_STAT_FRAME_MASK;
    if (display_scanned && (!display_enabled || display_next != display_current)) {
        display_released = display_current;
        flags |= EDRV32_DISP_IRQ_STAT_SWITCH_MASK;
    }
    if (display_enabled) display_current = display_next;
    display_scanned = display_enabled;
    ++display_frames;
    vision_display_irq(flags);
    vision_service();
}
static void camera_test(void)
{
    vision_app_camera.enter();
    assert(sensor_initializations == 1);
    vision_service();
    camera(0, 10);
    display_frame(); display_frame();
    vision_detection_changed(); assert(!vision_detection_applied());
    const lv_image_dsc_t *first = ui_data_vision().image;
    assert(!vision_detection_applied());
    vision_gui_presented(platform_ticks()); assert(vision_detection_applied());
    assert(first && first->data == physical(VISION_IMAGE_BASE));
    camera(1, 11);
    assert((busy[0] & 3) == 3);
    ui_data_vision(); /* GUI never releases a video surface. */
    assert((busy[0] & 3) == 3);
    display_frame();
    assert((busy[0] & 3) == 3); /* Submitted, old surface still scanned. */
    display_frame();
    assert(display_released == VISION_IMAGE_BASE);
    assert((busy[0] & 3) == 2);
    vision_pause(true); drain();
    assert(vision_ready(UI_STATE_PAUSED));
    vision_pause(false); drain();
    assert(vision_ready(UI_STATE_RUNNING));
    vision_app_camera.exit(); display_frame(); display_frame(); drain();
    display_frame(); display_frame();
    puts("PASS L0 SWITCH/REL_BASE releases VIN slots; GUI cannot release scanned frames");
}
static void upload(unsigned base, unsigned index)
{
    memset(physical(base), 0xff, VISION_IMAGE_BYTES);
    unsigned before = npu_runs;
    vision_image_receiving(100+index);
    assert(vision_bulk_done(2, base, VISION_IMAGE_BYTES) == 0);
    unsigned memory_before = memory_starts;
    for (unsigned step = 0; memory_starts == memory_before; ++step) {
        assert(step < 4000);
        vision_service();
    }
    assert(memory_base == base && npu_runs == before);
    frames[2] = (struct vin_frame){(index % 2) << EDRV32_VIN_CH_DONE_INFO_SLOT_POS, index};
    event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK);
    vision_service();
    assert(npu_runs == before + 1);
    accept_send = 0;
    event(ENGINE_NPU, EDRV32_NPU_IRQ_STAT_DONE_MASK);
    for (unsigned step = 0; step < 1000; ++step) vision_service();
    assert(submitted == index);
    accept_send = 1;
    vision_service();
    assert(submitted == index+1);
    const struct eth_tx_descriptor *tx = physical(VISION_TX_DESCRIPTORS);
    assert(tx[0].word[0] == VISION_INPUT_BASE + (index % 2)*VISION_INPUT_SPACING &&
           tx[0].word[2] == 0);
    assert(tx[1].word[0] == VISION_OUTPUT_BASE && tx[1].word[2] == 1);
    assert(tx[2].word[0] == VISION_TX_DETECTIONS && tx[2].word[2] == 0x102);
    assert(memcmp(physical(VISION_TX_DETECTIONS), "EDDT", 4) == 0);
    assert(vision_read32((uint8_t *)physical(VISION_TX_DETECTIONS)+12)==100+index);
    ++done_count;
    vision_service();
    assert(bulk_completions[2] == index);

    done_count += 2;
    drain();
    assert(bulk_completions[2] == index+1);
    ui_data_vision();
    display_frame(); display_frame();
}
static void image_test(void)
{
    hardware = APP_HW_NPU | APP_HW_ETH | APP_HW_VIN; /* DDR source requires VIN. */
    vision_app_image.enter();
    drain();
    assert(vision_upload_base() == 0x08000000);
    upload(0x08000000, 0);
    assert(vision_upload_base() == 0x08200000);
    upload(0x08200000, 1);
    assert(vision_upload_base() == 0x08000000);
    assert(ui_data_vision().image_status == UI_IMAGE_DONE);
    vision_app_image.exit();
    display_frame(); display_frame(); drain();
    display_frame(); display_frame();
    puts("PASS VIN DDR image CH2, BOARD TX arbitration, per-job windows and all-three TX completion");
}
static void cancel_test(void)
{
    vision_app_image.enter(); drain();
    unsigned before = submitted;
    unsigned base = vision_upload_base();
    vision_image_receiving(201);
    assert(!vision_bulk_done(2,base,VISION_IMAGE_BYTES));
    vision_service();
    event(ENGINE_VIN,EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK); vision_service();
    unsigned npu_before = npu_runs;
    vision_cancel(2);
    assert(npu_runs==npu_before); /* No NPU abort or replacement before DONE. */
    unsigned next = vision_upload_base(); assert(next && next!=base);
    vision_image_receiving(202);
    assert(!vision_bulk_done(2,next,VISION_IMAGE_BYTES));
    unsigned memory_before = memory_starts;
    event(ENGINE_NPU,EDRV32_NPU_IRQ_STAT_DONE_MASK);
    for(unsigned i=0;memory_starts==memory_before;++i) {
        assert(i<4000); vision_service();
    }
    assert(submitted==before && npu_runs==npu_before);
    event(ENGINE_VIN,EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK); vision_service();
    event(ENGINE_NPU,EDRV32_NPU_IRQ_STAT_DONE_MASK);
    for(unsigned i=0;submitted==before;++i) { assert(i<4000); vision_service(); }
    assert(vision_read32((uint8_t *)physical(VISION_TX_DETECTIONS)+12)==202);
    done_count+=3; drain();
    assert(ui_data_vision().image_status==UI_IMAGE_DONE);
    ui_data_vision(); vision_gui_presented(platform_ticks()); vision_service();
    vision_app_image.exit(); display_frame(); display_frame(); drain();
    puts("PASS CANCEL drains NPU, drops old EDDT, queues next request without overwriting OUTPUT");
}
static void process_test(void)
{
    hardware = APP_HW_VIN | APP_HW_PIX | APP_HW_GEO;
    vision_app_process.enter();
    drain();
    unsigned loads = gamma_loads;
    ui_process_config_t changed = ui_data_process_config();
    changed.gamma_tenths = 30; changed.enabled = UI_PROC_GAMMA;
    ui_data_process_set(&changed);
    for (unsigned i = 0; i < 255; ++i) vision_service();
    assert(gamma_loads == loads);
    pix_busy = 1;
    vision_service();
    assert(gamma_loads == loads); /* Complete table waits for an inactive bank boundary. */
    pix_busy = 0;
    vision_service();
    assert(gamma_loads == loads + 1);
    changed.brightness = -256; changed.contrast = 511;
    changed.enabled = UI_PROC_LEVEL | UI_PROC_GRAY | UI_PROC_BINARY | UI_PROC_INVERT;
    changed.threshold = 255;
    ui_data_process_set(&changed); drain();
    assert(last_pix.brightness == -256 && last_pix.contrast == 511 && last_pix.threshold == 255);
    assert((last_pix.flags & (EDRV32_PIX_CFG_GRAY_EN_MASK | EDRV32_PIX_CFG_BIN_EN_MASK |
        EDRV32_PIX_CFG_INV_EN_MASK)) == (EDRV32_PIX_CFG_GRAY_EN_MASK |
        EDRV32_PIX_CFG_BIN_EN_MASK | EDRV32_PIX_CFG_INV_EN_MASK));
    changed.enabled = 0; ui_data_process_set(&changed); drain();
    assert(last_pix.flags==0 && last_pix.stage1==PIX_BYPASS && last_pix.stage2==PIX_BYPASS);
    assert(ui_data_process_config().brightness==-256 && ui_data_process_config().contrast==511);
    ui_data_process_defaults(UI_PROC_LEVEL); drain();
    assert(ui_data_process_config().brightness==0 && ui_data_process_config().gamma_tenths==30);
    ui_data_process_defaults(UI_PROC_ALL); drain();
    assert(!ui_data_process_config().enabled && ui_data_process_config().stage1==2);
    assert(!vision_process_applied());
    puts("PASS one gamma sample per slice, inactive-bank boundary and PIX parameter extremes");
    for (unsigned mode = 0; mode < 7; ++mode) {
        ui_process_config_t config = ui_data_process_config();
        config.original = mode == 0;
        config.angle = (int)mode * 20;
        config.stage1 = mode ? (int)mode : 2;
        config.enabled = mode ? UI_PROC_S1 | UI_PROC_ROTATE : 0;
        ui_data_process_set(&config); drain();
        unsigned source = 0;
        while (busy[0] & (1u << source)) ++source;
        assert(source < 4);
        frames[0] = (struct vin_frame){source << EDRV32_VIN_CH_DONE_INFO_SLOT_POS, mode};
        event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_FRAME_MASK);
        vision_service();
        assert(vision_process_applied());
        if (mode) {
            assert(geo_descriptor == VISION_GEO_DESCRIPTOR);
            event(ENGINE_GEO, EDRV32_GEO_IRQ_STAT_DONE_MASK);
            drain();
        }
        display_frame(); display_frame();
        const lv_image_dsc_t *image = ui_data_process(0);
        assert(image && image->header.w == 1280 && image->header.h == 720);
    }
    vision_app_process.exit();
    display_frame(); display_frame(); drain();
    display_frame(); display_frame();
    unsigned bank = last_pix.gamma_bank;
    vision_app_camera.enter(); drain();
    assert(last_pix.gamma_bank == bank); /* Bypass retains the shadow bank selection. */
    vision_app_camera.exit(); display_frame(); display_frame(); drain();
    display_frame(); display_frame();
    puts("PASS all seven PIX/GEO modes, native surfaces and gamma bank across page changes");
}
static void model_test(void)
{
    hardware = APP_HW_NPU | APP_HW_ETH;
    assert(vision_model_ready());
    vision_model_receiving();
    assert(!vision_model_ready());
    for (ui_app_t app = UI_APP_CAMERA; app <= UI_APP_IMAGE; ++app) {
        model_session = (struct session){.ops = {model_start, model_stop, NULL, model_ready}};
        session_open(&model_session, app, 0);
        session_step(&model_session);
        assert(model_session.state == UI_STATE_FAILED && model_session.error == 7);
        drain();
    }
    unsigned runs_before = npu_runs;
    uint32_t base = 0x09000000;
    uint32_t header[] = {0x4d4e4445, 1, 68, 68*64, 2051,
                         VISION_WORK_BASE, VISION_INPUT_BASE, VISION_OUTPUT_BASE};
    memcpy(physical(base), header, sizeof header);
    memset(physical(base+0x1000), 0x12, 68*64);
    memset(physical(base+0x100000), 0x34, 2051);
    assert(vision_bulk_done(1, base, 31) == 1);
    assert(vision_bulk_done(2, 0x08000000, 31) == 1);
    header[0] = 0;
    memcpy(physical(base), header, sizeof header);
    assert(vision_bulk_done(1, base, 0x100000+2051) == 2);
    header[0] = 0x4d4e4445;
    memcpy(physical(base), header, sizeof header);
    assert(vision_bulk_done(1, base, 0x100000+2050) == 1);
    assert(vision_bulk_done(1, base, 0x100000+2051) == 0);
    assert(bulk_completions[1] == 0);
    drain();
    assert(bulk_completions[1] == 1);
    assert(vision_model_ready() && npu_runs == runs_before);
    hardware |= APP_HW_VIN;
    session_retry(&model_session);
    session_step(&model_session);
    drain();
    session_step(&model_session);
    drain();
    session_step(&model_session);
    assert(model_session.state == UI_STATE_RUNNING);
    vision_app_image.exit(); drain();

    /* A replacement waits for the active inference, then prevents new starts
     * until both descriptor and weight copies have completed (P5b 9.1). */
    vision_app_camera.enter(); drain();
    frames[0] = (struct vin_frame){0, 500};
    frames[2] = (struct vin_frame){0, 500};
    event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_FRAME_MASK | EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK);
    vision_service();
    assert(npu_runs == runs_before + 1);
    unsigned configured = npu_configurations;
    vision_model_receiving();
    assert(vision_bulk_done(1, base, 0x100000+2051) == 0);
    for (unsigned i = 0; i < 4; ++i) vision_service();
    assert(!vision_model_ready() && npu_configurations == configured);
    event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_FRAME_MASK | EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK);
    vision_service();
    assert(npu_runs == runs_before + 1);
    event(ENGINE_NPU, EDRV32_NPU_IRQ_STAT_DONE_MASK);
    drain();
    assert(vision_model_ready() && npu_configurations == configured + 1);
    assert(npu_runs == runs_before + 1 && bulk_completions[1] == 2);
    vision_app_camera.exit(); display_frame(); display_frame(); drain();

    assert(memcmp(physical(VISION_DESC_BASE), physical(base+0x1000), 68*64) == 0);
    assert(memcmp(physical(VISION_MODEL_BASE), physical(base+0x100000), 2051) == 0);
    puts("PASS sparse EDNM sliced loading, tail bytes, boundary status and deferred DONE");
}
static void matrix_test(void)
{
    int32_t m[6];
    geo_matrix(m, 0, 100, 0, 0, 0, 0, 1280, 720);
    assert(m[0] == 65536 && m[1] == 0 && m[2] == 0);
    assert(m[3] == 0 && m[4] == 65536 && m[5] == 0);
    geo_matrix(m, 0, 50, 10, -20, 0, 0, 1280, 720);
    assert(m[0] == 131072 && m[4] == 131072);
    assert(m[2] == -43220992 && m[5] == -20938752);
    geo_matrix(m, 90, 100, 0, 0, 0, 0, 1280, 720);
    assert(m[0] == 0 && m[1] == 65536 && m[3] == -65536 && m[4] == 0);
    geo_matrix(m, 0, 100, 0, 0, 1, 1, 1280, 720);
    assert(m[0] == -65536 && m[4] == -65536);
    assert(m[2] == 1279*65536 && m[5] == 719*65536);
    uint8_t gamma[256];
    pix_gamma_table(gamma, 10);
    for (unsigned i = 0; i < 256; ++i) assert(gamma[i] == i);
    pix_gamma_table(gamma, 3);
    assert(gamma[0] == 0 && gamma[255] == 255 && gamma[128] < 128);
    pix_gamma_table(gamma, 30);
    assert(gamma[0] == 0 && gamma[255] == 255 && gamma[128] > 128);
    puts("PASS centered GEO inverse matrices, scale bounds, mirrors and gamma extremes");
}
int main(void)
{
    matrix_test();
    assert(mmap((void *)(uintptr_t)EDRV32_DDR_BASE, 0x02000000,
                PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0)
           != MAP_FAILED);
    assert(mmap((void *)(uintptr_t)(EDRV32_DDR_BASE+VISION_OUTPUT_BASE), VISION_OUTPUT_BYTES,
                PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0)
           != MAP_FAILED);
    assert(mmap((void *)(uintptr_t)EDRV32_DDR_UNCACHED_BASE, 0x0b000000,
                PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0)
           != MAP_FAILED);
    memset(physical(VISION_OUTPUT_BASE), 0x80, VISION_OUTPUT_BYTES);
    vision_init();
    assert(vision_model_ready());
    assert(memcmp(physical(VISION_DESC_BASE), showcase_model_desc,
                  showcase_model_desc_bytes) == 0);
    assert(memcmp(physical(VISION_MODEL_BASE), showcase_model_weights,
                  showcase_model_weights_bytes) == 0);
    camera_test();
    image_test();
    cancel_test();
    process_test();
    model_test();
    assert(invalidates >= 6);
    return 0;
}
