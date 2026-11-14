/* main_shots.c — design P1a §5: headless RGB565 captures; scripted LVGL clock. */
#include "theme.h"
#include "sim_data.h"
#include "renderer.h"
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>

static uint16_t framebuffer[1280 * 720];
static uint32_t drawbuffer[1280 * 720];

static lv_indev_data_t test_input;
static void read_test_input(lv_indev_t *indev,lv_indev_data_t *data)
{
    (void)indev; *data=test_input; test_input.enc_diff=0;
}
static void key_tap(lv_indev_t *indev,uint32_t key)
{
    test_input.key=key; test_input.state=LV_INDEV_STATE_PRESSED; lv_indev_read(indev);
    test_input.state=LV_INDEV_STATE_RELEASED; lv_indev_read(indev);
}
static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    const lv_image_dsc_t *l0 = sim_l0_image();
    const uint32_t *source = (const uint32_t *)pixels;
    for(int y = area->y1; y <= area->y2; ++y)
        for(int x = area->x1; x <= area->x2; ++x)
        {
            uint32_t pixel = sim_composite(l0, *source++, (unsigned)x, (unsigned)y);
            framebuffer[y * 1280 + x] = (uint16_t)(((pixel >> 8)&0xf800) |
                ((pixel >> 5)&0x07e0) | ((pixel >> 3)&31));
        }
    lv_display_flush_ready(display);
}

static void check_labels(lv_obj_t *parent)
{
    for(unsigned i = 0; i < lv_obj_get_child_count(parent); ++i) {
        lv_obj_t *o = lv_obj_get_child(parent, (int)i);
        if(lv_obj_is_hidden(o)) continue;
        if(lv_obj_check_type(o, &lv_label_class) && lv_label_get_text(o)[0]) {
            const unsigned char *text = (const unsigned char *)lv_label_get_text(o);
            const lv_font_t *font = lv_obj_get_style_text_font(o, 0);
            while(*text) {
                unsigned code = *text++;
                if(code >= 0xc0) {
                    unsigned n = code >= 0xf0 ? 3 : code >= 0xe0 ? 2 : 1;
                    code &= (1u << (6 - n)) - 1;
                    while(n--) code = (code << 6) | (*text++ & 0x3f);
                }
                if(code == '\n') continue;
                lv_font_glyph_dsc_t glyph;
                if(!lv_font_get_glyph_dsc(font, &glyph, code, 0) || glyph.is_placeholder) {
                    fprintf(stderr, "Missing glyph U+%04X in %s\n", code,
                        lv_label_get_text(o));
                    exit(EXIT_FAILURE);
                }
            }
            if(!lv_obj_is_scrollable(parent) && (lv_obj_get_x(o) < 0 || lv_obj_get_y(o) < 0 ||
                lv_obj_get_x(o) + lv_obj_get_width(o) > lv_obj_get_width(parent) ||
                lv_obj_get_y(o) + lv_obj_get_height(o) > lv_obj_get_height(parent))) {
                fprintf(stderr, "Label outside parent: %s (%d,%d %dx%d in %dx%d)\n",
                    lv_label_get_text(o), (int)lv_obj_get_x(o), (int)lv_obj_get_y(o),
                    (int)lv_obj_get_width(o), (int)lv_obj_get_height(o),
                    (int)lv_obj_get_width(parent), (int)lv_obj_get_height(parent));
                exit(EXIT_FAILURE);
            }
            if(ui_page==1) for(unsigned j=i+1;j<lv_obj_get_child_count(parent);++j) {
                lv_obj_t *other=lv_obj_get_child(parent,(int)j);
                if(!lv_obj_check_type(other,&lv_label_class) ||
                    !lv_label_get_text(other)[0] || lv_obj_is_hidden(other)) continue;
                lv_area_t a, b;
                lv_obj_get_coords(o,&a); lv_obj_get_coords(other,&b);
                if(a.x1<=b.x2 && b.x1<=a.x2 && a.y1<=b.y2 && b.y1<=a.y2) {
                    fprintf(stderr,"Overlapping labels: %s / %s\n",
                        lv_label_get_text(o),lv_label_get_text(other));
                    exit(EXIT_FAILURE);
                }
            }
        }
        check_labels(o);
    }
}

