/* File: pipeline.c
 * Spec: design 2026-10-29-b2-software 3.4/3.4a; SoC 7.3–7.4.
 * Description: VIN pairing, cross-frame NPU/CPU overlap, GEO and display ownership.
 * Clock domain: clk_sys; callbacks execute with machine interrupts disabled.
 */
#include "runtime.h"
#include "cache.h"

static yolo_detection detections[YOLO_MAX_DETECTIONS];

uint32_t demo_surface_address(unsigned int slot)
{
    return slot < 4u ? DEMO_IMAGE_BASE + slot * DEMO_IMAGE_SPACING :
           DEMO_GEO_BASE + (slot - 4u) * DEMO_IMAGE_SPACING;
}

/* All callers either execute in an IRQ or hold demo_irq_lock(). */
void demo_reference(unsigned int slot, unsigned int add, unsigned int remove)
{
    demo.references[slot] = (demo.references[slot] & ~remove) | add;
    uint32_t bitmap = 0;
    for (unsigned int i = 0; i < 4u; ++i) {
        if (demo.references[i]) {
            bitmap |= 1u << i;
        }
    }
    vin_slots_busy(0, bitmap);
}

static void input_release(unsigned int slot)
{
    demo.input_busy &= ~(1u << slot);
    vin_slots_busy(2, demo.input_busy);
}

static void pair_release(void)
{
    if (demo.pair_image >= 0) {
        demo_reference((unsigned int)demo.pair_image, 0, REF_PAIR);
        demo.pair_image = -1;
    }
    if (demo.pair_input >= 0) {
        input_release((unsigned int)demo.pair_input);
        demo.pair_input = -1;
    }
}

void demo_try_inference(void)
{
    if (demo.transitioning || demo.active_npu >= 0 ||
        demo.pair_image < 0 || demo.pair_input < 0 ||
        demo.pair_image_id != demo.pair_input_id) {
        return;
    }
    int buffer = -1;
    for (unsigned int i = 0; i < 2; ++i) {
        if (demo.inference[i].state == BUFFER_FREE) {
            buffer = (int)i;
            break;
        }
    }
    /* Both OUTPUT buffers are still consumed: this camera frame is skipped. */
    if (buffer < 0) {
        pair_release();
        return;
    }
    struct demo_inference *job = &demo.inference[buffer];
    job->image_slot = (unsigned int)demo.pair_image;
    job->input_slot = (unsigned int)demo.pair_input;
    job->frame_id = demo.pair_image_id;
    job->checking = demo.checking;
    job->state = BUFFER_RUNNING;
    demo_reference(job->image_slot, REF_NPU, REF_PAIR);
    demo.pair_image = -1;
    demo.pair_input = -1;
    demo.active_npu = buffer;
    npu_start(DEMO_INPUT_BASE + job->input_slot * DEMO_INPUT_SPACING,
              DEMO_OUTPUT_BASE + (unsigned int)buffer * DEMO_OUTPUT_SPACING);
}

