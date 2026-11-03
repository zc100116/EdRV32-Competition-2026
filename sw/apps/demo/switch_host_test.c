/* File: switch_host_test.c
 * Spec: Task B3-12; PIX 2.6; VIN 5.2; DISP 5.3; SoC 7.3 R1–R4.
 * Description: Run production pipeline/scene/overlay code against ordered engine events.
 * Clock domain: none (host); only MMIO, IRQ locking and engine completion are modeled.
 */
#define _GNU_SOURCE
#include "runtime.h"
#include "overlay.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

struct demo_state demo;
const yolo_head yolo_default_heads[3] = {0};
const uint32_t demo_network_rx_mask = 0;

static engine_irq_callback callbacks[8];
static void *contexts[8];
static struct { uintptr_t address; uint32_t value; } cells[2048];
static unsigned int cell_count;
static unsigned int irq_depth;
static int callback_engine = -1;
static uint32_t callback_irq;
static uint32_t controls[8];
static unsigned int sample_during_flush;
static unsigned int flush_samples;
static unsigned int complete_tx;
static uint32_t scanning[2];
static unsigned int disp_stops;
static unsigned int vin_stops;
static unsigned int vin_disables;
static unsigned int pix_groups;
static unsigned int pix_words;
static unsigned int enforce_blanking;
static uint32_t pix_offsets[3];
static uint64_t now;
static uint32_t frame_id;
static unsigned int overlay_renders;
static char serial[256];
static unsigned int serial_length;

uint32_t mmio_read32(uintptr_t address)
{
    for (unsigned int i = 0; i < cell_count; ++i) {
        if (cells[i].address == address) {
            return cells[i].value;
        }
    }
    return 0;
}

void mmio_write32(uintptr_t address, uint32_t value)
{
    if (address == EDRV32_PIX_BASE + EDRV32_PIX_BC_OFFSET ||
        address == EDRV32_PIX_BASE + EDRV32_PIX_THRESH_OFFSET ||
        address == EDRV32_PIX_BASE + EDRV32_PIX_CFG_OFFSET) {
        if (enforce_blanking) {
            assert(callback_engine == ENGINE_VIN);
            assert(callback_irq & EDRV32_VIN_IRQ_STAT_FRAME_MASK);
        }
        const uint32_t order[] = {EDRV32_PIX_BC_OFFSET, EDRV32_PIX_THRESH_OFFSET,
                                  EDRV32_PIX_CFG_OFFSET};
        assert(address == EDRV32_PIX_BASE + order[pix_words % 3u]);
        pix_offsets[pix_words++ % 3u] = value;
        pix_groups += pix_words % 3u == 0u;
    }
    if (address == EDRV32_VIN_BASE + EDRV32_VIN_CH_CTRL_OFFSET(0) &&
        !(value & EDRV32_VIN_CH_CTRL_EN_MASK)) {
        ++vin_disables;
    }
    if (address == EDRV32_VIN_BASE + EDRV32_VIN_CH_SLOT_BUSY_OFFSET(0) &&
        controls[ENGINE_DISP]) {
        /* Every write to producer ownership must retain both scanning and shadow slots. */
        for (unsigned int i = 0; i < 4; ++i) {
            uint32_t base = demo_surface_address(i);
            if (base == scanning[0] ||
                base == mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_NEXT_BASE_OFFSET)) {
                if (!(value & (1u << i))) {
                    fprintf(stderr, "slot=%u busy=%x scene=%u frame=%u callback=%d "
                            "current=%d next=%d queue=%d epoch=%u\n", i, value,
                            demo.scene, frame_id, callback_engine, demo.display_current,
                            demo.display_next, demo.display_queue, demo.epoch);
                }
                assert(value & (1u << i));
            }
        }
    }
    for (unsigned int i = 0; i < cell_count; ++i) {
        if (cells[i].address == address) {
            cells[i].value = value;
            return;
        }
    }
    assert(cell_count < sizeof cells / sizeof cells[0]);
    cells[cell_count].address = address;
    cells[cell_count++].value = value;
}

uint32_t demo_irq_lock(void)
{
    return irq_depth++;
}

void demo_irq_unlock(uint32_t old)
{
    assert(irq_depth == old + 1u);
    irq_depth = old;
    if (!irq_depth && sample_during_flush) {
        /* A pending timer IRQ may run as soon as the main loop restores interrupts. */
        assert(++flush_samples <= 64u);
        demo_monitor_tick();
    }
}

