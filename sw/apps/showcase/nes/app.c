/* app.c: showcase design 4.2/4.4/4.5; Chinese game browser and one-frame task.
 * GUI owns the browser; NES owns RND/DISP only while a game is running.
 * Clock domain: clk_sys, deadlines in CLINT mtime ticks.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../app.h"
#include "../platform.h"
#include "display.h"
#include "game_pack.h"

extern const unsigned char __game_pack_start[];
static const struct game_pack_header *pack;
static const struct game_pack_entry *entries;
static const struct game_pack_entry *selected;
static const char *rom_data;
static lv_obj_t *page;
static lv_obj_t **cards;
static lv_image_dsc_t *icons;
static unsigned focus;
static uint32_t previous_keys;
static enum { BROWSER, PLAYING, STOPPING } state;
static uint64_t next_frame;
static uint64_t report_at;
static uint64_t busy_at;
static unsigned frames_at;
static unsigned shown_at;
static unsigned cadence;

char *osd_getromdata(void) { return (char *)rom_data; }
uint64_t nes_ticks(void) { return platform_ticks(); }
uint64_t nes_tick_hz(void) { return platform_clock_hz(); }
uint64_t nes_instructions(void) { return 0; }

unsigned nes_buttons(void)
{
    unsigned buttons = 0;
    uint32_t keys = platform_keys();
    if (keys & PLATFORM_LEFT) buttons |= 1u << 6;
    if (keys & PLATFORM_RIGHT) buttons |= 1u << 7;
    if (keys & PLATFORM_ENTER) buttons |= 1u;
    return nes_merge_virtual(buttons, platform_virtual_input().keys);
}

void nes_frame(const uint8_t *pixels, const struct nes_rgb *palette, unsigned frame)
{
    (void)frame;
    nes_display_frame(pixels, palette);
}

static void choose(lv_event_t *event)
{
    selected = lv_event_get_user_data(event);
    app_wake_at(platform_ticks());
}

static void browser(void)
{
    page = lv_obj_create(lv_screen_active());
    lv_obj_set_size(page, LV_PCT(100), LV_PCT(100));
    lv_obj_set_style_bg_color(page, lv_color_hex(0x101b2b), 0);
    lv_obj_set_style_text_color(page, lv_color_hex(0xf0f4fa), 0);
    lv_obj_set_style_text_font(page, &lv_font_source_han_sans_sc_16_cjk, 0);
    lv_obj_set_flex_flow(page, LV_FLEX_FLOW_COLUMN);
    lv_obj_t *label = lv_label_create(page);
    lv_label_set_text(label, "游戏选择");
    label = lv_label_create(page);
    lv_label_set_text(label, "左右选择 · 确认开始 · 返回退出");
    if (memcmp(pack->magic, "EDGP", 4) != 0) {
        label = lv_label_create(page);
        lv_label_set_text(label, "未打包游戏");
        return;
    }
    if (pack->version != GAME_PACK_VERSION) {
        fprintf(stderr, "Unsupported EDGP version %u\n", pack->version);
        exit(1);
    }
    cards = calloc(pack->count, sizeof(*cards));
    icons = calloc(pack->count, sizeof(*icons));
    if (pack->count && (!cards || !icons)) {
        fputs("NES browser allocation failed\n", stderr);
        exit(1);
    }
    lv_obj_t *grid = lv_obj_create(page);
    lv_obj_set_size(grid, LV_PCT(100), LV_PCT(80));
    lv_obj_set_style_bg_opa(grid, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(grid, 0, 0);
    lv_obj_set_flex_flow(grid, LV_FLEX_FLOW_ROW_WRAP);
    for (unsigned i = 0; i < pack->count; ++i) {
        lv_obj_t *card = lv_button_create(grid);
        cards[i] = card;
        /* Browser navigation belongs to the app task; pointer clicks use LVGL. */
        lv_group_remove_obj(card);
        lv_obj_set_size(card, 192, 144);
        lv_obj_set_style_bg_color(card, lv_color_hex(0x263c55), 0);
        lv_obj_set_style_border_color(card, lv_color_hex(0x64d8cb), LV_STATE_FOCUSED);
        lv_obj_set_style_border_width(card, 3, LV_STATE_FOCUSED);
        lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_flex_align(card, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER,
                             LV_FLEX_ALIGN_CENTER);
        lv_obj_add_event_cb(card, choose, LV_EVENT_CLICKED, (void *)&entries[i]);
        if (entries[i].icon_offset) {
            icons[i].header.magic = LV_IMAGE_HEADER_MAGIC;
            icons[i].header.cf = LV_COLOR_FORMAT_ARGB8888;
            icons[i].header.w = entries[i].icon_width;
            icons[i].header.h = entries[i].icon_height;
            icons[i].header.stride = entries[i].icon_width * 4;
            icons[i].data_size = entries[i].icon_width * entries[i].icon_height * 4;
            icons[i].data = __game_pack_start + entries[i].icon_offset;
            lv_obj_t *image = lv_image_create(card);
            lv_image_set_src(image, &icons[i]);
        }
        label = lv_label_create(card);
        lv_label_set_text(label, entries[i].name);
    }
    focus = 0;
    if (pack->count)
        lv_obj_add_state(cards[0], LV_STATE_FOCUSED);
}

