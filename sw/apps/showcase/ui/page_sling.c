/* page_sling.c — T-GAME-SLING; AR sprites and clipped moving overlays on L1.
 * GUI clock; fixed 30 Hz physics, image positions invalidate only old/new bounds.
 */
#include "theme.h"
#include "sling.h"
#include "src/draw/lv_draw_private.h"
#include "src/misc/lv_area_private.h"
#include <stdio.h>
LV_IMAGE_DECLARE(sling_slingshot);
LV_IMAGE_DECLARE(sling_ball);
LV_IMAGE_DECLARE(sling_crate);
LV_IMAGE_DECLARE(sling_balloon_coral);
LV_IMAGE_DECLARE(sling_balloon_blue);
LV_IMAGE_DECLARE(sling_platform);
LV_IMAGE_DECLARE(sling_wood_chip);
LV_IMAGE_DECLARE(sling_balloon_chip);
LV_IMAGE_DECLARE(sling_star);
static lv_obj_t *frame, *ball, *targets[SLING_TARGETS], *chips[SLING_PARTICLES];
static lv_obj_t *hud, *perf, *result, *result_text, *stars[3], *key_button;
static lv_timer_t *timer;
static sling_state_t shown;
static bool keypoints, painted;
static unsigned clock_at, accumulator, fps_at, frames, draw_fps;
static int points[21][2];
static bool visible[21];
static lv_area_t around(int x, int y, int radius)
{
    return (lv_area_t){x-radius, y-radius, x+radius, y+radius};
}
static void dirty(int x, int y, int nx, int ny, int radius)
{
    lv_area_t a = around(x,y,radius);
    lv_area_t b = around(nx,ny,radius);
    lv_area_join(&a,&a,&b);
    lv_obj_invalidate_area(frame,&a);
}
static lv_obj_t *sprite(lv_obj_t *parent, const lv_image_dsc_t *src, int x, int y)
{
    lv_obj_t *o = lv_image_create(parent);
    lv_image_set_src(o,src);
    lv_obj_set_pos(o,x-(int)src->header.w/2,y-(int)src->header.h/2);
    lv_obj_set_size(o,src->header.w,src->header.h);
    lv_obj_set_clickable(o,false);
    return o;
}
static void position(lv_obj_t *o, int x, int y)
{
    int nx = x-lv_obj_get_width(o)/2;
    int ny = y-lv_obj_get_height(o)/2;
    if (lv_obj_get_x(o) == nx && lv_obj_get_y(o) == ny) return;
    lv_area_t old;
    lv_obj_get_coords(o,&old);
    lv_obj_set_pos(o,nx,ny);
    lv_area_t next = {nx,ny,nx+lv_obj_get_width(o)-1,ny+lv_obj_get_height(o)-1};
    lv_area_join(&old,&old,&next);
    lv_obj_invalidate_area(frame,&old);
}
static void trajectory(const sling_state_t *s, sling_body_t *p)
{
    *p = s->ball;
    sling_launch_velocity(p,&p->vx,&p->vy);
}
static void invalidate_aim(const sling_state_t *s)
{
    if (s->phase != SLING_AIM && s->phase != SLING_READY) return;
    int x = s->ball.x/SLING_Q;
    int y = s->ball.y/SLING_Q;
    dirty(222,470,x,y,5);
    dirty(298,470,x,y,5);
    if (s->phase != SLING_AIM) return;
    sling_body_t p;
    trajectory(s,&p);
    for (unsigned i = 0; i < SLING_PREVIEW; ++i) {
        sling_integrate(&p);
        lv_area_t a = around(p.x/SLING_Q,p.y/SLING_Q,5);
        lv_obj_invalidate_area(frame,&a);
    }
}
static void draw(lv_event_t *e)
{
    painted = true;
    lv_layer_t *layer = lv_event_get_layer(e);
    lv_draw_line_dsc_t line;
    lv_draw_line_dsc_init(&line);
    line.color = lv_color_hex(0x633e27);
    line.width = 7;
    if (shown.phase == SLING_AIM || shown.phase == SLING_READY) {
        for (unsigned i = 0; i < 2; ++i) {
            line.p1 = (lv_point_precise_t){i ? 298 : 222,470};
            line.p2 = (lv_point_precise_t){shown.ball.x/SLING_Q,shown.ball.y/SLING_Q};
            lv_draw_line(layer,&line);
        }
    }
    lv_draw_rect_dsc_t dot;
    lv_draw_rect_dsc_init(&dot);
    dot.radius = LV_RADIUS_CIRCLE;
    dot.bg_color = lv_color_hex(0xfff1ab);
    if (shown.phase == SLING_AIM) {
        sling_body_t p;
        trajectory(&shown,&p);
        for (unsigned i = 0; i < SLING_PREVIEW; ++i) {
            sling_integrate(&p);
            lv_area_t a = around(p.x/SLING_Q,p.y/SLING_Q,3);
            lv_draw_rect(layer,&dot,&a);
        }
    }
    if (shown.present || shown.lost < SLING_LOST) {
        dot.bg_opa = LV_OPA_40;
        dot.bg_color = lv_color_hex(shown.closed ? 0xffba49 : 0xffffff);
        dot.border_color = dot.bg_color;
        dot.border_width = 3;
        lv_area_t a = around(shown.cursor_x,shown.cursor_y,15);
        lv_draw_rect(layer,&dot,&a);
    }
    if (!keypoints) return;
    dot.border_width = 0;
    dot.bg_opa = LV_OPA_COVER;
    dot.bg_color = lv_color_hex(0x39f5bc);
    for (unsigned i = 0; i < 21; ++i) if (visible[i]) {
        lv_area_t a = around(points[i][0],points[i][1],4);
        lv_draw_rect(layer,&dot,&a);
    }
}
static void sync_points(void)
{
    const ui_hand_t *hand = ui_data_hand();
    unsigned largest = 0;
    for (unsigned i = 1; i < hand->count; ++i)
        if (hand->people[i].width * hand->people[i].height >
            hand->people[largest].width * hand->people[largest].height) largest = i;
    for (unsigned i = 0; i < 21; ++i) {
        if (visible[i]) {
            lv_area_t a = around(points[i][0],points[i][1],5);
            lv_obj_invalidate_area(frame,&a);
        }
        visible[i] = hand->count != 0;
        if (visible[i]) {
            points[i][0] = (int)hand->points[largest][i].x;
            points[i][1] = (int)hand->points[largest][i].y;
            lv_area_t a = around(points[i][0],points[i][1],5);
            lv_obj_invalidate_area(frame,&a);
        }
    }
}
static void refresh(void)
{
    sling_state_t *s = &ui_sling;
    bool moved = shown.ball.x != s->ball.x || shown.ball.y != s->ball.y ||
                 shown.phase != s->phase;
    if (moved) { invalidate_aim(&shown); invalidate_aim(s); }
    if (shown.cursor_x != s->cursor_x || shown.cursor_y != s->cursor_y ||
        shown.closed != s->closed || shown.lost != s->lost)
        dirty(shown.cursor_x,shown.cursor_y,s->cursor_x,s->cursor_y,19);
    position(ball,s->ball.x/SLING_Q,s->ball.y/SLING_Q);
    lv_obj_set_hidden(ball,s->phase == SLING_DONE);
    for (unsigned i = 0; i < SLING_TARGETS; ++i)
        lv_obj_set_hidden(targets[i],!s->targets[i].alive);
    for (unsigned i = 0; i < SLING_PARTICLES; ++i) {
        sling_particle_t *p = &s->particles[i];
        lv_obj_set_hidden(chips[i],!p->life);
        if (!p->life || p->life == shown.particles[i].life) continue;
        position(chips[i],p->body.x/SLING_Q,p->body.y/SLING_Q);
        if (!shown.particles[i].life || p->balloon != shown.particles[i].balloon)
            lv_image_set_src(chips[i],p->balloon ? &sling_balloon_chip : &sling_wood_chip);
        lv_obj_set_style_image_opa(chips[i],p->life*255/SLING_FADE,0);
    }
    if (keypoints) sync_points();
    shown = *s;
    char text[160];
    snprintf(text,sizeof text,"分数 %u     弹丸 %u / %u",s->score,s->shots,SLING_SHOTS);
    ui_text(hud,text);
    lv_obj_set_hidden(result,s->phase != SLING_DONE);
    if (s->phase == SLING_DONE) {
        snprintf(text,sizeof text,"本局得分 %u\n握拳保持 1 秒，再来一局",s->score);
        ui_text(result_text,text);
        for (unsigned i = 0; i < 3; ++i)
            lv_obj_set_style_image_opa(stars[i],i < sling_stars(s) ? 255 : 50,0);
    }
    unsigned now = lv_tick_get();
    if (now - fps_at >= 1000) {
        draw_fps = frames*1000/(now-fps_at);
        frames = 0;
        fps_at = now;
        ui_vision_t v = ui_data_vision();
        snprintf(text,sizeof text,"识别 %u fps   延迟 %u.%u ms\nCPU 空闲 %u%%   游戏绘制 %u fps",
                 v.fps,v.latency_tenths/10,v.latency_tenths%10,
                 ui_data_system().idle,draw_fps);
        ui_text(perf,text);
    }
}
static void tick(lv_timer_t *t)
{
    (void)t;
    unsigned now = lv_tick_get();
    accumulator += (now-clock_at)*SLING_HZ;
    clock_at = now;
    while (accumulator >= 1000) { sling_step(&ui_sling); accumulator -= 1000; }
    refresh();
}
static void rendered(lv_event_t *e)
{
    (void)e;
    if (painted) ++frames;
    painted = false;
}
static void deleted(lv_event_t *e)
{
    (void)e;
    lv_timer_delete(timer);
    lv_display_remove_event_cb_with_user_data(lv_display_get_default(),rendered,frame);
}
void ui_sling_action(unsigned action)
{
    if (!action) {
        if (keypoints) {
            for (unsigned i = 0; i < 21; ++i) if (visible[i]) {
                lv_area_t a = around(points[i][0],points[i][1],5);
                lv_obj_invalidate_area(frame,&a);
            }
        }
        keypoints = !keypoints;
        ui_text(lv_obj_get_child(key_button,0),keypoints ? "关键点 开" : "关键点 关");
    } else sling_init(&ui_sling);
    refresh();
}
void ui_page_sling(lv_obj_t *p)
{
    sling_init(&ui_sling);
    shown = ui_sling;
    keypoints = false;
    for (unsigned i = 0; i < 21; ++i) visible[i] = false;
    ui_video_surface(p);
    ui_label(p,"体感弹弓",24,10,&sim_font_28,TEXT);
    hud = ui_label(p,"",220,15,&sim_font_20,TEXT);
    ui_button(p,"关键点 关",650,6,150,0);
    key_button = lv_obj_get_child(p,-1);
    lv_obj_t *panel = ui_box(p,900,54,356,64,PANEL);
    lv_obj_set_style_bg_opa(panel,LV_OPA_80,0);
    perf = ui_label(panel,"等待识别",12,8,&sim_font_16,TEXT);
    frame = ui_box(lv_screen_active(),0,0,1280,720,0);
    lv_obj_remove_style_all(frame);
    lv_obj_set_pos(frame,0,0);
    lv_obj_set_size(frame,1280,720);
    lv_obj_set_scrollable(frame,false);
    lv_obj_set_clickable(frame,false);
    lv_obj_move_to_index(frame,0);
    lv_obj_add_event_cb(frame,draw,LV_EVENT_DRAW_MAIN,NULL);
    lv_obj_add_event_cb(frame,deleted,LV_EVENT_DELETE,NULL);
    sprite(frame,&sling_slingshot,260,555);
    for (unsigned i = 0; i < 3; ++i) sprite(frame,&sling_platform,890+140*(int)i,614-160*(int)i);
    for (unsigned i = 0; i < SLING_TARGETS; ++i) {
        sling_target_t *t = &shown.targets[i];
        targets[i] = sprite(frame,t->balloon ?
            (i == 3 ? &sling_balloon_blue : &sling_balloon_coral) : &sling_crate,t->x,t->y);
    }
    ball = sprite(frame,&sling_ball,SLING_X,SLING_Y);
    for (unsigned i = 0; i < SLING_PARTICLES; ++i) {
        chips[i] = sprite(frame,&sling_wood_chip,0,0);
        lv_obj_set_hidden(chips[i],true);
    }
    result = ui_box(p,420,180,440,250,PANEL);
    lv_obj_set_style_bg_opa(result,LV_OPA_90,0);
    result_text = ui_label(result,"",30,20,&sim_font_20,TEXT);
    for (unsigned i = 0; i < 3; ++i) stars[i] = sprite(result,&sling_star,150+70*(int)i,120);
    ui_button(result,"再来一局",110,180,220,1);
    lv_obj_set_hidden(result,true);
    accumulator = frames = draw_fps = 0;
    clock_at = fps_at = lv_tick_get();
    painted = false;
    lv_display_add_event_cb(lv_display_get_default(),rendered,LV_EVENT_REFR_READY,frame);
    lv_obj_update_layout(frame);
    timer = lv_timer_create(tick,16,NULL);
    ui_hint("在弹丸附近握拳抓起 → 后拉瞄准 → 张开发射 · 手丢失取消 · 木箱 100 / 气球 50");
    refresh();
}