uint64_t clint_time(void)
{
    return now;
}

void engine_control(enum engine_id engine, uint32_t control)
{
    disp_stops += engine == ENGINE_DISP && !control;
    vin_stops += engine == ENGINE_VIN && !control;
    controls[engine] = control;
}

struct engine_event engine_poll(enum engine_id engine)
{
    uint32_t done = 0;
    if (engine == ENGINE_ETH && demo.tx_active && complete_tx) {
        done = demo.tx_done + demo.tx_count;
    }
    return (struct engine_event){0, EDRV32_VIN_STATUS_IDLE_MASK, 0, done};
}

uint32_t engine_perf(enum engine_id engine, unsigned int counter)
{
    (void)engine;
    (void)counter;
    return 0;
}

void engine_irq_register(enum engine_id engine, uint32_t mask, unsigned int priority,
                         engine_irq_callback callback, void *context)
{
    (void)mask;
    (void)priority;
    callbacks[engine] = callback;
    contexts[engine] = context;
}

static void event(enum engine_id engine, uint32_t irq)
{
    assert(irq_depth == 0);
    callback_engine = (int)engine;
    callback_irq = irq;
    struct engine_event e = {irq, EDRV32_VIN_STATUS_IDLE_MASK, 0, 0};
    callbacks[engine](&e, contexts[engine]);
    assert(pix_words % 3u == 0u);
    callback_engine = -1;
}

void demo_wait_idle(enum engine_id engine)
{
    assert(!controls[engine] || engine == ENGINE_VIN);
    if (engine == ENGINE_DISP) {
        scanning[0] = 0;
        scanning[1] = 0;
    }
    if (engine == ENGINE_VIN) {
        if (demo.active_npu >= 0) {
            event(ENGINE_NPU, EDRV32_NPU_IRQ_STAT_DONE_MASK);
        }
        if (demo.active_geo >= 0) {
            event(ENGINE_GEO, EDRV32_GEO_IRQ_STAT_DONE_MASK);
        }
    }
}

_Noreturn void demo_fail(const char *reason, enum engine_id engine)
{
    fprintf(stderr, "FAIL demo switch: %s engine=%u\n", reason, (unsigned int)engine);
    abort();
}

void info_hex(const char *key, uint32_t value)
{
    (void)key;
    (void)value;
}

void info_number(const char *key, uint64_t value)
{
    (void)key;
    (void)value;
}

void clint_set_compare(uint64_t deadline)
{
    (void)deadline;
}

void mem_xbar_snapshot(struct mem_xbar_stats *stats)
{
    memset(stats, 0, sizeof *stats);
}

void demo_monitor_media(struct eth_monitor *record)
{
    memset(record->vin, 0, sizeof record->vin);
    memset(record->disp, 0, sizeof record->disp);
}

void info_text(const char *key, const char *value)
{
    (void)key;
    (void)value;
}

const uint8_t *demo_network_model_header(void)
{
    assert(0);
    return NULL;
}

void demo_network_model_load(const uint8_t *header)
{
    (void)header;
    assert(0);
}

void mem_xbar_error(uint32_t *port, uint32_t *address, uint32_t *type)
{
    *port = 0;
    *address = 0;
    *type = 0;
}

void engine_dma_invalidate(uintptr_t address, uint32_t bytes)
{
    (void)address;
    (void)bytes;
}

uint32_t yolo_post_process(const int8_t *output, const yolo_head heads[3],
                           yolo_candidate workspace[YOLO_ANCHORS],
                           yolo_detection detections[YOLO_MAX_DETECTIONS],
                           yolo_post_stats *stats)
{
    (void)output;
    (void)heads;
    (void)workspace;
    (void)detections;
    (void)stats;
    return 0;
}

void demo_overlay_backend_init(void)
{
}

void demo_overlay_render(unsigned int buffer, const yolo_detection *detections,
                         unsigned int count)
{
    (void)detections;
    (void)count;
    assert(scanning[1] != demo_overlay_address(buffer));
    ++overlay_renders;
}

void uart_putc(uint8_t value)
{
    assert(serial_length + 1u < sizeof serial);
    serial[serial_length++] = (char)value;
    serial[serial_length] = 0;
}

