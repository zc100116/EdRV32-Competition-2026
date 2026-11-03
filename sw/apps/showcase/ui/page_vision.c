/* page_vision.c — showcase design 4.6.1; full-screen L0 with L1 detection objects.
 * Only result and statistic changes invalidate L1; video frames bypass LVGL.
 */
#include "theme.h"
static lv_obj_t *boxes[5];
static lv_obj_t *tags[5];
static lv_obj_t *metrics[4];
static lv_obj_t *counts[5];
static lv_obj_t *confidence[5];
static lv_obj_t *bars[5];
static lv_obj_t *image_status;
static lv_obj_t *pause_label;
static lv_obj_t *box_label;
static lv_obj_t *filter_label;
static lv_obj_t *previous_button, *next_button, *box_switch;
static void boxes_changed(lv_event_t *e)
{ (void)e; ui_data_boxes(); ui_refresh(); }
void ui_vision_build(lv_obj_t *p, bool batch)
{
    ui_video_surface(p);
    ui_label(p, batch ? "图片识别" : "实时视觉", 24, 12, &sim_font_28, TEXT);
    filter_label=ui_label(p,"",250,22,&sim_font_14,MUTED);
    lv_obj_t *frame = ui_box(lv_screen_active(), 0, 0, 1280, 720, BG);
    lv_obj_set_style_bg_opa(frame, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(frame, 0, 0);
    lv_obj_move_to_index(frame, 0);
    for(unsigned i = 0; i < 5; ++i) {
        boxes[i] = ui_box(frame, 0, 0, 1, 1, PANEL);
        lv_obj_set_style_bg_opa(boxes[i], LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_color(boxes[i], lv_color_hex(TEAL), 0);
        lv_obj_set_style_border_width(boxes[i], 2, 0);
        lv_obj_set_style_radius(boxes[i], 0, 0);
        tags[i] = ui_label(frame, "", 0, 0, &sim_font_14, PANEL);
        lv_obj_set_style_bg_color(tags[i], lv_color_hex(TEAL), 0);
        lv_obj_set_style_bg_opa(tags[i], LV_OPA_COVER, 0);
    }
    lv_obj_t *side = ui_box(p, 992, 56, 272, 540, PANEL);
    lv_obj_set_style_bg_opa(side, LV_OPA_80, 0);
    if(batch) {
        ui_label(side, "目标列表", 20, 18, &sim_font_20, TEXT);
        for(unsigned i = 0; i < 5; ++i) {
            int y = 62 + (int)i * 36;
            counts[i] = ui_label(side, "", 20, y, &sim_font_16, TEXT);
            confidence[i] = ui_label(side, "", 182, y, &sim_font_16, TEXT);
            lv_obj_set_width(confidence[i], 70);
            lv_obj_set_style_text_align(confidence[i], LV_TEXT_ALIGN_RIGHT, 0);
        }
        ui_label(side, "当前图片", 20, 282, &sim_font_20, TEXT);
        image_status = ui_label(side, "", 20, 328, &sim_font_16, MUTED);
        lv_obj_set_width(image_status,232);
    } else {
        const char *titles[] = {"识别帧率", "NPU / 每帧", "后处理", "端到端延迟"};
        for(unsigned i = 0; i < 4; ++i) {
            ui_label(side, titles[i], 20, 18 + (int)i * 67, &sim_font_14, MUTED);
            metrics[i] = ui_label(side, "", 20, 38 + (int)i * 67, &sim_font_28, ACCENT);
        }
        ui_label(side, "类别分布", 20, 294, &sim_font_20, TEXT);
        const char *categories[] = {"行人", "汽车", "自行车", "公交车", "交通灯"};
        for(unsigned i = 0; i < 5; ++i) {
            int y = 334 + (int)i * 37;
            ui_label(side, categories[i], 20, y, &sim_font_14, MUTED);
            counts[i] = ui_label(side, "", 224, y, &sim_font_14, TEXT);
            bars[i] = ui_box(side, 20, y + 24, 1, 5, ACCENT);
            lv_obj_set_style_border_width(bars[i], 0, 0);
        }
    }
    ui_button(p, batch ? "上一张" : "暂停画面", 614, 6, 160, 0);
    previous_button=lv_obj_get_child(p,-1);
    pause_label = lv_obj_get_child(previous_button, 0);
    if(batch) {
        ui_button(p,"下一张",790,6,186,1);
        next_button=lv_obj_get_child(p,-1);
    } else {
        box_label=ui_label(p,"检测框",790,17,&sim_font_16,TEXT);
        box_switch=ui_switch(p,918,14);
        lv_obj_add_event_cb(box_switch,boxes_changed,LV_EVENT_VALUE_CHANGED,NULL);
    }
    ui_button(p,"检测设置",992,6,272,2);
}
void ui_vision_frame(bool batch)
{
    ui_vision_t d=ui_data_vision();
    char s[200];
    for(unsigned i = 0; i < 5; ++i) {
        bool show = i < d.count && d.boxes && (!batch || d.image_status==UI_IMAGE_DONE);
        lv_obj_set_hidden(boxes[i], !show);
        lv_obj_set_hidden(tags[i], !show);
        if(show) {
            ui_detection_t t = d.targets[i];
            lv_obj_set_pos(boxes[i], t.x, t.y);
            lv_obj_set_size(boxes[i], t.width, t.height);
            lv_snprintf(s, sizeof(s), "%s %u%%", t.category, t.confidence);
            ui_text(tags[i], s);
            lv_obj_set_pos(tags[i], t.x, t.y < 22 ? 0 : t.y - 22);
        }
    }
}
void ui_vision_update(bool batch)
{
    ui_vision_t d = ui_data_vision();
    char s[200];
    ui_detection_config_t config=ui_data_detection_config();
    unsigned selected=0;
    for(unsigned i=0;i<80;++i) selected+=(config.classes[i/32]>>(i%32))&1u;
    lv_snprintf(s,sizeof(s),"≥%u.%02u · %u 类",config.threshold/100,
        config.threshold%100,selected); ui_text(filter_label,s);
    ui_vision_frame(batch);
    if(batch) {
        bool busy=d.image_status==UI_IMAGE_RECEIVING || d.image_status==UI_IMAGE_DETECTING;
        lv_obj_set_state(previous_button,LV_STATE_DISABLED,busy);
        lv_obj_set_state(next_button,LV_STATE_DISABLED,busy);
        lv_group_t *g=lv_group_get_default();
        lv_obj_t *focus=lv_group_get_focused(g);
        if(busy && (focus==previous_button || focus==next_button)) lv_group_focus_next(g);
        for(unsigned i = 0; i < 5; ++i) {
            bool available = i < d.count && (!batch || d.image_status==UI_IMAGE_DONE);
            ui_text(counts[i], available ? d.targets[i].category : "—");
            if(available) lv_snprintf(s, sizeof(s), "%u%%", d.targets[i].confidence);
            else lv_snprintf(s, sizeof(s), "—");
            ui_text(confidence[i], s);
        }
        const char *states[]={"等待","接收中","识别中","完成","失败"};
        lv_snprintf(s,sizeof s,"%s\n\n%u / %u 张 · %s\n\n往返时间  %u ms",
            d.image_name,d.image_index,d.image_total,states[d.image_status],d.roundtrip_ms);
        ui_text(image_status, s);
    } else {
        ui_text(pause_label, ui_data_session().state==UI_STATE_PAUSED ? "继续画面" : "暂停画面");
        lv_obj_set_state(box_switch,LV_STATE_CHECKED,d.boxes);
        lv_snprintf(s, sizeof(s), "%u fps", d.fps); ui_text(metrics[0], s);
        lv_snprintf(s, sizeof(s), "%u.%u ms", d.npu_tenths / 10, d.npu_tenths % 10);
        ui_text(metrics[1], s);
        lv_snprintf(s, sizeof(s), "%u.%u ms", d.post_tenths / 10, d.post_tenths % 10);
        ui_text(metrics[2], s);
        lv_snprintf(s, sizeof(s), "%u.%u ms", d.latency_tenths/10, d.latency_tenths%10);
        ui_text(metrics[3], s);
        for(unsigned i = 0; i < 5; ++i) {
            lv_snprintf(s, sizeof(s), "%u", d.category_count[i]); ui_text(counts[i], s);
            int width = 1 + (int)d.category_count[i] * 40;
            if(lv_obj_get_width(bars[i]) != width) lv_obj_set_width(bars[i], width);
        }
    }
}
void ui_page_vision(lv_obj_t *p) { ui_vision_build(p, false); }
