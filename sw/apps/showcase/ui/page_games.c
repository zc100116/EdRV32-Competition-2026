/* page_games.c — showcase design §4.3; portrait covers and build-time entries; no ROM access.
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
        const lv_image_dsc_t *name_image=ui_data_game_name(ui_mode);
        if(name_image) {
            lv_obj_t *name=lv_image_create(card); lv_image_set_src(name,name_image);
            lv_obj_set_pos(name,32,26);
            lv_obj_set_style_image_recolor(name,lv_color_hex(TEXT),0);
            lv_obj_set_style_image_recolor_opa(name,LV_OPA_COVER,0);
        } else ui_label(card, games[ui_mode].name, 32, 26, &sim_font_28, TEXT);
        ui_label(card, LV_SYMBOL_PLAY, 548, 146, &sim_font_40, ACCENT);
        ui_label(card, "游戏画面预览", 490, 220, &sim_font_28, MUTED);
        ui_label(card, "按返回键两次回到游戏列表", 470, 290, &sim_font_20, MUTED);
        return;
    }
    lv_obj_t *grid = ui_box(p, 40, 130, 1200, 458, BG);
    lv_obj_set_style_border_width(grid, 0, 0);
    lv_obj_set_scrollable(grid, true);
    lv_obj_set_scroll_dir(grid, LV_DIR_VER);
    for(unsigned i = 0; i < count; ++i) {
        ui_button(grid, "", (int)(i % 6) * 200, (int)(i / 6) * 234, 184, i);
        lv_obj_t *card = lv_obj_get_child(grid, -1);
        lv_obj_set_height(card, 222);
        if(games[i].cover) ui_picture(card, games[i].cover, 32, 12, 120, 160);
        else {
            uint32_t colors[] = {ACCENT, TEAL, 0x748ca6, 0x526bb4};
            lv_obj_t *cover = ui_box(card, 32, 12, 120, 160, colors[i % 4]);
            lv_obj_set_style_border_width(cover, 0, 0);
            const lv_image_dsc_t *bitmap=ui_data_game_initial(i);
            lv_obj_t *initial;
            if(bitmap) {
                initial=lv_image_create(cover); lv_image_set_src(initial,bitmap);
                lv_obj_set_style_image_recolor(initial,lv_color_hex(PANEL),0);
                lv_obj_set_style_image_recolor_opa(initial,LV_OPA_COVER,0);
            } else initial=ui_label(cover,games[i].initial,0,0,&sim_font_40,PANEL);
            lv_obj_center(initial);
        }
        const lv_image_dsc_t *name_image=ui_data_game_name(i);
        if(name_image) {
            lv_obj_t *name = lv_image_create(card);
            lv_image_set_src(name, name_image);
            lv_obj_set_pos(name, 2, 184);
            lv_obj_set_style_image_recolor(name, lv_color_hex(TEXT), 0);
            lv_obj_set_style_image_recolor_opa(name, LV_OPA_COVER, 0);
            continue;
        }
        lv_obj_t *name = ui_label(card, games[i].name, 12, 184, &sim_font_20, TEXT);
        lv_obj_set_width(name, 160);
        lv_obj_set_style_text_align(name, LV_TEXT_ALIGN_CENTER, 0);
    }
}
