/* common.h — npu-testplan 3.10 PP-SW-01/02; SoC 7.4.
 * Software-side oracle comparison and candidate DMA ownership checks.
 * Clock domain: clk_sys.
 */
#ifndef NPU_POST_TEST_COMMON_H
#define NPU_POST_TEST_COMMON_H
#include "npu.h"
#include "cache.h"
#include "sysctrl.h"
#include "uart.h"
#include "yolo_post.h"
#include "data.h"
#include "wire.h"
#define PP_DESC 0x00080000u
#define PP_MODEL 0x00100000u
#define PP_INPUT 0x04000000u
#define PP_RAW 0x05000000u
#define PP_POST 0x05200000u
#define PP_POST_STEP 0x00020000u
static yolo_detection pp_detections[YOLO_MAX_DETECTIONS];

static void *pp_cached(uint32_t physical)
{
    return (void *)(uintptr_t)(EDRV32_DDR_BASE + physical);
}

static void pp_equal(uint32_t expected, uint32_t actual)
{
    if (expected != actual) {
        uart_puts("FAIL PP-SW expected=");
        for (int shift = 28; shift >= 0; shift -= 4)
            uart_putc((uint8_t)"0123456789abcdef"[(expected >> shift) & 15]);
        uart_puts(" actual=");
        for (int shift = 28; shift >= 0; shift -= 4)
            uart_putc((uint8_t)"0123456789abcdef"[(actual >> shift) & 15]);
        uart_puts("\r\n");
        uart_drain();
        sysctrl_write(SYSCTRL_SIM_EXIT, 1);
        for (;;) {}
    }
}

static void pp_compare(const void *expected, const void *actual, unsigned bytes)
{
    const uint8_t *a = expected;
    const uint8_t *b = actual;
    for (unsigned i = 0; i < bytes; ++i) pp_equal(a[i], b[i]);
}

static void pp_copy(uint32_t dst, uint32_t src, unsigned bytes)
{
    uint32_t *out = pp_cached(dst);
    const uint32_t *in = pp_cached(src);
    for (unsigned i = 0; i < bytes / 4; ++i) out[i] = in[i];
}

static void pp_init(void)
{
    uart_init();
    pp_copy(PP_MODEL, 0x08400000u, PP_MODEL_BYTES);
    pp_copy(PP_DESC, 0x08500000u, PP_DESC_BYTES);
    cache_clean((uintptr_t)pp_cached(PP_MODEL), PP_MODEL_BYTES);
    cache_clean((uintptr_t)pp_cached(PP_DESC), PP_DESC_BYTES);
    for (unsigned frame = 0; frame < 2; ++frame) {
        pp_copy(PP_INPUT + frame * 0x100000u, 0x08000000u + frame * 0x100000u,
                YOLO_OUTPUT_BYTES);
        cache_clean((uintptr_t)pp_cached(PP_INPUT + frame * 0x100000u), YOLO_OUTPUT_BYTES);
    }
    struct npu_config config = {PP_MODEL, 0x01000000u, PP_INPUT, PP_RAW,
                                PP_DESC, PP_DESC_BYTES / 64};
    npu_configure(&config);
    npu_post_configure();
    mmio_write32(EDRV32_NPU_BASE + EDRV32_NPU_IRQ_EN_OFFSET, EDRV32_NPU_IRQ_EN_DONE_MASK);
}

static void pp_dirty(unsigned frame)
{
    uint32_t *post = pp_cached(PP_POST + frame * PP_POST_STEP);
    for (unsigned i = 0; i < YOLO_CANDIDATE_BYTES / 4; ++i) post[i] = 0xdead0000u + frame;
}

static void pp_start(unsigned frame)
{
    npu_post_start(PP_INPUT + frame * 0x100000u, PP_RAW, PP_POST + frame * PP_POST_STEP);
}

static uint32_t pp_wait(void)
{
    struct engine_event event;
    do {
        event = engine_poll(ENGINE_NPU);
        pp_equal(0, event.error);
    } while (!(event.irq & EDRV32_NPU_IRQ_STAT_DONE_MASK));
    pp_equal(EDRV32_NPU_POST_STATUS_POST_DONE_MASK, npu_post_status());
    uint32_t count = npu_post_count();
    engine_irq_clear(ENGINE_NPU, EDRV32_NPU_IRQ_STAT_DONE_MASK);
    return count;
}

static void pp_results(unsigned buffer, uint32_t count, unsigned frame)
{
    yolo_candidate *items = pp_cached(PP_POST + buffer * PP_POST_STEP);
    const yolo_candidate *expected = pp_cached(0x08600000u + frame * 0x10000u);
    pp_equal(pp_counts[frame], count);
    volatile uint8_t seen[YOLO_ANCHORS];
    for (unsigned i = 0; i < YOLO_ANCHORS; ++i) seen[i] = 0;
    /* Enqueue order is independent of oracle traversal; associate by anchor. */
    for (unsigned i = 0; i < count; ++i) {
        unsigned j = 0;
        while (j < count && expected[j].anchor != items[i].anchor) ++j;
        pp_equal(1, j < count);
        pp_equal(0, seen[j]);
        seen[j] = 1;
        pp_compare(&expected[j], &items[i], sizeof items[i]);
    }
    yolo_post_stats stats;
    unsigned kept = yolo_post_candidates(items, count, pp_detections, &stats);
    pp_equal(pp_kept[frame], kept);
    pp_compare(pp_cached(0x08700000u + frame * 0x10000u), pp_detections, kept * 12);
    uint8_t wire[16 + 12 * YOLO_MAX_DETECTIONS];
    unsigned bytes = (unsigned)vision_detection_pack(wire, pp_detections, kept,
                                                    100 + frame, 200 + frame);
    pp_equal(16 + kept * 12, bytes);
    pp_compare(pp_cached(0x08780000u + frame * 0x10000u), wire, bytes);
    pp_equal(count, stats.decoded_anchors);
    pp_equal(0, stats.class_comparisons + stats.dfl_bin_comparisons + stats.exp_lookups);
}

static _Noreturn void pp_pass(void)
{
    uart_puts("PASS PP-SW\r\n");
    uart_drain();
    sysctrl_write(SYSCTRL_SIM_EXIT, 0);
    for (;;) {}
}
#endif
