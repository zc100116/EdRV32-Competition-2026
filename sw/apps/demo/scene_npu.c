/* File: scene_npu.c
 * Spec: design 2026-10-29-b2-software 3.4/3.4a; SoC 7.3–7.4.
 * Description: S1 VIN pairing, NPU initialization and cross-frame CPU post-processing.
 * Clock domain: clk_sys; callbacks execute with machine interrupts disabled.
 */
#include "runtime.h"
#include "cache.h"

static yolo_detection detections[YOLO_MAX_DETECTIONS];

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

void demo_scene_frame(unsigned int channel, unsigned int slot, uint32_t frame_id)
{
    if (channel == 0u && demo.scene == 2u) {
        if (demo.ready_surface >= 0) {
            demo_reference((unsigned int)demo.ready_surface, 0, REF_READY);
        }
        demo_reference(slot, REF_READY, 0);
        demo.surface_frame[slot] = frame_id;
        demo.ready_surface = (int)slot;
    } else if (channel == 0u) {
        if (demo.pair_image >= 0) {
            demo_reference((unsigned int)demo.pair_image, 0, REF_PAIR);
        }
        demo.pair_image = (int)slot;
        demo.pair_image_id = frame_id;
        demo_reference(slot, REF_PAIR, 0);
    } else {
        if (demo.pair_input >= 0) {
            input_release((unsigned int)demo.pair_input);
        }
        demo.pair_input = (int)slot;
        demo.pair_input_id = frame_id;
        demo.input_busy |= 1u << slot;
        vin_slots_busy(2, demo.input_busy);
    }
}

void demo_scene_pair(void)
{
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

const unsigned int demo_vin_channels = 2;
const uint32_t demo_vin_frame_mask = EDRV32_VIN_IRQ_EN_FRAME_MASK |
    EDRV32_VIN_IRQ_EN_CH2_FRAME_MASK;

int demo_scene_allowed(unsigned int scene)
{
    (void)scene;
    return 1;
}

void demo_scene_ids(void)
{
    info_hex("NPU ID", mmio_read32(EDRV32_NPU_BASE + EDRV32_NPU_ID_OFFSET));
}

void demo_scene_status(void)
{
    info_number("NPU inferences", demo.inference_count);
    info_number("NPU cycles", demo.inference_cycles);
    info_number("Post cycles", demo.post_cycles);
    info_number("Detection count", demo.detection_count);
}

void demo_scene_init(void)
{
    engine_irq_register(ENGINE_NPU, EDRV32_NPU_IRQ_EN_ERROR_MASK |
                        EDRV32_NPU_IRQ_EN_DONE_MASK, 3, npu_event, NULL);
    engine_control(ENGINE_NPU, EDRV32_NPU_CTRL_ENABLE_MASK);
}

void demo_model_init(void)
{
    struct npu_config npu = {DEMO_MODEL_BASE, DEMO_WORK_BASE, DEMO_INPUT_BASE,
                            DEMO_OUTPUT_BASE, DEMO_DESC_BASE, 68};
    npu_configure(&npu);
}

void demo_scene_configure(enum vin_source source)
{
    struct vin_channel input = {source, 3, 2560, {0}, 0};
    for (unsigned int i = 0; i < 3; ++i) {
        input.base[i] = DEMO_INPUT_BASE + i * DEMO_INPUT_SPACING;
    }
    if (demo.scene == 1u) {
        vin_channel_configure(2, &input);
    }
}

void demo_scene_stop(void)
{
    pair_release();
    demo.input_busy = 0;
    vin_slots_busy(2, 0);
    demo.inference[0].state = BUFFER_FREE;
    demo.inference[1].state = BUFFER_FREE;
    demo.checking = 0;
}

void demo_scene_service(void)
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
        if (demo.output != DEMO_ETHERNET) {
            demo_overlay_draw(detections, count);
        }
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
}