static void capture(const char *name)
{
    lv_obj_update_layout(lv_screen_active());
    lv_obj_invalidate(lv_screen_active());
    lv_refr_now(NULL);
    check_labels(lv_screen_active());
    check_labels(lv_layer_sys());
    char path[256];
    snprintf(path, sizeof(path), "shots/%s.rgb565", name);
    FILE *file = fopen(path, "wb");
    if(!file) { perror(path); exit(EXIT_FAILURE); }
    if(fwrite(framebuffer, sizeof(framebuffer), 1, file) != 1) {
        perror(path);
        exit(EXIT_FAILURE);
    }
    if(fclose(file)) { perror(path); exit(EXIT_FAILURE); }
}

static lv_indev_t *keypad;
static void tap(uint32_t key) { key_tap(keypad,key); }
static lv_obj_t *focus(void) { return lv_group_get_focused(lv_group_get_default()); }
static void settle(void) { lv_tick_inc(200); ui_refresh(); }
static void select_action(unsigned action)
{
    lv_group_t *g=lv_group_get_default();
    unsigned n=lv_group_get_obj_count(g);
    for(unsigned i=0;i<n;++i) {
        lv_obj_t *o=lv_group_get_obj_by_index(g,i);
        if((unsigned)(uintptr_t)lv_obj_get_user_data(o)==action) {
            lv_group_focus_obj(o); return;
        }
    }
    fprintf(stderr,"Missing action %u\n",action); exit(EXIT_FAILURE);
}
static void click(unsigned action) { select_action(action); tap(LV_KEY_ENTER); }
static bool label_contains(lv_obj_t *p,const char *s)
{
    if(lv_obj_check_type(p,&lv_label_class) && strstr(lv_label_get_text(p),s)) return true;
    for(unsigned i=0;i<lv_obj_get_child_count(p);++i)
        if(label_contains(lv_obj_get_child(p,(int)i),s)) return true;
    return false;
}
static void select_control(lv_obj_t *target)
{
    unsigned n=lv_group_get_obj_count(lv_group_get_default());
    for(unsigned i=0;i<n && focus()!=target;++i) tap(LV_KEY_NEXT);
    assert(focus()==target);
}
static lv_obj_t *control(unsigned index)
{ return lv_group_get_obj_by_index(lv_group_get_default(),index); }
static bool available(lv_obj_t *o)
{
    if(lv_obj_has_state(o,LV_STATE_DISABLED)) return false;
    for(lv_obj_t *p=o;p;p=lv_obj_get_parent(p)) if(lv_obj_is_hidden(p)) return false;
    return true;
}
/* Enumerate actual interactive descendants, not a page-specific expected count. */
static void check_registered(lv_obj_t *parent)
{
    for(unsigned i=0;i<lv_obj_get_child_count(parent);++i) {
        lv_obj_t *o=lv_obj_get_child(parent,(int)i);
        if(available(o) && (lv_obj_check_type(o,&lv_button_class) ||
           lv_obj_check_type(o,&lv_slider_class) || lv_obj_check_type(o,&lv_switch_class) ||
           lv_obj_check_type(o,&lv_dropdown_class) || lv_obj_check_type(o,&lv_checkbox_class)))
            assert(lv_obj_get_group(o)==lv_group_get_default());
        check_registered(o);
    }
}
static void traverse(void)
{
    lv_group_t *g=lv_group_get_default();
    unsigned n=lv_group_get_obj_count(g), count=0;
    check_registered(lv_screen_active()); check_registered(lv_layer_sys());
    for(unsigned i=0;i<n;++i) {
        lv_obj_t *target=control(i);
        if(!available(target)) continue;
        select_control(target); ++count;
        assert(lv_obj_has_state(target,LV_STATE_FOCUS_KEY));
        lv_obj_update_layout(lv_screen_active());
        lv_area_t a; lv_obj_get_coords(target,&a);
        assert(a.y1>=0 && a.y2<720);
        tap(LV_KEY_NEXT); tap(LV_KEY_PREV); assert(focus()==target);
    }
    assert(count>=2);
}
static void pointer(lv_indev_t *mouse,int x,int y,bool pressed)
{
    test_input.point=(lv_point_t){x,y};
    test_input.state=pressed ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    lv_indev_read(mouse);
}
static void check_other_controls(void)
{
    ui_open(5); settle();
    unsigned games; ui_data_games(&games);
    select_control(control(games+1)); capture("games-last-row");
    tap(LV_KEY_ENTER); assert(ui_game_active() && ui_mode==games-1);
    settle(); capture("game-running");
    tap(LV_KEY_ESC); assert(!ui_game_active() && ui_page==5);
    assert(focus()==control(games+1));
    tap(LV_KEY_ENTER); sim_data_session(UI_APP_GAME,UI_STATE_IDLE,NULL); ui_refresh();
    assert(ui_page==5 && !ui_game_active() && focus()==control(games+1));
    tap(LV_KEY_ESC); assert(ui_page==0);

    ui_tab=1; ui_open(4); settle(); traverse(); capture("renderer-list");
    select_control(control(5)); tap(LV_KEY_ENTER); traverse(); capture("renderer-result");
    tap(LV_KEY_ESC); assert(ui_tab==1 && ui_mode==0);
    tap(LV_KEY_ESC); assert(ui_tab==0 && ui_page==4);
    ui_data_benchmark_start(); tap(LV_KEY_ESC); assert(!ui_data_benchmark_running());
    ui_data_benchmark_start(); lv_tick_inc(8000); ui_refresh(); capture("benchmark-results");
    tap(LV_KEY_ESC); assert(ui_page==0);
    ui_tab=1; ui_open(7); traverse(); capture("coremark-counters");
    tap(LV_KEY_ESC); assert(ui_tab==0 && ui_page==7);
    select_control(control(2)); tap(LV_KEY_ENTER);
    assert(ui_data_session().app==UI_APP_COREMARK);
    lv_tick_inc(6000); ui_refresh(); assert(ui_data_coremark().events[15]>0);
    capture("chip-coremark");
    ui_tab=1; ui_open(8); traverse(); capture("debug-network");
    tap(LV_KEY_ESC); assert(ui_tab==0 && ui_page==8);
    select_control(control(4)); bool hex=ui_data_debug().hex;
    tap(LV_KEY_ENTER); assert(ui_data_debug().hex!=hex);
    select_control(control(5)); tap(LV_KEY_ENTER); tap(LV_KEY_NEXT);
    ui_refresh(); assert(lv_dropdown_get_selected(focus())==1);
    tap(LV_KEY_ENTER); assert(ui_data_debug().baud==921600);
    tap(LV_KEY_NEXT); tap(LV_KEY_ENTER); assert(ui_data_debug().uart_tx==15);
    tap(LV_KEY_NEXT); tap(LV_KEY_ENTER); assert(ui_data_debug().uart_tx==0);
    ui_open(0);
    lv_indev_t *mouse=lv_indev_create(); lv_indev_set_type(mouse,LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(mouse,read_test_input);
    pointer(mouse,70,220,false); pointer(mouse,70,220,true); pointer(mouse,70,220,false);
    assert(ui_page==1);
    ui_hide_interface(); assert(ui_interface_hidden());
    pointer(mouse,55,24,true); pointer(mouse,55,24,false);
    assert(!ui_interface_hidden() && ui_page==1);
    lv_indev_delete(mouse);
    sim_data_session(UI_APP_PIPELINE,UI_STATE_FAILED,"格式错误"); ui_refresh();
    click(1002); assert(ui_data_session().state==UI_STATE_STARTING);
    settle(); assert(ui_data_session().state==UI_STATE_RUNNING);
    ui_open(0);
    puts("PASS existing game, renderer, CoreMark, debug, pointer and session controls");
}
static void check_pipeline(void)
{
    ui_open(1); settle();
    assert(ui_data_chain().preset==1);
    capture("pipeline-standard");
    select_action(2200); tap(LV_KEY_RIGHT);
    assert((unsigned)(uintptr_t)lv_obj_get_user_data(focus())==2201);
    tap(LV_KEY_LEFT);
    assert((unsigned)(uintptr_t)lv_obj_get_user_data(focus())==2200);
    tap(LV_KEY_ENTER);
    assert(lv_group_get_obj_count(lv_group_get_default())==5);
    capture("pipeline-menu");
    click(2012); click(2024); /* Insert gray after detection. */
    ui_chain_t c=ui_data_chain();
    assert(c.count==3 && c.block[1].type==UI_BLOCK_GRAY && c.preset==0);
    click(2201); click(2010); click(2022); /* Change to gamma. */
    assert(ui_data_chain().block[1].type==UI_BLOCK_GAMMA);
    click(2201); click(2011); /* Enter the selected parameter. */
    assert(lv_obj_check_type(focus(),&lv_slider_class));
    tap(LV_KEY_ENTER); assert(lv_group_get_editing(lv_group_get_default()));
    tap(LV_KEY_RIGHT); assert(ui_data_chain().block[1].p[0]==11);
    tap(LV_KEY_ESC); assert(!lv_group_get_editing(lv_group_get_default()));
    tap(LV_KEY_ESC); assert(ui_page==1);
    const uint8_t *final_pixels=sim_l0_image()->data;
    click(2201); click(2014); assert(ui_data_chain().view==1);
    assert(sim_l0_image()->data!=final_pixels);
    assert(sim_l0_image()==sim_pipeline_image());
    click(2001); assert(ui_data_chain().view==UI_VIEW_FINAL);
    click(2201); click(2013); assert(ui_data_chain().count==2);
    /* A second detector is rejected atomically and explained in Chinese. */
    c=ui_data_chain();
    click(2200); click(2012); click(2028);
    ui_chain_t after=ui_data_chain();
    assert(!memcmp(&c,&after,sizeof c));
    assert(label_contains(lv_screen_active(),"NPU 只有一个"));
    capture("pipeline-rejected");
    /* Removing the producer is rejected while its box overlay remains. */
    click(2200); click(2013);
    assert(ui_data_chain().count==2);
    assert(label_contains(lv_screen_active(),"必须先放置检测积木"));
    click(2200); click(2011); assert(ui_detection_settings);
    lv_obj_t *slider=lv_group_get_obj_by_index(lv_group_get_default(),2);
    lv_group_focus_obj(slider); tap(LV_KEY_ENTER); tap(LV_KEY_LEFT);
    assert(ui_data_detection_config().threshold==45);
    tap(LV_KEY_ESC); tap(LV_KEY_ESC); assert(!ui_detection_settings && ui_page==1);
    click(2105); assert(ui_data_chain().preset==5); settle();
    select_action(2202); capture("pipeline-rotation");
    click(2107); assert(ui_data_chain().preset==7); settle(); capture("pipeline-filter");
    ui_pipe_stats_t stats=ui_data_pipe_stats();
    assert(stats.hop_count==2 && stats.hop[0].engine==UI_HOP_CAM_PIX &&
        stats.hop[0].first==0 && stats.hop[0].last==2 && stats.hop[1].first==3);
    assert(ui_data_thumb(0)==ui_data_thumb(1) && ui_data_thumb(1)==ui_data_thumb(2));
    assert(label_contains(lv_screen_active(),"与摄像头融合"));
    click(2201); click(2014);
    assert(label_contains(lv_screen_active(),"显示本次 PIX 处理的输出"));
    click(2001);
    /* Check all source/parameter kinds with actual native controls. */
    for(unsigned preset=1;preset<=8;++preset) {
        click(2100+preset); settle();
        ui_chain_t chain=ui_data_chain();
        assert(chain.preset==preset);
        for(unsigned i=0;i<chain.count;++i) {
            select_action(2200+i); lv_obj_update_layout(lv_screen_active());
            capture("pipeline-control-check");
            const lv_image_dsc_t *thumb=ui_data_thumb(i);
            assert(thumb->header.w==160 && thumb->header.h==90);
        }
    }
    sim_data_image_status(UI_IMAGE_DONE); ui_refresh();
    unsigned image=ui_data_vision().image_index;
    click(2003); assert(ui_data_vision().image_index==image+1);
    sim_data_image_status(UI_IMAGE_DONE); ui_refresh(); click(2002);
    assert(ui_data_vision().image_index==image);
    click(2000); click(2042); assert(ui_data_chain().source==UI_SOURCE_TEST_IMAGE);
    click(2000); click(2061); assert(ui_data_chain().view==UI_VIEW_SOURCE);
    assert(label_contains(lv_screen_active(),"来源原图"));
    const lv_image_dsc_t *original=sim_l0_image();
    click(2200); click(2012); click(2024);
    assert(ui_data_chain().view==UI_VIEW_SOURCE && sim_l0_image()==original);
    click(2201); click(2013); assert(ui_data_chain().view==UI_VIEW_SOURCE);
    /* Empty and full chains remain editable; extra insertion is refused. */
    c=(ui_chain_t){.view=UI_VIEW_FINAL}; assert(!ui_data_chain_set(&c)); ui_refresh();
    click(2000); tap(LV_KEY_ESC); assert(ui_page==1);
    /* Source insertion Esc returns to the source menu, including an empty chain. */
    click(2000); click(2060); tap(LV_KEY_ESC);
    assert(lv_group_get_obj_count(lv_group_get_default())==5);
    tap(LV_KEY_ESC); assert(ui_page==1);
    /* Source menu also offers insertion when the chain is empty. */
    click(2000); click(2060); click(2024); assert(ui_data_chain().count==1);
    c=ui_data_chain(); c.count=8;
    for(unsigned i=0;i<8;++i) c.block[i]=(ui_block_t){.type=UI_BLOCK_GRAY};
    assert(!ui_data_chain_set(&c)); ui_refresh();
    click(2200); click(2012); click(2024);
    assert(ui_data_chain().count==8 && label_contains(lv_screen_active(),"最多 8 块"));
    capture("pipeline-full");
    select_action(2207); lv_obj_update_layout(lv_screen_active());
    lv_area_t last; lv_obj_get_coords(focus(),&last);
    assert(last.x1>=0 && last.x2<1280);
    tap(LV_KEY_ENTER); click(2010); tap(LV_KEY_ESC);
    assert(lv_group_get_obj_count(lv_group_get_default())==5);
    tap(LV_KEY_ESC); assert(ui_page==1);
    tap(LV_KEY_ESC); assert(ui_page==0);
    puts("PASS pipeline: movement, insert/delete, function/parameters, stage view, presets, "
        "atomic rejection/reasons, detection settings, PC image step, empty/full chains");
}
int main(void)
{
    lv_init();
    lv_display_t *display=lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    keypad=lv_indev_create(); lv_indev_set_type(keypad,LV_INDEV_TYPE_KEYPAD);
    lv_indev_set_read_cb(keypad,read_test_input);
    sim_data_init(); ui_start(); capture("home");
    check_pipeline(); check_other_controls();
    const unsigned pages[]={0,4,5,7,8};
    for(unsigned i=0;i<sizeof pages/sizeof pages[0];++i) {
        ui_open(pages[i]); settle(); capture("other-page-check");
    }
    lv_deinit(); return 0;
}
