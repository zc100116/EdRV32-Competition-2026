/* File: inference.c
 * Spec: Task T-NETN; SoC 7.2/7.4; npu-spec 2.4; eth-spec 2.4/2.6.
 * Description: Adapt RGB565 to CH2, run NPU/YOLO and retain tensors until TX DONE.
 * Clock domain: clk_sys; input and transmission objects use the uncached DDR alias.
 */
#include "runtime.h"

static yolo_detection detections[YOLO_MAX_DETECTIONS];
static uint32_t next_frame;

static void npu_event(const struct engine_event *event, void *context)
{
    (void)context;
    if (event->error || (event->irq & EDRV32_NPU_IRQ_STAT_ERROR_MASK)) {
        info_number("NPU CUR_DESC", npu_current_descriptor());
        demo_fail("NPU", ENGINE_NPU);
    }
    if (event->irq & EDRV32_NPU_IRQ_STAT_DONE_MASK) {
        demo.inference[demo.active_npu].state = BUFFER_READY;
        demo.active_npu = -1;
        ++demo.inference_count;
        demo.inference_cycles = engine_perf(ENGINE_NPU, 0);
    }
}

void demo_npu_init(void)
{
    engine_irq_register(ENGINE_NPU, EDRV32_NPU_IRQ_EN_ERROR_MASK |
                        EDRV32_NPU_IRQ_EN_DONE_MASK, 3, npu_event, NULL);
    engine_control(ENGINE_NPU, EDRV32_NPU_CTRL_ENABLE_MASK);
}

void demo_npu_receive(unsigned int window)
{
    uint32_t bytes = eth_window_bytes(window);
    if (bytes != DEMO_IMAGE_BYTES) {
        info_number("RGB565 image bytes", bytes);
        demo_fail("RGB565 image length", ENGINE_ETH);
    }
    demo_network_wait();
    struct demo_inference *job = &demo.inference[window];
    job->frame_id = next_frame++;
    job->input_slot = window;
    job->state = BUFFER_RUNNING;
    demo.image_window = window;
    demo.checking = 1;
    demo.active_npu = (int)window;
    uint32_t input = DEMO_INPUT_BASE + window * DEMO_INPUT_SPACING;
    demo_ch2(demo_uncached(DEMO_WINDOW_BASE + window * DEMO_WINDOW_SIZE),
             demo_uncached(input));
    npu_start(input,
              DEMO_OUTPUT_BASE + window * DEMO_OUTPUT_SPACING);
}

static void print_value(const char *name, uint32_t value)
{
    char digits[10];
    unsigned int count = 0;
    uart_puts(name);
    do {
        digits[count++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value);
    while (count) {
        uart_putc((uint8_t)digits[--count]);
    }
}

void demo_npu_service(void)
{
    for (unsigned int buffer = 0; buffer < 2; ++buffer) {
        struct demo_inference *job = &demo.inference[buffer];
        if (job->state != BUFFER_READY) {
            continue;
        }
        job->state = BUFFER_PROCESSING;
        uint32_t output = DEMO_OUTPUT_BASE + buffer * DEMO_OUTPUT_SPACING;
        engine_dma_invalidate(demo_cached(output), DEMO_OUTPUT_BYTES);
        uint32_t start = demo_npu_cpu_cycles();
        yolo_post_stats stats;
        unsigned int count = yolo_post_process((const int8_t *)demo_cached(output),
            yolo_default_heads, (yolo_candidate *)demo_cached(DEMO_WORKSPACE),
            detections, &stats);
        demo.post_cycles = demo_npu_cpu_cycles() - start;
        demo.detection_count = count;
        demo_network_wait();
        unsigned int bytes = (unsigned int)demo_detection_pack(
            demo_uncached(DEMO_TX_DETECTIONS), detections, count, job->frame_id);
        uint32_t lock = demo_irq_lock();
        unsigned int descriptors = demo_network_detections(
            demo_uncached(DEMO_TX_DESCRIPTORS), bytes, (int)buffer);
        demo_network_submit(descriptors, -1, (int)buffer);
        demo_irq_unlock(lock);
        print_value("frame_id=", job->frame_id);
        print_value(" NPU_PERF0=", demo.inference_cycles);
        print_value(" post_cpu_cycles=", demo.post_cycles);
        print_value(" detections=", count);
        uart_puts("\r\n");
    }
}
