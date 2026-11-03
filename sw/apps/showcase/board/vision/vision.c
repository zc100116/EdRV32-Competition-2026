/* vision.c — showcase design 4.3/4.5; cooperative VIN/YOLO/PIX/GEO applications.
 * IRQs latch events; task slices retain DMA and L0 display surface ownership.
 * Clock domain: clk_sys; accelerator data/interrupts originate in clk_mem.
 */
#include "vision_hooks.h"
#include "memory.h"
#include "model.h"
#include "wire.h"
#include "post.h"
#include "disp.h"
#include "../ddr_map.h"
#include "geo_matrix.h"
#include "../../platform.h"
#include "../../ui/ui_data.h"
#include "../../ui/detection.h"
#include "port.h"
#include "vin.h"
#include "npu.h"
#include "pix.h"
#include "geo.h"
#include "eth.h"
#include "ov5640.h"
#include "board.h"
#include <string.h>
#include <stdio.h>
#include "../../runtime.h"
#include "../../lvgl/showcase_lvgl.h"

enum { REF_PAIR = 1, REF_JOB = 2, REF_READY = 4, REF_DISPLAY = 8,
       REF_NPU = 16, REF_GEO = 32 };
enum { PAGE_NONE, PAGE_CAMERA, PAGE_IMAGE, PAGE_PROCESS };
enum { JOB_IDLE, JOB_CH2, JOB_NPU, JOB_POST, JOB_SEND, JOB_TX };
enum pipeline_state { PIPE_OFF, PIPE_STARTING, PIPE_LIVE, PIPE_PAUSING, PIPE_FROZEN,
                      PIPE_STOPPING, PIPE_CONFIGURE };
/* Per-application data survives switching; only the pipeline owns hardware. */
static struct vision_session {
    ui_vision_t data;
    ui_detection_t raw[YOLO_MAX_DETECTIONS];
    unsigned count;
    uint32_t frame;
    enum { UPLOAD_EMPTY, UPLOAD_READY } upload;
} sessions[4];
static ui_process_config_t process = {.contrast = 256, .gamma_tenths = 10,
    .stage1 = 2, .stage2 = 2, .threshold = 128, .scale_percent = 100};
static struct {
    unsigned page;
    enum pipeline_state state;
    unsigned process_dirty, gamma_bank;
    uint32_t process_revision, shadow_revision, applied_revision;
    int gamma_loaded;
    unsigned gamma_target, gamma_index;
    uint8_t gamma_table[256];
    int32_t matrix[6];
    unsigned capture;
    unsigned initialized;
    unsigned refs[8];
    int ready, current, pair_image, pair_input;
    uint32_t image_id, input_id;
    uint64_t image_tick;
    uint32_t input_busy;
    lv_image_dsc_t images[8];
    unsigned job;
    int job_image;
    unsigned job_input;
    unsigned image_job;
    uint32_t job_frame, job_request;
    uint32_t receive_base, receive_bytes;
    uint64_t ch2_start, ch2_ticks, send_start, receive_start, receive_ticks;
    int submitted;
    unsigned display_owned;
    uint32_t next_frame;
    uint64_t npu_start, upload_complete, post_ticks;
    unsigned npu_busy, npu_complete, npu_input;
    int npu_image;
    uint32_t npu_frame;
    uint64_t npu_vin, npu_done;
    struct vision_post post;
    yolo_detection detections[YOLO_MAX_DETECTIONS];
    int geo_source, geo_target;
    uint32_t tx_done;
    uint32_t upload_base, upload_bytes;
    unsigned model_pending;
    bool model_ready;
    uint32_t model_base, model_bytes, model_offset;
    unsigned model_phase;
    uint32_t model_count, model_desc_bytes, model_weight_bytes;
} v = {.ready = -1, .current = -1, .pair_image = -1, .pair_input = -1,
       .submitted = -1, .job_image = -1, .geo_source = -1, .geo_target = -1,
       .gamma_loaded = -1, .gamma_target = 10, .gamma_index = 256};
