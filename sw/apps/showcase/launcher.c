/* File: launcher.c
 * Design: showcase 4.2/4.5.
 * Description: Chinese application gallery, focus/keyboard/pointer navigation.
 * Clock domain: clk_sys.
 */
#include "apps.h"
#include "platform.h"
#include "runtime.h"
#include "lvgl/showcase_lvgl.h"
LV_FONT_DECLARE(showcase_title_24);
LV_FONT_DECLARE(showcase_title_32);
extern const struct app nes_app;
static void no_step(void) {}
static void no_exit(void) {}
static const struct app widgets_app = {
    "组件示例", NULL, APP_HW_RND, 0, showcase_lvgl_start_widgets, no_step, no_exit
};
static const struct app benchmark_app = {
    "性能测试", NULL, APP_HW_RND, 0, showcase_lvgl_start_benchmark, no_step, no_exit
};
static const struct app layers_app = {
    "图层示例", NULL, APP_HW_RND, 1, layers_enter, layers_step, layers_exit
};
static const struct app status_app = {
    "系统状态", NULL, 0, 0, status_enter, status_step, no_exit
};
const struct app *const showcase_apps[] = {
    &nes_app, &widgets_app, &benchmark_app, &layers_app, &status_app
};
const unsigned showcase_app_count = sizeof(showcase_apps) / sizeof(showcase_apps[0]);
static unsigned selected;
static lv_obj_t *cards[sizeof(showcase_apps) / sizeof(showcase_apps[0])];
static lv_obj_t *label(lv_obj_t *parent, const char *text, int x, int y, uint32_t color)
{
    lv_obj_t *object = lv_label_create(parent);
    lv_label_set_text(object, text);
    lv_obj_set_pos(object, x, y);
    lv_obj_set_style_text_color(object, lv_color_hex(color), 0);
    return object;
}
static void style(lv_obj_t *card, bool focused)
{
    lv_obj_set_style_bg_color(card, lv_color_hex(focused ? 0x173d42 : 0x142535), 0);
    lv_obj_set_style_border_color(card, lv_color_hex(focused ? 0x71e8bb : 0x294355), 0);
    lv_obj_set_style_border_width(card, focused ? 3 : 1, 0);
}
static void card_event(lv_event_t *event)
{
    /* Deleting the old screen moves group focus while another app is active. */
    if (!showcase_launcher_active()) return;
    unsigned index = (unsigned)(uintptr_t)lv_event_get_user_data(event);
    lv_event_code_t code = lv_event_get_code(event);
    style(lv_event_get_current_target(event), code != LV_EVENT_DEFOCUSED);
    if (code == LV_EVENT_DEFOCUSED) return;
    selected = index;
    if (code == LV_EVENT_CLICKED) launcher_request(index);
}
void launcher_show(void)
{
    lv_obj_t *screen = lv_screen_active();
    lv_obj_clean(screen);
    lv_obj_remove_style_all(screen);
    lv_obj_set_style_bg_color(screen, lv_color_hex(0x0b1725), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_set_scrollable(screen, false);
    label(screen, "EdRV32  /  2026", 64, 36, 0x71e8bb);
    lv_obj_t *title = label(screen, "芯片演示系统", 64, 80, 0xf2f7fc);
    lv_obj_set_style_text_font(title, &showcase_title_32, 0);
    label(screen, "选择应用，探索自主处理器与图形引擎", 64, 138, 0xa4b9cc);
    static const char *const symbols[] = {
        LV_SYMBOL_PLAY, LV_SYMBOL_LIST, LV_SYMBOL_CHARGE, LV_SYMBOL_IMAGE,
        LV_SYMBOL_SETTINGS
    };
    for (unsigned i = 0; i < showcase_app_count; ++i) {
        const struct app *app = showcase_apps[i];
        lv_obj_t *card = lv_obj_create(screen);
        cards[i] = card;
        lv_obj_remove_style_all(card);
        lv_obj_set_pos(card, 64 + (int)(i % 2u) * 588, 196 + (int)(i / 2u) * 128);
        lv_obj_set_size(card, 564, 112);
        lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
        lv_obj_set_style_radius(card, 12, 0);
        lv_obj_set_scrollable(card, false);
        lv_obj_set_clickable(card, true);
        lv_group_add_obj(lv_group_get_default(), card);
        lv_obj_add_event_cb(card, card_event, LV_EVENT_CLICKED, (void *)(uintptr_t)i);
        lv_obj_add_event_cb(card, card_event, LV_EVENT_FOCUSED, (void *)(uintptr_t)i);
        lv_obj_add_event_cb(card, card_event, LV_EVENT_DEFOCUSED, (void *)(uintptr_t)i);
        if (app->icon) {
            lv_obj_t *icon = lv_image_create(card);
            lv_image_set_src(icon, app->icon);
            lv_obj_set_pos(icon, 24, 24);
        } else {
            lv_obj_t *icon = label(card, symbols[i], 26, 36, 0x71e8bb);
            lv_obj_set_style_text_font(icon, &lv_font_montserrat_24, 0);
        }
        lv_obj_t *name = label(card, app->name, 84, 24, 0xf2f7fc);
        lv_obj_set_style_text_font(name, &showcase_title_24, 0);
        bool available = (app->needs & ~platform_hardware()) == 0;
        label(card, available ? "进入应用" : "硬件未安装", 84, 66, 0xa4b9cc);
        if (!available) {
            lv_obj_add_state(card, LV_STATE_DISABLED);
            lv_obj_set_style_opa(card, LV_OPA_40, 0);
        }
        style(card, i == selected);
    }
    lv_group_focus_obj(cards[selected]);
    label(screen, "按键 1 / 2 选择    按键 3 进入    按键 4 返回", 64, 612, 0xe6edf4);
    label(screen, "支持网口与串口虚拟键盘、鼠标", 64, 646, 0xa4b9cc);
    lv_obj_t *footer = label(screen, "RISC-V  ·  LVGL 9.6  ·  1280 × 720",
                             64, 682, 0x708b9f);
    lv_obj_set_style_text_font(footer, &lv_font_source_han_sans_sc_14_cjk, 0);
}
void launcher_input(uint32_t pressed)
{
    if (pressed & PLATFORM_LEFT) selected = (selected + showcase_app_count - 1u) %
                                                   showcase_app_count;
    if (pressed & PLATFORM_RIGHT) selected = (selected + 1u) % showcase_app_count;
    if (pressed & (PLATFORM_LEFT | PLATFORM_RIGHT)) lv_group_focus_obj(cards[selected]);
    if (pressed & PLATFORM_ENTER) launcher_request(selected);
}
