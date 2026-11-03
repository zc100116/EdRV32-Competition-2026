/* vision.c — showcase design 4.3/4.5; cooperative VIN/YOLO/PIX/GEO applications.
 * IRQs latch events; task slices retain DMA and L0 display surface ownership.
 * Clock domain: clk_sys; accelerator data/interrupts originate in clk_mem.
 */
#include "vision_hooks.h"
#include "memory.h"
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

enum { REF_PAIR = 1, REF_JOB = 2, REF_READY = 4, REF_DISPLAY = 8,
       REF_GEO = 32 };
enum { PAGE_NONE, PAGE_CAMERA, PAGE_IMAGE, PAGE_PROCESS };
enum { JOB_IDLE, JOB_CH2, JOB_NPU, JOB_POST, JOB_SEND, JOB_TX };
static struct {
    unsigned page;
    ui_process_config_t process;
    unsigned process_dirty, gamma_bank;
    int gamma_loaded;
    unsigned gamma_target, gamma_index;
    uint8_t gamma_table[256];
    int32_t matrix[6];
    unsigned capture;
    unsigned reconfigure;
    unsigned camera_source;
    unsigned initialized;
    unsigned refs[8];
    int ready, current, pair_image, pair_input;
    uint32_t image_id, input_id;
    uint32_t input_busy;
    lv_image_dsc_t images[8];
    ui_vision_t data;
    ui_detection_t display_raw[YOLO_MAX_DETECTIONS];
    unsigned display_count;
    unsigned job;
    int job_image;
    unsigned job_input;
    unsigned job_batch;
    uint32_t job_frame;
    uint32_t receive_base, receive_bytes;
    uint64_t ch2_start, ch2_ticks, send_start, receive_start, receive_ticks;
    uint64_t report_start;
    uint32_t report_frames;
    int submitted;
    unsigned display_owned;
    uint32_t next_frame;
    uint64_t npu_start, batch_start, post_ticks, last_result;
    struct vision_post post;
    yolo_detection detections[YOLO_MAX_DETECTIONS];
    int geo_source, geo_target;
    uint32_t tx_done;
    unsigned image_pending;
    uint32_t upload_base, upload_bytes;
    unsigned model_pending;
    uint32_t model_base, model_bytes, model_offset;
    unsigned model_phase;
    uint32_t model_count, model_desc_bytes, model_weight_bytes;
} v = {.ready = -1, .current = -1, .pair_image = -1, .pair_input = -1,
       .submitted = -1, .job_image = -1, .geo_source = -1, .geo_target = -1,
       .process = {.contrast = 256, .gamma_tenths = 10, .threshold = 128,
                   .scale_percent = 100},
       .gamma_loaded = -1, .gamma_target = 10, .gamma_index = 256,
       .data = {.boxes = true, .waiting = true}};
