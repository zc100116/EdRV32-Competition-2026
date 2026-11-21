/* main_grab_shot.c — T-GRAB-TEST; replay verified gesture keypoints through D.
 * Native LVGL screenshot; fixture hand moves to object 3, then back to its photo position.
 */
#include "theme.h"
#include "grab.h"
#include "sim_data.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint16_t framebuffer[1280*720];
static uint16_t background[1280*720];
static uint32_t drawbuffer[1280*720];
static const lv_image_dsc_t image = {
    .header = {.magic=LV_IMAGE_HEADER_MAGIC,.cf=LV_COLOR_FORMAT_RGB565,
        .w=1280,.h=720,.stride=2560},
    .data_size=sizeof background,.data=(const uint8_t *)background
};
static void flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    const uint32_t *source = (const uint32_t *)pixels;
    for (int y = area->y1; y <= area->y2; ++y)
        for (int x = area->x1; x <= area->x2; ++x) {
            uint32_t c = sim_composite(&image,*source++,(unsigned)x,(unsigned)y);
            framebuffer[y*1280+x] =
                (uint16_t)(((c>>8)&0xf800)|((c>>5)&0x7e0)|((c>>3)&31));
        }
    lv_display_flush_ready(display);
}
int main(int argc, char **argv)
{
    assert(argc == 2);
    char path[1024];
    snprintf(path,sizeof path,"%s/gesture.rgb565",argv[1]);
    FILE *f = fopen(path,"rb"); assert(f);
    assert(fread(background,sizeof background,1,f) == 1); fclose(f);
    snprintf(path,sizeof path,"%s/gesture.expected",argv[1]);
    f = fopen(path,"rb"); assert(f);
    uint32_t count;
    uint16_t record[7];
    float mapped[4];
    ui_hand_t hand = {.state={.cls=8,.candidate=8,.frames=3}};
    assert(fread(&count,sizeof count,1,f) == 1 && count > 0);
    assert(fread(record,sizeof record,1,f) == 1);
    assert(fread(mapped,sizeof mapped,1,f) == 1);
    assert(fread(hand.points[0],sizeof hand.points[0],1,f) == 1); fclose(f);
    hand.count = 1;
    hand.people[0] = (ui_detection_t){.width=record[3]-record[1],
        .height=record[4]-record[2]};
    lv_init();
    lv_display_t *display = lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init(); ui_start();
    ui_demo_t demo = {0};
    sim_data_demo(&demo,&hand,&image);
    ui_open(14);
    ui_grab.mode = 3;
    ui_grab.keypoints = true;
    ui_pose_point_t moved[21];
    float dx = 740 - (hand.points[0][4].x+hand.points[0][8].x)/2;
    float dy = 600 - (hand.points[0][4].y+hand.points[0][8].y)/2;
    for (unsigned k = 0; k < 21; ++k) {
        moved[k] = hand.points[0][k]; moved[k].x += dx; moved[k].y += dy;
    }
    uint32_t sample_ms = 0;
    grab_frame(&ui_grab,moved,8,sample_ms+=40);
    grab_frame(&ui_grab,moved,8,sample_ms+=40);
    assert(ui_grab.held == 3);
    for (unsigned i = 0; i < 12; ++i)
        grab_frame(&ui_grab,hand.points[0],8,sample_ms+=40);
    assert(ui_grab.closed && ui_grab.held == 3 && ui_grab.objects[3].y < 550);
    lv_tick_inc(200);
    ui_refresh();
    ui_grab_update();
    lv_obj_update_layout(lv_screen_active());
    lv_refr_now(NULL);
    f = fopen("shots/demo-grab.rgb565","wb"); assert(f);
    assert(fwrite(framebuffer,sizeof framebuffer,1,f) == 1); fclose(f);
    lv_deinit();
    puts("PASS native grab screenshot: verified fixture, D pick/drag object 3");
}