void uart_puts(const char *text)
{
    while (*text) {
        uart_putc((uint8_t)*text++);
    }
}

static unsigned int camera_frame(void)
{
    unsigned int slot = 0;
    while (slot < 4u && demo.references[slot]) {
        ++slot;
    }
    assert(slot < 4u);
    now += 100;
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_INFO_OFFSET(0), slot);
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_FRAME_ID_OFFSET(0), ++frame_id);
    event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_FRAME_MASK);
    return slot;
}

static void display_frame(void)
{
    now += 50;
    assert(controls[ENGINE_DISP]);
    uint32_t irq = EDRV32_DISP_IRQ_STAT_FRAME_MASK;
    uint32_t layers = mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_LAYER_CTRL_OFFSET);
    assert(layers & 1u);
    const uint32_t next[] = {EDRV32_DISP_NEXT_BASE_OFFSET, EDRV32_DISP_L1_NEXT_BASE_OFFSET};
    const uint32_t current[] = {EDRV32_DISP_CUR_BASE_OFFSET, EDRV32_DISP_L1_CUR_BASE_OFFSET};
    const uint32_t release[] = {EDRV32_DISP_REL_BASE_OFFSET, EDRV32_DISP_L1_REL_BASE_OFFSET};
    const uint32_t switches[] = {EDRV32_DISP_IRQ_STAT_SWITCH_MASK,
                                 EDRV32_DISP_IRQ_STAT_SWITCH1_MASK};
    for (unsigned int layer = 0; layer < 2; ++layer) {
        uint32_t old = scanning[layer];
        uint32_t base = mmio_read32(EDRV32_DISP_BASE + next[layer]);
        if (old && (!(layers & (1u << layer)) || old != base)) {
            mmio_write32(EDRV32_DISP_BASE + release[layer], old);
            irq |= switches[layer];
        }
        if (layers & (1u << layer)) {
            assert(base);
            scanning[layer] = base;
            mmio_write32(EDRV32_DISP_BASE + current[layer], base);
        } else {
            scanning[layer] = 0;
        }
    }
    event(ENGINE_DISP, irq);
}

static void publish_camera(void)
{
    camera_frame();
    demo_pipeline_service();
    display_frame();
    display_frame();
}

static void test_pix_switches(void)
{
    enforce_blanking = 1;
    for (unsigned int mode = 0; mode < 5; ++mode) {
        unsigned int groups = pix_groups;
        unsigned int old = demo.pix;
        demo_switch_begin((struct demo_command){DEMO_PIX, mode});
        assert(demo.pix == old && pix_groups == groups);
        unsigned int before = camera_frame();
        assert(demo.surface_epoch[before] != demo.switch_epoch);
        assert(pix_groups == groups + 1u && demo.pix == mode);
        demo_pipeline_service();
        assert(!demo.switch_done);
        if (mode == 1u) {
            assert((pix_offsets[0] & EDRV32_PIX_BC_CONTRAST_MASK) == 320u);
            assert(pix_offsets[0] >> EDRV32_PIX_BC_BRIGHTNESS_POS == 24u);
        }
        if (mode == 4u) {
            assert(pix_offsets[2] & EDRV32_PIX_CFG_GRAY_EN_MASK);
        }
        uint64_t start = demo.switch_start;
        unsigned int frames = demo.display_frames;
        publish_camera();
        assert(demo.switch_done && !demo.switch_waiting);
        assert(demo.switch_frames == demo.display_frames - frames);
        assert(demo.switch_ticks == now - start);
        assert(disp_stops == 0 && vin_stops == 0 && vin_disables == 0);
    }
    enforce_blanking = 0;
}

static void test_geo_switches(void)
{
    for (unsigned int mode = 1; mode <= 3; ++mode) {
        unsigned int old_current = (unsigned int)demo.display_current;
        demo_reference(old_current, REF_ETH, 0);
        demo_switch_begin((struct demo_command){DEMO_GEO, mode % 3u});
        camera_frame();
        demo_pipeline_service();
        display_frame();
        assert(demo.references[old_current] & REF_DISPLAY);
        unsigned int source = camera_frame();
        demo_pipeline_service();
        if (demo.geo) {
            assert(demo.active_geo >= 4);
            assert(demo.references[source] & REF_GEO);
            assert(!demo.switch_done);
            display_frame();
            assert(demo.references[old_current] & REF_DISPLAY);
            event(ENGINE_GEO, EDRV32_GEO_IRQ_STAT_DONE_MASK);
            assert(!(demo.references[source] & REF_GEO));
            demo_pipeline_service();
        }
        assert(!demo.switch_done);
        display_frame();
        assert(demo.references[old_current] & REF_DISPLAY);
        display_frame();
        assert(demo.switch_done);
        assert(!(demo.references[old_current] & REF_DISPLAY));
        assert(demo.references[old_current] & REF_ETH);
        demo_reference(old_current, 0, REF_ETH);
        assert(disp_stops == 0 && vin_stops == 0 && vin_disables == 0);
    }
}