static volatile uint32_t irq_flags[ENGINE_NPU + 1];
static volatile uint32_t irq_errors[ENGINE_NPU + 1];
static volatile uint64_t npu_done_tick;
static volatile uint64_t vin_done_tick[3];
static uint32_t request;
static char image_name[257];
static unsigned boxes = 1;
static struct {
    uint64_t vin, npu_done, post_start, decode_end, sort_end, nms_end, cpu[3], handoff;
    uint64_t sums[10], since, completed[6], handoff_vin;
    uint64_t job_npu_start, copy_ticks, last_start;
    unsigned periods;
    uint32_t samples, gui_samples;
    bool await_gui, gui_taken, cancelled;
} timing;
static volatile unsigned gui_armed, gui_ready;
static uint32_t detection_revision;
static volatile uint32_t detection_armed, detection_applied;
void vision_detection_changed(void) { ++detection_revision; }
bool vision_detection_applied(void) { return detection_applied == detection_revision; }
static volatile uint64_t gui_done;
void vision_gui_presented(uint64_t tick)
{
    if (gui_armed) { gui_done = tick; gui_armed = 0; gui_ready = 1; }
    detection_applied = detection_armed;
}
static char report[320];
/* Design P5 8.6 / card 54: one line per completed PC image, emitted once. */
static char image_line[240];
const char *vision_report(void)
{
    static char taken[sizeof image_line];
    if (v.page == PAGE_CAMERA && v.state == PIPE_LIVE) return report;
    memcpy(taken, image_line, sizeof taken);
    image_line[0] = 0;
    return taken;
}
uint32_t vision_frame(void) { return v.job_frame; }
void vision_image_info(unsigned index, unsigned total, const uint8_t *name, unsigned bytes)
{
    memcpy(image_name, name, bytes); image_name[bytes] = 0;
    sessions[PAGE_IMAGE].data.image_name = image_name;
    sessions[PAGE_IMAGE].data.image_index = index;
    sessions[PAGE_IMAGE].data.image_total = total;
    platform_gui_wake();
}
void vision_image_receiving(uint32_t seq)
{
    request = seq;
    sessions[PAGE_IMAGE].data.image_status = UI_IMAGE_RECEIVING;
}
void vision_model_receiving(void) { v.model_ready = false; }
bool vision_model_ready(void) { return v.model_ready; }
uint32_t vision_request(void) { return request; }
void vision_state(uint8_t payload[56])
{
    payload[3] = (uint8_t)boxes;
    uint32_t values[2] = {v.page == PAGE_IMAGE ? request : 0,
        v.page == PAGE_IMAGE ? sessions[PAGE_IMAGE].frame : 0};
    for (unsigned j = 0; j < 2; ++j)
        for (unsigned i = 0; i < 4; ++i) payload[44+j*4+i] = values[j] >> (i*8);
    payload[52] = sessions[PAGE_IMAGE].data.image_status;
}
bool vision_process_applied(void) { return v.applied_revision == v.process_revision; }
static void reference(int slot, unsigned add, unsigned remove);
void vision_cancel(unsigned kind)
{
    if (kind == 1) { v.model_pending = 0; return; }
    timing.cancelled = true;
    /* After CH2, NPU/TX use only CH2 and the output snapshot. Release the
     * cancelled upload surface so a new folder can immediately reserve it. */
    if (v.page == PAGE_IMAGE && v.job >= JOB_NPU) {
        if (v.ready == v.job_image) {
            reference(v.ready, 0, REF_READY); v.ready = -1;
        }
        reference(v.job_image, 0, REF_JOB);
        v.job_image = v.npu_image = -1;
    }
    sessions[PAGE_IMAGE].upload = UPLOAD_EMPTY;
    if (sessions[PAGE_IMAGE].data.image_status == UI_IMAGE_RECEIVING ||
        sessions[PAGE_IMAGE].data.image_status == UI_IMAGE_DETECTING)
        sessions[PAGE_IMAGE].data.image_status = UI_IMAGE_FAILED;
    app_wake_at(platform_ticks());
}

