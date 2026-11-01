/* File: menu.c
 * Spec: Task B3-3b C; SoC 1.2 S3.
 * Description: Five applications, keyboard selection and a persistent control legend.
 * Clock domain: clk_sys CPU.
 */
#include "menu.h"
#include "s3_platform.h"
#include "lvgl.h"

static lv_obj_t *cards[S3_APP_COUNT];
static unsigned int selected;
static enum s3_application requested = S3_APP_NONE;

static lv_obj_t *label(lv_obj_t *parent, const char *text, int32_t x, int32_t y,
                       uint32_t color)
{
    lv_obj_t *object = lv_label_create(parent);
    lv_label_set_text(object, text);
    lv_obj_set_pos(object, x, y);
    lv_obj_set_style_text_color(object, lv_color_hex(color), 0);
    return object;
}

static void style_card(lv_obj_t *card, bool active)
{
    lv_obj_set_style_bg_color(card, lv_color_hex(active ? 0x193c47 : 0x142535), 0);
    lv_obj_set_style_border_color(card, lv_color_hex(active ? 0x71e8bb : 0x294355), 0);
    lv_obj_set_style_border_width(card, active ? 3 : 1, 0);
}

static void select_card(void)
{
    for (unsigned int i = 0; i < S3_APP_COUNT; ++i) style_card(cards[i], i == selected);
}

static void card_event(lv_event_t *event)
{
    unsigned int index = (unsigned int)(uintptr_t)lv_event_get_user_data(event);
    lv_event_code_t code = lv_event_get_code(event);
    /* Refocus during deletion runs after earlier cards have been freed.
     * Update only the event's live target, never its siblings in cards[].
     */
    style_card(lv_event_get_current_target(event), code != LV_EVENT_DEFOCUSED);
    if (code == LV_EVENT_DEFOCUSED) return;
    selected = index;
    if (code == LV_EVENT_CLICKED) requested = (enum s3_application)index;
}

void s3_menu_show(void)
{
    static const char *titles[] = {
        "01   AMBER RUN", "02   LVGL WIDGETS", "03   BENCHMARK", "04   RN-17 COMPARE",
        "05   LAYERS"
    };
    static const char *descriptions[] = {
        "Run, jump and collect.\nA four-screen platform adventure.",
        "Explore the LVGL widget gallery.\nControls, charts and typography.",
        "Run the LVGL benchmark scenes.\nScene and average frame rates on UART.",
        "Render one frame with both engines.\nPixel difference statistics on UART.",
        "DISP overlays and LVGL layers.\nFive visual checks with UART guidance."
    };
    requested = S3_APP_NONE;
    lv_obj_t *screen = lv_screen_active();
    lv_obj_clean(screen);
    lv_obj_remove_style_all(screen);
    lv_obj_set_style_bg_color(screen, lv_color_hex(0x0b1725), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_set_scrollable(screen, false);
    label(screen, "EdRV32  /  S3", 64, 42, 0x71e8bb);
    lv_obj_t *title = label(screen, "APPLICATIONS", 64, 84, 0xf2f7fc);
    lv_obj_set_style_text_font(title, &lv_font_montserrat_40, 0);
    label(screen, "Choose an application with KEY1 / KEY2, then press KEY3 to launch.",
          64, 140, 0xa4b9cc);
    for (unsigned int i = 0; i < S3_APP_COUNT; ++i) {
        lv_obj_t *card = lv_obj_create(screen);
        cards[i] = card;
        lv_obj_set_clickable(card, true);
        lv_group_add_obj(lv_group_get_default(), card);
        lv_obj_add_event_cb(card, card_event, LV_EVENT_CLICKED, (void *)(uintptr_t)i);
        lv_obj_add_event_cb(card, card_event, LV_EVENT_FOCUSED, (void *)(uintptr_t)i);
        lv_obj_add_event_cb(card, card_event, LV_EVENT_DEFOCUSED, (void *)(uintptr_t)i);
        lv_obj_remove_style_all(card);
        lv_obj_set_pos(card, 64 + (int32_t)(i % 2u) * 588,
                        184 + (int32_t)(i / 2u) * 128);
        lv_obj_set_size(card, 564, 118);
        lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
        lv_obj_set_style_radius(card, 12, 0);
        lv_obj_set_scrollable(card, false);
        label(card, titles[i], 26, 14, 0xf2f7fc);
        label(card, descriptions[i], 26, 48, 0xb3c7d8);
    }
    select_card();
    lv_group_focus_obj(cards[selected]);
    label(screen, "KEY1  previous     KEY2  next     KEY3  launch     KEY4  back / pause",
          64, 591, 0xe6edf4);
    label(screen, "UART: a / d / w / p     |     In game: left / right / jump / pause",
          64, 625, 0xa4b9cc);
    label(screen, "EdRV32 Competition 2026", 64, 680, 0x708b9f);
}

enum s3_application s3_menu_input(uint32_t pressed)
{
    if (pressed & S3_KEY_LEFT) {
        selected = (selected + S3_APP_COUNT - 1u) % S3_APP_COUNT;
        select_card();
    }
    if (pressed & S3_KEY_RIGHT) {
        selected = (selected + 1u) % S3_APP_COUNT;
        select_card();
    }
    if (pressed & S3_KEY_JUMP) {
        return (enum s3_application)selected;
    }
    enum s3_application result = requested;
    requested = S3_APP_NONE;
    return result;
}
