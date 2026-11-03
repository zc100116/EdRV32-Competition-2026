/* page_process.c — showcase design §4.3; selectable PIX/GEO previews.
 * The sample remains unchanged; mode is explicitly identified in text.
 */
#include "theme.h"
void ui_page_process(lv_obj_t *p)
{
    ui_title(p, "图像处理", "从像素到几何，探索图像的多种表达");
    const char *modes[] = {"原图", "灰度", "伽马", "边缘", "缩放", "旋转", "镜像"};
    ui_picture(p, ui_data_process(), 40, 133, 918, 459);
    lv_obj_t *tag = ui_box(p, 60, 150, 190, 42, PANEL);
    ui_label(tag, modes[ui_mode], 18, 9, &sim_font_20, ACCENT);
    lv_obj_t *side = ui_box(p, 982, 133, 258, 459, PANEL);
    ui_label(side, "PIX · 像素处理", 20, 16, &sim_font_20, TEXT);
    for(unsigned i = 0; i < 7; ++i) {
        if(i == 4) ui_label(side, "GEO · 几何变换", 20, 263, &sim_font_20, TEXT);
        int y = i < 4 ? 54 + (int)i * 49 : 303 + (int)(i - 4) * 49;
        char s[80];
        lv_snprintf(s, sizeof(s), "%s%s", modes[i], ui_mode == i ? "  · 当前模式" : "");
        ui_button(side, s, 20, y, 218, i);
    }
}