static void *uncached(uint32_t address)
{
    return (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + address);
}
static uint32_t image_address(unsigned slot)
{
    if (slot >= 6) return SHOWCASE_IMAGE_BASE + (slot - 6) * SHOWCASE_IMAGE_BYTES;
    return slot < 4 ? VISION_IMAGE_BASE + slot * VISION_IMAGE_SPACING :
           VISION_GEO_BASE + (slot - 4) * VISION_IMAGE_SPACING;
}
static _Noreturn void fail(const char *message)
{
    platform_puts("showcase vision: ");
    platform_puts(message);
    platform_puts("\r\n");
    platform_stop();
}
static unsigned tenths(uint64_t ticks)
{
    return (unsigned)(ticks * 10000u / platform_clock_hz());
}
static void reference(int slot, unsigned add, unsigned remove)
{
    if (slot < 0) return;
    v.refs[slot] = (v.refs[slot] & ~remove) | add;
    if (v.capture) {
        uint32_t busy = 0;
        for (unsigned i = 0; i < 4; ++i) {
            if (v.refs[i]) busy |= 1u << i;
        }
        vin_slots_busy(0, busy);
    }
}
static int free_image(unsigned first, unsigned end)
{
    for (unsigned i = first; i < end; ++i) {
        if (!v.refs[i]) return (int)i;
    }
    return -1;
}
static void initialize(void)
{
    if (v.initialized) return;
    for (unsigned i = 0; i < 8; ++i) {
        v.images[i] = (lv_image_dsc_t){
            .header = {.magic = LV_IMAGE_HEADER_MAGIC, .cf = LV_COLOR_FORMAT_RGB565,
                       .flags = LV_IMAGE_FLAGS_MODIFIABLE, .w = 1280, .h = 720,
                       .stride = VISION_STRIDE},
            .data_size = VISION_IMAGE_BYTES, .data = uncached(image_address(i))};
    }
    for (unsigned i = 0; i < 256; ++i) v.gamma_table[i] = (uint8_t)i;
    v.initialized = 1;
}
void vision_irq(const struct engine_event *event, void *context)
{
    unsigned engine = (unsigned)(uintptr_t)context;
    if (engine == ENGINE_VIN) {
        uint64_t now = platform_ticks();
        if (event->irq & EDRV32_VIN_IRQ_STAT_FRAME_MASK) vin_done_tick[0] = now;
        if (event->irq & EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK) vin_done_tick[2] = now;
    }
    if (engine == ENGINE_NPU && (event->irq & EDRV32_NPU_IRQ_STAT_DONE_MASK))
        npu_done_tick = platform_ticks();
    irq_flags[engine] |= event->irq;
    irq_errors[engine] |= event->error;
}
static void pair_release(void)
{
    reference(v.pair_image, 0, REF_PAIR);
    v.pair_image = -1;
    if (v.pair_input >= 0) v.input_busy &= ~(1u << v.pair_input);
    v.pair_input = -1;
    if (v.capture) vin_slots_busy(2, v.input_busy);
}
static void queue_image(int slot)
{
    reference(v.ready, 0, REF_READY);
    v.ready = slot;
    reference(slot, REF_READY, 0);
}
/* DISP 2.4: only SWITCH releases a surface which has been scanned. */
void vision_display_irq(uint32_t irq)
{
    irq_flags[ENGINE_DISP] |= irq;
}
uint32_t vision_upload_base(void)
{
    for (unsigned i = 6; i < 8; ++i)
        if (!v.refs[i]) { v.receive_start = platform_ticks(); return image_address(i); }
    return 0;
}
static void display_step(uint32_t flags)
{
    /* DISP 2.4/5.3: stopped IDLE also releases the last scanned surface. */
    if (v.state == PIPE_STOPPING && v.display_owned &&
        (engine_poll(ENGINE_DISP).status & EDRV32_DISP_STATUS_IDLE_MASK)) {
        for (unsigned i = 0; i < 8; ++i) reference((int)i, 0, REF_DISPLAY);
        v.display_owned = 0;
        v.submitted = -1;
    }
    if (flags & EDRV32_DISP_IRQ_STAT_SWITCH_MASK) {
        uint32_t released = disp_released(DISP_L0);
        for (unsigned i = 0; i < 8; ++i)
            if (image_address(i) == released) reference((int)i, 0, REF_DISPLAY);
    }
    if (!(flags & EDRV32_DISP_IRQ_STAT_FRAME_MASK)) return;
    if (v.submitted >= 0 && disp_current(DISP_L0) == image_address((unsigned)v.submitted))
        v.submitted = -1;
    if (v.state == PIPE_STOPPING && v.display_owned) {
        disp_layer_enable(DISP_L0, 0);
        reference(v.ready, 0, REF_READY);
        v.ready = -1;
        unsigned held = 0;
        for (unsigned i = 0; i < 8; ++i) held |= v.refs[i] & REF_DISPLAY;
        if (!held) v.display_owned = 0;
    } else if (v.ready >= 0 && v.submitted < 0) {
        v.current = v.ready;
        reference(v.current, REF_DISPLAY, REF_READY);
        v.ready = -1;
        v.submitted = v.current;
        v.display_owned = 1;
        disp_submit(DISP_L0, image_address((unsigned)v.current), VISION_STRIDE);
        disp_layer_enable(DISP_L0, 1);
    }
}
static const lv_image_dsc_t *take_image(void)
{
    return v.current < 0 ? NULL : &v.images[v.current];
}
ui_vision_t ui_data_vision(void)
{
    if (timing.await_gui && !timing.gui_taken) {
        timing.gui_taken = true; gui_armed = 1;
    }
    sessions[v.page].data.image = take_image();
    ui_vision_t result=sessions[v.page].data;
    result.boxes = boxes;
    ui_detection_filter(&result,sessions[v.page].raw,sessions[v.page].count);
    detection_armed = detection_revision;
    return result;
}
void ui_data_boxes(void) { boxes = !boxes; }
ui_process_config_t ui_data_process_config(void) { return process; }
void ui_data_process_set(const ui_process_config_t *config)
{
    if ((unsigned)config->gamma_tenths != v.gamma_target) {
        v.gamma_target = (unsigned)config->gamma_tenths;
        v.gamma_index = 0;
    }
    process = *config;
    ++v.process_revision;
    v.process_dirty = 1;
    if (v.state == PIPE_LIVE && v.page == PAGE_PROCESS) v.state = PIPE_CONFIGURE;
    app_wake_at(platform_ticks());
}
void ui_data_process_defaults(uint32_t stages)
{
    ui_process_config_t p = process;
    if (stages & UI_PROC_LEVEL) { p.brightness = 0; p.contrast = 256; }
    if (stages & UI_PROC_GAMMA) p.gamma_tenths = 10;
    if (stages & UI_PROC_S1) p.stage1 = 2;
    if (stages & UI_PROC_S2) p.stage2 = 2;
    if (stages & UI_PROC_BINARY) p.threshold = 128;
    if (stages & UI_PROC_ROTATE) p.angle = 0;
    if (stages & UI_PROC_SCALE) p.scale_percent = 100;
    if (stages & UI_PROC_TRANSLATE) p.translate_x = p.translate_y = 0;
    if (stages == UI_PROC_ALL) { p.enabled = 0; p.original = false; }
    ui_data_process_set(&p);
}
const lv_image_dsc_t *ui_data_process(unsigned mode)
{
    (void)mode;
    return take_image();
}
static void stop_capture(void)
{
    if (!v.capture) return;
    vin_channel_enable(0, 0);
    vin_channel_enable(2, 0);
    engine_control(ENGINE_VIN, 0);
}
static void request_page(unsigned page)
{
    initialize();
    v.page = page;
    if (page != PAGE_PROCESS && !v.model_ready) {
        board_session_fail(7);
        return;
    }
    v.state = PIPE_STARTING;
    memset(&timing, 0, sizeof timing);
    timing.since = platform_ticks();
    gui_armed = gui_ready = 0; report[0] = 0;
    sessions[page].data.boxes = boxes;
    app_wake_at(platform_ticks());
}
static void enter_camera(void) { request_page(PAGE_CAMERA); }
static void enter_image(void) { request_page(PAGE_IMAGE); }
static void enter_process(void) { request_page(PAGE_PROCESS); }
static void leave(void)
{
    v.state = PIPE_STOPPING;
    vision_cancel(2);
    stop_capture();
    reference(v.ready, 0, REF_READY); v.ready = -1;
    app_wake_at(platform_ticks());
}
void vision_pause(bool paused)
{
    if (paused) { v.state = PIPE_PAUSING; stop_capture(); }
    else v.state = PIPE_STARTING;
    app_wake_at(platform_ticks());
}
bool vision_ready(ui_state_t target)
{
    if (target == UI_STATE_IDLE) return v.state == PIPE_OFF;
    if (target == UI_STATE_PAUSED) return v.state == PIPE_FROZEN;
    return v.state == PIPE_LIVE;
}
static void pix_mode(void)
{
    const ui_process_config_t *p = &process;
    if (v.gamma_loaded != p->gamma_tenths) {
        if (v.gamma_index < 256) return;
        /* PIX 2.3: with no active frame, the bank opposite the shadow selection
         * is writable, including if SOF arrives during the APB table writes. */
        if (!(engine_poll(ENGINE_PIX).status & EDRV32_PIX_STATUS_IDLE_MASK)) return;
        v.gamma_bank ^= 1;
        pix_gamma_load(v.gamma_bank, v.gamma_table);
        v.gamma_loaded = p->gamma_tenths;
    }
    uint32_t flags = 0;
    if (p->enabled & UI_PROC_LEVEL) flags |= EDRV32_PIX_CFG_BC_EN_MASK;
    if (p->enabled & UI_PROC_GAMMA) flags |= EDRV32_PIX_CFG_GAMMA_EN_MASK;
    if (p->enabled & UI_PROC_GRAY) flags |= EDRV32_PIX_CFG_GRAY_EN_MASK;
    if (p->enabled & UI_PROC_BINARY) flags |= EDRV32_PIX_CFG_BIN_EN_MASK;
    if (p->enabled & UI_PROC_INVERT) flags |= EDRV32_PIX_CFG_INV_EN_MASK;
    struct pix_config config = {flags,
        (p->enabled & UI_PROC_S1) ? (enum pix_operation)p->stage1 : PIX_BYPASS,
        (p->enabled & UI_PROC_S2) ? (enum pix_operation)p->stage2 : PIX_BYPASS,
        v.gamma_bank, (unsigned)p->contrast,
        p->brightness, (unsigned)p->threshold};
    pix_configure(&config);
    engine_control(ENGINE_PIX, p->original ? 0 : EDRV32_PIX_CTRL_ENABLE_MASK);
    geo_matrix(v.matrix, (p->enabled & UI_PROC_ROTATE) ? p->angle : 0,
        (p->enabled & UI_PROC_SCALE) ? p->scale_percent : 100,
        (p->enabled & UI_PROC_TRANSLATE) ? p->translate_x : 0,
        (p->enabled & UI_PROC_TRANSLATE) ? p->translate_y : 0,
        !!(p->enabled & UI_PROC_MIRROR_X), !!(p->enabled & UI_PROC_MIRROR_Y),
        VISION_WIDTH, VISION_HEIGHT);
    v.shadow_revision = v.process_revision;
    v.process_dirty = 0;
}
static void configure_capture(void)
{
    struct vin_channel image = {VIN_CAM0, 4, VISION_STRIDE, {0}, 0};
    struct vin_channel input = {VIN_CAM0, 3, VISION_STRIDE, {0}, 0};
    for (unsigned i = 0; i < 4; ++i) {
        image.base[i] = image_address(i);
        if (v.refs[i]) image.busy_slots |= 1u << i;
    }
    for (unsigned i = 0; i < 3; ++i) input.base[i] = VISION_INPUT_BASE +
                                                               i * VISION_INPUT_SPACING;
    /* VRN must never touch PIX/GEO, including camera configuration. */
    if (v.page == PAGE_PROCESS) {
        pix_mode();
        if (v.process_dirty) return;
    }
    else if (platform_hardware() & APP_HW_PIX) {
        struct pix_config bypass = {0, PIX_BYPASS, PIX_BYPASS, v.gamma_bank, 256, 0, 128};
        pix_configure(&bypass);
        engine_control(ENGINE_PIX, EDRV32_PIX_CTRL_ENABLE_MASK);
    }
    vin_camera_size(0, VISION_WIDTH, VISION_HEIGHT);
    vin_channel_configure(0, &image);
    if (v.page != PAGE_PROCESS) vin_channel_configure(2, &input);
    v.capture = 1;
    engine_control(ENGINE_VIN, EDRV32_VIN_CTRL_ENABLE_MASK);
}
static void start_inference(unsigned input, int image, uint32_t frame, uint64_t vin)
{
    v.npu_input = input; v.npu_image = image; v.npu_frame = frame; v.npu_vin = vin;
    v.npu_busy = 1;
    v.npu_start = platform_ticks();
    if (timing.last_start) {
        timing.sums[8] += v.npu_start - timing.last_start;
        ++timing.periods;
    }
    timing.last_start = v.npu_start;
    engine_control(ENGINE_NPU, EDRV32_NPU_CTRL_ENABLE_MASK);
    npu_start(VISION_INPUT_BASE + input * VISION_INPUT_SPACING, VISION_OUTPUT_BASE);
}
static void camera_frame(unsigned channel)
{
    struct vin_frame frame = vin_frame_done(channel);
    if (frame.info & (EDRV32_VIN_CH_DONE_INFO_INCOMPLETE_MASK |
                      EDRV32_VIN_CH_DONE_INFO_BUS_ERR_MASK)) fail("VIN frame error");
    if (v.state != PIPE_LIVE || v.page == PAGE_IMAGE ||
        (v.page == PAGE_CAMERA && !v.model_ready)) return;
    int slot = (int)vin_frame_slot(frame.info);
    if (v.page == PAGE_PROCESS) {
        if (channel == 0) {
            v.applied_revision = v.shadow_revision;
            if (process.original || !(process.enabled & 0xf80u)) queue_image(slot);
            else if (v.geo_source < 0) {
                int target = free_image(4, 6);
                if (target < 0) return;
                v.geo_source = slot;
                v.geo_target = target;
                reference(slot, REF_GEO, 0);
                reference(target, REF_GEO, 0);
                struct geo_config config = {.src_base = image_address((unsigned)slot),
                    .src_stride = VISION_STRIDE, .src_width = VISION_WIDTH,
                    .src_height = VISION_HEIGHT, .dst_base = image_address((unsigned)target),
                    .dst_stride = VISION_STRIDE, .rect_width = VISION_WIDTH,
                    .rect_height = VISION_HEIGHT};
                memcpy(config.matrix, v.matrix, sizeof(config.matrix));
                geo_descriptor_pack(uncached(VISION_GEO_DESCRIPTOR), &config);
                geo_submit(VISION_GEO_DESCRIPTOR, 1);
            }
        }
        return;
    }
    if (channel == 0) queue_image(slot);
    if (channel == 0) {
        reference(v.pair_image, 0, REF_PAIR);
        v.pair_image = slot;
        v.image_id = frame.frame_id;
        v.image_tick = vin_done_tick[0];
        reference(slot, REF_PAIR, 0);
    } else {
        if (v.pair_input >= 0) v.input_busy &= ~(1u << v.pair_input);
        v.pair_input = slot;
        v.input_id = frame.frame_id;
        v.input_busy |= 1u << slot;
        vin_slots_busy(2, v.input_busy);
    }
}
/* Latest matched VIN pair is retained while NPU and the previous post overlap. */
static void camera_start(void)
{
    if (v.page != PAGE_CAMERA || v.state != PIPE_LIVE || v.npu_busy ||
        !v.model_ready || v.model_pending) return;
    if (v.pair_image >= 0 && v.pair_input >= 0 && v.image_id == v.input_id) {
        reference(v.pair_image, REF_NPU, REF_PAIR);
        start_inference((unsigned)v.pair_input, v.pair_image, v.image_id, v.image_tick);
        v.pair_image = v.pair_input = -1;
    }
}
/* P5c 10.2: one synchronous RND batch; the cooperative GUI cannot submit until
 * this call returns, and its own run_batch obeys the same ownership rule. */
