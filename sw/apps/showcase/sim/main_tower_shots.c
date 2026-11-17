/* main_tower_shots.c — R4 §6 native LVGL captures with shared rule snapshots.
 * Deterministic scene construction, original assets and desktop camera fixture.
 */
#include "theme.h"
#include "sim_data.h"
#include "tower.h"
#include "../../../tests/showcase/tower_scenes.h"
#include "game_loop.h"
#include "grab.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
extern const lv_image_dsc_t sim_indoor;
extern bool ui_tower_key(uint32_t key);
extern void ui_tower_update(void);
extern bool ui_tower_loading(void);
extern unsigned ui_tower_atlas_bytes(void);
static uint16_t framebuffer[1280*720];
static uint32_t drawbuffer[1280*720];
static tower_state fixture;
static tower_snapshot buffers[3];
static const char *directory;
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
    ui_tower_update();
    lv_obj_update_layout(lv_screen_active());
    lv_refr_now(NULL);
    char path[1024];
    snprintf(path,sizeof path,"%s/%s.rgb565",directory,name);
    FILE *f = fopen(path,"wb");
    assert(f && fwrite(framebuffer,sizeof framebuffer,1,f) == 1);
    fclose(f);
}
static void freeze(void *context) { (void)context; }
static void snapshot(void *context, void *destination)
{
    tower_snapshot_copy(context,destination);
}
static void report(void *context, unsigned a, unsigned b, unsigned c, unsigned d)
{
    (void)context; (void)a; (void)b; (void)c; (void)d;
}
static void publish(void)
{
    lv_tick_inc(17);
    game_loop_step();
}
int main(int argc, char **argv)
{
    assert(argc == 2);
    directory = argv[1];
    lv_init();
    lv_font_glyph_dsc_t glyph;
    assert(lv_font_get_glyph_dsc(&showcase_bold_24,&glyph,0x7406,0));
    assert(!glyph.is_placeholder);
    lv_display_t *display = lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init();
    ui_start();
    ui_open(18);
    sim_data_session(UI_APP_GRAB,UI_STATE_RUNNING,NULL);
    ui_demo_t demo = {0};
    ui_hand_t gesture = {0};
    sim_data_demo(&demo,&gesture,&sim_indoor);
    ui_refresh();
    assert(ui_tower_loading());
    clock_t begin = clock();
    unsigned batches = 0;
    while (ui_tower_loading()) { ui_tower_update(); ++batches; }
    assert(batches == 36);
    printf("physblocks atlas host_cpu_ms=%ld bytes=%u batches=%u\n",
        (long)((clock()-begin)*1000/CLOCKS_PER_SEC),ui_tower_atlas_bytes(),batches);
    unsigned bytes = ui_tower_atlas_bytes();
    game_loop_stop();
    /* Re-enter: no generation or progress, same boot-lifetime atlas. */
    ui_open(0);
    ui_open(18);
    sim_data_session(UI_APP_GRAB,UI_STATE_RUNNING,NULL);
    ui_refresh();
    assert(!ui_tower_loading() && ui_tower_atlas_bytes() == bytes);
    assert(ui_tower_key(LV_KEY_ENTER));
    publish();
    tower_snapshot keyshot;
    assert(game_loop_read(&keyshot) && keyshot.bodies == 1);
    game_loop_stop();
    tower_scene(&fixture,0);
    for (unsigned t = 0; t < 90; ++t)
        tower_step(&fixture,(tower_input){850,280,0,false,0});
    tower_snapshot snap;
    tower_snapshot_copy(&fixture,&snap);
    assert(snap.bodies == 5 && snap.awake == 0);
    game_loop_config config = {freeze,snapshot,report,&fixture,
        {&buffers[0],&buffers[1],&buffers[2]},sizeof(tower_snapshot)};
    game_loop_start(&config);
    publish(); capture("stacked");
    for (unsigned t = 0; t < 72; ++t)
        tower_step(&fixture,(tower_input){850,280,8,false,0});
    assert(fixture.sequence == 6);
    tower_snapshot_copy(&fixture,&snap);
    assert(snap.bodies == 6 && snap.awake > 0);
    publish(); capture("falling");
    tower_init(&fixture,42);
    int id = tower_spawn(&fixture,1,640,300);
    /* Feed the shared fist and scissors path with a steady cursor. */
    fixture.world.gravity.y = 0;
    for (unsigned t = 0; t < 60; ++t)
        tower_step(&fixture,(tower_input){640,300,1,true,0});
    assert(fixture.world.grab.body == id);
    for (unsigned t = 0; t < 8; ++t)
        tower_step(&fixture,(tower_input){640,300,2,true,0});
    assert(fixture.rotations == 1);
    publish(); capture("rotated");
    game_loop_stop();
    ui_open(0);
    lv_deinit();
    puts("PASS native physblocks stacked/falling/rotated captures and atlas re-entry");
}
