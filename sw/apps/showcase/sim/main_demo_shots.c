/* main_demo_shots.c — T-DEMO-PAGES; actual C-verified INT8 evaluation fixtures.
 * Native LVGL framebuffer capture, no SoC/RTL simulation; host domain.
 */
#include "theme.h"
#include "sim_data.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint16_t framebuffer[1280*720], background[1280*720];
static uint32_t drawbuffer[1280*720];
static const lv_image_dsc_t image = {
    .header = {.magic = LV_IMAGE_HEADER_MAGIC, .cf = LV_COLOR_FORMAT_RGB565,
        .w = 1280, .h = 720, .stride = 2560},
    .data_size = sizeof background, .data = (const uint8_t *)background
};
static void flush(lv_display_t *display, const lv_area_t *a, uint8_t *pixels)
{
    const uint32_t *source = (const uint32_t *)pixels;
    for (int y = a->y1; y <= a->y2; ++y) for (int x = a->x1; x <= a->x2; ++x) {
        uint32_t c = sim_composite(&image, *source++, (unsigned)x, (unsigned)y);
        framebuffer[y*1280+x] = (uint16_t)(((c >> 8)&0xf800) | ((c >> 5)&0x7e0) | ((c >> 3)&31));
    }
    lv_display_flush_ready(display);
}
static void read_exact(void *data, size_t size, FILE *f)
{ assert(fread(data, size, 1, f) == 1); }
int main(int argc, char **argv)
{
    assert(argc == 2);
    lv_init();
    lv_display_t *display = lv_display_create(1280,720);
    lv_display_set_color_format(display, LV_COLOR_FORMAT_ARGB8888);
    lv_display_set_buffers(display, drawbuffer, NULL, sizeof drawbuffer,
                           LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(display, flush);
    sim_data_init(); ui_start();
    static const char *const names[] = {"gesture","face","doodle","helmet"};
    for (unsigned model = 0; model < 4; ++model) {
        char path[1024];
        snprintf(path, sizeof path, "%s/%s.rgb565", argv[1], names[model]);
        FILE *f = fopen(path, "rb"); assert(f);
        read_exact(background, sizeof background, f); fclose(f);
        snprintf(path, sizeof path, "%s/%s.expected", argv[1], names[model]);
        f = fopen(path, "rb"); assert(f);
        uint32_t count;
        read_exact(&count, sizeof count, f);
        ui_demo_t demo = {0};
        ui_hand_t hand = {.state = {.cls = -1, .candidate = -1}};
        demo.count = hand.count = count;
        unsigned largest = 0;
        for (unsigned i = 0; i < count; ++i) {
            uint16_t anchor, d[6];
            float mapped[4];
            read_exact(&anchor, sizeof anchor, f);
            read_exact(d, sizeof d, f); read_exact(mapped, sizeof mapped, f);
            unsigned cls = d[4];
            const char *label = model == 0 ? ui_gesture_names[cls] : model == 1 ? "人脸" :
                model == 2 ? ui_doodle_names[cls] : cls ? "未戴" : "安全帽";
            ui_detection_t box = {label,d[5]/10,d[0],d[1],d[2]-d[0],d[3]-d[1],cls};
            demo.objects[i] = hand.people[i] = box;
            unsigned size = (unsigned)LV_MAX(box.width,box.height);
            demo.size = LV_MAX(demo.size,size);
            if (model == 3) { if (cls) ++demo.head; else ++demo.helmet; }
            unsigned nk = model == 0 ? 21 : model == 1 ? 5 : 0;
            ui_pose_point_t points[21];
            if (nk) read_exact(points, nk*sizeof points[0], f);
            if (model == 0) memcpy(hand.points[i],points,21*sizeof points[0]);
            if (model == 1) memcpy(demo.points[i],points,5*sizeof points[0]);
            if (box.width*box.height > hand.people[largest].width*hand.people[largest].height)
                largest = i;
        }
        fclose(f);
        if (count) {
            const ui_detection_t *b = &hand.people[largest];
            hand.size = (unsigned)LV_MAX(b->width,b->height); hand.confidence = b->confidence;
            for (unsigned i = 0; i < 3; ++i) ui_gesture_debounce(&hand.state,(int)b->class_id);
        }
        sim_data_demo(&demo,&hand,&image);
        ui_open(10+model); lv_tick_inc(200); ui_refresh();
        lv_obj_update_layout(lv_screen_active()); lv_obj_invalidate(lv_screen_active());
        lv_refr_now(NULL);
        snprintf(path,sizeof path,"shots/demo-%s.rgb565",names[model]);
        f = fopen(path,"wb"); assert(f);
        assert(fwrite(framebuffer,sizeof framebuffer,1,f) == 1); assert(!fclose(f));
    }
    lv_deinit();
    puts("PASS four model pages captured from C-verified INT8 fixtures");
    return 0;
}
