/* File: pipeline.c
 * Spec: design 2026-10-29-b2-software 3.4/3.4a; SoC 7.3–7.4.
 * Description: VIN pairing, cross-frame NPU/CPU overlap, GEO and display ownership.
 * Clock domain: clk_sys; callbacks execute with machine interrupts disabled.
 */
#include "runtime.h"

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

static void vin_event(const struct engine_event *event, void *context)
{
    (void)context;
    if (event->error || (event->irq & EDRV32_VIN_IRQ_STAT_ERROR_MASK)) {
        demo_fail("VIN", ENGINE_VIN);
    }
    const unsigned int channels[] = {0, 2};
    const uint32_t masks[] = {EDRV32_VIN_IRQ_STAT_FRAME_MASK,
                              EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK};
    for (unsigned int i = 0; i < demo_vin_channels; ++i) {
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
        if (channels[i] == 0u) {
            demo.surface_epoch[slot] = demo.epoch;
        }
        demo_scene_frame(channels[i], slot, frame.frame_id);
    }
    demo_scene_pair();
    if (event->irq & EDRV32_VIN_IRQ_STAT_FRAME_MASK) {
        ++demo.vin_frames;
        /* PIX 2.6: write the whole shadow group in blanking, after the old frame.
         * The next SOF starts the new epoch; no old Surface can finish the switch.
         */
        if (demo.switch_pending) {
            enum demo_command_kind kind = (enum demo_command_kind)(demo.switch_pending - 1u);
            if (kind == DEMO_PIX) {
                demo.pix_custom = 0;
                demo.pix = demo.switch_value;
                demo_pix_configure();
            } else if (kind == DEMO_GEO) {
                demo.geo_custom = 0;
                demo.geo = demo.switch_value;
            } else {
                demo.output = demo.switch_value;
            }
            ++demo.epoch;
            demo.switch_pending = 0;
        }
    }
}

