/* page_demo.c — T-DEMO-PAGES; face stickers, doodles and helmet validation.
 * RND-supported circles/rounded rectangles and horizontal strips; GUI domain.
 */
#include "theme.h"
#include <string.h>
#include <math.h>
static lv_obj_t *surface, *tags[100], *metrics, *warning, *pause_label;
static ui_demo_t shown;
static bool points_enabled;
static uint32_t color(unsigned cls)
{
    static const uint32_t colors[] = {0x2563eb,0xdc2626,0x059669,0x9333ea,0xea580c};
    return colors[cls % 5];
}
static void shape(lv_layer_t *layer, int x, int y, int w, int h,
                  uint32_t ink, bool outline, bool round)
{
    lv_draw_rect_dsc_t d;
    lv_draw_rect_dsc_init(&d);
    d.radius = round ? LV_RADIUS_CIRCLE : 0;
    d.bg_color = d.border_color = lv_color_hex(ink);
    if (outline) { d.bg_opa = LV_OPA_TRANSP; d.border_width = 3; }
    lv_area_t a = {x, y, x + w - 1, y + h - 1};
    lv_draw_rect(layer, &d, &a);
}
static void draw(lv_event_t *event)
{
    lv_layer_t *layer = lv_event_get_layer(event);
    for (unsigned i = 0; i < shown.count; ++i) {
        const ui_detection_t *box = &shown.objects[i];
        uint32_t ink = ui_page == 13 ? (box->class_id ? 0xdc2626 : 0x059669) :
                       color(box->class_id);
        shape(layer, box->x, box->y, box->width, box->height, ink, true, false);
        if (ui_page == 12) shape(layer, box->x + 6, box->y + 6, 16, 16, ink, false, true);
        if (ui_page != 11) continue;
        const ui_pose_point_t *p = shown.points[i];
        int eye = (int)hypotf(p[1].x - p[0].x, p[1].y - p[0].y);
        int radius = eye / 3;
        for (unsigned k = 0; k < 2; ++k)
            shape(layer, (int)p[k].x-radius, (int)p[k].y-radius,
                  radius*2, radius*2, 0x152b45, true, true);
        int left = (int)fminf(p[0].x, p[1].x);
        int right = (int)fmaxf(p[0].x, p[1].x);
        shape(layer, left, (int)((p[0].y+p[1].y)/2), right-left, 3, 0x152b45, false, false);
        int nose = eye / 6;
        shape(layer, (int)p[2].x-nose, (int)p[2].y-nose,
              nose*2, nose*2, 0xdc2626, false, true);
        for (unsigned k = 0; k < 3; ++k) {
            shape(layer, (int)p[3].x-eye/2, (int)p[3].y+(int)k*eye/10,
                  eye/2, 3, 0x152b45, false, false);
            shape(layer, (int)p[4].x, (int)p[4].y+(int)k*eye/10,
                  eye/2, 3, 0x152b45, false, false);
        }
        shape(layer, box->x+box->width/6, box->y-eye/2, box->width*2/3,
              eye/2, 0x2563eb, false, true);
        if (points_enabled) for (unsigned k = 0; k < 5; ++k)
            shape(layer, (int)p[k].x-3, (int)p[k].y-3, 7, 7, 0xea580c, false, true);
    }
}
static void invalidate(void)
{
    for (unsigned i = 0; i < shown.count; ++i) {
        const ui_detection_t *b = &shown.objects[i];
        /* Sticker extent includes hat above and whiskers beside the face. */
        lv_area_t a = {b->x-b->width, b->y-b->height,
                      b->x+b->width*2, b->y+b->height*2};
        lv_obj_invalidate_area(surface, &a);
    }
}
static void page(lv_obj_t *p, const char *title)
{
    ui_video_surface(p);
    ui_label(p, title, 24, 12, &sim_font_28, TEXT);
    if (ui_page == 11) ui_button(p, "关键点 开关", 580, 6, 184, 1);
    if (ui_page == 12) {
        ui_button(p, "阈值 -8", 400, 6, 160, 1);
        ui_button(p, "阈值 +8", 580, 6, 160, 2);
    }
    ui_button(p, "暂停画面", 792, 6, 184, 0);
    pause_label = lv_obj_get_child(lv_obj_get_child(p, -1), 0);
    memset(&shown, 0, sizeof shown);
    points_enabled = false;
    surface = ui_box(lv_screen_active(), 0, 0, 1280, 720, BG);
    lv_obj_set_style_bg_opa(surface, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(surface, 0, 0);
    lv_obj_move_to_index(surface, 0);
    lv_obj_add_event_cb(surface, draw, LV_EVENT_DRAW_MAIN, NULL);
    for (unsigned i = 0; i < 100; ++i) {
        tags[i] = ui_label(surface, "", 0, 0, &sim_font_16, PANEL);
        lv_obj_set_style_bg_opa(tags[i], LV_OPA_COVER, 0);
        lv_obj_set_hidden(tags[i], true);
    }
    lv_obj_t *side = ui_box(p, 992, 56, 272, 340, PANEL);
    metrics = ui_label(side, "", 16, 20, &sim_font_20, TEXT);
    warning = ui_box(p, 180, 550, 700, 56, 0xdc2626);
    ui_label(warning, "警示：有人未戴安全帽", 24, 12, &sim_font_28, PANEL);
    lv_obj_set_hidden(warning, true);
    ui_hint(ui_page == 12 ? "白底黑线 · 摄像头 → 灰度二值化 → 内存源 → NPU" :
            ui_page == 11 ? "眼镜 / 红鼻子 / 胡须 / 帽子 · 关键点默认关闭" :
            "绿框 安全帽 · 红框 未戴 · 上板功能验证");
}
void ui_page_face(lv_obj_t *p) { page(p, "人脸贴纸"); }
void ui_page_doodle(lv_obj_t *p) { page(p, "简笔画识别"); }
void ui_page_helmet(lv_obj_t *p) { page(p, "安全帽检测"); }
void ui_demo_action(unsigned action)
{
    if (!action) ui_data_app_pause(ui_data_session().state != UI_STATE_PAUSED);
    else if (ui_page == 11) { points_enabled = !points_enabled; invalidate(); }
    else if (ui_page == 12) ui_data_doodle_adjust(action == 1 ? -8 : 8);
}
void ui_demo_update(void)
{
    ui_vision_t stats = ui_data_vision();
    const ui_demo_t *d = ui_data_demo();
    if (memcmp(&shown, d, sizeof shown)) {
        invalidate(); shown = *d;
        for (unsigned i = 0; i < 100; ++i) {
            lv_obj_set_hidden(tags[i], i >= shown.count);
            if (i >= shown.count) continue;
            const ui_detection_t *b = &shown.objects[i];
            lv_label_set_text_fmt(tags[i], "%s %u%%", b->category, b->confidence);
            lv_obj_set_style_bg_color(tags[i], lv_color_hex(ui_page == 13 ?
                (b->class_id ? 0xdc2626 : 0x059669) : color(b->class_id)), 0);
            lv_obj_set_pos(tags[i], b->x, b->y < 24 ? 0 : b->y-24);
        }
        lv_obj_update_layout(surface); invalidate();
    }
    char detail[80];
    if (ui_page == 13) lv_snprintf(detail, sizeof detail, "安全帽 %u 人\n未戴 %u 人",
                                  d->helmet, d->head);
    else if (ui_page == 12) lv_snprintf(detail, sizeof detail, "目标 %u\n阈值 %u",
                                       d->count, ui_data_doodle_threshold());
    else lv_snprintf(detail, sizeof detail, "人脸 %u\n最大框 %u px", d->count, d->size/2);
    lv_label_set_text_fmt(metrics, "%s\n\nNPU %u.%u ms\n\n帧率 %u fps\n\n延迟 %u.%u ms",
        detail, stats.npu_tenths/10, stats.npu_tenths%10, stats.fps,
        stats.latency_tenths/10, stats.latency_tenths%10);
    lv_obj_set_hidden(warning, ui_page != 13 || !d->head);
    ui_text(pause_label, ui_data_session().state == UI_STATE_PAUSED ? "继续画面" : "暂停画面");
}
