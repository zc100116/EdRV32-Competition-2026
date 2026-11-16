/* page_hand.c — T-DEMO-PAGES; live L0 video with class-colored L1 hands.
 * All retained hands are drawn; the largest controls the debounced model class.
 * Clock domain: cooperative GUI task.
 */
#include "widgets.h"
#include <string.h>
#include <math.h>
#include <stdio.h>
#include "src/draw/lv_draw_private.h"
#include "src/misc/lv_area_private.h"
static lv_obj_t *frame, *tags[100], *metrics, *hands, *pause_label;
static ui_hand_t shown;
static const unsigned bones[][2] = {
    {0,1},{1,2},{2,3},{3,4},{0,5},{5,6},{6,7},{7,8},
    {0,9},{9,10},{10,11},{11,12},{0,13},{13,14},{14,15},{15,16},
    {0,17},{17,18},{18,19},{19,20}
};

void ui_hand_toggle(void)
{
    ui_debug_overlay=!ui_debug_overlay;
    for(unsigned i=0;i<100;++i)
        lv_obj_set_hidden(tags[i],!ui_debug_overlay || i>=shown.count);
    lv_obj_invalidate(frame);
}
static uint32_t class_color(unsigned cls)
{
    static const uint32_t colors[] = {0x0d9488,0xdc2626,0x2563eb,0x9333ea,0xea580c,0xdb2777,
        0x0891b2,0x65a30d,0xd97706,0x7c3aed,0x059669,0x4f46e5,0xbe123c,0x475569};
    return colors[cls];
}
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
        for (unsigned k = 0; k < 21; ++k) {
            const ui_pose_point_t *point = &shown.points[i][k];
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
        rect.border_color = lv_color_hex(class_color(person->class_id));
        if (ui_debug_overlay) lv_draw_rect(layer, &rect, &box);
        if (!ui_debug_overlay) continue;
        const ui_pose_point_t *points = shown.points[i];
        for (unsigned b = 0; b < sizeof bones / sizeof bones[0]; ++b) {
            const ui_pose_point_t *a = &points[bones[b][0]], *c = &points[bones[b][1]];
            line.p1 = (lv_point_precise_t){a->x, a->y};
            line.p2 = (lv_point_precise_t){c->x, c->y};
            lv_draw_line(layer, &line);
        }
        lv_draw_rect_dsc_t dot;
        lv_draw_rect_dsc_init(&dot);
        dot.bg_color = lv_color_hex(ACCENT);
        dot.radius = LV_RADIUS_CIRCLE;
        for (unsigned k = 0; k < 21; ++k) {
            int x = (int)(points[k].x + .5f), y = (int)(points[k].y + .5f);
            lv_area_t area = {x - 3, y - 3, x + 3, y + 3};
            lv_draw_rect(layer, &dot, &area);
        }
    }
}
void ui_page_hand(lv_obj_t *p)
{
    if (!line_unit) {
        line_unit = lv_draw_create_unit(sizeof(*line_unit));
        line_unit->name = "Hand solid lines";
        line_unit->evaluate_cb = line_evaluate;
        line_unit->dispatch_cb = line_dispatch;
    }
    lv_obj_t *header=ui_page_layout(p,"手势识别",true);
    lv_obj_t *pause=ui_action_button(header,"暂停画面",0);
    pause_label=lv_obj_get_child(pause,0);
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
    lv_obj_t *body=ui_stack(p,LV_FLEX_FLOW_ROW,0);
    lv_obj_set_flex_grow(body,1);
    lv_obj_set_flex_align(body,LV_FLEX_ALIGN_END,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_START);
    lv_obj_t *side=ui_panel(body,300);
    metrics=ui_text_label(side,"",&sim_font_20,TEXT);
    hands=ui_live_badge(side,"",ACCENT);
    ui_hint("最大手连续 3 帧确认 · 设置中控制调试叠加");
}
void ui_hand_update(void)
{
    ui_vision_t stats = ui_data_vision();
    const ui_hand_t *data = ui_data_hand();
    char text[400];
    if (memcmp(&shown, data, sizeof shown)) {
        invalidate_people();
        shown = *data;
        for (unsigned i = 0; i < 100; ++i) {
            lv_obj_set_hidden(tags[i], i >= shown.count || !ui_debug_overlay);
            if (i >= shown.count) continue;
            lv_snprintf(text, sizeof text, "%s %u%%",
                        shown.people[i].category, shown.people[i].confidence);
            ui_text(tags[i], text);
            lv_obj_set_style_bg_color(tags[i],
                lv_color_hex(class_color(shown.people[i].class_id)), 0);
            lv_obj_set_pos(tags[i], shown.people[i].x,
                          shown.people[i].y < 22 ? 0 : shown.people[i].y - 22);
        }
        lv_obj_update_layout(frame);
        invalidate_people();
    }
    lv_snprintf(text, sizeof text,
        "手数  %u\n\nNPU  %u.%u ms\n\n帧率  %u fps\n\n延迟  %u.%u ms",
        data->count, stats.npu_tenths / 10, stats.npu_tenths % 10, stats.fps,
        stats.latency_tenths / 10, stats.latency_tenths % 10);
    ui_text(metrics, text);
    if (data->count && data->state.cls >= 0) {
        unsigned cls = (unsigned)data->state.cls;
        lv_snprintf(text, sizeof text, "%s %u%%\n数字 %s\n猜拳 %s", ui_gesture_names[cls],
                    data->confidence,
                    ui_gesture_numbers[cls], ui_gesture_rps[cls]);
        lv_obj_set_style_bg_color(hands, lv_color_hex(cls == 5 ? 0xdc2626 : ACCENT), 0);
        lv_obj_set_style_bg_opa(hands, LV_OPA_COVER, 0);
        lv_obj_set_style_text_color(hands, lv_color_hex(PANEL), 0);
    } else lv_snprintf(text, sizeof text, "等待手势");
    ui_text(hands, text);
    ui_text(pause_label, ui_data_session().state == UI_STATE_PAUSED ? "继续画面" : "暂停画面");
}