static volatile uint32_t irq_flags[ENGINE_NPU + 1];
static volatile uint32_t irq_errors[ENGINE_NPU + 1];

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
static void print_time(const char *name, uint64_t ticks)
{
    unsigned value = tenths(ticks);
    platform_puts(name);
    platform_put_u32(value / 10);
    platform_puts(".");
    platform_put_u32(value % 10);
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
    if (v.page == PAGE_NONE && v.display_owned &&
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
    if (v.page == PAGE_NONE && v.display_owned) {
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
ui_vision_t ui_data_vision(bool batch)
{
    (void)batch;
    v.data.image = take_image();
    ui_vision_t result=v.data;
    ui_detection_filter(&result,v.display_raw,v.display_count);
    return result;
}
void ui_data_pause(void)
{
    v.data.paused = !v.data.paused;
    v.reconfigure = 1;
    app_wake_at(platform_ticks());
}
void ui_data_boxes(void) { v.data.boxes = !v.data.boxes; }
void ui_data_batch_stop(void)
{
    v.data.waiting = true;
    v.data.batch_total = v.data.batch_index;
    /* A submitted inference/TX drains normally; no tensor is overwritten. */
}
ui_process_config_t ui_data_process_config(void) { return v.process; }
void ui_data_process_set(const ui_process_config_t *config)
{
    if ((unsigned)config->gamma_tenths != v.gamma_target) {
        v.gamma_target = (unsigned)config->gamma_tenths;
        v.gamma_index = 0;
    }
    v.process = *config;
    v.process_dirty = 1;
    app_wake_at(platform_ticks());
}
void ui_data_process_defaults(void)
{
    const ui_process_config_t defaults = {.contrast = 256, .gamma_tenths = 10,
        .threshold = 128, .scale_percent = 100};
    ui_data_process_set(&defaults);
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
    v.camera_source = page != PAGE_IMAGE;
    v.data.paused = false;
    v.data.waiting = page == PAGE_IMAGE;
    v.reconfigure = 1;
    app_wake_at(platform_ticks());
}
static void enter_camera(void) { request_page(PAGE_CAMERA); }
static void enter_image(void) { request_page(PAGE_IMAGE); }
static void enter_process(void) { request_page(PAGE_PROCESS); }
static void leave(void)
{
    v.page = PAGE_NONE;
    v.reconfigure = 1;
    stop_capture();
    reference(v.ready, 0, REF_READY);
    v.ready = -1;
    app_wake_at(platform_ticks());
}
void vision_camera(void)
{
    v.camera_source = 1;
    v.data.paused = false;
    v.data.waiting = false;
    v.reconfigure = 1;
    app_wake_at(platform_ticks());
}
static void pix_mode(void)
{
    const ui_process_config_t *p = &v.process;
    if (v.gamma_loaded != p->gamma_tenths) {
        if (v.gamma_index < 256) return;
        /* PIX 2.3: with no active frame, the bank opposite the shadow selection
         * is writable, including if SOF arrives during the APB table writes. */
        if (!(engine_poll(ENGINE_PIX).status & EDRV32_PIX_STATUS_IDLE_MASK)) return;
        v.gamma_bank ^= 1;
        pix_gamma_load(v.gamma_bank, v.gamma_table);
        v.gamma_loaded = p->gamma_tenths;
    }
    uint32_t flags = EDRV32_PIX_CFG_BC_EN_MASK | EDRV32_PIX_CFG_GAMMA_EN_MASK;
    if (p->gray) flags |= EDRV32_PIX_CFG_GRAY_EN_MASK;
    if (p->binary) flags |= EDRV32_PIX_CFG_BIN_EN_MASK;
    if (p->invert) flags |= EDRV32_PIX_CFG_INV_EN_MASK;
    struct pix_config config = {flags, (enum pix_operation)p->stage1,
        (enum pix_operation)p->stage2, v.gamma_bank, (unsigned)p->contrast,
        p->brightness, (unsigned)p->threshold};
    pix_configure(&config);
    engine_control(ENGINE_PIX, p->original ? 0 : EDRV32_PIX_CTRL_ENABLE_MASK);
    geo_matrix(v.matrix, p->angle, p->scale_percent, p->translate_x, p->translate_y,
               p->mirror_x, p->mirror_y, VISION_WIDTH, VISION_HEIGHT);
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
    if (v.page == PAGE_PROCESS) pix_mode();
    else if (platform_hardware() & APP_HW_PIX) {
        struct pix_config bypass = {0, PIX_BYPASS, PIX_BYPASS, 0, 256, 0, 128};
        pix_configure(&bypass);
        engine_control(ENGINE_PIX, EDRV32_PIX_CTRL_ENABLE_MASK);
    }
    vin_camera_size(0, VISION_WIDTH, VISION_HEIGHT);
    vin_channel_configure(0, &image);
    if (v.page != PAGE_PROCESS) vin_channel_configure(2, &input);
    v.capture = 1;
    engine_control(ENGINE_VIN, EDRV32_VIN_CTRL_ENABLE_MASK);
}
static void start_inference(void)
{
    v.npu_start = platform_ticks();
    engine_control(ENGINE_NPU, EDRV32_NPU_CTRL_ENABLE_MASK);
    npu_start(VISION_INPUT_BASE + v.job_input * VISION_INPUT_SPACING, VISION_OUTPUT_BASE);
    v.job = JOB_NPU;
}
static void camera_frame(unsigned channel)
{
    struct vin_frame frame = vin_frame_done(channel);
    if (frame.info & (EDRV32_VIN_CH_DONE_INFO_INCOMPLETE_MASK |
                      EDRV32_VIN_CH_DONE_INFO_BUS_ERR_MASK)) fail("VIN frame error");
    if (v.reconfigure || v.data.paused || !v.camera_source) return;
    int slot = (int)vin_frame_slot(frame.info);
    if (v.page == PAGE_PROCESS) {
        if (channel == 0) {
            if (v.process.original) queue_image(slot);
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
    if (v.job != JOB_IDLE || v.model_pending) return;
    if (channel == 0) {
        reference(v.pair_image, 0, REF_PAIR);
        v.pair_image = slot;
        v.image_id = frame.frame_id;
        reference(slot, REF_PAIR, 0);
    } else {
        if (v.pair_input >= 0) v.input_busy &= ~(1u << v.pair_input);
        v.pair_input = slot;
        v.input_id = frame.frame_id;
        v.input_busy |= 1u << slot;
        vin_slots_busy(2, v.input_busy);
    }
    if (v.pair_image >= 0 && v.pair_input >= 0 && v.image_id == v.input_id) {
        v.job_image = v.pair_image;
        v.job_input = (unsigned)v.pair_input;
        v.job_frame = v.image_id;
        v.job_batch = 0;
        reference(v.job_image, REF_JOB, REF_PAIR);
        v.pair_image = v.pair_input = -1;
        start_inference();
    }
}

static void publish_result(void)
{
    platform_gui_wake();
    v.display_count=v.post.kept;
    for(unsigned i=0;i<v.display_count;++i) {
        const yolo_detection *d=&v.detections[i];
        v.display_raw[i]=(ui_detection_t){ui_coco_names[d->class_id],d->score/10,
            d->x0,d->y0,d->x1-d->x0,d->y1-d->y0,d->class_id};
    }
    uint64_t now = platform_ticks();
    if (!v.job_batch && now - v.report_start >= platform_clock_hz()) {
        platform_puts("vision");
        print_time(" npu_ms=", (uint64_t)v.data.npu_tenths * platform_clock_hz() / 10000);
        print_time(" post_ms=", v.post_ticks);
        platform_puts(" display_fps=");
        platform_put_u32((unsigned)((uint64_t)(platform_frames() - v.report_frames) *
                                   platform_clock_hz() / (now - v.report_start)));
        platform_puts("\r\n");
        v.report_start = now;
        v.report_frames = platform_frames();
    }
    v.data.post_tenths = tenths(v.post_ticks);
    if (v.last_result) v.data.fps = (unsigned)(platform_clock_hz() / (now - v.last_result));
    v.last_result = now;
    if (v.job_batch && v.page != PAGE_NONE) queue_image(v.job_image);
}
static void finish_job(void)
{
    reference(v.job_image, 0, REF_JOB);
    v.job_image = -1;
    v.input_busy &= ~(1u << v.job_input);
    if (v.capture) vin_slots_busy(2, v.input_busy);
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
        v.batch_start = platform_ticks();
        v.receive_ticks = v.batch_start - v.receive_start;
        v.upload_base = base;
        v.upload_bytes = bytes;
        v.image_pending = 1;
        v.camera_source = 0;
        v.data.waiting = false;
        ++v.data.batch_total;
    }
    v.reconfigure = 1;
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
                            v.detections, v.post.kept, v.job_frame);
    eth_tx_descriptor_pack(&tx[0], VISION_INPUT_BASE + v.job_input * VISION_INPUT_SPACING,
                           VISION_INPUT_BYTES, 0, 0, 0);
    eth_tx_descriptor_pack(&tx[1], VISION_OUTPUT_BASE, VISION_OUTPUT_BYTES, 1, 0, 0);
    eth_tx_descriptor_pack(&tx[2], VISION_TX_DETECTIONS, bytes, 2, 1, 0);
    v.tx_done = engine_poll(ENGINE_ETH).done_count;
    if (board_eth_send(VISION_TX_DESCRIPTORS, 3)) v.job = JOB_TX;
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
    if (v.reconfigure) stop_capture();
    if (flags[ENGINE_GEO] & EDRV32_GEO_IRQ_STAT_DONE_MASK) {
        if (!v.reconfigure && v.page == PAGE_PROCESS) queue_image(v.geo_target);
        reference(v.geo_source, 0, REF_GEO);
        reference(v.geo_target, 0, REF_GEO);
        v.geo_source = v.geo_target = -1;
    }
    if (v.capture) {
        if (v.page == PAGE_PROCESS && v.process_dirty) pix_mode();
        if (flags[ENGINE_VIN] & EDRV32_VIN_IRQ_STAT_FRAME_MASK) camera_frame(0);
        if (flags[ENGINE_VIN] & EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK) camera_frame(2);
    }
    if ((flags[ENGINE_NPU] & EDRV32_NPU_IRQ_STAT_DONE_MASK) && v.job == JOB_NPU) {
        v.data.npu_tenths = tenths(platform_ticks() - v.npu_start);
        /* OUTPUT and workspace use uncached aliases; no full-buffer invalidation step. */
        vision_post_begin(&v.post, uncached(VISION_OUTPUT_BASE), uncached(VISION_WORKSPACE),
                          v.detections);
        v.post_ticks = 0;
        v.job = JOB_POST;
    }
    if (v.job == JOB_TX && engine_poll(ENGINE_ETH).done_count - v.tx_done >= 3) {
        ++v.data.success;
        v.data.batch_index = v.job_frame + 1;
        v.data.roundtrip = (unsigned)((platform_ticks() - v.batch_start) * 1000 /
                                      platform_clock_hz());
        eth_window_configure(0, v.receive_base, v.receive_bytes);
        platform_puts("image");
        print_time(" receive_ms=", v.receive_ticks);
        print_time(" ch2_ms=", v.ch2_ticks);
        platform_puts(" npu_ms="); platform_put_u32(v.data.npu_tenths / 10);
        platform_puts("."); platform_put_u32(v.data.npu_tenths % 10);
        print_time(" post_ms=", v.post_ticks);
        print_time(" return_ms=", platform_ticks() - v.send_start);
        print_time(" upload_to_done_ms=", platform_ticks() - v.batch_start);
        platform_puts("\r\n");
        board_bulk_complete(2);
        finish_job();
    }
    if (v.job == JOB_CH2 &&
        (flags[ENGINE_VIN] & EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK)) {
        struct vin_frame frame = vin_frame_done(2);
        if (frame.info & (EDRV32_VIN_CH_DONE_INFO_INCOMPLETE_MASK |
                          EDRV32_VIN_CH_DONE_INFO_BUS_ERR_MASK)) fail("DDR CH2 frame error");
        v.job_input = vin_frame_slot(frame.info);
        v.ch2_ticks = platform_ticks() - v.ch2_start;
        vin_channel_enable(2, 0);
        start_inference();
    } else if (v.job == JOB_POST) {
        uint64_t start = platform_ticks();
        int complete = vision_post_step(&v.post);
        v.post_ticks += platform_ticks() - start;
        if (complete) {
            publish_result();
            if (v.job_batch) { v.send_start = platform_ticks(); v.job = JOB_SEND; }
            else finish_job();
        }
    } else if (v.job == JOB_SEND) send_results();
    if (v.reconfigure && v.job == JOB_IDLE && v.geo_source < 0) {
        if (v.capture && !(engine_poll(ENGINE_VIN).status & EDRV32_VIN_STATUS_IDLE_MASK))
            return 1;
        pair_release();
        v.capture = 0;
        v.reconfigure = 0;
    }
    if (!v.reconfigure && v.job == JOB_IDLE && v.geo_source < 0) {
        if (v.model_pending) {
            model_step();
            return 1;
        }
        if (v.image_pending) {
            int slot = 6 + (int)((v.upload_base - SHOWCASE_IMAGE_BASE) / SHOWCASE_IMAGE_BYTES);
            v.job_image = slot;
            reference(slot, REF_JOB, 0);
            v.job_input = 0;
            v.job_frame = v.next_frame++;
            v.job_batch = 1;
            v.receive_base = v.upload_base;
            v.receive_bytes = v.upload_bytes;
            v.image_pending = 0;
            queue_image(slot);
            struct vin_channel input = {VIN_MEMORY, 2, VISION_STRIDE,
                {VISION_INPUT_BASE, VISION_INPUT_BASE + VISION_INPUT_SPACING}, 0};
            vin_channel_configure(2, &input);
            engine_control(ENGINE_VIN, EDRV32_VIN_CTRL_ENABLE_MASK);
            v.ch2_start = platform_ticks();
            vin_memory_start(v.receive_base, VISION_STRIDE, VISION_WIDTH, VISION_HEIGHT);
            v.job = JOB_CH2;
        } else if (!v.capture && v.page && v.camera_source && !v.data.paused) {
            configure_capture();
        }
    }
    return v.reconfigure || v.model_pending || v.image_pending || v.job != JOB_IDLE ||
           v.geo_source >= 0 || (v.page == PAGE_PROCESS && v.process_dirty);
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
        struct npu_config config = {VISION_MODEL_BASE, VISION_WORK_BASE,
            VISION_INPUT_BASE, VISION_OUTPUT_BASE, VISION_DESC_BASE, 68};
        npu_configure(&config);
    }
}
