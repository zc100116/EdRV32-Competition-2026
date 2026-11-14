/* runtime.c — PIPE-SPEC 3.3/7.4; IRQ sequencing, queue pressure and Surface lifetime.
 * Production executor with mocked engines, no SoC simulation; host CPU clock.
 */
#define _GNU_SOURCE
#include "pipeline_exec.c"
#include <assert.h>
#include <stdlib.h>
#include <sys/mman.h>
static uint64_t ticks;
static struct vin_channel channels[3];
static struct vin_frame done[3];
static unsigned camera_writing;
static unsigned memory_runs, geo_runs, rnd_runs, npu_runs;
static unsigned npu_active, l1_pin, l1_hidden, gui_busy;
static uint32_t next, current, released;
static unsigned enabled;
static uint32_t memory_input;
static struct geo_config last_geo;
static struct rnd_command captured[8];
static unsigned captured_count;
const unsigned char _binary_build_showcase_pipe_test_bin_start[1] = {0};
uint64_t platform_ticks(void) { return ticks; }
uint32_t platform_clock_hz(void) { return 1000000; }
void platform_puts(const char *s) { fputs(s, stderr); }
void platform_put_hex(uint32_t v) { fprintf(stderr, "%x",v); }
_Noreturn void platform_stop(void) { abort(); }
static unsigned locks;
uint32_t sched_port_lock(void) { return locks++; }
void sched_port_unlock(uint32_t lock) { assert(locks == lock + 1); locks = lock; }
void app_wake_at(uint64_t tick) { (void)tick; }
void engine_control(enum engine_id engine, uint32_t value) { (void)engine; (void)value; }
struct engine_event engine_poll(enum engine_id engine)
{ (void)engine; return (struct engine_event){.status = 2}; }
void vin_camera_size(unsigned camera, unsigned w, unsigned h)
{ assert(camera == 0 && w == 1280 && h == 720); }
void vin_channel_configure(unsigned channel, const struct vin_channel *c)
{ channels[channel] = *c; }
void vin_channel_enable(unsigned channel, unsigned value) { (void)channel; assert(!value); }
uint32_t vin_write_status(unsigned channel) { return channel == 0 ? camera_writing : 0; }
void vin_slots_busy(unsigned channel, uint32_t slots) { channels[channel].busy_slots = slots; }
struct vin_frame vin_frame_done(unsigned channel) { return done[channel]; }
unsigned vin_frame_slot(uint32_t info)
{ return (info & EDRV32_VIN_CH_DONE_INFO_SLOT_MASK) >> EDRV32_VIN_CH_DONE_INFO_SLOT_POS; }
void vin_memory_start(uint32_t base, uint32_t stride, unsigned w, unsigned h)
{
    assert(stride == 2560 && w == 1280 && h == 720);
    memory_input = base; ++memory_runs;
}
void pix_configure(const struct pix_config *c) { (void)c; }
void pix_gamma_load(unsigned bank, const uint8_t values[256])
{ assert(bank <= 1 && values[255] == 255); }
void geo_descriptor_pack(struct geo_descriptor *descriptor, const struct geo_config *c)
{ (void)descriptor; last_geo = *c; }
void geo_submit(uint32_t descriptors, uint32_t count)
{ assert(descriptors == SHOWCASE_PIPE_GEO_DESC && count == 1); ++geo_runs; }
void disp_submit(enum disp_layer layer, uint32_t base, uint32_t stride)
{ assert(layer == DISP_L0 && stride == 2560); next = base; }
void disp_layer_enable(enum disp_layer layer, unsigned value)
{ assert(layer == DISP_L0); enabled = value; }
uint32_t disp_current(enum disp_layer layer) { assert(layer == DISP_L0); return current; }
uint32_t disp_released(enum disp_layer layer) { assert(layer == DISP_L0); return released; }
bool vision_pipe_start(unsigned input, uint32_t frame, uint64_t tick)
{
    (void)input; (void)frame; (void)tick;
    if (npu_active) return false;
    npu_active = 1; ++npu_runs; return true;
}
void vision_pipe_image_done(uint32_t frame) { (void)frame; }
bool vision_pipe_idle(void) { return !npu_active; }
unsigned vision_pipe_boxes(ui_detection_t *boxes)
{ boxes[0] = (ui_detection_t){.x=100,.y=100,.width=200,.height=100}; return 1; }
void showcase_gui_pipeline_overlay(bool value) { l1_hidden = value; }
bool showcase_gui_l1_acquire(void)
{ if (gui_busy) return false; l1_pin = 1; return true; }
void showcase_gui_l1_release(void) { assert(l1_pin); l1_pin = 0; }
const void *showcase_gui_l1_front(void)
{ return (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + 0x123000); }
void board_pipe_rnd_submit(const struct rnd_batch *batch)
{
    captured_count = batch->count;
    assert(captured_count <= 8);
    memcpy(captured,batch->commands,captured_count * sizeof *captured); ++rnd_runs;
}
static void irq(unsigned engine, unsigned flags)
{
    struct engine_event e = {.irq=flags}; ++ticks;
    pipe_irq(&e,engine);
}
static void camera(unsigned frame, unsigned slot)
{
    unsigned ch = p.capture_channel;
    if (ch == 0) {
        done[1] = (struct vin_frame){.frame_id=frame,
            .info=slot << EDRV32_VIN_CH_DONE_INFO_SLOT_POS};
        irq(ENGINE_VIN,EDRV32_VIN_IRQ_STAT_CH1_FRAME_MASK);
    }
    done[ch] = (struct vin_frame){.frame_id=frame,
        .info=slot << EDRV32_VIN_CH_DONE_INFO_SLOT_POS};
    irq(ENGINE_VIN,ch == 0 ? EDRV32_VIN_IRQ_STAT_FRAME_MASK :
        EDRV32_VIN_IRQ_STAT_CH1_FRAME_MASK);
}
static void memory_done(void)
{
    unsigned flags = p.memory_need;
    if (flags & 1) irq(ENGINE_VIN,EDRV32_VIN_IRQ_STAT_FRAME_MASK);
    if (flags & 2) irq(ENGINE_VIN,EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK);
}
static void frame(void)
{
    unsigned flags = EDRV32_DISP_IRQ_STAT_FRAME_MASK;
    if (current && (!enabled || current != next)) {
        released = current; flags |= EDRV32_DISP_IRQ_STAT_SWITCH_MASK;
    }
    if (enabled) current = next;
    pipe_display_irq(flags);
}
static void load(unsigned preset)
{
    npu_active = l1_pin = gui_busy = 0; enabled = current = next = released = 0;
    ui_data_chain_preset(preset); pipe_enter(); pipe_service();
    assert(pipe_ready(UI_STATE_RUNNING));
}
int main(void)
{
    assert(mmap((void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + SHOWCASE_PIPE_BASE),
        0x04f00000,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED,-1,0)
        != MAP_FAILED);
    load(1);
    assert(channels[1].source == VIN_CAM0 && channels[1].ring_count == 3);
    unsigned mem = memory_runs, rnd = rnd_runs;
    camera(42,0);
    assert(memory_runs == mem + 1 && rnd_runs == rnd + 1 && !npu_runs);
    assert(memory_input == SHOWCASE_PIPE_BASE + 3*SHOWCASE_PIPE_SLOT_BYTES);
    memory_done(); assert(npu_active && npu_runs == 1);
    ticks += 4000; pipe_rnd_done(); frame(); frame();
    assert(current >= SHOWCASE_PIPE_BASE && p.display >= 0);
    camera(43,1); memory_done(); camera(44,2); memory_done();
    assert(p.waiting_input >= 0 && p.input_frame[p.waiting_input] == 44);
    npu_active = 0; pipe_npu_done(); assert(npu_active && npu_runs == 2);
    assert(p.input_frame[p.npu_input] == 44);
    puts("PASS CAM CH1 -> CH2/NPU + RND IRQ starts, asynchronous latest NPU input");

    load(7); assert(p.capture_channel == 0);
    camera(51,0); assert(channels[0].source == VIN_MEMORY);
    memory_done(); assert(channels[0].source == VIN_CAM0);
    assert(p.latest[1] >= 0 && p.token[p.latest[1]].frame == 51);
    puts("PASS fused CAM CH0 -> MEM CH0 -> restored camera, original frame ID");

    load(3); camera(61,0); unsigned before = memory_runs;
    irq(ENGINE_GEO,EDRV32_GEO_IRQ_STAT_DONE_MASK);
    assert(memory_runs == before + 1 && p.active[2].hop >= 0);
    puts("PASS GEO DONE starts downstream CH2 and RND in the interrupt");

    load(5); gui_busy = 1; camera(71,0); memory_done();
    assert(p.active[2].hop == -1 && p.pending[2] >= 0);
    gui_busy = 0; pipe_service(); assert(l1_pin && l1_hidden && captured_count == 3);
    before = geo_runs; pipe_rnd_done(); assert(!l1_pin && geo_runs == before + 1);
    ui_detection_t box = {.x=100,.y=100,.width=200,.height=100};
    pipe_map_detections(&box,1); assert(box.width > 0 && box.height > 100);
    puts("PASS UI-layer pin, RND DONE starts GEO, arbitrary-angle bounding box");

    load(8); ui_chain_t c = ui_data_chain(), saved = c;
    uint32_t rev = pipe_revision(); c.block[0].flags = 1;
    assert(ui_data_chain_set(&c) == 2 && pipe_revision() == rev);
    c = ui_data_chain(); assert(!memcmp(&c,&saved,sizeof c));
    saved.view = 0; assert(!ui_data_chain_set(&saved));
    c = ui_data_chain(); assert(!c.preset && pipe_revision() == rev + 1);
    puts("PASS atomic rejected chains and preset reset on modification");

    load(1); c = ui_data_chain(); c.source = UI_SOURCE_TEST_IMAGE;
    assert(!ui_data_chain_set(&c)); pipe_enter(); pipe_service();
    assert(p.active[1].hop == -2 && last_geo.src_width == 640);
    assert(last_geo.matrix[0] == 32768 && last_geo.rect_width == 1280);
    irq(ENGINE_GEO,EDRV32_GEO_IRQ_STAT_DONE_MASK); assert(p.source >= 0);
    memory_done(); pipe_rnd_done();
    ticks += 200001; pipe_service(); assert(p.thumb_active);
    assert(p.thumbs[8].header.w == 160 && p.thumbs[8].header.h == 90);
    pipe_rnd_done();
    puts("PASS test-source GEO upscale and 5 Hz RND BLIT thumbnail");
    puts("PASS pipeline runtime");
}