static void copy_output(void)
{
    static _Alignas(64) struct rnd_command command;
    struct rnd_common c = {.dst_base = VISION_POST_BASE, .dst_stride = 5040,
        .dst_fmt = RND_ARGB8888, .src_fmt = RND_ARGB8888,
        .clip = {0, 0, 1259, 143}, .rect = {0, 0, 1259, 143}};
    struct rnd_source source = {VISION_OUTPUT_BASE, 5040, 0, 0};
    rnd_copy(&command, &c, &source);
    struct rnd_range target = {(void *)(uintptr_t)(EDRV32_DDR_BASE + VISION_POST_BASE),
                               VISION_OUTPUT_BYTES};
    struct rnd_range input = {uncached(VISION_OUTPUT_BASE), VISION_OUTPUT_BYTES};
    struct rnd_batch batch = {&command, 1, &input, 1, &target, 1};
    uint64_t begin = platform_ticks();
    showcase_rnd_run(&batch);
    timing.copy_ticks = platform_ticks() - begin;
}

static void publish_result(void)
{
    platform_gui_wake();
    sessions[v.page].count=v.post.kept;
    for(unsigned i=0;i<sessions[v.page].count;++i) {
        const yolo_detection *d=&v.detections[i];
        sessions[v.page].raw[i]=(ui_detection_t){ui_coco_names[d->class_id],d->score/10,
            d->x0,d->y0,d->x1-d->x0,d->y1-d->y0,d->class_id};
    }
    timing.handoff = platform_ticks();
    timing.completed[0] = timing.npu_done - timing.job_npu_start;
    timing.sums[9] += timing.copy_ticks;
    timing.completed[1] = timing.post_start - timing.npu_done;
    for (unsigned i = 0; i < 3; ++i) timing.completed[2+i] = timing.cpu[i];
    timing.completed[5] = timing.nms_end - timing.post_start;
    for (unsigned i = 0; i < 6; ++i) timing.sums[i] += timing.completed[i];
    ++timing.samples;
    timing.handoff_vin = timing.vin;
    timing.await_gui = true; timing.gui_taken = false;
    gui_armed = gui_ready = 0;
    if (v.image_job && v.state == PIPE_LIVE) queue_image(v.job_image);
}
static void finish_job(void)
{
    reference(v.job_image, 0, REF_JOB);
    v.job_image = -1;
    if (v.image_job) {
        v.input_busy &= ~(1u << v.job_input);
        if (v.capture) vin_slots_busy(2, v.input_busy);
    }
    v.job = JOB_IDLE;
}
uint32_t vision_bulk_done(unsigned kind, uint32_t base, uint32_t bytes)
{
    initialize();
    if (kind == 1) {
        if (bytes < 32) return 1;
        const uint8_t *header = uncached(base);
        const char *error = vision_model_header(header, bytes);
        if (error) {
            platform_puts(error);
            platform_puts("\r\n");
            return strcmp(error, "Model bytes") == 0 ? 1 : 2;
        }
        v.model_base = base;
        v.model_bytes = bytes;
        v.model_count = vision_read32(header + 8);
        v.model_desc_bytes = vision_read32(header + 12);
        v.model_weight_bytes = vision_read32(header + 16);
        v.model_offset = v.model_phase = 0;
        v.model_pending = 1;
    } else if (kind == 2) {
        if (bytes != VISION_IMAGE_BYTES) return 1;
        v.upload_complete = platform_ticks();
        v.receive_ticks = v.upload_complete - v.receive_start;
        v.upload_base = base;
        v.upload_bytes = bytes;
        sessions[PAGE_IMAGE].upload = UPLOAD_READY;
        sessions[PAGE_IMAGE].data.image_status = UI_IMAGE_DETECTING;
    }
    if (kind == 1 && v.page == PAGE_CAMERA && v.state == PIPE_LIVE) v.state = PIPE_CONFIGURE;
    app_wake_at(platform_ticks());
    return 0;
}
static void model_step(void)
{
    uint32_t length = v.model_phase ? v.model_weight_bytes : v.model_desc_bytes;
    uint32_t source = v.model_base + (v.model_phase ? 0x100000u : 0x1000u);
    uint32_t destination = v.model_phase ? VISION_MODEL_BASE : VISION_DESC_BASE;
    unsigned bytes = length - v.model_offset;
    if (bytes > 1024) bytes = 1024;
    memcpy(uncached(destination + v.model_offset), uncached(source + v.model_offset), bytes);
    v.model_offset += bytes;
    if (v.model_offset == length) {
        v.model_offset = 0;
        if (++v.model_phase == 2) {
            struct npu_config config = {VISION_MODEL_BASE, VISION_WORK_BASE,
                VISION_INPUT_BASE, VISION_OUTPUT_BASE, VISION_DESC_BASE, v.model_count};
            npu_configure(&config);
            v.model_pending = 0;
            v.model_ready = true;
            /* Each upload owns its own window metadata; no global image_window. */
            eth_window_configure(0, v.model_base, v.model_bytes);
            board_bulk_complete(1);
        }
    }
}
static void send_results(void)
{
    struct eth_tx_descriptor *tx = uncached(VISION_TX_DESCRIPTORS);
    unsigned bytes = (unsigned)vision_detection_pack(uncached(VISION_TX_DETECTIONS),
                            v.detections, v.post.kept, v.job_frame, v.job_request);
    eth_tx_descriptor_pack(&tx[0], VISION_INPUT_BASE + v.job_input * VISION_INPUT_SPACING,
                           VISION_INPUT_BYTES, 0, 0, 0);
    eth_tx_descriptor_pack(&tx[1], VISION_POST_BASE, VISION_OUTPUT_BYTES, 1, 0, 0);
    eth_tx_descriptor_pack(&tx[2], VISION_TX_DETECTIONS, bytes, 2, 1, 0);
    v.tx_done = engine_poll(ENGINE_ETH).done_count;
    if (board_eth_send(VISION_TX_DESCRIPTORS, 3)) v.job = JOB_TX;
}
static void timing_step(void)
{
    uint64_t now = platform_ticks();
    uint32_t lock = sched_port_lock();
    unsigned presented = gui_ready;
    uint64_t tick = gui_done;
    gui_ready = 0;
    sched_port_unlock(lock);
    if (timing.await_gui && presented) {
        timing.sums[6] += tick - timing.handoff;
        timing.sums[7] += tick - timing.handoff_vin;
        ++timing.gui_samples; timing.await_gui = false;
    }
    if (now - timing.since < platform_clock_hz()) return;
    unsigned a[10] = {0};
    for (unsigned i = 0; i < 10; ++i) {
        unsigned count = i == 8 ? timing.periods :
            (i == 6 || i == 7) ? timing.gui_samples : timing.samples;
        if (count) a[i] = tenths(timing.sums[i] / count);
    }
    ui_vision_t *data = &sessions[v.page].data;
    data->fps = (unsigned)((uint64_t)timing.samples * platform_clock_hz() /
                           (now - timing.since));
    data->npu_tenths = a[0]; data->post_tenths = a[2] + a[3] + a[4];
    data->latency_tenths = a[7];
    if (v.page == PAGE_CAMERA && v.state == PIPE_LIVE) {
        ui_system_t sys = ui_data_system();
        snprintf(report, sizeof report,
            "vision fps=%u npu=%u.%u wait=%u.%u decode=%u.%u sort=%u.%u nms=%u.%u "
            "post_span=%u.%u gui=%u.%u e2e=%u.%u period=%u.%u copy=%u.%u "
            "cpu_comm=%u%% cpu_app=%u%% cpu_gui=%u%%\r\n",
            data->fps, a[0]/10,a[0]%10,a[1]/10,a[1]%10,a[2]/10,a[2]%10,
            a[3]/10,a[3]%10,a[4]/10,a[4]%10,a[5]/10,a[5]%10,a[6]/10,a[6]%10,
            a[7]/10,a[7]%10,a[8]/10,a[8]%10,a[9]/10,a[9]%10,
            sys.task_cpu[0],sys.task_cpu[1],sys.task_cpu[2]);
    } else report[0] = 0;
    memset(timing.sums, 0, sizeof timing.sums);
    timing.samples = timing.gui_samples = timing.periods = 0; timing.since = now;
}
int vision_service(void)
{
    /* Design 4.5.2: software floating-point gamma work is one sample per slice. */
    if (v.page == PAGE_PROCESS && v.gamma_index < 256) {
        v.gamma_table[v.gamma_index] = pix_gamma_value(v.gamma_index, v.gamma_target);
        ++v.gamma_index;
    }
    uint32_t flags[ENGINE_NPU + 1];
    uint32_t errors[ENGINE_NPU + 1];
    uint32_t lock = sched_port_lock();
    for (unsigned i = 0; i <= ENGINE_NPU; ++i) {
        flags[i] = irq_flags[i];
        errors[i] = irq_errors[i];
        irq_flags[i] = irq_errors[i] = 0;
    }
    sched_port_unlock(lock);
    const unsigned engines[] = {ENGINE_VIN, ENGINE_PIX, ENGINE_GEO, ENGINE_NPU};
    const uint32_t error_masks[] = {EDRV32_VIN_IRQ_STAT_ERROR_MASK,
        EDRV32_PIX_IRQ_STAT_ERROR_MASK, EDRV32_GEO_IRQ_STAT_ERROR_MASK,
        EDRV32_NPU_IRQ_STAT_ERROR_MASK};
    const char *const messages[] = {"VIN error", "PIX error", "GEO error", "NPU error"};
    for (unsigned i = 0; i < 4; ++i) {
        if (errors[engines[i]] || (flags[engines[i]] & error_masks[i])) fail(messages[i]);
    }
    display_step(flags[ENGINE_DISP]);
    if (v.state == PIPE_CONFIGURE || v.state == PIPE_PAUSING ||
        v.state == PIPE_STOPPING) stop_capture();
    if (flags[ENGINE_GEO] & EDRV32_GEO_IRQ_STAT_DONE_MASK) {
        if (v.state == PIPE_LIVE && v.page == PAGE_PROCESS) queue_image(v.geo_target);
        reference(v.geo_source, 0, REF_GEO);
        reference(v.geo_target, 0, REF_GEO);
        v.geo_source = v.geo_target = -1;
    }
    if (v.capture) {
        if (flags[ENGINE_VIN] & EDRV32_VIN_IRQ_STAT_FRAME_MASK) camera_frame(0);
        if (flags[ENGINE_VIN] & EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK) camera_frame(2);
    }
    if (flags[ENGINE_NPU] & EDRV32_NPU_IRQ_STAT_DONE_MASK) {
        v.npu_complete = 1; v.npu_done = npu_done_tick;
    }
    if (v.npu_complete && (v.job == JOB_IDLE || v.job == JOB_NPU)) {
        timing.npu_done = v.npu_done;
        timing.job_npu_start = v.npu_start;
        timing.vin = v.npu_vin;
        v.job_input = v.npu_input; v.job_frame = v.npu_frame;
        v.job_image = v.npu_image;
        v.image_job = v.page == PAGE_IMAGE;
        if (!v.image_job) {
            reference(v.job_image, REF_JOB, REF_NPU);
        }
        copy_output();
        v.npu_busy = v.npu_complete = 0;
        if (!v.image_job) {
            v.input_busy &= ~(1u << v.npu_input);
            if (v.capture) vin_slots_busy(2, v.input_busy);
        }
        v.job = JOB_POST;
        camera_start();
        timing.post_start = platform_ticks();
        memset(timing.cpu, 0, sizeof timing.cpu);
        vision_post_begin(&v.post, (void *)(uintptr_t)(EDRV32_DDR_BASE + VISION_POST_BASE),
                          (void *)(uintptr_t)(EDRV32_DDR_BASE + VISION_WORKSPACE), v.detections);
        v.post_ticks = 0;
    }
    if (v.job == JOB_TX && engine_poll(ENGINE_ETH).done_count - v.tx_done >= 3) {
        sessions[PAGE_IMAGE].data.roundtrip_ms =
            (unsigned)((platform_ticks() - v.upload_complete) * 1000 / platform_clock_hz());
        if (!timing.cancelled) {
            sessions[PAGE_IMAGE].data.image_status = UI_IMAGE_DONE;
            board_bulk_complete(2);
            unsigned t[8] = {tenths(v.receive_ticks), tenths(v.ch2_ticks)};
            for (unsigned i = 0; i < 6; ++i) t[2 + i] = tenths(timing.completed[i]);
            snprintf(image_line, sizeof image_line,
                "image request=%lu receive=%u.%u ch2=%u.%u npu=%u.%u wait=%u.%u "
                "decode=%u.%u sort=%u.%u nms=%u.%u post_span=%u.%u upload_to_done=%u\r\n",
                (unsigned long)v.job_request, t[0]/10,t[0]%10, t[1]/10,t[1]%10,
                t[2]/10,t[2]%10, t[3]/10,t[3]%10, t[4]/10,t[4]%10, t[5]/10,t[5]%10,
                t[6]/10,t[6]%10, t[7]/10,t[7]%10, sessions[PAGE_IMAGE].data.roundtrip_ms);
        }
        finish_job();
    }
    if (v.job == JOB_CH2 &&
        (flags[ENGINE_VIN] & EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK)) {
        struct vin_frame frame = vin_frame_done(2);
        if (frame.info & (EDRV32_VIN_CH_DONE_INFO_INCOMPLETE_MASK |
                          EDRV32_VIN_CH_DONE_INFO_BUS_ERR_MASK)) fail("DDR CH2 frame error");
        v.job_input = vin_frame_slot(frame.info);
        timing.vin = vin_done_tick[2];
        v.ch2_ticks = timing.vin - v.ch2_start;
        vin_channel_enable(2, 0);
        start_inference(v.job_input, v.job_image, v.job_frame, timing.vin);
        v.job = JOB_NPU;
    } else if (v.job == JOB_POST) {
        uint64_t start = platform_ticks();
        unsigned phase = v.post.phase == 0 ? 0 : v.post.phase < 3 ? 1 : 2;
        int complete = vision_post_step(&v.post);
        uint64_t end = platform_ticks();
        uint64_t elapsed = end - start;
        if (phase == 0 && v.post.phase != 0) timing.decode_end = end;
        if (phase == 1 && v.post.phase >= 3) timing.sort_end = end;
        if (complete) timing.nms_end = end;
        timing.cpu[phase] += elapsed;
        v.post_ticks += elapsed;
        if (complete) {
            if (!timing.cancelled) publish_result();
            if (v.image_job && !timing.cancelled) {
                v.send_start = platform_ticks(); v.job = JOB_SEND;
            } else finish_job();
        }
    } else if (v.job == JOB_SEND) {
        if (timing.cancelled) finish_job(); else send_results();
    }
    if ((v.state == PIPE_CONFIGURE || v.state == PIPE_PAUSING ||
         v.state == PIPE_STOPPING) && v.job == JOB_IDLE && !v.npu_busy && v.geo_source < 0) {
        if (v.capture && !(engine_poll(ENGINE_VIN).status & EDRV32_VIN_STATUS_IDLE_MASK))
            return 1;
        if (v.page == PAGE_PROCESS &&
            (!(engine_poll(ENGINE_PIX).status & EDRV32_PIX_STATUS_IDLE_MASK) ||
             !(engine_poll(ENGINE_GEO).status & EDRV32_GEO_STATUS_IDLE_MASK))) return 1;
        pair_release(); v.capture = 0;
        if (v.state == PIPE_STOPPING) {
            if (v.display_owned) return 1;
            engine_control(ENGINE_VIN, 0);
            if (v.page == PAGE_CAMERA || v.page == PAGE_IMAGE) engine_control(ENGINE_NPU, 0);
            if (v.page == PAGE_PROCESS) {
                engine_control(ENGINE_PIX, 0); engine_control(ENGINE_GEO, 0);
            }
            v.current = -1; v.page = PAGE_NONE; v.state = PIPE_OFF;
        } else if (v.state == PIPE_PAUSING) v.state = PIPE_FROZEN;
        else v.state = PIPE_STARTING;
    }
    if (v.job == JOB_IDLE && !v.npu_busy && v.geo_source < 0 && v.model_pending) {
        model_step(); return 1;
    }
    if (v.state == PIPE_STARTING) {
        if (v.page == PAGE_PROCESS && v.gamma_index < 256) return 1;
        if (v.page != PAGE_IMAGE) configure_capture();
        if (v.page == PAGE_PROCESS && v.process_dirty) return 1;
        v.state = PIPE_LIVE;
    }
    if (v.state == PIPE_LIVE && v.job == JOB_IDLE && v.model_ready &&
        sessions[PAGE_IMAGE].upload == UPLOAD_READY) {
        sessions[PAGE_IMAGE].upload = UPLOAD_EMPTY;
        timing.cancelled = false; v.job_request = request;
        int slot = 6 + (int)((v.upload_base - SHOWCASE_IMAGE_BASE) / SHOWCASE_IMAGE_BYTES);
        v.job_image = slot; reference(slot, REF_JOB, 0);
        v.job_input = 0; v.job_frame = v.next_frame++; v.image_job = 1;
        sessions[PAGE_IMAGE].frame = v.job_frame;
        v.receive_base = v.upload_base; v.receive_bytes = v.upload_bytes;
        queue_image(slot);
        struct vin_channel input = {VIN_MEMORY, 2, VISION_STRIDE,
            {VISION_INPUT_BASE, VISION_INPUT_BASE + VISION_INPUT_SPACING}, 0};
        vin_channel_configure(2, &input); v.capture = 1;
        engine_control(ENGINE_VIN, EDRV32_VIN_CTRL_ENABLE_MASK);
        v.ch2_start = platform_ticks();
        vin_memory_start(v.receive_base, VISION_STRIDE, VISION_WIDTH, VISION_HEIGHT);
        v.job = JOB_CH2;
    }
    camera_start();
    timing_step();
    return v.state == PIPE_STARTING || v.state == PIPE_STOPPING ||
        v.state == PIPE_PAUSING || v.state == PIPE_CONFIGURE || v.model_pending ||
        v.job != JOB_IDLE || v.npu_busy || v.geo_source >= 0;
}

