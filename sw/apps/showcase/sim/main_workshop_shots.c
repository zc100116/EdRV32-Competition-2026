/* main_workshop_shots.c — T-WS-GAME acceptance; shared LVGL and rule captures.
 * Fixed scene/gesture stimuli use the real snapshots and original workshop art.
 */
#include "theme.h"
#include "sim_data.h"
#include "workshop.h"
#include "game_loop.h"
#include <assert.h>
#include <stdio.h>
#include <time.h>
#include <string.h>
extern const lv_image_dsc_t sim_indoor;
void ui_workshop_update(void);
unsigned ui_workshop_pending(void);
static uint16_t framebuffer[1280*720];
static uint32_t drawbuffer[1280*720];
static workshop_state fixture;
static workshop_snapshot snapshots[3];
static const char *directory;
static void flush(lv_display_t *display,const lv_area_t *area,uint8_t *pixels)
{
    const uint32_t *source=(const uint32_t *)pixels;
    for (int y=area->y1;y<=area->y2;++y) for (int x=area->x1;x<=area->x2;++x) {
        uint32_t c=sim_composite(sim_l0_image(),*source++,1279-(unsigned)x,(unsigned)y);
        framebuffer[y*1280+x]=(uint16_t)(((c>>8)&0xf800)|((c>>5)&0x7e0)|((c>>3)&31));
    }
    lv_display_flush_ready(display);
}
static void freeze(void *context) { (void)context; }
static void snapshot(void *context,void *destination)
{
    workshop_snapshot_copy(context,destination);
}
static void report(void *context,unsigned a,unsigned b,unsigned c,unsigned d)
{
    (void)context; (void)a; (void)b; (void)c; (void)d;
}
static void capture(const char *name)
{
    lv_tick_inc(17);
    game_loop_step();
    unsigned frames=0;
    clock_t total=0,maximum=0;
    do {
        unsigned pending=ui_workshop_pending();
        clock_t begin=clock();
        ui_workshop_update();
        if (pending) assert(ui_workshop_pending()<pending);
        clock_t elapsed=clock()-begin;
        total+=elapsed;
        if (elapsed>maximum) maximum=elapsed;
        ++frames;
    } while (ui_workshop_pending());
    if (!strcmp(name,"house-dusk") || !strcmp(name,"house-night") ||
        !strcmp(name,"castle-night")) assert(frames<=29);
    printf("cache_capture name=%s frames=%u total_us=%lu max_frame_us=%lu\n",name,frames,
        (unsigned long)(total*1000000/CLOCKS_PER_SEC),
        (unsigned long)(maximum*1000000/CLOCKS_PER_SEC));
    lv_obj_update_layout(lv_screen_active());
    lv_refr_now(NULL);
    char path[1024];
    snprintf(path,sizeof path,"%s/%s.rgb565",directory,name);
    FILE *file=fopen(path,"wb");
    assert(file && fwrite(framebuffer,sizeof framebuffer,1,file)==1);
    fclose(file);

}
static void step(unsigned count,int x,int y,int cls)
{
    for (unsigned i=0;i<count;++i) workshop_step(&fixture,(ws_input){x,y,cls,false,0});
}
int main(int argc,char **argv)
{
    assert(argc==2);
    directory=argv[1];
    lv_init();
    lv_display_t *display=lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init();
    ui_start();
    ui_demo_t demo={0};
    ui_hand_t hand={0};
    sim_data_demo(&demo,&hand,&sim_indoor);
    ui_open(17);
    sim_data_session(UI_APP_GRAB,UI_STATE_RUNNING,NULL);
    ui_refresh();
    game_loop_stop();
    workshop_init(&fixture);
    fixture.hand=(ws_input){660,505,0,false,0};
    game_loop_config config={freeze,snapshot,report,&fixture,
        {&snapshots[0],&snapshots[1],&snapshots[2]},sizeof(workshop_snapshot)};
    game_loop_start(&config);
    capture("selection");
    static const char *const names[]={"clearing-day","house-day","castle-day"};
    for (unsigned scene=0;scene<3;++scene) {
        workshop_scene(&fixture,scene);
        fixture.hand=(ws_input){1020,240,0,false,0};
        capture(names[scene]);
        if (scene==1) {
            fixture.sky=WS_DUSK; capture("house-dusk");
            fixture.sky=WS_NIGHT; capture("house-night");
        }
        if (scene==2) { fixture.sky=WS_NIGHT; capture("castle-night"); }
    }
    workshop_scene(&fixture,1);
    step(24,760,340,7);
    capture("inventory-hold-half");
    lv_obj_t *arc=NULL;
    for(unsigned i=0;i<lv_obj_get_child_count(lv_screen_active());++i) {
        lv_obj_t *object=lv_obj_get_child(lv_screen_active(),(int)i);
        if(lv_obj_check_type(object,&lv_arc_class)) arc=object;
    }
    assert(arc && !lv_obj_is_hidden(arc));
    assert(lv_arc_get_value(arc)==24 && lv_arc_get_max_value(arc)==48);
    step(1,760,340,0);
    lv_tick_inc(17); game_loop_step(); ui_workshop_update();
    assert(lv_obj_is_hidden(arc));
    workshop_scene(&fixture,1);
    fixture.sky=WS_NIGHT;
    fixture.inventory=true;
    fixture.inventory_hover=6;
    fixture.hand=(ws_input){500,270,0,false,0};
    capture("inventory");
    workshop_scene(&fixture,1);
    fixture.selected=WS_PICK;
    step(18,424,512,1);
    workshop_snapshot snap;
    workshop_snapshot_copy(&fixture,&snap);
    assert(snap.crack==4);
    capture("crack-4");
    workshop_scene(&fixture,0);
    for (int x=5;x<15;++x) for (int y=3;y<6;++y)
        fixture.blocks[40+(x-5)*3+y-3]=(ws_block){true,WS_STONEBRICK,0,
                                               (int16_t)x,(int16_t)y,0};
    workshop_reconnect(&fixture);
    step(20,1000,300,0);
    capture("falling");
    workshop_scene(&fixture,1);
    ws_animal *animal=&fixture.animals[0];
    step(1,animal->x/2,animal->y/2-20,1);
    step(1,750,320,1);
    assert(animal->action==WS_LIFT);
    capture("animal-lift");
    workshop_scene(&fixture,1);
    fixture.selected=WS_PICK;
    animal=&fixture.animals[0];
    step(1,animal->x/2+4,animal->y/2-20,1);
    assert(animal->action==WS_STUN);
    capture("animal-stun");
    workshop_scene(&fixture,1);
    fixture.selected=WS_BRICK_SLOPE;
    fixture.orientation=1;
    step(1,808,368,0);
    capture("slope-preview");
    fixture.sky=WS_NIGHT;
    lv_tick_inc(17); game_loop_step(); ui_workshop_update();
    while (ui_workshop_pending()) ui_workshop_update();
    workshop_remove(&fixture,fixture.grid[10][0]);
    lv_tick_inc(17); game_loop_step(); ui_workshop_update();
    assert(ui_workshop_pending()==0);
    puts("PASS night single-cell edit completes in the current GUI frame");
    game_loop_stop();
    ui_open(0);
    lv_deinit();
    puts("PASS native workshop 14 scene, sky and interaction captures");
}