static void test_inflight_geo(void)
{
    demo_switch_begin((struct demo_command){DEMO_GEO, 1});
    camera_frame();
    demo_pipeline_service();
    camera_frame();
    demo_pipeline_service();
    event(ENGINE_GEO, EDRV32_GEO_IRQ_STAT_DONE_MASK);
    demo_pipeline_service();
    display_frame();
    display_frame();
    assert(demo.switch_done);
    camera_frame();
    demo_pipeline_service();
    int old_target = demo.active_geo;
    assert(old_target >= 4);
    uint32_t old_epoch = demo.surface_epoch[old_target];
    /* A PIX request can arrive while a full-frame GEO job still owns its input. */
    demo_switch_begin((struct demo_command){DEMO_PIX, 3});
    camera_frame();
    demo_pipeline_service();
    assert(demo.epoch != old_epoch);
    camera_frame();
    event(ENGINE_GEO, EDRV32_GEO_IRQ_STAT_DONE_MASK);
    demo_pipeline_service();
    assert(!demo.switch_done && demo.ready_surface < 0);
    assert(demo.references[old_target] == 0);
    display_frame();
    camera_frame();
    demo_pipeline_service();
    assert(demo.active_geo >= 4);
    event(ENGINE_GEO, EDRV32_GEO_IRQ_STAT_DONE_MASK);
    demo_pipeline_service();
    display_frame();
    display_frame();
    assert(demo.switch_done && disp_stops == 0 && vin_stops == 0);
    demo_switch_begin((struct demo_command){DEMO_GEO, 0});
    camera_frame();
    demo_pipeline_service();
    publish_camera();
    assert(demo.switch_done);
}

static void test_scene_switches(void)
{
    demo_switch_begin((struct demo_command){DEMO_SCENE, 1});
    assert(demo.scene == 1u && disp_stops == 0 && demo.display_enabled);
    display_frame();
    display_frame();
    unsigned int slot = camera_frame();
    /* Matching CH2 completes the S1 pair; actual NPU callback transfers it to CPU. */
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_INFO_OFFSET(2), 0);
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_FRAME_ID_OFFSET(2), frame_id);
    event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK);
    assert(demo.active_npu >= 0);
    event(ENGINE_NPU, EDRV32_NPU_IRQ_STAT_DONE_MASK);
    demo_pipeline_service();
    assert(overlay_renders == 1);
    display_frame();
    display_frame();
    assert(demo.switch_done && demo.display_current == (int)slot);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_LAYER_CTRL_OFFSET) == 3u);
    /* Put a second L0/L1 pair in shadow, then switch before its FRAME callback. */
    camera_frame();
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_INFO_OFFSET(2), 1);
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_FRAME_ID_OFFSET(2), frame_id);
    event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK);
    event(ENGINE_NPU, EDRV32_NPU_IRQ_STAT_DONE_MASK);
    demo_pipeline_service();
    display_frame();
    int shadow = demo.display_next;
    assert(shadow >= 0 && overlay_renders == 2);
    /* Leave another inference running when returning to S2: pause must drain it. */
    unsigned int pending = camera_frame();
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_INFO_OFFSET(2), 1);
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_FRAME_ID_OFFSET(2), frame_id);
    event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK);
    assert(demo.active_npu >= 0);
    demo_switch_begin((struct demo_command){DEMO_SCENE, 2});
    assert(!(demo.references[pending] & (REF_NPU | REF_POST | REF_PAIR)));
    assert(demo.references[slot] & REF_DISPLAY);
    assert(demo.references[shadow] & REF_DISPLAY);
    assert(disp_stops == 0 && demo.display_enabled);
    display_frame();
    assert(demo.display_current == shadow && (demo.references[shadow] & REF_DISPLAY));
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_LAYER_CTRL_OFFSET) == 1u);
    display_frame();
    publish_camera();
    assert(demo.switch_done && overlay_renders == 2);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_LAYER_CTRL_OFFSET) == 1u);
    demo_switch_begin((struct demo_command){DEMO_SCENE, 1});
    display_frame();
    display_frame();
    camera_frame();
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_INFO_OFFSET(2), 0);
    mmio_write32(EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_FRAME_ID_OFFSET(2), frame_id);
    event(ENGINE_VIN, EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK);
    event(ENGINE_NPU, EDRV32_NPU_IRQ_STAT_DONE_MASK);
    demo_pipeline_service();
    display_frame();
    display_frame();
    assert(demo.switch_done && overlay_renders == 3);
    assert(mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_LAYER_CTRL_OFFSET) == 3u);
    demo_switch_begin((struct demo_command){DEMO_SCENE, 2});
    display_frame();
    display_frame();
    publish_camera();
    assert(demo.switch_done && disp_stops == 0);
}

