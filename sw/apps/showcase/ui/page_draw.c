/* page_draw.c — T-DRAW / R5-5; retained ARGB8888 strokes above the live camera.
 * GUI clock at 40 ms; only new stamps and old/new cursor bounds are invalidated.
 */
#include "widgets.h"
#include "draw.h"
#include "grab.h"
#include <stdio.h>
#include <string.h>
#include "src/misc/lv_area_private.h"
static uint32_t pixels[DRAW_WIDTH*DRAW_HEIGHT] __attribute__((aligned(64)));
static const lv_image_dsc_t image = {
    .header = {.magic = LV_IMAGE_HEADER_MAGIC, .cf = LV_COLOR_FORMAT_ARGB8888,
               .w = DRAW_WIDTH, .h = DRAW_HEIGHT, .stride = DRAW_WIDTH*4},
    .data_size = sizeof pixels, .data = (const uint8_t *)pixels
};
static draw_state_t state;
static lv_obj_t *canvas;
static lv_obj_t *cursor;
static lv_obj_t *arc;
static lv_obj_t *buttons[DRAW_ITEMS];
static lv_timer_t *timer;
static uint32_t report_at;
static unsigned frames;
static bool changed;
static lv_area_t dirty;
static lv_area_t stamp_bounds(int x, int y, int radius)
{
    return (lv_area_t){x-radius,y-radius,x+radius,y+radius};
}
static void stamp(void *context, const draw_state_t *s, int x, int y)
{
    (void)context;
    draw_raster(pixels,s,x,y);
    lv_area_t area = stamp_bounds(x,y,(int)draw_sizes[s->size]/2+1);
    if (changed) lv_area_join(&dirty,&dirty,&area);
    else dirty = area;
    changed = true;
}
static void selection(void)
{
    for (unsigned i = 0; i < DRAW_ITEMS; ++i) {
        bool selected = i == state.color || i == 8+state.size ||
            i == (state.tool == DRAW_PEN ? 11u : 12u);
        lv_obj_set_state(buttons[i],LV_STATE_CHECKED,selected);
    }
}
static void select_item(unsigned item)
{
    draw_select(&state,item);
    if (item == 13) {
        memset(pixels,0,sizeof pixels);
        lv_obj_invalidate(canvas);
    }
    selection();
}
static void clicked(lv_event_t *event)
{
    select_item((unsigned)(uintptr_t)lv_event_get_user_data(event));
}
void ui_draw_update(void)
{
    const ui_hand_t *hand = ui_data_hand();
    uint32_t now = lv_tick_get();
    unsigned largest = 0;
    for (unsigned i = 1; i < hand->count; ++i)
        if (hand->people[i].width*hand->people[i].height >
            hand->people[largest].width*hand->people[largest].height) largest = i;
    bool present = hand->count != 0;
    float x = present ? hand->points[largest][8].x : state.x;
    float y = present ? hand->points[largest][8].y : state.y;
    int item = draw_hover(&state,present,(int)x,(int)y,now);
    if (item >= 0) select_item((unsigned)item);
    changed = false;
    draw_point_t points[21];
    if (present)
        for (unsigned i = 0; i < 21; ++i)
            points[i] = (draw_point_t){hand->points[largest][i].x,hand->points[largest][i].y};
    draw_step(&state,present,present ? (int)hand->people[largest].class_id : -1,
              present && draw_pointing(points),x,y,now,stamp,NULL);
    if (changed) lv_obj_invalidate_area(canvas,&dirty);
    int size = (int)draw_sizes[state.size];
    lv_obj_set_size(cursor,size,size);
    lv_obj_set_pos(cursor,(int)state.x-size/2,(int)state.y-size/2);
    lv_obj_set_style_radius(cursor,state.tool == DRAW_ERASER ? 0 : LV_RADIUS_CIRCLE,0);
    lv_obj_set_style_bg_color(cursor,lv_color_hex(draw_colors[state.color]),0);
    lv_obj_set_style_border_color(cursor,lv_color_hex(draw_colors[state.color]),0);
    lv_obj_set_style_bg_opa(cursor,state.down ? LV_OPA_COVER : LV_OPA_TRANSP,0);
    lv_obj_set_hidden(cursor,!state.visible);
    lv_arc_set_value(arc,(int)state.hold);
    lv_obj_set_hidden(arc,!present || state.hover < 0 || state.selected);
    if (state.hover >= 0) lv_obj_set_pos(arc,188+64*state.hover,76);
    if (now-report_at >= 1000) {
        char line[128];
        snprintf(line,sizeof line,
            "draw draw_fps=%u strokes=%u points=%u tool=%s cls=%d\r\n",
            (unsigned)(frames*1000/(now-report_at)),state.strokes,state.points,
            state.tool == DRAW_PEN ? "pen" : "eraser",state.cls);
        ui_data_grab_output(line);
        frames = 0;
        report_at = now;
    }
}
static void tick(lv_timer_t *t) { (void)t; ui_draw_update(); }
static void rendered(lv_event_t *event) { (void)event; ++frames; }
static void deleted(lv_event_t *event)
{
    (void)event;
    lv_timer_delete(timer);
    lv_display_remove_event_cb_with_user_data(lv_display_get_default(),rendered,canvas);
}
void ui_page_draw(lv_obj_t *parent)
{
    draw_init(&state);
    memset(pixels,0,sizeof pixels);
    lv_obj_set_style_bg_opa(parent,LV_OPA_TRANSP,0);
    /* Absolute children stay outside the camera header's flex flow. */
    lv_obj_t *shade = ui_box(parent,0,48,1280,672,0x071225);
    lv_obj_set_ignore_layout(shade,true);
    lv_obj_set_style_bg_opa(shade,LV_OPA_20,0);
    lv_obj_set_style_border_width(shade,0,0);
    lv_obj_set_style_radius(shade,0,0);
    canvas = lv_image_create(parent);
    lv_obj_set_ignore_layout(canvas,true);
    lv_obj_set_pos(canvas,0,0);
    lv_image_set_src(canvas,&image);
    lv_obj_t *header = ui_camera_layout(parent,"空中画板");
    ui_text_label(header,"伸出食指画，换手势抬笔",&sim_font_16,MUTED);
    lv_obj_t *bar = ui_box(parent,180,72,920,72,PANEL);
    lv_obj_set_ignore_layout(bar,true);
    lv_obj_set_style_border_width(bar,1,0);
    static const char *const names[] = {"6","12","24","笔","橡皮","清空"};
    for (unsigned i = 0; i < DRAW_ITEMS; ++i) {
        lv_obj_t *b = lv_button_create(bar);
        buttons[i] = b;
        ui_control_style(b);
        lv_obj_set_pos(b,12+64*(int)i,8);
        lv_obj_set_size(b,56,56);
        lv_obj_add_event_cb(b,clicked,LV_EVENT_CLICKED,(void *)(uintptr_t)i);
        ui_control(b);
        if (i < 8) {
            lv_obj_t *dot = ui_box(b,13,13,30,30,draw_colors[i]);
            lv_obj_set_style_radius(dot,LV_RADIUS_CIRCLE,0);
            lv_obj_set_style_border_width(dot,1,0);
            lv_obj_set_style_border_color(dot,lv_color_hex(LINE),0);
        } else {
            lv_obj_t *label = ui_text_label(b,names[i-8],&sim_font_16,TEXT);
            lv_obj_center(label);
        }
    }
    cursor = ui_box(parent,0,0,12,12,0xffffff);
    lv_obj_set_ignore_layout(cursor,true);
    lv_obj_set_style_border_width(cursor,2,0);
    lv_obj_set_hidden(cursor,true);
    arc = ui_hold_arc(parent,DRAW_HOLD_MS);
    lv_obj_set_ignore_layout(arc,true);
    lv_obj_set_hidden(arc,true);
    selection();
    frames = 0;
    report_at = lv_tick_get();
    timer = lv_timer_create(tick,40,NULL);
    lv_obj_add_event_cb(canvas,deleted,LV_EVENT_DELETE,NULL);
    lv_display_add_event_cb(lv_display_get_default(),rendered,LV_EVENT_REFR_READY,canvas);
}
