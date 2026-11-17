/* main_draw_shots.c — T-DRAW; synthetic fingertip strokes through the real page.
 * Host LVGL rendering, toolbar dwell and four-key controls, camera composition.
 */
#include "widgets.h"
#include "draw.h"
#include "sim_data.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
extern void ui_draw_update(void);
extern const lv_image_dsc_t sim_indoor;
static uint16_t framebuffer[1280*720];
static uint32_t drawbuffer[1280*720];
static ui_hand_t hand;
static const char *directory;
static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    const uint32_t *source = (const uint32_t *)pixels;
    for (int y = area->y1; y <= area->y2; ++y)
        for (int x = area->x1; x <= area->x2; ++x) {
            uint32_t c = sim_composite(sim_l0_image(),*source++,(unsigned)x,(unsigned)y);
            framebuffer[y*1280+x] =
                (uint16_t)(((c>>8)&0xf800)|((c>>5)&0x7e0)|((c>>3)&31));
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
            assert(lv_font_get_glyph_dsc(font,&glyph,code,0) && !glyph.is_placeholder);
        }
    }
    for (unsigned i = 0; i < lv_obj_get_child_count(parent); ++i)
        check_labels(lv_obj_get_child(parent,(int)i));
}
static void capture(const char *name)
{
    lv_obj_update_layout(lv_screen_active());
    check_labels(lv_screen_active());
    lv_refr_now(NULL);
    char path[1024];
    snprintf(path,sizeof path,"%s/%s.rgb565",directory,name);
    FILE *f = fopen(path,"wb");
    assert(f && fwrite(framebuffer,sizeof framebuffer,1,f) == 1);
    assert(fclose(f) == 0);
}
static void sample(int x, int y, int cls)
{
    hand.count = 1;
    hand.people[0] = (ui_detection_t){.width=200,.height=200,.class_id=(unsigned)cls};
    hand.points[0][8] = (ui_pose_point_t){x,y,1};
    hand.state.cls = cls;
    ui_demo_t demo = {0};
    sim_data_demo(&demo,&hand,&sim_indoor);
    lv_tick_inc(40);
    ui_draw_update();
    lv_refr_now(NULL);
}
static void line(int x, int y, int nx, int ny)
{
    for (unsigned i = 0; i < 4; ++i) sample(x,y,0);
    sample(x,y,DRAW_POINT);
    int dx = nx-x;
    int dy = ny-y;
    int steps = (LV_MAX(LV_ABS(dx),LV_ABS(dy))+7)/8;
    for (int i = 1; i <= steps; ++i) sample(x+dx*i/steps,y+dy*i/steps,DRAW_POINT);
    for (int i = 0; i < 6; ++i) sample(nx,ny,DRAW_POINT);
    for (unsigned i = 0; i < 4; ++i) sample(nx,ny,0);
}
static void hover(unsigned item)
{
    for (unsigned i = 0; i < 16; ++i) sample(220+64*(int)item,108,0);
}
int main(int argc, char **argv)
{
    assert(argc == 2);
    directory = argv[1];
    lv_init();
    lv_display_t *display = lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,
                           LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init();
    ui_start();
    ui_open(DRAW_PAGE);
    sim_data_session(UI_APP_GRAB,UI_STATE_RUNNING,NULL);
    ui_refresh();
    lv_obj_update_layout(lv_screen_active());
    /* Write “山川”: each stroke enters via simulated point-8 samples. */
    hover(6);
    line(420,270,420,510);
    line(320,350,320,510);
    line(320,510,520,510);
    line(520,350,520,510);
    hover(4);
    line(680,280,680,460);
    line(680,460,640,520);
    line(800,300,800,500);
    line(920,270,920,520);
    sample(960,540,0);
    capture("writing");
    /* Noisy cursive input through the actual page, including class and hand gaps. */
    ui_back();
    ui_open(DRAW_PAGE);
    sim_data_session(UI_APP_GRAB,UI_STATE_RUNNING,NULL);
    ui_refresh();
    hover(6);
    for (unsigned i = 0; i < 220; ++i) {
        int x = 260+3*(int)i;
        int y = 370+(int)(85*sinf(i*.045f));
        int jitter_x = (int)((i*17)%21)-10;
        int jitter_y = (int)((i*29)%21)-10;
        if (i >= 90 && i < 94) {
            hand.count = 0;
            ui_demo_t demo = {0};
            sim_data_demo(&demo,&hand,&sim_indoor);
            lv_tick_inc(40);
            ui_draw_update();
        } else sample(x+jitter_x,y+jitter_y,i%10 == 5 ? 0 : DRAW_POINT);
    }
    for (unsigned i = 0; i < 4; ++i) sample(920,370,0);
    capture("smooth");
    hover(10);
    hover(12);
    sample(960,540,0);
    capture("eraser");
    /* Buttons are ordinary focus controls: traverse, select pen, then clear. */
    lv_group_t *group = lv_group_get_default();
    lv_obj_t *pen = NULL;
    lv_obj_t *clear = NULL;
    for (unsigned i = 0; i < lv_group_get_obj_count(group); ++i) {
        lv_obj_t *o = lv_group_get_obj_by_index(group,i);
        for (unsigned j = 0; j < lv_obj_get_child_count(o); ++j) {
            lv_obj_t *child = lv_obj_get_child(o,(int)j);
            if (!lv_obj_check_type(child,&lv_label_class)) continue;
            const char *text = lv_label_get_text(child);
            if (!lv_strcmp(text,"笔")) pen = o;
            if (!lv_strcmp(text,"清空")) clear = o;
        }
    }
    assert(pen && clear);
    bool visited_pen = false;
    bool visited_clear = false;
    for (unsigned i = 0; i < lv_group_get_obj_count(group)*2; ++i) {
        ui_key(LV_KEY_NEXT);
        lv_obj_t *focused = lv_group_get_focused(group);
        visited_pen |= focused == pen;
        visited_clear |= focused == clear;
    }
    assert(visited_pen && visited_clear);
    lv_group_focus_obj(pen);
    ui_key(LV_KEY_ENTER);
    assert(lv_obj_has_state(pen,LV_STATE_CHECKED));
    lv_group_focus_obj(clear);
    ui_key(LV_KEY_ENTER);
    ui_back();
    assert(ui_page == 0 && ui_home_tab() == 1);
    capture("motion-tab");
    puts("PASS draw page: writing, eraser dwell, key traversal/selection/clear, tab, glyphs");
    return 0;
}
