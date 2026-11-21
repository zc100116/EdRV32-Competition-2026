/* main_games_shots.c — R4 §6 native LVGL captures with shared rule snapshots.
 * Deterministic scene construction, original assets and desktop camera fixture.
 */
#include "game_view.h"
#include "widgets.h"
#include "sim_data.h"
#include "workshop.h"
#include "game_loop.h"
#include "grab.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
extern const lv_image_dsc_t sim_indoor;
static uint16_t framebuffer[1280*720];
static uint32_t drawbuffer[1280*720];
static const char *directory;
static motion_snapshot_t motion_fixture, motion_buffers[3];
static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    const uint32_t *source = (const uint32_t *)pixels;
    for (int y = area->y1; y <= area->y2; ++y)
        for (int x = area->x1; x <= area->x2; ++x) {
            uint32_t c = sim_composite(sim_l0_image(),*source++,1279-(unsigned)x,(unsigned)y);
            framebuffer[y*1280+x] =
                (uint16_t)(((c>>8)&0xf800)|((c>>5)&0x7e0)|((c>>3)&31));
        }
    lv_display_flush_ready(display);
}
static void capture(const char *name)
{
    ui_motion_update();
    lv_obj_update_layout(lv_screen_active());
    lv_refr_now(NULL);
    char path[1024];
    snprintf(path,sizeof path,"%s/%s.rgb565",directory,name);
    FILE *f = fopen(path,"wb");
    assert(f && fwrite(framebuffer,sizeof framebuffer,1,f) == 1);
    fclose(f);
}
static void freeze(void *context) { (void)context; }
static void report(void *context, unsigned a, unsigned b, unsigned c, unsigned d)
{
    (void)context; (void)a; (void)b; (void)c; (void)d;
}
static void publish(void)
{
    lv_tick_inc(17);
    game_loop_step();
}
static void motion_snapshot(void *context, void *destination)
{
    memcpy(destination,context,sizeof(motion_snapshot_t));
}
static void motion_capture(const char *game, const char *phase)
{
    motion_snapshot_copy(&motion_fixture);
    publish();
    char name[64];
    snprintf(name,sizeof name,"%s-%s",game,phase);
    capture(name);
}
static void games(void)
{
    static const char *const names[] = {"","sling","rps","mole","slice","catch"};
    for (unsigned game = MOTION_SLING; game <= MOTION_CATCH; ++game) {
        ui_motion_entry = game;
        ui_open(MOTION_PAGE);
        sim_data_session(UI_APP_GRAB,UI_STATE_RUNNING,NULL);
        ui_refresh();
        game_loop_stop();
        motion_snapshot_copy(&motion_fixture);
        game_loop_config config = {freeze,motion_snapshot,report,&motion_fixture,
            {&motion_buffers[0],&motion_buffers[1],&motion_buffers[2]},sizeof motion_fixture};
        game_loop_start(&config);
        motion_capture(names[game],"start");
        motion_start();
        ui_motion.hand = (motion_hand_t){640,360,0,false,true,0};
        if (game == MOTION_SLING) {
            sling_input(&ui_sling,SLING_X,SLING_Y,true,0,1);
            sling_input(&ui_sling,240,570,true,0,1);
            sling_input(&ui_sling,240,570,false,0,0);
            for (unsigned i = 0; i < 18; ++i) sling_step(&ui_sling);
        } else if (game == MOTION_RPS) {
            for (unsigned i = 0; i < RPS_COUNT*GAME_SUBSTEPS; ++i) rps_step(&ui_motion.rps);
            int cls[] = {1,2,0};
            rps_input(&ui_motion.rps,cls[(ui_motion.rps.board+2)%3],true);
            for (unsigned i = 0; i < RPS_WINDOW*GAME_SUBSTEPS; ++i) rps_step(&ui_motion.rps);
        } else if (game == MOTION_MOLE) {
            for (unsigned i = 0; i < 180; ++i) mole_step(&ui_motion.mole);
            ui_motion.mole.holes[1] = (mole_hole_t){60,0,0};
            ui_motion.mole.holes[3] = (mole_hole_t){60,0,1};
            ui_motion.mole.holes[5] = (mole_hole_t){60,0,2};
            ui_motion.mole.score = 80;
        } else if (game == MOTION_SLICE) {
            for (unsigned i = 0; i < 100; ++i) slice_step(&ui_motion.slice);
            slice_input(&ui_motion.slice,510,290,true,1000);
            slice_input(&ui_motion.slice,560,260,true,1040);
        } else {
            for (unsigned i = 0; i < 420; ++i) catch_step(&ui_motion.basket);
            catch_input(&ui_motion.basket,700,true);
            for (unsigned i = 0; i < 4; ++i) catch_step(&ui_motion.basket);
            ui_motion.basket.score = 50;
        }
        motion_capture(names[game],"playing");
        if (game == MOTION_SLING) { ui_sling.phase = SLING_DONE; ui_sling.score = 450; }
        if (game == MOTION_RPS) { ui_motion.rps.phase = RPS_DONE; ui_motion.rps.wins = 3; }
        if (game == MOTION_MOLE) { ui_motion.mole.done = true; ui_motion.mole.score = 280; }
        if (game == MOTION_SLICE) { ui_motion.slice.done = true; ui_motion.slice.score = 270; }
        if (game == MOTION_CATCH) { ui_motion.basket.done = true; ui_motion.basket.score = 320; }
        motion_finish();
        motion_capture(names[game],"result");
        game_loop_stop();
        ui_open(0);
    }
}
static lv_obj_t *find_type(lv_obj_t *parent,const lv_obj_class_t *type)
{
    if(lv_obj_check_type(parent,type)) return parent;
    for(unsigned i=0;i<lv_obj_get_child_count(parent);++i) {
        lv_obj_t *found=find_type(lv_obj_get_child(parent,(int)i),type);
        if(found) return found;
    }
    return NULL;
}
static void check_dropdown(lv_obj_t *dropdown)
{
    assert(dropdown);
    lv_dropdown_open(dropdown);
    lv_obj_t *list=lv_dropdown_get_list(dropdown);
    assert(lv_obj_get_style_bg_opa(list,0)==LV_OPA_COVER);
    assert(lv_obj_get_style_border_width(list,0)>0);
    assert(lv_obj_get_parent(list)==lv_layer_top());
}
static void settings_capture(void)
{
    ui_open(3);
    sim_data_session(UI_APP_PROCESS,UI_STATE_RUNNING,NULL);
    ui_refresh();
    ui_process_config_t config=ui_data_process_config();
    config.enabled|=1u<<2;
    ui_data_process_set(&config);
    ui_process_update();
    ui_camera_drawer_toggle();
    lv_tick_inc(200); lv_timer_handler();
    lv_obj_t *dropdown=find_type(lv_screen_active(),&lv_dropdown_class);
    assert(dropdown);
    lv_obj_t *row=lv_obj_get_parent(dropdown);
    lv_obj_scroll_to_y(lv_obj_get_parent(row),lv_obj_get_y(row)-12,LV_ANIM_OFF);
    check_dropdown(dropdown);
    capture("process-s1-open");
    lv_dropdown_close(dropdown);
    ui_open(0); ui_home_select_tab(0);
    capture("home-ai");
    ui_open(1); ui_detection_settings=true; ui_open(1);
    check_dropdown(find_type(lv_screen_active(),&lv_dropdown_class));
    ui_open(8);
    check_dropdown(find_type(lv_screen_active(),&lv_dropdown_class));
    ui_open(0);
}
int main(int argc, char **argv)
{
    assert(argc == 2);
    directory = argv[1];
    lv_init();
    static const uint32_t required[] = {
        0x5f39,0x5f13,0x6253,0x9776,0x77f3,0x5934,0x526a,0x5200,0x5e03,
        0x5730,0x9f20,0x5207,0x56fe,0x5f62,0x63a5,0x7269,0x7bee,
        0x79ef,0x6728,0x5854,0x672c,0x5c40,0x5f97,0x5206,0x642d,0x5efa,0x5b8c,0x6210};
    for (unsigned i = 0; i < sizeof required/sizeof required[0]; ++i) {
        lv_font_glyph_dsc_t glyph;
        assert(lv_font_get_glyph_dsc(&showcase_bold_32,&glyph,required[i],0));
        assert(!glyph.is_placeholder);
    }
    lv_display_t *display = lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init();
    ui_start();
    ui_demo_t demo = {0};
    ui_hand_t gesture = {0};
    sim_data_demo(&demo,&gesture,&sim_indoor);
    games();
    settings_capture();
    lv_deinit();
    puts("PASS native five arcade games start/playing/result captures; workshop has separate scenes");
}
