/* main.c — npu-testplan 3.10 PP-SW-01, npu-spec 2.6/4.5.
 * Check hardware candidates, exact ordering/NMS boundaries and EDDT entries.
 * Clock domain: clk_sys.
 */
#include "common.h"
#include "detection.h"
int main(void)
{
    pp_init();
    pp_dirty(0);
    pp_start(0);
    uint32_t count = pp_wait();
    pp_equal(count, npu_post_acquire(PP_POST));
    pp_results(0, count, 0);
    /* Directed Q8 records exercise the exact IoU equality and both adjacent units. */
    pp_copy(PP_POST, 0x08800000u, PP_DIRECTED_COUNT * 24);
    yolo_post_stats stats;
    unsigned kept = yolo_post_candidates(pp_cached(PP_POST), PP_DIRECTED_COUNT,
                                        pp_detections, &stats);
    pp_equal(PP_DIRECTED_KEPT, kept);
    pp_equal(100, kept);
    pp_compare(pp_cached(0x08900000u), pp_detections, kept * 12);
    /* Real-frame raw features still pass through NPU class selection/DFL. */
    pp_copy(PP_INPUT, 0x08200000u, YOLO_OUTPUT_BYTES);
    cache_clean((uintptr_t)pp_cached(PP_INPUT), YOLO_OUTPUT_BYTES);
    pp_start(0);
    count = pp_wait();
    pp_equal(count, npu_post_acquire(PP_POST));
    pp_results(0, count, 2);
    static ui_detection_t display[YOLO_MAX_DETECTIONS];
    for (unsigned i = 0; i < pp_kept[2]; ++i) {
        const yolo_detection *d = &pp_detections[i];
        display[i] = (ui_detection_t){"", d->score / 10u, d->x0, d->y0,
                                      d->x1 - d->x0, d->y1 - d->y0, d->class_id};
    }
    ui_vision_t shown;
    pp_equal(50, ui_data_detection_config().threshold);
    ui_detection_filter(&shown, display, pp_kept[2]);
    pp_equal(PP_UI_DEFAULT, shown.count);
    ui_data_detection_class(pp_detections[0].class_id, false);
    ui_detection_filter(&shown, display, pp_kept[2]);
    pp_equal(PP_UI_WHITELIST, shown.count);
    pp_compare(pp_cached(0x08720000u), pp_detections, pp_kept[2] * 12);
    pp_pass();
}