static void vin_event(const struct engine_event *event, void *context)
{
    (void)context;
    if (event->error || (event->irq & EDRV32_VIN_IRQ_STAT_ERROR_MASK)) {
        demo_fail("VIN", ENGINE_VIN);
    }
    const unsigned int channels[] = {0, 2};
    const uint32_t masks[] = {EDRV32_VIN_IRQ_STAT_FRAME_MASK,
                              EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK};
    for (unsigned int i = 0; i < 2; ++i) {
        if (!(event->irq & masks[i])) {
            continue;
        }
        struct vin_frame frame = vin_frame_done(channels[i]);
        if (frame.info & (EDRV32_VIN_CH_DONE_INFO_INCOMPLETE_MASK |
                          EDRV32_VIN_CH_DONE_INFO_BUS_ERR_MASK)) {
            info_hex("VIN DONE_INFO", frame.info);
            info_number("VIN frame_id", frame.frame_id);
            demo_fail("VIN frame", ENGINE_VIN);
        }
        if (demo.transitioning) {
            continue;
        }
        unsigned int slot = vin_frame_slot(frame.info);
        if (i == 0u && demo.scene == 2u) {
            if (demo.ready_surface >= 0) {
                demo_reference((unsigned int)demo.ready_surface, 0, REF_READY);
            }
            demo_reference(slot, REF_READY, 0);
            demo.surface_frame[slot] = frame.frame_id;
            demo.ready_surface = (int)slot;
        } else if (i == 0u) {
            if (demo.pair_image >= 0) {
                demo_reference((unsigned int)demo.pair_image, 0, REF_PAIR);
            }
            demo.pair_image = (int)slot;
            demo.pair_image_id = frame.frame_id;
            demo_reference(slot, REF_PAIR, 0);
        } else {
            if (demo.pair_input >= 0) {
                input_release((unsigned int)demo.pair_input);
            }
            demo.pair_input = (int)slot;
            demo.pair_input_id = frame.frame_id;
            demo.input_busy |= 1u << slot;
            vin_slots_busy(2, demo.input_busy);
        }
    }
    /* Camera frames arriving while NPU is busy are discarded, per design 3.4. */
    if (demo.active_npu >= 0) {
        pair_release();
    } else {
        demo_try_inference();
    }
}

static void npu_event(const struct engine_event *event, void *context)
{
    (void)context;
    if (event->error || (event->irq & EDRV32_NPU_IRQ_STAT_ERROR_MASK)) {
        info_number("NPU CUR_DESC", npu_current_descriptor());
        demo_fail("NPU", ENGINE_NPU);
    }
    if (event->irq & EDRV32_NPU_IRQ_STAT_DONE_MASK) {
        struct demo_inference *job = &demo.inference[demo.active_npu];
        demo_reference(job->image_slot, REF_POST, REF_NPU);
        /* Image-check TX still needs the exact CH2 input, so retains that slot. */
        if (!job->checking) {
            input_release(job->input_slot);
        }
        job->state = BUFFER_READY;
        demo.active_npu = -1;
        ++demo.inference_count;
        demo.inference_cycles = engine_perf(ENGINE_NPU, 0);
        demo_try_inference();
    }
}

static void display_event(const struct engine_event *event, void *context)
{
    (void)context;
    if (event->error || (event->irq & EDRV32_DISP_IRQ_STAT_ERROR_MASK)) {
        demo_fail("DISP", ENGINE_DISP);
    }
    if (event->irq & EDRV32_DISP_IRQ_STAT_SWITCH_MASK) {
        uint32_t released = disp_released();
        if (demo.display_current >= 0 &&
            released == demo_surface_address((unsigned int)demo.display_current)) {
            demo_reference((unsigned int)demo.display_current, 0, REF_DISPLAY);
            demo.display_current = -1;
        }
    }
    if (event->irq & EDRV32_DISP_IRQ_STAT_FRAME_MASK) {
        if (demo.display_next >= 0 &&
            disp_current() == demo_surface_address((unsigned int)demo.display_next)) {
            demo.display_current = demo.display_next;
            demo.display_next = -1;
        }
        if (!demo.transitioning && demo.display_next < 0 && demo.display_queue >= 0) {
            demo.display_next = demo.display_queue;
            demo.display_queue = -1;
            disp_submit(demo_surface_address((unsigned int)demo.display_next), DEMO_STRIDE);
            ++demo.submitted;
        }
    }
}

static void geo_event(const struct engine_event *event, void *context)
{
    (void)context;
    if (event->error || (event->irq & EDRV32_GEO_IRQ_STAT_ERROR_MASK)) {
        demo_fail("GEO", ENGINE_GEO);
    }
    if (event->irq & EDRV32_GEO_IRQ_STAT_DONE_MASK) {
        unsigned int target = (unsigned int)demo.active_geo;
        demo_reference(demo.geo_source, 0, REF_GEO);
        if (demo.ready_surface >= 0) {
            demo_reference((unsigned int)demo.ready_surface, 0, REF_READY);
        }
        demo_reference(target, REF_READY, REF_GEO);
        demo.ready_surface = (int)target;
        demo.active_geo = -1;
    }
}

