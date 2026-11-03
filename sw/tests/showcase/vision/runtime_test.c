/* runtime_test.c — showcase 4.5.4/4.5.6; production pipeline ownership tests.
 * Mock the hardware/BOARD boundary only; real slices, CH2 and wire code, host clock.
 */
#define _GNU_SOURCE
#include "vision_hooks.h"
#include "memory.h"
#include "../../../apps/showcase/ui/ui_data.h"
#include "vin.h"
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
static uint32_t hardware = APP_HW_VIN | APP_HW_NPU | APP_HW_ETH;
static uint64_t ticks;
static uint32_t busy[3];
static struct vin_frame frames[3];
static unsigned npu_runs, submitted, done_count, window_reopened;
static uint32_t reopened_base, reopened_bytes;
static unsigned accept_send = 1;
static unsigned sensor_initializations;
static unsigned bulk_completions[3];
static uint32_t geo_descriptor;
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
void npu_configure(const struct npu_config *c) { assert(c->count == 68); }
void npu_start(uint32_t input, uint32_t output)
{
    assert(input >= VISION_INPUT_BASE && input < VISION_INPUT_BASE + 3*VISION_INPUT_SPACING);
    assert(output == VISION_OUTPUT_BASE);
    ++npu_runs;
}
void pix_configure(const struct pix_config *c) { (void)c; assert(hardware & APP_HW_PIX); }
void pix_gamma_load(unsigned bank, const uint8_t values[256])
{ assert(hardware & APP_HW_PIX); assert(bank == 1 && values[255] == 255); }
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
static void camera_test(void)
{
    vision_app_camera.enter();
    assert(sensor_initializations == 1);
    vision_service();
    camera(0, 10);
    const lv_image_dsc_t *first = ui_data_vision(false).image;
    assert(!ui_data_vision(false).waiting);
    assert(first && first->data == physical(VISION_IMAGE_BASE));
    camera(1, 11);
    assert((busy[0] & 3) == 3);
    vision_frame_presented(); /* Merely rendering the old image cannot release it. */
    assert((busy[0] & 3) == 3);
    const lv_image_dsc_t *second = ui_data_vision(false).image;
    assert(second != first && (busy[0] & 3) == 3);
    vision_frame_presented();
    assert((busy[0] & 3) == 2);
    ui_data_pause();
    drain();
    assert(ui_data_vision(false).paused);
    ui_data_pause();
    drain();
    assert(!ui_data_vision(false).paused);
    vision_app_camera.exit();
    drain();
    vision_frame_presented();
    puts("PASS VRN camera pairing, IRQ-only events, pause, GUI retirement");
}
static void upload(unsigned base, unsigned index)
{
    memset(physical(base), 0xff, VISION_IMAGE_BYTES);
    unsigned before = npu_runs;
    assert(vision_bulk_done(2, base, VISION_IMAGE_BYTES) == 0);
    for (unsigned step = 0; npu_runs == before; ++step) {
        assert(step < 4000);
        vision_service();
    }
    assert(((const uint8_t *)physical(VISION_INPUT_BASE))[12*2560] == 127);
    accept_send = 0;
    event(ENGINE_NPU, EDRV32_NPU_IRQ_STAT_DONE_MASK);
    for (unsigned step = 0; step < 1000; ++step) vision_service();
    assert(submitted == index && window_reopened == index);
    accept_send = 1;
    vision_service();
    assert(submitted == index+1);
    const struct eth_tx_descriptor *tx = physical(VISION_TX_DESCRIPTORS);
    assert(tx[0].word[0] == VISION_INPUT_BASE && tx[0].word[2] == 0);
    assert(tx[1].word[0] == VISION_OUTPUT_BASE && tx[1].word[2] == 1);
    assert(tx[2].word[0] == VISION_TX_DETECTIONS && tx[2].word[2] == 0x102);
    assert(memcmp(physical(VISION_TX_DETECTIONS), "EDDT", 4) == 0);
    ++done_count;
    vision_service();
    assert(bulk_completions[2] == index);
    assert(window_reopened == index); /* Partial TX must keep CH2/OUTPUT/window owned. */
    done_count += 2;
    drain();
    assert(window_reopened == index+1);
    assert(bulk_completions[2] == index+1);
    assert(reopened_base == base && reopened_bytes == VISION_IMAGE_BYTES);
    ui_data_vision(true);
    vision_frame_presented();
}
static void image_test(void)
{
    hardware = APP_HW_NPU | APP_HW_ETH; /* Image checks must not touch VIN/PIX/GEO. */
    vision_app_image.enter();
    drain();
    upload(0x08000000, 0);
    upload(0x08200000, 1);
    assert(ui_data_vision(true).success == 2);
    ui_data_batch_stop();
    assert(ui_data_vision(true).waiting);
    vision_app_image.exit();
    drain();
    vision_frame_presented();
    puts("PASS CPU image CH2, BOARD TX arbitration, per-job windows and all-three TX completion");
}
static void process_test(void)
{
    hardware = APP_HW_VIN | APP_HW_PIX | APP_HW_GEO;
    vision_app_process.enter();
    drain();
    for (unsigned mode = 0; mode < 7; ++mode) {
        ui_data_process(mode);
        drain();
        unsigned source = 0;
        while (busy[0] & (1u << source)) ++source;
        assert(source < 4);
        frames[0] = (struct vin_frame){source << EDRV32_VIN_CH_DONE_INFO_SLOT_POS, mode};
        event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_FRAME_MASK);
        vision_service();
        if (mode >= 4) {
            assert(geo_descriptor == VISION_GEO_DESCRIPTOR);
            event(ENGINE_GEO, EDRV32_GEO_IRQ_STAT_DONE_MASK);
            drain();
        }
        const lv_image_dsc_t *image = ui_data_process(mode);
        assert(image && image->header.w == 1280 && image->header.h == 720);
        vision_frame_presented();
    }
    vision_app_process.exit();
    drain();
    vision_frame_presented();
    puts("PASS all seven PIX/GEO modes and 1280x720 RGB565 descriptors");
}
static void model_test(void)
{
    hardware = APP_HW_NPU | APP_HW_ETH;
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
    assert(reopened_base == base && reopened_bytes == 0x100000+2051);
    assert(memcmp(physical(VISION_DESC_BASE), physical(base+0x1000), 68*64) == 0);
    assert(memcmp(physical(VISION_MODEL_BASE), physical(base+0x100000), 2051) == 0);
    puts("PASS sparse EDNM sliced loading, tail bytes, boundary status and deferred DONE");
}
int main(void)
{
    assert(mmap((void *)(uintptr_t)EDRV32_DDR_UNCACHED_BASE, 0x0b000000,
                PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0)
           != MAP_FAILED);
    memset(physical(VISION_OUTPUT_BASE), 0x80, VISION_OUTPUT_BYTES);
    vision_init();
    camera_test();
    image_test();
    process_test();
    model_test();
    return 0;
}
