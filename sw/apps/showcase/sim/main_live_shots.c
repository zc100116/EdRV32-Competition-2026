/* main_compact_shots.c — R4 §5; native LVGL page checks and framebuffer captures.
 * Host clock timings include software rendering and RGB565 output composition.
 */
#define _POSIX_C_SOURCE 200809L
#include "widgets.h"
#include "live_demo.h"
#include "detection.h"
#include "sim_data.h"
#include "motion.h"
#include "grab.h"
#include "sticker.h"
#include "track.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static uint16_t framebuffer[1280*720];
static uint32_t drawbuffer[1280*720];
static const char *output;
static unsigned covered;
static uint64_t host_ns(void)
{
    struct timespec time;
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&time);
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
    covered=0;
    for(unsigned i=0;i<1280*720;++i) covered+=(drawbuffer[i]>>24)!=0;
    check_labels(lv_screen_active());
    printf("coverage %s pixels=%u ratio=%.3f%%\n",name,covered,covered*100.0/(1280*720));
    char path[1024];
    snprintf(path,sizeof path,"%s/%s.rgb565",output,name);
    FILE *file = fopen(path,"wb");
    if (!file) { perror(path); exit(EXIT_FAILURE); }
    assert(fwrite(framebuffer,sizeof framebuffer,1,file) == 1);
    assert(fclose(file) == 0);
}
int main(int argc,char **argv)
{
    assert(argc==2); output=argv[1];
    lv_init();
    lv_display_t *display=lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init(); ui_start();
    capture("home");
    ui_live_command(4,0); capture("directory");
    assert(ui_page==LIVE_DEMO_PAGE && ui_live_scene()==255);
    ui_live_command(0,4);
    ui_demo_t demo={.count=1,.helmet=1,.size=240}; ui_hand_t hand={0};
    extern const lv_image_dsc_t sim_indoor;
    demo.objects[0]=(ui_detection_t){.x=420,.y=190,.width=180,.height=240,
        .confidence=92,.category="安全帽"};
    sim_data_demo(&demo,&hand,&sim_indoor);
    ++helmet_revision;
    capture("helmet-banner");
    ui_camera_drawer_toggle();
    lv_tick_inc(200); lv_timer_handler();
    capture("preset-drawer");
    ui_preprocess_t config = ui_data_preprocess();
    config.auto_levels = true; config.auto_gamma = false;
    ui_data_preprocess_custom(&config);
    /* Show the complete advanced section, including the exposure and filter rows. */
    lv_obj_t *advanced = NULL;
    lv_group_t *group = lv_group_get_default();
    for (unsigned i = 0; i < lv_group_get_obj_count(group); ++i) {
        lv_obj_t *o = lv_group_get_obj_by_index(group,i);
        if (lv_obj_check_type(o,&lv_dropdown_class) && ui_camera_drawer_contains(o))
            advanced = o;
    }
    assert(advanced);
    lv_obj_scroll_to_view_recursive(advanced,LV_ANIM_OFF);
    capture("advanced-drawer");
    ui_back(); assert(ui_page==13);
    ui_back(); assert(ui_page==LIVE_DEMO_PAGE);
    /* Directory focus is next scene; remote NEXT still uses last entered scene 4. */
    ui_live_command(1,0); assert(ui_page==19 && ui_live_scene()==5);
    ui_live_command(0,11); ui_live_command(1,0); assert(ui_live_scene()==1);
    ui_live_command(2,0); assert(ui_live_scene()==11);
    ui_live_command(0,7); ui_tab=1; ui_back(); assert(ui_page==LIVE_DEMO_PAGE);
    ui_live_command(0,8); ui_key(LV_KEY_ESC); assert(ui_page==LIVE_DEMO_PAGE);
    ui_back(); assert(ui_page==0 && ui_live_scene()==0);
    ui_live_command(2,0); assert(ui_live_scene()==11);
    ui_live_command(0,6);
    uint32_t process_start=lv_tick_get();
    lv_tick_inc(18000-200); capture("process-sobel");
    assert(ui_data_process_config().stage1==4);
    lv_tick_inc(process_start+36750-lv_tick_get()-200); capture("process-rotation");
    assert(ui_data_process_config().angle==90);
    lv_tick_inc(process_start+51000-lv_tick_get()-200); capture("process-combined");
    assert(ui_data_process_config().stage2==4);
    ui_back();
    puts("PASS live UI: eleven scenes, wrap, drawer priority, custom ESC and directory return");
    return 0;
}