static void error_event(const struct engine_event *event, void *context)
{
    enum engine_id engine = (enum engine_id)(uintptr_t)context;
    if (event->error || (event->status & EDRV32_PIX_STATUS_ERROR_MASK)) {
        if (engine == ENGINE_MEM_XBAR) {
            uint32_t port;
            uint32_t address;
            uint32_t type;
            mem_xbar_error(&port, &address, &type);
            info_number("MEM error port", port);
            info_hex("MEM error address", address);
            info_hex("MEM error type", type);
        }
        demo_fail("engine error", engine);
    }
}

void demo_pipeline_init(void)
{
    engine_irq_register(ENGINE_VIN, EDRV32_VIN_IRQ_EN_ERROR_MASK |
                        EDRV32_VIN_IRQ_EN_FRAME_MASK | EDRV32_VIN_IRQ_EN_CH2_FRAME_MASK,
                        3, vin_event, NULL);
    engine_irq_register(ENGINE_NPU, EDRV32_NPU_IRQ_EN_ERROR_MASK |
                        EDRV32_NPU_IRQ_EN_DONE_MASK, 3, npu_event, NULL);
    engine_irq_register(ENGINE_GEO, EDRV32_GEO_IRQ_EN_ERROR_MASK |
                        EDRV32_GEO_IRQ_EN_DONE_MASK, 2, geo_event, NULL);
    engine_irq_register(ENGINE_DISP, EDRV32_DISP_IRQ_EN_ERROR_MASK |
                        EDRV32_DISP_IRQ_EN_FRAME_MASK | EDRV32_DISP_IRQ_EN_SWITCH_MASK,
                        4, display_event, NULL);
    engine_irq_register(ENGINE_PIX, EDRV32_PIX_IRQ_EN_ERROR_MASK,
                        4, error_event, (void *)(uintptr_t)ENGINE_PIX);
    engine_irq_register(ENGINE_MEM_XBAR, EDRV32_MEM_XBAR_IRQ_EN_ERROR_MASK,
                        5, error_event, (void *)(uintptr_t)ENGINE_MEM_XBAR);
    engine_control(ENGINE_GEO, EDRV32_GEO_CTRL_ENABLE_MASK);
    engine_control(ENGINE_NPU, EDRV32_NPU_CTRL_ENABLE_MASK);
    engine_control(ENGINE_PIX, EDRV32_PIX_CTRL_ENABLE_MASK);
    engine_control(ENGINE_VIN, EDRV32_VIN_CTRL_ENABLE_MASK);
    vin_camera_size(0, DEMO_WIDTH, DEMO_HEIGHT);
    vin_camera_size(1, DEMO_WIDTH, DEMO_HEIGHT);
    uint8_t gamma[256];
    /* Brightening gamma approximation: 2*x - x*x/255, monotone with fixed endpoints. */
    for (unsigned int i = 0; i < 256u; ++i) {
        gamma[i] = (uint8_t)(2u * i - i * i / 255u);
    }
    pix_gamma_load(1, gamma);
}

void demo_pix_configure(void)
{
    struct pix_config config = {0, PIX_BYPASS, PIX_BYPASS, 1, 256, 0, 128};
    if (demo.scene == 2u) {
        switch (demo.pix) {
        case 1:
            config.flags = EDRV32_PIX_CFG_BC_EN_MASK;
            config.contrast = 320;
            config.brightness = 24;
            break;
        case 2:
            config.flags = EDRV32_PIX_CFG_GAMMA_EN_MASK;
            break;
        case 3:
            config.stage1 = PIX_GAUSSIAN;
            break;
        case 4:
            config.stage1 = PIX_SOBEL;
            config.flags = EDRV32_PIX_CFG_GRAY_EN_MASK;
            break;
        default:
            break;
        }
    }
    pix_configure(&config);
}

