/* page_grab.c — T-GRAB-TEST; minimal L1 objects over live L0 camera.
 * GUI domain; redraw unions of old/new bounds, gravity ticks independently at 30 Hz.
 */
#include "theme.h"
#include "grab.h"
#include "src/draw/lv_draw_private.h"
#include "src/misc/lv_area_private.h"
#include <stdio.h>
#include <string.h>
static lv_obj_t *frame;
static lv_obj_t *status;
static lv_timer_t *animation;
static uint32_t animated_at;
static grab_state_t shown;
static ui_pose_point_t points[21];
static bool have_points;
static const unsigned bones[][2] = {
    {0,1},{1,2},{2,3},{3,4},{0,5},{5,6},{6,7},{7,8},
    {0,9},{9,10},{10,11},{11,12},{0,13},{13,14},{14,15},{15,16},
    {0,17},{17,18},{18,19},{19,20}
};
static lv_area_t bounds(float x, float y, int radius)
{
    int cx = (int)x;
    int cy = (int)y;
    return (lv_area_t){cx-radius,cy-radius,cx+radius,cy+radius};
}
static void invalidate_move(float x, float y, float nx, float ny, int radius)
{
    lv_area_t old = bounds(x,y,radius);
    lv_area_t next = bounds(nx,ny,radius);
    lv_area_join(&old,&old,&next);
    lv_obj_invalidate_area(frame,&old);
}
static void invalidate_points(void)
{
    if (!have_points) return;
    lv_area_t area = bounds(points[0].x,points[0].y,4);
    for (unsigned i = 1; i < 21; ++i) {
        lv_area_t p = bounds(points[i].x,points[i].y,4);
        lv_area_join(&area,&area,&p);
    }
    lv_obj_invalidate_area(frame,&area);
}
static void draw(lv_event_t *event)
{
    lv_layer_t *layer = lv_event_get_layer(event);
    lv_draw_rect_dsc_t rect;
    lv_draw_rect_dsc_init(&rect);
    rect.bg_color = lv_color_hex(0xffffff);
    lv_area_t ground = {40,GRAB_GROUND,1240,GRAB_GROUND+2};
    lv_draw_rect(layer,&rect,&ground);
    static const uint32_t colors[] = {0xef4444,0xf97316,0xfacc15,0x22c55e,0x3b82f6,0xa855f7};
    for (unsigned i = 0; i < GRAB_OBJECTS; ++i) {
        rect.bg_color = lv_color_hex(colors[i]);
        rect.radius = i < 3 ? 12 : LV_RADIUS_CIRCLE;
        int x = (int)shown.objects[i].x;
        int y = (int)shown.objects[i].y;
        lv_area_t area = {x-50,y-50,x+49,y+49};
        lv_draw_rect(layer,&rect,&area);
    }
    rect.radius = LV_RADIUS_CIRCLE;
    rect.border_width = 3;
    rect.border_color = lv_color_hex(shown.closed ? 0xff4fad : 0xffffff);
    rect.bg_color = rect.border_color;
    rect.bg_opa = shown.closed ? LV_OPA_COVER : LV_OPA_TRANSP;
    lv_area_t cursor = bounds(shown.x,shown.y,13);
    lv_draw_rect(layer,&rect,&cursor);
    if (!shown.keypoints || !have_points) return;
    lv_draw_line_dsc_t line;
    lv_draw_line_dsc_init(&line);
    line.color = lv_color_hex(0xffffff);
    line.width = 2;
    for (unsigned b = 0; b < sizeof bones / sizeof bones[0]; ++b) {
        const ui_pose_point_t *a = &points[bones[b][0]];
        const ui_pose_point_t *c = &points[bones[b][1]];
        if (a->visibility < .5f || c->visibility < .5f) continue;
        line.p1 = (lv_point_precise_t){a->x,a->y};
        line.p2 = (lv_point_precise_t){c->x,c->y};
        lv_draw_line(layer,&line);
    }
    rect.border_width = 0;
    rect.bg_opa = LV_OPA_COVER;
    rect.bg_color = lv_color_hex(0x22c55e);
    for (unsigned i = 0; i < 21; ++i) {
        if (points[i].visibility < .5f) continue;
        lv_area_t dot = bounds(points[i].x,points[i].y,3);
        lv_draw_rect(layer,&rect,&dot);
    }
}
void ui_grab_update(void)
{
    for (unsigned i = 0; i < GRAB_OBJECTS; ++i) {
        const grab_object_t *a = &shown.objects[i];
        const grab_object_t *b = &ui_grab.objects[i];
        if (a->x != b->x || a->y != b->y) invalidate_move(a->x,a->y,b->x,b->y,51);
    }
    if (shown.x != ui_grab.x || shown.y != ui_grab.y || shown.closed != ui_grab.closed)
        invalidate_move(shown.x,shown.y,ui_grab.x,ui_grab.y,15);
    const ui_hand_t *hand = ui_data_hand();
    if (shown.keypoints || ui_grab.keypoints) invalidate_points();
    have_points = hand->count != 0;
    if (have_points) {
        unsigned largest = 0;
        for (unsigned i = 1; i < hand->count; ++i)
            if (hand->people[i].width * hand->people[i].height >
                hand->people[largest].width * hand->people[largest].height) largest = i;
        memcpy(points,hand->points[largest],sizeof points);
    }
    shown = ui_grab;
    if (shown.keypoints) invalidate_points();
    char value[32];
    char param[48];
    char text[320];
    grab_value(&shown,value,sizeof value);
    if (shown.mode < 2) {
        int t = shown.thresholds[shown.mode];
        int r = t + (shown.mode == 0 ? 15 : 20);
        snprintf(param,sizeof param,"%s%d.%02d / %s%d.%02d",
                 t < 0 ? "-" : "",LV_ABS(t)/100,LV_ABS(t)%100,
                 r < 0 ? "-" : "",LV_ABS(r)/100,LV_ABS(r)%100);
    } else if (shown.mode == 2) snprintf(param,sizeof param,"无");
    else snprintf(param,sizeof param,"m=%d px",shown.thresholds[3]);
    snprintf(text,sizeof text,
        "模式 %c   d=%s   参数 %s\n状态 %s   物体 %d   拿起 %u   放下 %u   fps %u\n"
        "关键点 %s   镜像 %s   物体 0–5：红 橙 黄 绿 蓝 紫",
        'A'+shown.mode,value,param,shown.closed ? "抓" : "放",shown.held,
        shown.picks,shown.drops,ui_data_vision().fps,
        shown.keypoints ? "开" : "关",shown.mirror ? "开" : "关");
    ui_text(status,text);
}
static void tick(lv_timer_t *timer)
{
    (void)timer;
    uint32_t now = lv_tick_get();
    grab_animate(&ui_grab,(now-animated_at)/1000.f);
    animated_at = now;
    ui_grab_update();
}
static void deleted(lv_event_t *event)
{
    (void)event;
    lv_timer_delete(animation);
}
void ui_grab_action(unsigned action)
{
    if (action == 0) {
        ui_grab.mode = (ui_grab.mode + 1) % 4;
        ui_grab.pending_frames = 0;
        ui_grab.smooth = false;
    } else if (action == 1 || action == 2) {
        if (ui_grab.mode == 2) return;
        ui_grab.thresholds[ui_grab.mode] += action == 1 ? -5 : 5;
        char text[80];
        int t = ui_grab.thresholds[ui_grab.mode];
        if (ui_grab.mode < 2)
            snprintf(text,sizeof text,"grab param mode=%c value=%s%d.%02d\r\n",
                     'A'+ui_grab.mode,t < 0 ? "-" : "",LV_ABS(t)/100,LV_ABS(t)%100);
        else snprintf(text,sizeof text,"grab param mode=D value=%d\r\n",t);
        ui_data_grab_output(text);
        ui_grab.pending_frames = 0;
    } else if (action == 3) ui_grab.keypoints = !ui_grab.keypoints;
    else if (action == 4) {
        ui_grab.mirror = !ui_grab.mirror;
        ui_data_grab_mirror(ui_grab.mirror);
    } else if (action == 5) grab_reset_objects(&ui_grab);
    ui_grab_update();
}
void ui_page_grab(lv_obj_t *p)
{
    grab_init(&ui_grab);
    shown = ui_grab;
    have_points = false;
    ui_video_surface(p);
    ui_label(p,"抓取测试",24,10,&sim_font_28,TEXT);
    static const char *const labels[] = {
        "模式", "参数 −", "参数 +", "关键点 开关", "镜像 开关", "物体复位"
    };
    for (unsigned i = 0; i < 6; ++i)
        ui_button(p,labels[i],230+170*(int)i,6,160,i);
    frame = ui_box(lv_screen_active(),0,0,1280,720,BG);
    lv_obj_set_style_bg_opa(frame,LV_OPA_TRANSP,0);
    lv_obj_set_style_border_width(frame,0,0);
    lv_obj_move_to_index(frame,0);
    lv_obj_add_event_cb(frame,draw,LV_EVENT_DRAW_MAIN,NULL);
    lv_obj_add_event_cb(frame,deleted,LV_EVENT_DELETE,NULL);
    lv_obj_t *panel = ui_box(p,24,60,900,94,PANEL);
    lv_obj_set_style_bg_opa(panel,LV_OPA_80,0);
    status = ui_label(panel,"",12,8,&sim_font_16,TEXT);
    animated_at = lv_tick_get();
    animation = lv_timer_create(tick,33,NULL);
    ui_hint("选择模式和参数 · 捏起、拖动、松手自由下落 · 只跟踪最大的手");
}
