/* page_graphics.c — showcase design §4.3; benchmark, comparison and layers.
 * Fixed measurement rows supplied by backend; no expensive scene effects.
 */
#include "theme.h"
static lv_obj_t *progress;
void ui_page_graphics(lv_obj_t *p)
{
    ui_title(p, "图形引擎", "高效绘制，让每一帧更从容");
    const char *tabs[] = {"性能测试", "硬件 / 软件对比", "显示图层"};
    for(unsigned i = 0; i < 3; ++i) {
        ui_button(p, tabs[i], 40 + (int)i * 240, 119, 220, i);
        if(ui_tab == i) lv_obj_set_style_bg_color(lv_obj_get_child(p, -1),
            lv_color_hex(SELECTED), 0);
    }
    progress = NULL;
    const ui_benchmark_t *rows = ui_data_benchmark();
    if(ui_tab == 0) {
        for(unsigned col = 0; col < 2; ++col) {
            lv_obj_t *card = ui_box(p, 40 + (int)col * 612, 177, 588, 350, PANEL);
            ui_label(card, "场景", 20, 14, &sim_font_16, MUTED);
            ui_label(card, "每帧 ms", 368, 14, &sim_font_16, MUTED);
            ui_label(card, "fps", 500, 14, &sim_font_16, MUTED);
            for(unsigned r = 0; r < 8; ++r) {
                unsigned n = col * 8 + r;
                int y = 53 + (int)r * 36;
                ui_label(card, rows[n].name, 20, y, &sim_font_16, TEXT);
                char s[40];
                lv_snprintf(s, sizeof(s), "%u.%u", rows[n].ms_tenths / 10,
                    rows[n].ms_tenths % 10);
                ui_label(card, s, 384, y, &sim_font_16, ACCENT);
                lv_snprintf(s, sizeof(s), "%u.%u", rows[n].fps_tenths / 10,
                    rows[n].fps_tenths % 10);
                ui_label(card, s, 500, y, &sim_font_16, TEXT);
            }
        }
        ui_button(p, "开始测试", 40, 548, 180, 3);
        progress = ui_label(p, "", 244, 558, &sim_font_16, MUTED);
    } else if(ui_tab == 1) {
        ui_label(p, "同一场景 · Moving wallpaper", 42, 184, &sim_font_20, TEXT);
        for(unsigned i = 0; i < 2; ++i) {
            lv_obj_t *card = ui_box(p, 40 + (int)i * 430, 230, 406, 244, PANEL);
            ui_label(card, i ? "RND 关闭" : "RND 开启", 28, 24, &sim_font_28, TEXT);
            char s[40];
            unsigned value = i ? rows[1].software_tenths : rows[1].ms_tenths;
            lv_snprintf(s, sizeof(s), "%u.%u", value / 10, value % 10);
            ui_label(card, s, 28, 88, &sim_digits_40, i ? MUTED : ACCENT);
            ui_label(card, "ms / 每帧", 28, 160, &sim_font_16, MUTED);
        }
        lv_obj_t *card = ui_box(p, 900, 230, 340, 244, SELECTED);
        ui_label(card, "加速比", 28, 24, &sim_font_28, TEXT);
        unsigned ratio = rows[1].ms_tenths ? rows[1].software_tenths * 100 / rows[1].ms_tenths : 0;
        char s[40];
        lv_snprintf(s, sizeof(s), "%u.%02u", ratio / 100, ratio % 100);
        ui_label(card, s, 28, 88, &sim_digits_40, ACCENT);
        ui_label(card, "倍 · 相同画面内容", 28, 160, &sim_font_16, MUTED);
        ui_button(p, "开始测试", 40, 548, 180, 3);
    } else {
        ui_button(p, "开始测试", 854, 548, 180, 3);
        lv_obj_t *card = ui_box(p, 40, 182, 770, 410, PANEL);
        ui_label(card, "显示图层预览", 26, 20, &sim_font_20, TEXT);
        lv_obj_t *base = ui_box(card, 28, 72, 520, 284, SELECTED);
        ui_label(base, "L0 · RGB565", 24, 24, &sim_font_28, ACCENT);
        ui_label(base, "基础画面 / 卷轴", 24, 80, &sim_font_20, MUTED);
        lv_obj_t *overlay = ui_box(card, 336, 190, 380, 176, PANEL);
        ui_label(overlay, "L1 · ARGB8888", 24, 24, &sim_font_28, TEAL);
        ui_label(overlay, "叠加画面", 24, 82, &sim_font_20, MUTED);
        ui_label(p, "DISP 双层合成\n\n支持透明叠加、图层移动\n与基础画面卷轴。\n\n板上由显示控制器直接显示。",
            854, 216, &sim_font_20, TEXT);
    }
}
void ui_graphics_update(void)
{
    if(!progress) return;
    char s[80];
    unsigned n = ui_data_benchmark_progress();
    if(n == 16) lv_snprintf(s, sizeof(s), "测试完成 · 16 / 16 个场景");
    else if(n) lv_snprintf(s, sizeof(s), "测试中 · %u / 16 个场景", n);
    else lv_snprintf(s, sizeof(s), "16 个场景 · 按确认开始");
    ui_text(progress, s);
}