void demo_pipeline_configure(enum vin_source source)
{
    struct vin_channel image = {source, 4, DEMO_STRIDE, {0}, 0};
    struct vin_channel input = {source, 3, 2560, {0}, 0};
    for (unsigned int i = 0; i < 4; ++i) {
        image.base[i] = DEMO_IMAGE_BASE + i * DEMO_IMAGE_SPACING;
    }
    for (unsigned int i = 0; i < 3; ++i) {
        input.base[i] = DEMO_INPUT_BASE + i * DEMO_INPUT_SPACING;
    }
    uint32_t lock = demo_irq_lock();
    demo_pix_configure();
    demo.transitioning = 0;
    /* Global VIN disable keeps CH0/CH2 source selection together at the next SOF. */
    engine_control(ENGINE_VIN, 0);
    vin_channel_configure(0, &image);
    if (demo.scene == 1u) {
        vin_channel_configure(2, &input);
    }
    engine_control(ENGINE_VIN, EDRV32_VIN_CTRL_ENABLE_MASK);
    demo_irq_unlock(lock);
}

void demo_pipeline_stop(void)
{
    uint32_t lock = demo_irq_lock();
    demo.transitioning = 1;
    vin_channel_enable(0, 0);
    vin_channel_enable(2, 0);
    demo_irq_unlock(lock);
    demo_wait_idle(ENGINE_VIN);
    while (demo.active_npu >= 0 || demo.active_geo >= 0) {
        __asm__ volatile ("nop");
    }
    demo_network_wait();
    engine_control(ENGINE_DISP, 0);
    demo_wait_idle(ENGINE_DISP);
    lock = demo_irq_lock();
    pair_release();
    for (unsigned int i = 0; i < 6; ++i) {
        demo.references[i] = 0;
    }
    demo.input_busy = 0;
    vin_slots_busy(0, 0);
    vin_slots_busy(2, 0);
    demo.inference[0].state = BUFFER_FREE;
    demo.inference[1].state = BUFFER_FREE;
    demo.ready_surface = -1;
    demo.display_current = -1;
    demo.display_next = -1;
    demo.display_queue = -1;
    demo.display_enabled = 0;
    demo.checking = 0;
    demo_irq_unlock(lock);
}

static void start_geo(unsigned int source)
{
    uint32_t lock = demo_irq_lock();
    int target = -1;
    if (demo.active_geo < 0) {
        for (unsigned int i = 4; i < 6; ++i) {
            if (demo.references[i] == 0u) {
                target = (int)i;
                break;
            }
        }
    }
    if (target < 0) {
        demo_reference(source, 0, REF_READY);
        demo_irq_unlock(lock);
        return;
    }
    struct geo_config config = {0};
    config.src_base = demo_surface_address(source);
    config.src_stride = DEMO_STRIDE;
    config.src_width = DEMO_WIDTH;
    config.src_height = DEMO_HEIGHT;
    config.dst_base = demo_surface_address((unsigned int)target);
    config.dst_stride = DEMO_STRIDE;
    config.rect_width = DEMO_WIDTH;
    config.rect_height = DEMO_HEIGHT;
    if (demo.geo == 1u) {
        /* Inverse 180-degree rotation keeps the 1280x720 output extent. */
        config.matrix[0] = geo_q16(-1, 1);
        config.matrix[2] = geo_q16(DEMO_WIDTH - 1u, 1);
        config.matrix[4] = geo_q16(-1, 1);
        config.matrix[5] = geo_q16(DEMO_HEIGHT - 1u, 1);
    } else {
        /* Inverse 2x zoom, centered on the source. */
        config.matrix[0] = geo_q16(1, 2);
        config.matrix[2] = geo_q16(DEMO_WIDTH, 4);
        config.matrix[4] = geo_q16(1, 2);
        config.matrix[5] = geo_q16(DEMO_HEIGHT, 4);
    }
    geo_descriptor_pack(demo_uncached(DEMO_GEO_DESCRIPTOR), &config);
    demo_reference(source, REF_GEO, REF_READY);
    demo_reference((unsigned int)target, REF_GEO, 0);
    demo.surface_frame[target] = demo.surface_frame[source];
    demo.geo_source = source;
    demo.active_geo = target;
    geo_submit(DEMO_GEO_DESCRIPTOR, 1);
    demo_irq_unlock(lock);
}