static void test_outputs(void)
{
    unsigned int stops = vin_stops;
    for (unsigned int mode = 0; mode < 2; ++mode) {
        demo_switch_begin((struct demo_command){DEMO_OUTPUT, mode ? DEMO_HDMI : DEMO_BOTH});
        camera_frame();
        demo_pipeline_service();
        publish_camera();
        assert(demo.switch_done && disp_stops == 0 && vin_stops == stops);
    }
    demo_switch_begin((struct demo_command){DEMO_OUTPUT, DEMO_ETHERNET});
    assert(disp_stops == 1 && !demo.display_enabled);
    camera_frame();
    demo_pipeline_service();
    assert(demo.switch_done);
    serial_length = 0;
    demo_switch_report();
    assert(strstr(serial, "frames=1 ") && strstr(serial, "HDMI off (Surface ready)"));
    demo_switch_begin((struct demo_command){DEMO_PIX, 2});
    camera_frame();
    demo_pipeline_service();
    assert(!demo.switch_done);
    camera_frame();
    demo_pipeline_service();
    assert(demo.switch_done);
    demo_switch_begin((struct demo_command){DEMO_OUTPUT, DEMO_HDMI});
    camera_frame();
    demo_pipeline_service();
    display_frame();
    assert(demo.switch_done);
    serial_length = 0;
    demo_switch_report();
    assert(strstr(serial, "HDMI FRAME") && !strstr(serial, "HDMI off"));
}

static void test_latency_wrap(void)
{
    demo.display_frames = UINT32_MAX - 1u;
    now = UINT64_MAX - 200u;
    demo_switch_begin((struct demo_command){DEMO_PIX, 4});
    camera_frame();
    demo_pipeline_service();
    publish_camera();
    assert(demo.switch_done && demo.switch_frames == 2u && demo.switch_ticks == 300u);
    serial_length = 0;
    demo_switch_report();
    assert(strcmp(serial, "Switch: frames=2 mtime_ticks=300 HDMI FRAME\r\n") == 0);
}

