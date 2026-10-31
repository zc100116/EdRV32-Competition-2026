/* File: geometry_range.c
 * Spec: rnd-spec v0.4 2.3/5.4; rnd-testplan v0.3 driver range checks.
 * Description: Exercise the real evaluation callback with oversized G1 tasks.
 * Clock domain: host.
 */
#include "../lvgl/draw_rnd.c"
#include <stdio.h>

int s3_geometry_range_test(void)
{
    lv_layer_t layer = { .buf_area = {0, 0, 1279, 719},
                         .color_format = LV_COLOR_FORMAT_RGB565 };
    lv_draw_task_t task = { .target_layer = &layer, .clip_area = {0, 0, 1279, 719},
                           .area = {-30000, -30000, 30000, 30000},
                           ._real_area = {-30000, -30000, 30000, 30000} };
    lv_draw_triangle_dsc_t tri;
    lv_draw_triangle_dsc_init(&tri);
    tri.p[0] = (lv_point_precise_t) {-30000, -30000};
    tri.p[1] = (lv_point_precise_t) {30000, -30000};
    tri.p[2] = (lv_point_precise_t) {-30000, 30000};
    lv_draw_line_dsc_t segment;
    lv_draw_line_dsc_init(&segment);
    segment.p1 = (lv_point_precise_t) {0, 0};
    segment.p2 = segment.p1;
    segment.width = 50000;
    segment.round_start = 1;
    lv_draw_arc_dsc_t ring;
    lv_draw_arc_dsc_init(&ring);
    ring.center = (lv_point_t) {0, 0};
    ring.radius = 30000;
    ring.width = 1;
    ring.end_angle = 360;
    const lv_draw_task_type_t types[3] = {
        LV_DRAW_TASK_TYPE_TRIANGLE, LV_DRAW_TASK_TYPE_LINE, LV_DRAW_TASK_TYPE_ARC
    };
    void *descriptors[3] = {&tri, &segment, &ring};
    for (unsigned k = 0; k < 3; ++k) {
        task.type = types[k];
        task.draw_dsc = descriptors[k];
        task.preference_score = 100;
        task.preferred_draw_unit_id = 0;
        uint32_t before = stats.unclaimed[task.type];
        evaluate(NULL, &task);
        if (task.preferred_draw_unit_id == RND_UNIT ||
            stats.unclaimed[task.type] != before + 1) {
            fprintf(stderr, "FAIL oversized task type=%u was claimed\n", task.type);
            return 1;
        }
        printf("PASS oversized task type=%u keeps software preference\n", task.type);
    }
    return 0;
}