static void step(void)
{
    int busy = vision_service();
    /* IRQ events wake idle camera work; sliced CPU work resumes immediately. */
    unsigned cpu = v.job == JOB_POST || (v.page == PAGE_PROCESS && v.gamma_index < 256) ||
                   v.model_pending;
    app_wake_at(busy ? platform_ticks() + (cpu ? 0 : platform_clock_hz() / 1000) :
                      UINT64_MAX);
}
const struct app vision_app_camera = {
    "视觉识别", NULL, APP_HW_VIN | APP_HW_NPU, 0, enter_camera, step, leave};
const struct app vision_app_image = {
    "图片识别", NULL, APP_HW_NPU | APP_HW_ETH | APP_HW_VIN, 0, enter_image, step, leave};
const struct app vision_app_process = {
    "图像处理", NULL, APP_HW_VIN | APP_HW_PIX | APP_HW_GEO, 0, enter_process, step, leave};

void vision_init(void)
{
    initialize();
    if (platform_hardware() & APP_HW_VIN) {
        if (ov5640_init(0, platform_clock_hz())) fail("OV5640 camera 0 initialization");
    }
    if (platform_hardware() & APP_HW_NPU) {
        /* SoC 7.4: destination uses only its uncached alias. */
        memcpy(uncached(VISION_DESC_BASE), showcase_model_desc, showcase_model_desc_bytes);
        memcpy(uncached(VISION_MODEL_BASE), showcase_model_weights,
               showcase_model_weights_bytes);
        struct npu_config config = {VISION_MODEL_BASE, VISION_WORK_BASE,
            VISION_INPUT_BASE, VISION_OUTPUT_BASE, VISION_DESC_BASE, showcase_model_count};
        npu_configure(&config);
        v.model_ready = true;
    }
}
