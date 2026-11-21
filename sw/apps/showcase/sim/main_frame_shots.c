/* main_frame_shots.c — R4 §4/5; native LVGL entry checks and framebuffer captures.
 * Host clock timings include software rendering and RGB565 output composition.
 */
#include "theme.h"
#include "sim_data.h"
#include "motion.h"
#include "grab.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static uint16_t framebuffer[1280*720];
static uint32_t drawbuffer[1280*720];
static const char *output;
static uint64_t host_ns(void)
{
    struct timespec time;
    timespec_get(&time,TIME_UTC);
    return (uint64_t)time.tv_sec*1000000000u+time.tv_nsec;
}
static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    const uint32_t *source = (const uint32_t *)pixels;
    const lv_image_dsc_t *background = sim_l0_image();
    for (int y = area->y1; y <= area->y2; ++y)
        for (int x = area->x1; x <= area->x2; ++x) {
            uint32_t c = sim_composite(background,*source++,(unsigned)x,(unsigned)y);
            framebuffer[y*1280+x] = (uint16_t)(((c >> 8)&0xf800) |
                ((c >> 5)&0x07e0) | ((c >> 3)&31));
        }
    lv_display_flush_ready(display);
}
static void check_labels(lv_obj_t *parent)
{
    if (lv_obj_is_hidden(parent)) return;
    if (lv_obj_check_type(parent,&lv_label_class)) {
        const unsigned char *text = (const unsigned char *)lv_label_get_text(parent);
        const lv_font_t *font = lv_obj_get_style_text_font(parent,0);
        while (*text) {
            unsigned code = *text++;
            if (code >= 0xc0) {
                unsigned n = code >= 0xf0 ? 3 : code >= 0xe0 ? 2 : 1;
                code &= (1u << (6-n))-1;
                while (n--) code = (code << 6) | (*text++ & 0x3f);
            }
            if (code == '\n') continue;
            lv_font_glyph_dsc_t glyph;
            if (!lv_font_get_glyph_dsc(font,&glyph,code,0) || glyph.is_placeholder) {
                fprintf(stderr,"Missing glyph U+%04X in %s\n",code,lv_label_get_text(parent));
                exit(EXIT_FAILURE);
            }
        }
    }
    for (unsigned i = 0; i < lv_obj_get_child_count(parent); ++i)
        check_labels(lv_obj_get_child(parent,(int)i));
}
static void capture(const char *name)
{
    lv_tick_inc(200);
    ui_refresh();
    lv_obj_update_layout(lv_screen_active());
    lv_obj_invalidate(lv_screen_active());
    uint64_t start = host_ns();
    lv_refr_now(NULL);
    printf("frame %s draw_us=%llu\n",name,(unsigned long long)((host_ns()-start)/1000));
    check_labels(lv_screen_active());
    char path[1024];
    snprintf(path,sizeof path,"%s/%s.rgb565",output,name);
    FILE *file = fopen(path,"wb");
    if (!file) { perror(path); exit(EXIT_FAILURE); }
    assert(fwrite(framebuffer,sizeof framebuffer,1,file) == 1);
    assert(fclose(file) == 0);
}
static lv_obj_t *find_widget(lv_obj_t *parent, const lv_obj_class_t *type)
{
    if (lv_obj_check_type(parent,type)) return parent;
    for (unsigned i = 0; i < lv_obj_get_child_count(parent); ++i) {
        lv_obj_t *found = find_widget(lv_obj_get_child(parent,(int)i),type);
        if (found) return found;
    }
    return NULL;
}
static void entries(void)
{
    lv_obj_update_layout(lv_screen_active());
    lv_obj_t *tabs = find_widget(lv_screen_active(),&lv_tabview_class);
    lv_obj_t *pages = lv_tabview_get_content(tabs);
    const unsigned counts[] = {7,6,3,4};
    for (unsigned tab = 0; tab < 4; ++tab) {
        lv_obj_t *page = lv_obj_get_child(pages,(int)tab);
        assert(lv_obj_get_width(page) == lv_obj_get_content_width(pages));
        assert(lv_obj_get_child_count(page) == counts[tab]);
    }
    lv_obj_t *visited[22];
    for (unsigned i = 0; i < 22; ++i) {
        visited[i] = lv_group_get_focused(lv_group_get_default());
        for (unsigned j = 0; j < i; ++j) assert(visited[j] != visited[i]);
        if (i >= 2) assert(ui_home_tab() == (i < 9 ? 0 : i < 15 ? 1 : i < 18 ? 2 : 3));
        ui_key(LV_KEY_NEXT);
        assert(lv_obj_has_state(lv_group_get_focused(lv_group_get_default()),
                                LV_STATE_FOCUS_KEY));
    }
    assert(lv_group_get_focused(lv_group_get_default()) == visited[0]);
    ui_key(LV_KEY_PREV);
    assert(ui_home_tab() == 3);
    ui_key(LV_KEY_NEXT);
    for (unsigned game = 1; game <= 5; ++game) {
        ui_activate(100+game);
        assert(ui_page == MOTION_PAGE && ui_motion.game == game);
        assert(ui_motion.waiting == (game >= MOTION_MOLE));
        ui_key(LV_KEY_ESC);
        assert(ui_page == 0 && ui_home_tab() == 1);
    }
    ui_activate(16);
    lv_obj_t *spin = find_widget(lv_screen_active(),&lv_spinbox_class);
    assert(spin);
    lv_obj_t *selector = find_widget(lv_screen_active(),&lv_buttonmatrix_class);
    lv_buttonmatrix_set_selected_button(selector,1);
    lv_obj_send_event(selector,LV_EVENT_VALUE_CHANGED,NULL);
    assert(lv_spinbox_get_value(spin) == 35);
    lv_buttonmatrix_set_selected_button(selector,2);
    lv_obj_send_event(selector,LV_EVENT_VALUE_CHANGED,NULL);
    assert(lv_obj_has_state(spin,LV_STATE_DISABLED));
    lv_buttonmatrix_set_selected_button(selector,0);
    lv_buttonmatrix_set_button_ctrl(selector,0,LV_BUTTONMATRIX_CTRL_CHECKED);
    lv_obj_send_event(selector,LV_EVENT_VALUE_CHANGED,NULL);
    assert(lv_spinbox_get_value(spin) == 25);
    lv_group_focus_obj(spin);
    int before = lv_spinbox_get_value(spin);
    ui_key(LV_KEY_ENTER);
    ui_key(LV_KEY_NEXT);
    assert(lv_spinbox_get_value(spin) == before+5);
    ui_key(LV_KEY_ESC);
    ui_key(LV_KEY_ESC);
    assert(ui_page == 0);
    ui_activate(14);
    assert(ui_grab.thresholds[0] == before+5);
    ui_key(LV_KEY_ESC);
    ui_activate(16);
    spin = find_widget(lv_screen_active(),&lv_spinbox_class);
    assert(lv_spinbox_get_value(spin) == before+5);
    /* Restore the default value for the review capture. */
    lv_spinbox_set_value(spin,before);
    ui_key(LV_KEY_ESC);
    puts("PASS: 22 cards, cross-tab four-key focus, five direct games, settings persistence");
}
int main(int argc, char **argv)
{
    assert(argc == 2);
    output = argv[1];
    lv_init();
    lv_display_t *display = lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init();
    ui_start();
    entries();
    const char *const names[] = {"home-ai","home-motion","home-media","home-system"};
    for (unsigned tab = 0; tab < 4; ++tab) {
        ui_home_select_tab(tab);
        ui_home_focus();
        capture(names[tab]);
    }
    ui_activate(16);
    capture("settings");
    ui_back();
    ui_activate(103);
    extern const lv_image_dsc_t sim_indoor;
    ui_demo_t demo = {0};
    ui_hand_t hand = {0};
    sim_data_demo(&demo,&hand,&sim_indoor);
    capture("game-start");
    return 0;
}
