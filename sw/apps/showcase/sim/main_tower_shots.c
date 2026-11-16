/* main_tower_shots.c — R4 §6 native LVGL captures with shared rule snapshots.
 * Deterministic scene construction, original assets and desktop camera fixture.
 */
#include "theme.h"
#include "sim_data.h"
#include "tower.h"
#include "game_loop.h"
#include "grab.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
extern const lv_image_dsc_t sim_indoor;
extern void ui_tower_action(unsigned action);
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
static void block(int kind, int x, int y)
{
    int id = tower_spawn(&fixture,kind,x,y);
    fixture.world.bodies[id].awake = false;
}
int main(int argc, char **argv)
{
    assert(argc == 2);
    directory = argv[1];
    lv_init();
    lv_font_glyph_dsc_t glyph;
    assert(lv_font_get_glyph_dsc(&showcase_bold_32,&glyph,0x5854,0));
    assert(!glyph.is_placeholder);
    lv_display_t *display = lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init();
    ui_start();
    ui_open(17);
    sim_data_session(UI_APP_GRAB,UI_STATE_RUNNING,NULL);
    ui_demo_t demo = {0};
    ui_hand_t gesture = {0};
    sim_data_demo(&demo,&gesture,&sim_indoor);
    ui_refresh();
    publish(); capture("start");
    ui_tower_action(3);
    clock_t begin = clock();
    while (ui_tower_loading()) ui_tower_update();
    printf("tower atlas host_cpu_ms=%ld\n",(long)((clock()-begin)*1000/CLOCKS_PER_SEC));
    printf("tower atlas bytes=%u\n",ui_tower_atlas_bytes());
    game_loop_stop();
    tower_init(&fixture,TOWER_FREE,42,0);
    fixture.hand = (tower_input){735,275,1,true,0};
    block(6,530,580); block(6,730,580);
    block(1,630,520); block(0,590,460); block(0,670,460);
    block(2,630,390); block(3,630,320);
    fixture.peak = fixture.height = 340;
    fixture.ticks = 35*60;
    game_loop_config config = {freeze,snapshot,report,&fixture,
        {&buffers[0],&buffers[1],&buffers[2]},sizeof(tower_snapshot)};
    game_loop_start(&config);
    publish(); capture("building");
    int glass = tower_spawn(&fixture,30,770,465);
    fixture.world.bodies[glass].max_normal_impulse = TOWER_GLASS_IMPULSE+1;
    tower_impacts(&fixture);
    for (unsigned t = 0; t < 8; ++t)
        for (unsigned i = 0; i < TOWER_PARTICLES; ++i) {
            tower_particle *p = &fixture.particles[i];
            if (p->life) { p->x += p->vx; p->y += p->vy; --p->life; }
        }
    fixture.hand = (tower_input){790,360,0,false,0};
    publish(); capture("glass");
    fixture.mode = TOWER_HIGH;
    fixture.stable = TOWER_STABLE;
    fixture.new_record = true;
    tower_finish(&fixture);
    publish(); capture("result");
    game_loop_stop();
    ui_open(0);
    lv_deinit();
    puts("PASS native tower start/building/glass/result captures");
}