static void demo_test_batch(void)
{
    demo_pipeline_stop();
    demo.clock_hz = 100000000;
    demo.sample_hz = 100;
    demo.monitor_produced = demo.monitor_consumed = 0;
    complete_tx = 1;
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_PORT_OFFSET, 6000);
    /* A timer IRQ at each unlock keeps the old produced==consumed target moving. */
    sample_during_flush = 1;
    demo_monitor_flush();
    assert(flush_samples > 0 && flush_samples <= 64u);
    assert(demo.monitor_consumed == 1);
    assert(demo.monitor_produced > demo.monitor_consumed);
    assert(!demo.monitor_flush && !demo.tx_active);
    sample_during_flush = 0;
    for (unsigned int image = 0; image < 10; ++image) {
        unsigned int window = image % 2;
        mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_WIN_BYTES_OFFSET(window),
                     DEMO_IMAGE_BYTES);
        demo.received = EDRV32_ETH_IRQ_STAT_RX_NOTIFY0_MASK << window;
        demo_network_receive();
        assert(demo.checking && demo.image_window == window && !demo.transitioning);
        assert(mmio_read32(EDRV32_VIN_BASE + EDRV32_VIN_MSRC_BASE_OFFSET) ==
               DEMO_WINDOW_BASE + window * DEMO_WINDOW_SIZE);
        demo.inference[0].input_slot = 0;
        demo.inference[0].state = BUFFER_PROCESSING;
        demo.input_busy = 1;
        demo.tx_check_buffer = 0;
        demo_network_check_complete();
        demo.tx_check_buffer = -1;
        assert(!demo.checking && !demo.input_busy);
        assert(eth_window_bytes(window) == 0);
    }
    /* Existing one-byte NUL peer probe must leave the memory pipeline untouched. */
    uint32_t epoch = demo.epoch;
    *(uint8_t *)demo_uncached(DEMO_COMMAND_WINDOW) = 0;
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_WIN_BYTES_OFFSET(3), 1);
    demo.received = EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK;
    demo_network_receive();
    assert(demo.epoch == epoch && eth_window_bytes(3) == 0);
    memcpy(demo_uncached(DEMO_COMMAND_WINDOW), "camera", 6);
    mmio_write32(EDRV32_ETH_BASE + EDRV32_ETH_WIN_BYTES_OFFSET(3), 6);
    demo.received = EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK;
    demo_network_receive();
    assert(demo.scene == 1 && !demo.checking && !demo.transitioning);
    assert(eth_window_bytes(3) == 0);
    uint32_t ctrl = mmio_read32(EDRV32_VIN_BASE + EDRV32_VIN_CH_CTRL_OFFSET(0));
    assert(((ctrl & EDRV32_VIN_CH_CTRL_SRC_MASK) >> EDRV32_VIN_CH_CTRL_SRC_POS) == VIN_CAM0);
    ctrl = mmio_read32(EDRV32_VIN_BASE + EDRV32_VIN_CH_CTRL_OFFSET(2));
    assert(((ctrl & EDRV32_VIN_CH_CTRL_SRC_MASK) >> EDRV32_VIN_CH_CTRL_SRC_POS) == VIN_CAM0);
    puts("PASS demo VN batch: finite monitor flush, alternating windows, WIN3 camera/peer");
}

void demo_test_switching(void)
{
    void *send = demo_uncached(DEMO_SEND_BASE);
    assert(mmap(send, DEMO_SEND_SIZE, PROT_READ | PROT_WRITE,
                MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) == send);
    void *command = demo_uncached(DEMO_COMMAND_WINDOW);
    assert(mmap(command, DEMO_COMMAND_WINDOW_SIZE, PROT_READ | PROT_WRITE,
                MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) == command);
    demo.clock_hz = 100000000;
    demo.sample_hz = 100;
    demo.scene = 2;
    demo.fps = 30;
    demo.pair_image = -1;
    demo.pair_input = -1;
    demo.ready_surface = -1;
    demo.active_npu = -1;
    demo.active_geo = -1;
    demo.display_current = -1;
    demo.display_next = -1;
    demo.display_queue = -1;
    demo.tx_surface = -1;
    demo.tx_check_buffer = -1;
    demo_pipeline_init();
    /* A retained Gamma preset must not rewrite a bank when custom controls apply. */
    demo.pix = 2;
    demo.pix_custom = 1;
    demo.pix_config = (struct pix_config){0, PIX_MEAN, PIX_DILATE, 0, 256, 0, 128};
    mmio_write32(EDRV32_PIX_BASE + EDRV32_PIX_GAMMA_WR_OFFSET, 0x12345678);
    demo_pix_configure();
    assert(mmio_read32(EDRV32_PIX_BASE + EDRV32_PIX_GAMMA_WR_OFFSET) == 0x12345678);
    assert(mmio_read32(EDRV32_PIX_BASE + EDRV32_PIX_CFG_OFFSET) ==
           pix_config_word(&demo.pix_config));
    demo.pix_custom = 0;
    demo.pix = 0;
    demo_pipeline_configure(VIN_CAM0);
    publish_camera();
    disp_stops = 0;
    vin_stops = 0;
    vin_disables = 0;
    test_pix_switches();
    test_geo_switches();
    test_inflight_geo();
    test_scene_switches();
    test_outputs();
    test_latency_wrap();
    demo_test_batch();
    assert(munmap(command, DEMO_COMMAND_WINDOW_SIZE) == 0);
    assert(munmap(send, DEMO_SEND_SIZE) == 0);
}
