/* page_games.c — showcase design §4.3; portrait covers and build-time entries; no ROM access.
 * One linear group scrolls through the game grid on the UI thread.
 */
#include "widgets.h"
void ui_page_games(lv_obj_t *p)
{
    unsigned count;
    const ui_game_t *games = ui_data_games(&count);
    ui_page_layout(p,"经典游戏",false);
    ui_hint("← → 选择    Enter 确认    Esc 返回    游戏中按返回退出");
    if(ui_game_active()) {
        lv_obj_t *card=ui_panel(p,LV_PCT(100));
        ui_text_label(card,games[ui_mode].name,&sim_font_28,TEXT);
        ui_text_label(card,LV_SYMBOL_PLAY,&sim_font_40,ACCENT);
        ui_text_label(card,"游戏画面预览 · 按返回键回到游戏列表",&sim_font_20,MUTED);
        return;
    }
    lv_obj_t *grid=ui_stack(p,LV_FLEX_FLOW_ROW_WRAP,UI_SPACE_SM);
    lv_obj_set_flex_grow(grid,1);
    lv_obj_set_scrollable(grid,true); lv_obj_set_scroll_dir(grid,LV_DIR_VER);
    for(unsigned i=0;i<count;++i) {
        lv_obj_t *card=ui_action_button(grid,"",i); lv_obj_clean(card);
        lv_obj_set_size(card,LV_PCT(15),248);
        lv_obj_set_flex_flow(card,LV_FLEX_FLOW_COLUMN);
        lv_obj_set_style_pad_all(card,UI_SPACE_SM,0);
        const lv_image_dsc_t *cover=games[i].cover;
        if(cover) {
            lv_obj_t *image=lv_image_create(card); lv_image_set_src(image,cover);
            lv_obj_set_size(image,120,160);
            lv_image_set_inner_align(image,LV_IMAGE_ALIGN_CONTAIN);
        } else {
            lv_obj_t *placeholder=ui_panel(card,120); lv_obj_set_height(placeholder,160);
            lv_obj_set_style_bg_color(placeholder,lv_color_hex(SELECTED),0);
            const lv_image_dsc_t *bitmap=ui_data_game_initial(i);
            if(bitmap) {
                lv_obj_t *initial=lv_image_create(placeholder); lv_image_set_src(initial,bitmap);
            } else ui_text_label(placeholder,games[i].initial,&sim_font_40,ACCENT);
        }
        const lv_image_dsc_t *name=ui_data_game_name(i);
        if(name) {
            lv_obj_t *image=lv_image_create(card); lv_image_set_src(image,name);
            lv_obj_set_style_image_recolor(image,lv_color_hex(TEXT),0);
            lv_obj_set_style_image_recolor_opa(image,LV_OPA_COVER,0);
        } else {
            lv_obj_t *label=ui_text_label(card,games[i].name,&sim_font_20,TEXT);
            lv_obj_set_width(label,LV_PCT(100));
            lv_obj_set_style_text_align(label,LV_TEXT_ALIGN_CENTER,0);
        }
    }
}
