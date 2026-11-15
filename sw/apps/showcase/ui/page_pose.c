/* page_pose.c — T-POSE-BOARD; live L0 video with LVGL L1 skeletons.
 * All retained people are drawn; only the largest controls the hand indicators.
 * Clock domain: cooperative GUI task.
 */
#include "theme.h"
#include <string.h>
#include "src/draw/lv_draw_private.h"
#include "src/misc/lv_area_private.h"
static lv_obj_t *frame, *tags[100], *metrics, *hands, *pause_label;
static ui_pose_t shown;
static const unsigned bones[][2] = {
    {0,1},{0,2},{1,3},{2,4},{0,5},{0,6},{5,6},{5,7},{7,9},{6,8},{8,10},
    {5,11},{6,12},{11,12},{11,13},{13,15},{12,14},{14,16}
};
/* Only this page's tagged lines use the integer rasterizer. The dispatcher waits
 * for overlapping older tasks; RND submit() completes before FINISHED. Later RND
 * tasks clean destination rows (including these CPU stores) before invalidation,
 * and display flush publishes the remaining CPU stores through BSP cache APIs.
 */
static lv_draw_unit_t *line_unit;
static int32_t line_evaluate(lv_draw_unit_t *unit, lv_draw_task_t *task)
{
    if (task->type == LV_DRAW_TASK_TYPE_LINE &&
        ((lv_draw_line_dsc_t *)task->draw_dsc)->base.user_data == &shown) {
        task->preference_score = 0;
        task->preferred_draw_unit_id = unit->idx;
    }
    return 0;
}
static int32_t line_dispatch(lv_draw_unit_t *unit, lv_layer_t *layer)
{
    lv_draw_task_t *task = lv_draw_get_available_task(layer, NULL, unit->idx);
    if (!task) return LV_DRAW_UNIT_IDLE;
    task->state = LV_DRAW_TASK_STATE_IN_PROGRESS;
    lv_draw_layer_alloc_buf(layer);
    const lv_draw_line_dsc_t *d = task->draw_dsc;
    lv_area_t clip;
    if (lv_area_intersect(&clip, &task->clip_area, &layer->buf_area)) {
        int x = (int)(d->p1.x + .5f), y = (int)(d->p1.y + .5f);
        int end_x = (int)(d->p2.x + .5f), end_y = (int)(d->p2.y + .5f);
        int dx = LV_ABS(end_x - x), dy = LV_ABS(end_y - y);
        int sx = x < end_x ? 1 : -1, sy = y < end_y ? 1 : -1;
        int error = dx - dy;
        uint32_t color = lv_color_to_u32(d->color);
        for (;;) {
            /* Three solid pixels across the minor axis, without alpha blending. */
            for (int offset = -1; offset <= 1; ++offset) {
                int px = x + (dx < dy ? offset : 0);
                int py = y + (dx >= dy ? offset : 0);
                if (px < clip.x1 || px > clip.x2 || py < clip.y1 || py > clip.y2) continue;
                uint32_t *row = (uint32_t *)(layer->draw_buf->data +
                    (py - layer->buf_area.y1) * layer->draw_buf->header.stride);
                row[px - layer->buf_area.x1] = color;
            }
            if (x == end_x && y == end_y) break;
            int twice = 2 * error;
            if (twice > -dy) { error -= dy; x += sx; }
            if (twice < dx) { error += dx; y += sy; }
        }
    }
    task->state = LV_DRAW_TASK_STATE_FINISHED;
    lv_draw_dispatch_request();
    return 1;
}
static void invalidate_people(void)
{
    for (unsigned i = 0; i < shown.count; ++i) {
        const ui_detection_t *p = &shown.people[i];
        lv_area_t area = {p->x, p->y, p->x + p->width - 1, p->y + p->height - 1};
        for (unsigned k = 0; k < 17; ++k) {
            const ui_pose_point_t *point = &shown.points[i][k];
            if (point->visibility <= .5f) continue;
            int x = (int)(point->x + .5f), y = (int)(point->y + .5f);
            area.x1 = LV_MIN(area.x1, x); area.x2 = LV_MAX(area.x2, x);
            area.y1 = LV_MIN(area.y1, y); area.y2 = LV_MAX(area.y2, y);
        }
        lv_area_t label;
        lv_obj_get_coords(tags[i], &label);
        lv_area_join(&area, &area, &label);
        lv_area_increase(&area, 4, 4); /* 3 px joint radius plus raster rounding. */
        lv_obj_invalidate_area(frame, &area);
    }
}
static void draw(lv_event_t *event)
{
    lv_layer_t *layer = lv_event_get_layer(event);
    lv_draw_rect_dsc_t rect;
    lv_draw_rect_dsc_init(&rect);
    rect.bg_opa = LV_OPA_TRANSP;
    rect.border_color = lv_color_hex(TEAL);
    rect.border_width = 2;
    lv_draw_line_dsc_t line;
    lv_draw_line_dsc_init(&line);
    line.color = lv_color_hex(TEAL);
    line.width = 3;
    line.base.user_data = &shown;
    for (unsigned i = 0; i < shown.count; ++i) {
        const ui_detection_t *person = &shown.people[i];
        lv_area_t box = {person->x, person->y, person->x + person->width - 1,
                         person->y + person->height - 1};
        lv_draw_rect(layer, &rect, &box);
        const ui_pose_point_t *points = shown.points[i];
        for (unsigned b = 0; b < sizeof bones / sizeof bones[0]; ++b) {
            const ui_pose_point_t *a = &points[bones[b][0]], *c = &points[bones[b][1]];
            if (a->visibility <= .5f || c->visibility <= .5f) continue;
            line.p1 = (lv_point_precise_t){a->x, a->y};
            line.p2 = (lv_point_precise_t){c->x, c->y};
            lv_draw_line(layer, &line);
        }
        lv_draw_rect_dsc_t dot;
        lv_draw_rect_dsc_init(&dot);
        dot.bg_color = lv_color_hex(ACCENT);
        dot.radius = LV_RADIUS_CIRCLE;
        for (unsigned k = 0; k < 17; ++k) {
            if (points[k].visibility <= .5f) continue;
            int x = (int)(points[k].x + .5f), y = (int)(points[k].y + .5f);
            lv_area_t area = {x - 3, y - 3, x + 3, y + 3};
            lv_draw_rect(layer, &dot, &area);
        }
    }
}
void ui_page_pose(lv_obj_t *p)
{
    if (!line_unit) {
        line_unit = lv_draw_create_unit(sizeof(*line_unit));
        line_unit->name = "Pose solid lines";
        line_unit->evaluate_cb = line_evaluate;
        line_unit->dispatch_cb = line_dispatch;
    }
    ui_video_surface(p);
    ui_label(p, "人体姿态", 24, 12, &sim_font_28, TEXT);
    ui_button(p, "暂停画面", 792, 6, 184, 0);
    pause_label = lv_obj_get_child(lv_obj_get_child(p, -1), 0);
    memset(&shown, 0, sizeof shown);
    frame = ui_box(lv_screen_active(), 0, 0, 1280, 720, BG);
    lv_obj_set_style_bg_opa(frame, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(frame, 0, 0);
    lv_obj_move_to_index(frame, 0);
    lv_obj_add_event_cb(frame, draw, LV_EVENT_DRAW_MAIN, NULL);
    for (unsigned i = 0; i < 100; ++i) {
        tags[i] = ui_label(frame, "", 0, 0, &sim_font_14, PANEL);
        lv_obj_set_style_bg_color(tags[i], lv_color_hex(TEAL), 0);
        lv_obj_set_style_bg_opa(tags[i], LV_OPA_COVER, 0);
        lv_obj_set_hidden(tags[i], true);
    }
    lv_obj_t *side = ui_box(p, 992, 56, 272, 440, PANEL);
    lv_obj_set_style_bg_opa(side, LV_OPA_80, 0);
    metrics = ui_label(side, "", 20, 20, &sim_font_20, TEXT);
    hands = ui_label(side, "", 20, 270, &sim_font_20, ACCENT);
    ui_hint("最大行人 · 手腕高于同侧肩膀且两点可见时，显示举手");
}
void ui_pose_update(void)
{
    ui_vision_t stats = ui_data_vision();
    const ui_pose_t *data = ui_data_pose();
    char text[200];
    if (memcmp(&shown, data, sizeof shown)) {
        invalidate_people();
        shown = *data;
        for (unsigned i = 0; i < 100; ++i) {
            lv_obj_set_hidden(tags[i], i >= shown.count);
            if (i >= shown.count) continue;
            lv_snprintf(text, sizeof text, "行人 %u%%", shown.people[i].confidence);
            ui_text(tags[i], text);
            lv_obj_set_pos(tags[i], shown.people[i].x,
                          shown.people[i].y < 22 ? 0 : shown.people[i].y - 22);
        }
        lv_obj_update_layout(frame);
        invalidate_people();
    }
    lv_snprintf(text, sizeof text,
        "人数  %u\n\nNPU  %u.%u ms\n\n帧率  %u fps\n\n延迟  %u.%u ms",
        data->count, stats.npu_tenths / 10, stats.npu_tenths % 10, stats.fps,
        stats.latency_tenths / 10, stats.latency_tenths % 10);
    ui_text(metrics, text);
    lv_snprintf(text, sizeof text, "最大行人\n\n左手举起  %s\n右手举起  %s",
        data->left_up ? "是" : "否", data->right_up ? "是" : "否");
    ui_text(hands, text);
    ui_text(pause_label, ui_data_session().state == UI_STATE_PAUSED ? "继续画面" : "暂停画面");
}
