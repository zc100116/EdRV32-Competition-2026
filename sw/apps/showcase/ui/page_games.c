/* page_games.c — showcase design §4.3; eight example entries; no ROM access.
 * One linear group scrolls through the game grid on the UI thread.
 */
#include "theme.h"
void ui_page_games(lv_obj_t *p)
{
    unsigned count;
    const ui_game_t *games = ui_data_games(&count);
    ui_title(p, "游戏", "经典像素，小小世界里的无限乐趣");
    ui_hint("← → 选择    Enter 确认    Esc 返回    游戏中按返回两次退出");
    if(ui_game_open) {
        lv_obj_t *card = ui_box(p, 40, 132, 1200, 460, PANEL);
        ui_label(card, games[ui_mode].name, 32, 26, &sim_font_28, TEXT);
        ui_label(card, LV_SYMBOL_PLAY, 548, 146, &sim_font_40, ACCENT);
        ui_label(card, "游戏画面预览", 490, 220, &sim_font_28, MUTED);
        ui_label(card, "按返回键回到游戏列表", 480, 290, &sim_font_20, MUTED);
        return;
    }
    lv_obj_t *grid = ui_box(p, 40, 130, 1200, 470, BG);
    lv_obj_set_style_border_width(grid, 0, 0);
    lv_obj_set_scrollable(grid, true);
    for(unsigned i = 0; i < count; ++i) {
        ui_button(grid, "", (int)(i % 4) * 300, (int)(i / 4) * 234, 280, i);
        lv_obj_t *card = lv_obj_get_child(grid, -1);
        lv_obj_set_height(card, 210);
        uint32_t colors[] = {ACCENT, TEAL, 0x748ca6, 0x526bb4};
        lv_obj_t *icon = ui_box(card, 22, 20, 64, 64, colors[i % 4]);
        lv_obj_set_style_border_width(icon, 0, 0);
        ui_label(icon, games[i].initial, 18, 12, &sim_font_28, PANEL);
        ui_label(card, games[i].name, 22, 108, &sim_font_28, TEXT);
        ui_label(card, "进入游戏  >", 22, 171, &sim_font_14, ACCENT);
    }
}
