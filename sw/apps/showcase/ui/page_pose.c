/* page_pose.c — T-POSE-BOARD; live L0 video with LVGL L1 skeletons.
 * All retained people are drawn; only the largest controls the hand indicators.
 * Clock domain: cooperative GUI task.
 */
#include "theme.h"
#include <string.h>
static lv_obj_t *frame, *tags[100], *metrics, *hands, *pause_label;
static ui_pose_t shown;
static const unsigned bones[][2] = {
    {0,1},{0,2},{1,3},{2,4},{0,5},{0,6},{5,6},{5,7},{7,9},{6,8},{8,10},
    {5,11},{6,12},{11,12},{11,13},{13,15},{12,14},{14,16}
};
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
        shown = *data;
        lv_obj_invalidate(frame);
        for (unsigned i = 0; i < 100; ++i) {
            lv_obj_set_hidden(tags[i], i >= shown.count);
            if (i >= shown.count) continue;
            lv_snprintf(text, sizeof text, "行人 %u%%", shown.people[i].confidence);
            ui_text(tags[i], text);
            lv_obj_set_pos(tags[i], shown.people[i].x,
                          shown.people[i].y < 22 ? 0 : shown.people[i].y - 22);
        }
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