static void destroy_browser(void)
{
    lv_obj_delete(page);
    page = NULL;
    free(cards);
    free(icons);
    cards = NULL;
    icons = NULL;
}

static void enter(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    pack = (const struct game_pack_header *)__game_pack_start;
    entries = (const struct game_pack_entry *)(pack + 1);
    state = BROWSER;
    selected = NULL;
    previous_keys = platform_keys();
    app_gui_pause(0);
    lv_obj_clean(lv_screen_active());
    browser();
    app_wake_at(UINT64_MAX);
}

static void start_game(void)
{
    destroy_browser();
    app_gui_pause(1);
    platform_media_callbacks(nes_display_rnd_irq, nes_display_disp_irq, NULL);
    nes_display_init();
    rom_data = (const char *)__game_pack_start + selected->rom_offset;
    nes_start();
    state = PLAYING;
    next_frame = platform_ticks();
    report_at = next_frame;
    busy_at = app_busy_ticks();
    frames_at = 0;
    shown_at = 0;
    cadence = 0;
}

static void stop_game(void)
{
    nes_display_stop();
    nes_stop();
    state = STOPPING;
}

static void report(uint64_t now)
{
    uint64_t elapsed = now - report_at;
    if (elapsed < platform_clock_hz())
        return;
    uint64_t busy = app_busy_ticks();
    unsigned fps10 = (unsigned)((nes_frames - frames_at) * 10ull * nes_tick_hz() / elapsed);
    unsigned display10 = (unsigned)((nes_shown - shown_at) * 10ull * nes_tick_hz() / elapsed);
    unsigned cpu = (unsigned)((busy - busy_at) * 100 / elapsed);
    printf("NES fps=%u.%u display=%u.%u CPU=%u%%\n", fps10 / 10, fps10 % 10,
           display10 / 10, display10 % 10, cpu);
    report_at = now;
    busy_at = busy;
    frames_at = nes_frames;
    shown_at = nes_shown;
}

static void step(void)
{
    (void)app_events();
    uint32_t keys = platform_keys();
    uint32_t pressed = keys & ~previous_keys;
    previous_keys = keys;
    uint64_t now = platform_ticks();
    if (state == BROWSER) {
        if (pressed & PLATFORM_BACK) {
            app_return();
            return;
        }
        if (cards && pack->count) {
            lv_obj_remove_state(cards[focus], LV_STATE_FOCUSED);
            if (pressed & PLATFORM_LEFT)
                focus = (focus + pack->count - 1) % pack->count;
            if (pressed & PLATFORM_RIGHT)
                focus = (focus + 1) % pack->count;
            lv_obj_add_state(cards[focus], LV_STATE_FOCUSED);
            lv_obj_scroll_to_view(cards[focus], LV_ANIM_OFF);
            if (pressed & PLATFORM_ENTER)
                selected = &entries[focus];
        }
        if (!selected) {
            app_wake_at(UINT64_MAX);
            return;
        }
        start_game();
        now = platform_ticks();
    }
    if (state == PLAYING) {
        nes_display_check();
        if (pressed & PLATFORM_BACK) {
            stop_game();
        } else {
            if (now >= next_frame) {
                nes_step();
                /* Distribute fractional mtime ticks over exactly 60 frame deadlines. */
                uint32_t hz = platform_clock_hz();
                cadence += hz % 60;
                next_frame += hz / 60 + cadence / 60;
                cadence %= 60;
                now = platform_ticks();
                if (next_frame < now)
                    next_frame = now;
            }
            report(now);
            app_wake_at(next_frame);
            return;
        }
    }
    if (nes_display_idle()) {
        platform_media_callbacks(NULL, NULL, NULL);
        app_gui_pause(0);
        selected = NULL;
        state = BROWSER;
        browser();
        app_wake_at(UINT64_MAX);
    } else {
        app_wake_at(platform_ticks() + platform_clock_hz() / 1000);
    }
}

static void leave(void)
{
    if (state == PLAYING)
        stop_game();
    if (page)
        destroy_browser();
    platform_media_callbacks(NULL, NULL, NULL);
}

const struct app nes_app = {
    .name = "NES 游戏", .icon = NULL, .needs = APP_HW_RND, .owns_display = 1,
    .enter = enter, .step = step, .exit = leave
};