static void display_event(const struct engine_event *event, void *context)
{
    (void)context;
    if (event->error || (event->irq & EDRV32_DISP_IRQ_STAT_ERROR_MASK)) {
        demo_fail("DISP", ENGINE_DISP);
    }
    demo_overlay_frame(event->irq);
    if (event->irq & EDRV32_DISP_IRQ_STAT_SWITCH_MASK) {
        uint32_t released = disp_released(DISP_L0);
        if (demo.display_current >= 0 &&
            released == demo_surface_address((unsigned int)demo.display_current)) {
            demo_reference((unsigned int)demo.display_current, 0, REF_DISPLAY);
            demo.display_current = -1;
        }
    }
    if (event->irq & EDRV32_DISP_IRQ_STAT_FRAME_MASK) {
        ++demo.display_frames;
        if (demo.display_next >= 0 &&
            disp_current(DISP_L0) == demo_surface_address((unsigned int)demo.display_next)) {
            demo.display_current = demo.display_next;
            demo.display_next = -1;
            demo_switch_complete((unsigned int)demo.display_current);
        }
        if (!demo.transitioning && demo.display_next < 0 && demo.display_queue >= 0) {
            demo.display_next = demo.display_queue;
            demo.display_queue = -1;
            disp_submit(DISP_L0, demo_surface_address((unsigned int)demo.display_next),
                        DEMO_STRIDE);
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
    engine_control(ENGINE_DISP, 0);
    demo_wait_idle(ENGINE_DISP);
    disp_l0_scroll(0, 0);
    disp_layer_enable(DISP_L0, 1);
    demo_overlay_init();
    engine_irq_register(ENGINE_VIN, EDRV32_VIN_IRQ_EN_ERROR_MASK |
                        demo_vin_frame_mask,
                        3, vin_event, NULL);
    demo_scene_init();
    engine_irq_register(ENGINE_GEO, EDRV32_GEO_IRQ_EN_ERROR_MASK |
                        EDRV32_GEO_IRQ_EN_DONE_MASK, 2, geo_event, NULL);
    engine_irq_register(ENGINE_DISP, EDRV32_DISP_IRQ_EN_ERROR_MASK |
                        EDRV32_DISP_IRQ_EN_FRAME_MASK | EDRV32_DISP_IRQ_EN_SWITCH_MASK |
                        EDRV32_DISP_IRQ_EN_SWITCH1_MASK,
                        4, display_event, NULL);
    engine_irq_register(ENGINE_PIX, EDRV32_PIX_IRQ_EN_ERROR_MASK,
                        4, error_event, (void *)(uintptr_t)ENGINE_PIX);
    engine_irq_register(ENGINE_MEM_XBAR, EDRV32_MEM_XBAR_IRQ_EN_ERROR_MASK,
                        5, error_event, (void *)(uintptr_t)ENGINE_MEM_XBAR);
    engine_control(ENGINE_GEO, EDRV32_GEO_CTRL_ENABLE_MASK);
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
    demo.gamma_bank = 1;
}

void demo_pix_configure(void)
{
    if (demo.pix_custom) {
        demo.gamma_bank = demo.pix_config.gamma_bank;
        pix_configure(&demo.pix_config);
        return;
    }
    struct pix_config config = {0, PIX_BYPASS, PIX_BYPASS, 1, 256, 0, 128};
    if (demo.scene == 2u) {
        switch (demo.pix) {
        case 1:
            config.flags = EDRV32_PIX_CFG_BC_EN_MASK;
            config.contrast = 320;
            config.brightness = 24;
            break;
        case 2: {
            uint8_t table[256];
            for (unsigned int i = 0; i < 256; ++i) {
                table[i] = (uint8_t)(2u * i - i * i / 255u);
            }
            config.gamma_bank = 1u - demo.gamma_bank;
            pix_gamma_load(config.gamma_bank, table);
            config.flags = EDRV32_PIX_CFG_GAMMA_EN_MASK;
            break;
        }
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
    demo.gamma_bank = config.gamma_bank;
    pix_configure(&config);
}

void demo_pipeline_configure(enum vin_source source)
{
    struct vin_channel image = {source, 4, DEMO_STRIDE, {0}, 0};
    for (unsigned int i = 0; i < 4; ++i) {
        image.base[i] = DEMO_IMAGE_BASE + i * DEMO_IMAGE_SPACING;
    }
    uint32_t lock = demo_irq_lock();
    for (unsigned int i = 0; i < 4; ++i) {
        if (demo.references[i]) {
            image.busy_slots |= 1u << i;
        }
    }
    /* Global VIN disable keeps CH0/CH2 source selection together at the next SOF. */
    engine_control(ENGINE_VIN, 0);
    demo_pix_configure();
    ++demo.epoch;
    demo.transitioning = 0;
    vin_channel_configure(0, &image);
    demo_scene_configure(source);
    engine_control(ENGINE_VIN, EDRV32_VIN_CTRL_ENABLE_MASK);
    demo_irq_unlock(lock);
}

void demo_pipeline_pause(void)
{
    uint32_t lock = demo_irq_lock();
    demo.transitioning = 1;
    vin_channel_enable(0, 0);
    vin_channel_enable(2, 0);
    engine_control(ENGINE_VIN, 0);
    demo_irq_unlock(lock);
    demo_wait_idle(ENGINE_VIN);
    while (demo.active_npu >= 0 || demo.active_geo >= 0) {
        __asm__ volatile ("nop");
    }
    demo_network_wait();
    lock = demo_irq_lock();
    demo_scene_stop();
    demo_overlay_hide();
    if (demo.ready_surface >= 0) {
        demo_reference((unsigned int)demo.ready_surface, 0, REF_READY);
        demo.ready_surface = -1;
    }
    if (demo.display_queue >= 0) {
        demo_reference((unsigned int)demo.display_queue, 0, REF_DISPLAY);
        demo.display_queue = -1;
    }
    /* Current and shadow-next retain REF_DISPLAY until SWITCH, per SoC 7.3 R3. */
    demo_irq_unlock(lock);
}

void demo_pipeline_stop(void)
{
    demo_pipeline_pause();
    engine_control(ENGINE_DISP, 0);
    demo_wait_idle(ENGINE_DISP);
    uint32_t lock = demo_irq_lock();
    demo_overlay_stop();
    for (unsigned int i = 0; i < 6; ++i) {
        demo.references[i] = 0;
    }
    vin_slots_busy(0, 0);
    demo.ready_surface = -1;
    demo.display_current = -1;
    demo.display_next = -1;
    demo.display_queue = -1;
    demo.display_enabled = 0;
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
    if (demo.geo_custom) {
        for (unsigned int i = 0; i < 6; ++i) {
            config.matrix[i] = demo.geo_matrix[i];
        }
    } else if (demo.geo == 1u) {
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
    demo.surface_epoch[target] = demo.surface_epoch[source];
    demo.geo_source = source;
    demo.active_geo = target;
    geo_submit(DEMO_GEO_DESCRIPTOR, 1);
    demo_irq_unlock(lock);
}

void demo_pipeline_service(void)
{
    demo_scene_service();
    uint32_t lock = demo_irq_lock();
    int ready = demo.ready_surface;
    demo.ready_surface = -1;
    if (ready >= 0) {
        if (demo.surface_epoch[ready] != demo.epoch) {
            demo_reference((unsigned int)ready, 0, REF_READY);
        } else if (demo.scene == 2u && demo.geo && ready < 4) {
            start_geo((unsigned int)ready);
        } else {
            demo_present((unsigned int)ready, demo.surface_frame[ready], 0, -1);
            demo_reference((unsigned int)ready, 0, REF_READY);
        }
    }
    demo_irq_unlock(lock);
}