void demo_pipeline_service(void)
{
    for (unsigned int processed = 0; processed < 2; ++processed) {
        uint32_t lock = demo_irq_lock();
        int oldest = -1;
        for (unsigned int i = 0; i < 2; ++i) {
            if (demo.inference[i].state == BUFFER_READY &&
                (oldest < 0 || (int32_t)(demo.inference[i].frame_id -
                                        demo.inference[oldest].frame_id) < 0)) {
                oldest = (int)i;
            }
        }
        if (oldest < 0) {
            demo_irq_unlock(lock);
            break;
        }
        unsigned int buffer = (unsigned int)oldest;
        struct demo_inference *job = &demo.inference[buffer];
        job->state = BUFFER_PROCESSING;
        demo_try_inference();
        demo_irq_unlock(lock);
        uint32_t output = DEMO_OUTPUT_BASE + buffer * DEMO_OUTPUT_SPACING;
        engine_dma_invalidate(demo_cached(output), DEMO_OUTPUT_BYTES);
        uint64_t start = clint_time();
        yolo_post_stats stats;
        unsigned int count = yolo_post_process((const int8_t *)demo_cached(output),
            yolo_default_heads, (yolo_candidate *)demo_cached(DEMO_WORKSPACE),
            detections, &stats);
        demo.post_cycles = (uint32_t)(clint_time() - start);
        demo.detection_count = count;
        uint32_t image = demo_surface_address(job->image_slot);
        engine_dma_invalidate(demo_cached(image), DEMO_IMAGE_BYTES);
        draw_surface surface = {(uint16_t *)demo_cached(image), DEMO_STRIDE,
                                 DEMO_WIDTH, DEMO_HEIGHT};
        for (unsigned int i = 0; i < count; ++i) {
            draw_detection(&surface, &detections[i], 0x07e0, 0xffff);
        }
        engine_dma_clean(demo_cached(image), DEMO_IMAGE_BYTES);
        /* The previous TX owns the EDDT/header storage until DONE_COUNT advances. */
        unsigned int due = demo.output != DEMO_HDMI &&
            demo_frame_due(job->frame_id, demo_frame_divisor(DEMO_CAMERA_FPS, demo.fps));
        if (due && demo.tx_active) {
            ++demo.video_skips;
            due = 0;
        }
        demo_network_wait();
        unsigned int bytes = (unsigned int)demo_detection_pack(
            demo_uncached(DEMO_TX_DETECTIONS), detections, count, job->frame_id);
        /* check_buffer=-2 means a due frame already skipped while its EDDT waited. */
        demo_present(job->image_slot, job->frame_id, bytes,
                     job->checking ? (int)buffer : (due ? -1 : -2));
        lock = demo_irq_lock();
        demo_reference(job->image_slot, 0, REF_POST);
        if (!job->checking || demo.tx_check_buffer != (int)buffer) {
            if (job->checking) {
                input_release(job->input_slot);
                demo.checking = 0;
            }
            job->state = BUFFER_FREE;
        }
        demo_try_inference();
        demo_irq_unlock(lock);
    }
    uint32_t lock = demo_irq_lock();
    int ready = demo.ready_surface;
    demo.ready_surface = -1;
    demo_irq_unlock(lock);
    if (ready >= 0) {
        if (demo.geo && ready < 4) {
            start_geo((unsigned int)ready);
        } else {
            demo_present((unsigned int)ready, demo.surface_frame[ready], 0, -1);
            lock = demo_irq_lock();
            demo_reference((unsigned int)ready, 0, REF_READY);
            demo_irq_unlock(lock);
        }
    }
}
