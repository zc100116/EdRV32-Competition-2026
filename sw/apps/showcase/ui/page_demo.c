/* page_demo.c — T-DEMO-PAGES; face stickers, doodles and helmet validation.
 * RND-supported circles/rounded rectangles and horizontal strips; GUI domain.
 */
#include "theme.h"
#include <string.h>
#include "sticker.h"
static lv_obj_t *surface, *tags[100], *metrics, *warning, *pause_label;
static ui_demo_t shown;
static bool points_enabled;
static sticker_state_t stickers;
static unsigned selected, revision, frame_tick;
static lv_obj_t *sticker_name;
#define ART(name) \
    extern const lv_image_dsc_t sticker_##name##_m24, sticker_##name##_m12, \
        sticker_##name##_z0, sticker_##name##_p12, sticker_##name##_p24
ART(cat_ears); ART(bunny_ears); ART(sunglasses); ART(crown); ART(party_hat); ART(heart_headband);
#define FRAMES(name) {&sticker_##name##_m24, &sticker_##name##_m12, &sticker_##name##_z0, \
    &sticker_##name##_p12, &sticker_##name##_p24}
static const lv_image_dsc_t *const artwork[6][5] = {
    FRAMES(cat_ears), FRAMES(bunny_ears), FRAMES(sunglasses), FRAMES(crown),
    FRAMES(party_hat), FRAMES(heart_headband)
};
static lv_area_t sticker_area(const sticker_track_t *t, lv_draw_image_dsc_t *image)
{
    sticker_placement_t p;
    sticker_place(t, selected, &p);
    const lv_image_dsc_t *art = artwork[selected][t->angle];
    /* Rotated frames share a square 220 canvas and a 160 px source width. */
    int size = p.width*220/160;
    lv_area_t area = {p.x-size/2, p.y-size/2, p.x+(size+1)/2-1, p.y+(size+1)/2-1};
    if (image) {
        lv_draw_image_dsc_init(image);
        image->src = art;
        image->opa = sticker_opacity(t);
        image->scale_x = image->scale_y = p.width*256/160;
        image->pivot = (lv_point_t){0,0};
        image->antialias = 0;
    }
    return area;
}
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
    if (ui_page == 11) {
        for (unsigned i = 0; i < STICKER_FACES; ++i) {
            const sticker_track_t *t = &stickers.tracks[i];
            if (!sticker_opacity(t)) continue;
            lv_draw_image_dsc_t image;
            lv_area_t a = sticker_area(t, &image);
            a.x2 = a.x1 + 219; a.y2 = a.y1 + 219;
            lv_draw_image(layer, &image, &a);
            if (points_enabled) {
                sticker_placement_t p;
                sticker_place(t, selected, &p);
                shape(layer,p.anchor_x-3,p.anchor_y-3,7,7,0x00ff88,false,true);
                shape(layer,p.x-3,p.y-3,7,7,0xff00ff,false,true);
            }
        }
        if (!points_enabled) return;
    }
    for (unsigned i = 0; i < shown.count; ++i) {
        const ui_detection_t *box = &shown.objects[i];
        uint32_t ink = ui_page == 13 ? (box->class_id ? 0xdc2626 : 0x059669) :
                       color(box->class_id);
        shape(layer, box->x, box->y, box->width, box->height, ink, true, false);
        if (ui_page == 12) shape(layer, box->x + 6, box->y + 6, 16, 16, ink, false, true);
        if (ui_page != 11) continue;
        const ui_pose_point_t *p = shown.points[i];
        if (points_enabled) for (unsigned k = 0; k < 5; ++k)
            shape(layer, (int)p[k].x-3, (int)p[k].y-3, 7, 7, 0xea580c, false, true);
    }
}
static void invalidate(void)
{
    if (ui_page == 11) {
        for (unsigned i = 0; i < STICKER_FACES; ++i) {
            if (!sticker_opacity(&stickers.tracks[i])) continue;
            lv_area_t a = sticker_area(&stickers.tracks[i], NULL);
            lv_obj_invalidate_area(surface, &a);
        }
        if (!points_enabled) return;
    }
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
    if (ui_page == 11) {
        ui_button(p, "换贴纸", 400, 6, 160, 2);
        ui_button(p, "调试", 580, 6, 184, 1);
        sticker_name = ui_label(p, sticker_styles[0].name, 220, 14, &sim_font_20, TEXT);
        memset(&stickers, 0, sizeof stickers);
        selected = 0; revision = sticker_revision; frame_tick = lv_tick_get();
    }
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
            ui_page == 11 ? "六款原创贴纸 · 镜像摄像头 · 调试显示关键点" :
            "绿框 安全帽 · 红框 未戴 · 上板功能验证");
}
void ui_page_face(lv_obj_t *p) { page(p, "人脸贴纸"); }
void ui_page_doodle(lv_obj_t *p) { page(p, "简笔画识别"); }
void ui_page_helmet(lv_obj_t *p) { page(p, "安全帽检测"); }
void ui_demo_action(unsigned action)
{
    if (!action) ui_data_app_pause(ui_data_session().state != UI_STATE_PAUSED);
    else if (ui_page == 11) {
        invalidate();
        if (action == 1) points_enabled = !points_enabled;
        else { selected = (selected+1)%STICKER_SETS;
               ui_text(sticker_name, sticker_styles[selected].name); }
        for (unsigned i = 0; i < shown.count; ++i)
            lv_obj_set_hidden(tags[i], !points_enabled);
        invalidate();
    }
    else if (ui_page == 12) ui_data_doodle_adjust(action == 1 ? -8 : 8);
}
void ui_demo_update(void)
{
    ui_vision_t stats = ui_data_vision();
    const ui_demo_t *d = ui_data_demo();
    bool fresh = ui_page == 11 && revision != sticker_revision;
    if (fresh || memcmp(&shown, d, sizeof shown)) {
        invalidate(); shown = *d;
        if (ui_page == 11) {
            static sticker_detection_t detections[100];
            for (unsigned i = 0; i < d->count; ++i)
                for (unsigned k = 0; k < 5; ++k)
                    detections[i].points[k] = (sticker_point_t){
                        (int)d->points[i][k].x, (int)d->points[i][k].y};
            unsigned now = lv_tick_get();
            unsigned ms = now-frame_tick;
            sticker_step(&stickers, detections, d->count, ms);
            frame_tick = now; revision = sticker_revision;
        }
        for (unsigned i = 0; i < 100; ++i) {
            lv_obj_set_hidden(tags[i], i >= shown.count || (ui_page == 11 && !points_enabled));
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
