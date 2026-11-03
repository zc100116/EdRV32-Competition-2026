/* page_vision.c — showcase design §4.3; 960x540 camera and detections.
 * Persistent image and labels; 1 Hz boxes, 2 Hz statistics on LVGL clock.
 */
#include "theme.h"
static lv_obj_t *picture;
static lv_obj_t *boxes[5];
static lv_obj_t *tags[5];
static lv_obj_t *metrics[4];
static lv_obj_t *counts[5];
static lv_obj_t *confidence[5];
static lv_obj_t *bars[5];
static lv_obj_t *batch_status;
static lv_obj_t *pause_label;
static lv_obj_t *box_label;
static lv_obj_t *filter_label;
static const lv_image_dsc_t *last_image;
void ui_vision_build(lv_obj_t *p, bool batch)
{
    ui_vision_t d = ui_data_vision(batch);
    ui_label(p, batch ? "图片识别" : "实时视觉", 24, 12, &sim_font_28, TEXT);
    ui_label(p, "YOLO · 目标检测", 204, 22, &sim_font_14, MUTED);
    filter_label=ui_label(p,"",360,22,&sim_font_14,MUTED);
    lv_obj_t *frame = ui_box(p, 16, 56, 960, 540, BG);
    lv_obj_set_style_border_width(frame, 0, 0);
    lv_obj_set_style_radius(frame, 0, 0);
    ui_picture(frame, d.image, 0, 0, 960, 540);
    picture = lv_obj_get_child(frame, -1);
    last_image = d.image;
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
    if(batch) {
        ui_label(side, "目标列表", 20, 18, &sim_font_20, TEXT);
        for(unsigned i = 0; i < 5; ++i) {
            int y = 62 + (int)i * 36;
            counts[i] = ui_label(side, "", 20, y, &sim_font_16, TEXT);
            confidence[i] = ui_label(side, "", 182, y, &sim_font_16, TEXT);
            lv_obj_set_width(confidence[i], 70);
            lv_obj_set_style_text_align(confidence[i], LV_TEXT_ALIGN_RIGHT, 0);
        }
        ui_label(side, "批量进度", 20, 282, &sim_font_20, TEXT);
        batch_status = ui_label(side, "", 20, 328, &sim_font_16, MUTED);
    } else {
        const char *titles[] = {"识别帧率", "NPU / 每帧", "后处理", "目标总数"};
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
    ui_button(p, batch ? "停止批量" : "暂停画面", 614, 6, 160, 0);
    pause_label = lv_obj_get_child(lv_obj_get_child(p, -1), 0);
    ui_button(p, batch ? "切回摄像头识别" : "检测框：开启", 790, 6, 186, 1);
    box_label = lv_obj_get_child(lv_obj_get_child(p, -1), 0);
    ui_button(p,"检测设置",992,6,272,2);
}
void ui_vision_frame(bool batch)
{
    ui_vision_t d=ui_data_vision(batch);
    char s[200];
    if(d.image != last_image) { lv_image_set_src(picture, d.image); last_image = d.image; }
    for(unsigned i = 0; i < 5; ++i) {
        bool show = i < d.count && d.boxes && !d.waiting;
        lv_obj_set_hidden(boxes[i], !show);
        lv_obj_set_hidden(tags[i], !show);
        if(show) {
            ui_detection_t t = d.targets[i];
            lv_obj_set_pos(boxes[i], t.x, t.y);
            lv_obj_set_size(boxes[i], t.width, t.height);
            lv_snprintf(s, sizeof(s), "%s %u%%", t.category, t.confidence);
            ui_text(tags[i], s);
            lv_obj_set_pos(tags[i], t.x, t.y - 22);
        }
    }
}
void ui_vision_update(bool batch)
{
    ui_vision_t d = ui_data_vision(batch);
    char s[200];
    ui_detection_config_t config=ui_data_detection_config();
    unsigned selected=0;
    for(unsigned i=0;i<80;++i) selected+=(config.classes[i/32]>>(i%32))&1u;
    lv_snprintf(s,sizeof(s),"≥%u.%02u · %u 类",config.threshold/100,
        config.threshold%100,selected); ui_text(filter_label,s);
    ui_vision_frame(batch);
    if(batch) {
        for(unsigned i = 0; i < 5; ++i) {
            bool available = i < d.count && !d.waiting;
            ui_text(counts[i], available ? d.targets[i].category : "—");
            if(available) lv_snprintf(s, sizeof(s), "%u%%", d.targets[i].confidence);
            else lv_snprintf(s, sizeof(s), "—");
            ui_text(confidence[i], s);
        }
        if(d.waiting) lv_snprintf(s, sizeof(s), "等待 PC 发送图片\n\n通过网口上传图片\n即可开始识别");
        else lv_snprintf(s, sizeof(s), "第 %u / %u 张\n\n成功 %u    失败 %u\n\n平均往返 %u ms",
            d.batch_index, d.batch_total, d.success, d.failed, d.roundtrip);
        ui_text(batch_status, s);
    } else {
        ui_text(pause_label, d.paused ? "继续画面" : "暂停画面");
        ui_text(box_label, d.boxes ? "检测框：开启" : "检测框：关闭");
        lv_snprintf(s, sizeof(s), "%u fps", d.fps); ui_text(metrics[0], s);
        lv_snprintf(s, sizeof(s), "%u.%u ms", d.npu_tenths / 10, d.npu_tenths % 10);
        ui_text(metrics[1], s);
        lv_snprintf(s, sizeof(s), "%u.%u ms", d.post_tenths / 10, d.post_tenths % 10);
        ui_text(metrics[2], s);
        lv_snprintf(s, sizeof(s), "%u", d.count); ui_text(metrics[3], s);
        for(unsigned i = 0; i < 5; ++i) {
            lv_snprintf(s, sizeof(s), "%u", d.category_count[i]); ui_text(counts[i], s);
            int width = 1 + (int)d.category_count[i] * 40;
            if(lv_obj_get_width(bars[i]) != width) lv_obj_set_width(bars[i], width);
        }
    }
}
void ui_page_vision(lv_obj_t *p) { ui_vision_build(p, false); }
