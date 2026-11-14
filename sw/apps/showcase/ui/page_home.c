/* page_home.c — showcase design §4.3; six application entry cards.
 * UI thread; hardware availability comes exclusively from ui_data.
 */
#include "theme.h"
void ui_page_home(lv_obj_t *p)
{
    ui_title(p, "探索芯片的无限可能");
    lv_obj_t *heading = ui_label(p, "应用中心  /  06", 0, 84, &sim_font_16, ACCENT);
    lv_obj_update_layout(heading);
    lv_obj_set_x(heading, 1240 - lv_obj_get_width(heading));
    const char *names[] = {"视觉流水线", "图形引擎", "游戏", "系统监控", "芯片信息",
        "调试助手"};
    const char *icons[] = {LV_SYMBOL_VIDEO, LV_SYMBOL_EDIT, LV_SYMBOL_PLAY,
        LV_SYMBOL_BARS, LV_SYMBOL_SETTINGS, LV_SYMBOL_USB};
    const unsigned pages[] = {1,4,5,6,7,8};
    unsigned required[] = {UI_VIN | UI_NPU, UI_RND | UI_DISP, UI_RND | UI_DISP, 0, 0, 0};
    for(unsigned i = 0; i < 6; ++i) {
        bool enabled = (ui_data_hardware() & required[i]) == required[i];
        ui_button(p, "", 40 + (int)(i % 3) * 408, 133 + (int)(i / 3) * 238, 384, pages[i]);
        lv_obj_t *card = lv_obj_get_child(p, -1);
        lv_obj_set_height(card, 216);
        if(!enabled) lv_obj_add_state(card,LV_STATE_DISABLED);
        uint32_t ink = enabled ? ACCENT : MUTED;
        ui_label(card, icons[i], 24, 22, &sim_font_40, ink);
        ui_label(card, names[i], 24, 89, &sim_font_28, enabled ? TEXT : MUTED);
        if(!enabled) ui_label(card, "当前硬件无此模块", 24, 137, &sim_font_16, MUTED);
    }
}
