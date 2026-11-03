/* page_chip.c — showcase design §4.3; SoC topology and CoreMark card.
 * Rectangles and orthogonal connectors only; UI thread, LVGL tick clock.
 */
#include "theme.h"
static lv_obj_t *score;
static lv_obj_t *per_mhz;
static lv_obj_t *progress;
static void wire(lv_obj_t *p, int x, int y, int w, int h)
{
    lv_obj_t *o = ui_box(p, x, y, w, h, LINE);
    lv_obj_set_style_border_width(o, 0, 0);
    lv_obj_set_style_radius(o, 0, 0);
}
static void module(lv_obj_t *p, const char *name, int x, int y, int w, unsigned mask)
{
    bool present = (ui_data_hardware() & mask) == mask;
    lv_obj_t *o = ui_box(p, x, y, w, 46, present ? SELECTED : DISABLED);
    ui_label(o, name, 12, 12, &sim_font_16, present ? ACCENT : MUTED);
}
void ui_page_chip(lv_obj_t *p)
{
    ui_title(p, "芯片信息", "自主设计的 RISC-V 边缘视觉系统");
    lv_obj_t *diagram = ui_box(p, 40, 124, 710, 484, PANEL);
    ui_label(diagram, "EdRV32 SoC", 24, 18, &sim_font_28, TEXT);
    wire(diagram, 83, 140, 2, 260);
    wire(diagram, 83, 140, 542, 2);
    wire(diagram, 623, 140, 2, 260);
    wire(diagram, 353, 110, 2, 322);
    wire(diagram, 83, 297, 542, 2);
    module(diagram, "CPU", 285, 65, 140, 0);
    module(diagram, "I$", 184, 116, 100, 0);
    module(diagram, "D$", 426, 116, 100, 0);
    module(diagram, "sys_xbar", 268, 187, 174, 0);
    module(diagram, "SRAM", 24, 187, 130, 0);
    module(diagram, "ROM", 556, 187, 130, 0);
    module(diagram, "mem_xbar", 268, 273, 174, 0);
    module(diagram, "DDR3", 268, 368, 174, 0);
    const char *names[] = {"VIN", "PIX", "GEO", "DISP", "RND", "NPU", "ETH", "UART"};
    unsigned masks[] = {UI_VIN, UI_PIX, UI_GEO, UI_DISP, UI_RND, UI_NPU, UI_ETH, 0};
    for(unsigned i = 0; i < 8; ++i) {
        int x = i < 4 ? 24 : 556;
        int y = 240 + (int)(i % 4) * 50;
        module(diagram, names[i], x, y, 130, masks[i]);
    }
    ui_label(diagram, "PG2L200H  ·  160K LUT / 415 DRM / 740 APM", 24, 442,
        &sim_font_16, MUTED);
    lv_obj_t *params = ui_box(p, 774, 124, 466, 262, PANEL);
    ui_label(params, "芯片参数", 24, 18, &sim_font_20, TEXT);
    ui_label(params, "CPU    顺序双发射 RV32 · 100 MHz\n\n"
        "I$ / D$    各 8 KiB    SRAM 64 KiB\n\n"
        "NPU    每拍 512 次乘加 @150 MHz\n\n"
        "DDR3    32 位 · 1000 MT/s\n\n显示    1280×720 @60 Hz",
        24, 60, &sim_font_16, TEXT);
    lv_obj_t *card = ui_box(p, 774, 406, 466, 202, PANEL);
    ui_label(card, "CoreMark", 24, 18, &sim_font_20, TEXT);
    score = ui_label(card, "", 24, 54, &sim_digits_40, ACCENT);
    per_mhz = ui_label(card, "", 216, 70, &sim_font_16, MUTED);
    progress = ui_label(card, "", 24, 115, &sim_font_14, MUTED);
    ui_button(card, "运行 CoreMark", 24, 148, 210, 0);
}
void ui_chip_update(void)
{
    ui_coremark_t d = ui_data_coremark();
    char s[100];
    if(d.score_tenths) lv_snprintf(s, sizeof(s), "%u.%u", d.score_tenths / 10,
        d.score_tenths % 10);
    else lv_snprintf(s, sizeof(s), "--");
    ui_text(score, s);
    if(d.score_tenths) lv_snprintf(s, sizeof(s), "%u.%03u\nCoreMark/MHz",
        d.per_mhz_thousandths / 1000, d.per_mhz_thousandths % 1000);
    else lv_snprintf(s, sizeof(s), "CoreMark/MHz");
    ui_text(per_mhz, s);
    if(d.running) lv_snprintf(s, sizeof(s), "正在运行 · %u%%", d.progress);
    else lv_snprintf(s, sizeof(s), "%s", d.score_tenths ? "运行完成" : "按确认开始跑分");
    ui_text(progress, s);
}
