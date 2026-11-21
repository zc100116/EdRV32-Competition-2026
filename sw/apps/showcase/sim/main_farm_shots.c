/* main_farm_shots.c — R5-11; single-area counts, intrusion and dashboard captures.
 * Host clock timings include software rendering and RGB565 output composition.
 */
#define _POSIX_C_SOURCE 200809L
#include "widgets.h"
#include "detection.h"
#include "sim_data.h"
#include "motion.h"
#include "grab.h"
#include "sticker.h"
#include "farm.h"
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
static lv_obj_t *find_label(lv_obj_t *parent, const char *text)
{
    if(lv_obj_check_type(parent,&lv_label_class) &&
       !lv_strcmp(lv_label_get_text(parent),text)) return parent;
    for(unsigned i=0;i<lv_obj_get_child_count(parent);++i) {
        lv_obj_t *found=find_label(lv_obj_get_child(parent,(int)i),text);
        if(found) return found;
    }
    return NULL;
}
static bool hidden(lv_obj_t *object)
{
    for(;object;object=lv_obj_get_parent(object))
        if(lv_obj_is_hidden(object)) return true;
    return false;
}
static void traverse(void)
{
    lv_group_t *group=lv_group_get_default();
    unsigned count=lv_group_get_obj_count(group);
    bool visited[256]={false};
    assert(count<256);
    for(unsigned i=0;i<count*2;++i) {
        ui_key(LV_KEY_NEXT);
        lv_obj_t *focused=lv_group_get_focused(group);
        for(unsigned j=0;j<count;++j)
            if(focused==lv_group_get_obj_by_index(group,j)) visited[j]=true;
    }
    for(unsigned j=0;j<count;++j) {
        lv_obj_t *object=lv_group_get_obj_by_index(group,j);
        if(!hidden(object) && !lv_obj_is_disabled(object)) assert(visited[j]);
    }
}
static ui_detection_t animals[10];
static void frame(unsigned count, unsigned elapsed)
{
    sim_data_farm(animals,count);
    lv_tick_inc(elapsed);
    ui_refresh();
}
int main(int argc,char **argv)
{
    assert(argc==2); output=argv[1];
    setvbuf(stdout,NULL,_IOLBF,0);
    lv_init();
    lv_display_t *display=lv_display_create(1280,720);
    lv_display_set_color_format(display,LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display,drawbuffer,NULL,sizeof drawbuffer,LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display,flush);
    sim_data_init(); ui_start();
    const unsigned ids[10]={19,19,19,17,14,14,18,18,18,0};
    const int positions[10][2]={{80,220},{320,320},{510,480},{280,480},
        {990,510},{1130,440},{620,240},{720,420},{1020,310},{850,180}};
    for(unsigned i=0;i<10;++i) animals[i]=(ui_detection_t){
        .category=ui_coco_names[ids[i]],.class_id=ids[i],.confidence=95,
        .x=positions[i][0],.y=positions[i][1],.width=i==9 ? 120 : 80,
        .height=i==9 ? 260 : 80};
    ui_open(FARM_PAGE);
    /* Use full raw boxes even when the other application's display filter excludes them. */
    ui_data_detection_all(false);
    for(unsigned i=0;i<60;++i) {
        frame(7+i%3,9000);
        frame(7+i%3,1000);
    }
    frame(9,33);
    ui_activate(0);
    capture("normal");
    assert(covered*100<=1280*720*15);
    assert(find_label(lv_screen_active(),"牛 3 / 3"));
    assert(find_label(lv_screen_active(),"羊 3 / 3"));
    assert(!find_label(lv_screen_active(),"栏位对齐"));
    traverse();
    frame(10,33);
    frame(10,499);
    frame(10,1);
    capture("intrude");
    lv_obj_t *warning=find_label(lv_screen_active(),"有人闯入");
    assert(warning && !hidden(warning));
    assert(find_label(lv_screen_active(),"牛 3 / 3"));
    unsigned red=0;
    for(unsigned y=180;y<440;++y) for(unsigned x=850;x<970;++x)
        red+=(drawbuffer[y*1280+x]&0xffffff)==0xdc2626;
    assert(red>500);
    frame(9,33);
    frame(9,1000);
    assert(hidden(warning));
    frame(8,33);
    frame(8,1000);
    frame(8,3000);
    capture("missing");
    assert(find_label(lv_screen_active(),"羊 走失：少 1 只"));
    assert(find_label(lv_screen_active(),"羊 #dc2626 2# / 3"));
    lv_obj_t *label=find_label(lv_screen_active(),"看板"); assert(label);
    lv_obj_send_event(lv_obj_get_parent(label),LV_EVENT_CLICKED,NULL);
    lv_tick_inc(200); lv_timer_handler();
    lv_obj_update_layout(lv_screen_active());
    lv_obj_t *inventory=find_label(lv_screen_active(),"动物盘点 · 当前 / 基准");
    assert(inventory);
    lv_obj_scroll_to_y(lv_obj_get_parent(inventory),lv_obj_get_y(inventory),LV_ANIM_OFF);
    capture("dashboard");
    assert(find_label(lv_screen_active(),"今日走失 1 次 · 闯入 1 次"));
    assert(find_label(lv_screen_active(),"动物盘点 · 当前 / 基准"));
    const uint32_t colors[]={TEAL,ACCENT,0xd97706,0x9333ea};
    for(unsigned c=0;c<4;++c) {
        unsigned pixels=0;
        for(unsigned y=300;y<650;++y) for(unsigned x=972;x<1260;++x)
            pixels+=(drawbuffer[y*1280+x]&0xffffff)==colors[c];
        assert(pixels>50);
    }
    traverse();
    ui_back(); assert(ui_page==FARM_PAGE);
    frame(9,33);
    frame(9,3000);
    assert(hidden(find_label(lv_screen_active(),"羊 走失：少 1 只")));
    ui_hide_interface(); assert(ui_restore_interface());
    ui_back(); assert(ui_page==0);
    ui_home_select_tab(0);
    capture("home-ai");
    assert(find_label(lv_screen_active(),"智慧农场"));
    assert(find_label(lv_screen_active(),"动物盘点与闯入告警"));
    ui_open(FARM_PAGE);
    assert(!find_label(lv_screen_active(),"左分界 33%"));
    ui_data_detection_all(true);
    puts("PASS farm UI: whole-area counts, inventory, red person box, "
         "intrusion/clear, loss/clear, drawer and home");
    return 0;
}
