/* page_motion.c — T-GAMES-MORE; direct game entries, shared HUD and result controls.
 * GUI clock; reads application-task snapshots and locally invalidated cursor/keypoint overlay.
 */
#include "game_view.h"
#include "game_loop.h"
#include "widgets.h"
#include "sling.h"
#include "grab.h"
#include "src/draw/lv_draw_private.h"
#include <stdio.h>
LV_IMAGE_DECLARE(sling_star);
LV_FONT_DECLARE(game_digits_28);
LV_IMAGE_DECLARE(ws_cursor_hand_grab);
LV_IMAGE_DECLARE(ws_cursor_hand_open);
static const char *const names[] = {
    "", "弹弓打靶", "石头剪刀布", "打地鼠", "切图形", "接物篮"};
static const char *const instructions[] = {
    "",
    "弹丸附近握拳抓起，后拉瞄准，张开发射；手丢失会取消",
    "看倒数，看到出后亮出石头、剪刀或布；五局三胜",
    "对准冒出的怪物，张开再握拳击打；金色加分，炸弹扣分",
    "快速挥手切开宝石；避开炸弹，别漏掉三个",
    "左右移动手掌接住水果；避开炸弹，篮子只跟随横向位置"};
static lv_obj_t *frame, *scene, *overlay, *labels;
static lv_obj_t *hud, *title, *prompt, *perf, *key_button, *result, *result_text;
static lv_obj_t *stars[3], *countdown, *hold_arc, *record_badge, *setup_title;
static motion_snapshot_t snapshots[3], next;
static bool result_shown;
static lv_timer_t *timer;
static uint32_t shown_revision, points_revision, fps_at;
static unsigned frames;
static bool keypoints, painted;
static int cursor_x, cursor_y, point_xy[21][2];
static bool cursor_closed, cursor_visible, points_visible;
static lv_obj_t *setup, *speed_segment, *setup_text, *start_button;
static unsigned last_segments, last_fast, last_hits, last_near;
static lv_obj_t *surface(lv_obj_t *p, int height)
{
    lv_obj_t *o = lv_obj_create(p);
    lv_obj_remove_style_all(o);
    lv_obj_set_pos(o,0,0);
    lv_obj_set_size(o,1280,height);
    lv_obj_set_clickable(o,false);
    lv_obj_set_scrollable(o,false);
    return o;
}
static void draw_scene(lv_event_t *e)
{
    painted = true;
    lv_layer_t *layer = lv_event_get_layer(e);
    if (ui_motion_view.state.waiting) return;
    if (ui_motion_view.state.game == MOTION_SLING) ui_sling_draw(layer);
    else ui_arcade_draw(layer);
}
static void draw_overlay(lv_event_t *e)
{
    painted = true;
    lv_layer_t *layer = lv_event_get_layer(e);
    lv_draw_rect_dsc_t dot;
    lv_draw_rect_dsc_init(&dot);
    dot.radius = LV_RADIUS_CIRCLE;
    dot.bg_opa = LV_OPA_COVER;
    dot.bg_color = lv_color_hex(cursor_closed ? 0xffc24c : 0xffffff);
    dot.border_color = dot.bg_color;
    dot.border_width = 3;
    if (cursor_visible && !ui_motion_view.done) {
        lv_area_t a = {cursor_x-18,cursor_y-18,cursor_x+18,cursor_y+18};
        lv_draw_rect(layer,&dot,&a);
    }
    if (!keypoints || !points_visible) return;
    dot.border_width = 0;
    dot.bg_opa = LV_OPA_COVER;
    dot.bg_color = lv_color_hex(0x39f5bc);
    for (unsigned i = 0; i < 21; ++i) {
        lv_area_t a = {point_xy[i][0]-4,point_xy[i][1]-4,
                       point_xy[i][0]+4,point_xy[i][1]+4};
        lv_draw_rect(layer,&dot,&a);
    }
}
static void dirty_points(void)
{
    if (!points_visible) return;
    for (unsigned i = 0; i < 21; ++i)
        game_dirty(overlay,point_xy[i][0],point_xy[i][1],point_xy[i][0],point_xy[i][1],5);
}
static void sync_input(void)
{
    motion_hand_t h = ui_motion_view.state.hand;
    if (ui_motion_view.state.game == MOTION_SLICE && ui_motion_view.state.slice.cursor_valid) {
        h.x = ui_motion_view.state.slice.cursor_x;
        h.y = ui_motion_view.state.slice.cursor_y;
    }
    bool show = h.present || h.lost < SLING_LOST;
    if (h.x != cursor_x || h.y != cursor_y ||
        h.closed != cursor_closed || show != cursor_visible)
        game_dirty(overlay,cursor_x,cursor_y,h.x,h.y,22);
    cursor_x = h.x;
    cursor_y = h.y;
    cursor_closed = h.closed;
    cursor_visible = show;
    if (!keypoints || points_revision == ui_motion_view.state.sample) return;
    bool changed = points_visible != ui_motion_view.points_present;
    if (ui_motion_view.points_present)
        for (unsigned i = 0; i < 21; ++i)
            if (point_xy[i][0] != ui_motion_view.points[i][0] ||
                point_xy[i][1] != ui_motion_view.points[i][1]) changed = true;
    if (changed) {
        dirty_points();
        points_visible = ui_motion_view.points_present;
        if (points_visible)
            for (unsigned i = 0; i < 21; ++i) {
                point_xy[i][0] = ui_motion_view.points[i][0];
                point_xy[i][1] = ui_motion_view.points[i][1];
            }
        dirty_points();
    }
    points_revision = ui_motion_view.state.sample;
}
static void build_game(void)
{
    lv_obj_clean(scene);
    lv_obj_clean(labels);
    lv_obj_set_hidden(result,true);
    ui_text(title,names[ui_motion_view.state.game]);
    ui_text(setup_title,names[ui_motion_view.state.game]);
    ui_text(prompt,instructions[ui_motion_view.state.game]);
    if (ui_motion_view.state.game == MOTION_SLING) ui_sling_build(scene);
    else ui_arcade_build(scene,labels);
    frames = 0;
    fps_at = lv_tick_get()-1000;
    shown_revision = ui_motion_view.state.revision;
    lv_obj_set_hidden(setup,!ui_motion_view.state.waiting);
    lv_obj_set_hidden(speed_segment,ui_motion_view.state.game < MOTION_MOLE);
    if (ui_motion_view.state.waiting)
        lv_group_focus_obj(ui_motion_view.state.game >= MOTION_MOLE ? speed_segment : start_button);
    result_shown = false;
    lv_obj_update_layout(scene);
}
static void hud_sync(void)
{
    const motion_state_t *s = &ui_motion_view.state;
    char text[180];
    int score = ui_motion_view.score;
    snprintf(text,sizeof text,"%d",score);
    ui_text(hud,text);
    unsigned left = 100;
    switch (s->game) {
        case MOTION_SLING:
            snprintf(text,sizeof text,"弹丸 %u / %u",ui_motion_view.sling.shots,SLING_SHOTS);
            left = ui_motion_view.sling.shots*100/SLING_SHOTS;
            break;
        case MOTION_RPS:
            snprintf(text,sizeof text,"回合 %u / %u   胜 %u  负 %u",
                     s->rps.rounds,RPS_ROUNDS,s->rps.wins,s->rps.losses);
            left = s->rps.phase == RPS_COUNTDOWN ?
                100-s->rps.ticks*100/(RPS_COUNT*GAME_SUBSTEPS) : 0;
            break;
        case MOTION_MOLE:
            snprintf(text,sizeof text,"剩余 %u 秒",MOLE_SECONDS-s->mole.ticks/GAME_STEP_HZ);
            left = 100-s->mole.ticks*100/(MOLE_SECONDS*GAME_STEP_HZ);
            break;
        case MOTION_SLICE:
            snprintf(text,sizeof text,"剩余 %u 秒   漏掉 %u / %u",
                SLICE_SECONDS-s->slice.ticks/GAME_STEP_HZ,s->slice.misses,SLICE_MISSES);
            left = 100-s->slice.ticks*100/(SLICE_SECONDS*GAME_STEP_HZ);
            break;
        case MOTION_CATCH:
            snprintf(text,sizeof text,"剩余 %u 秒",CATCH_SECONDS-s->basket.ticks/GAME_STEP_HZ);
            left = 100-s->basket.ticks*100/(CATCH_SECONDS*GAME_STEP_HZ);
            break;
        default: text[0] = 0; break;
    }
    ui_text(prompt,text);
    lv_bar_set_value(countdown,(int)left,LV_ANIM_OFF);
    bool done = ui_motion_view.done;
    lv_obj_set_hidden(hud,done);
    lv_obj_set_hidden(result,!done);
    if (done && !result_shown) {
        snprintf(text,sizeof text,"%d",score);
        ui_text(result_text,text);
        for (unsigned i = 0; i < 3; ++i)
            lv_obj_set_style_image_opa(stars[i],i < ui_motion_view.stars ? 255 : 50,0);
        lv_obj_set_hidden(record_badge,!s->new_record);
        lv_group_focus_obj(lv_obj_get_child(result,-2));
    }
    result_shown = done;
}
static void refresh(void)
{
    if (shown_revision != ui_motion_view.state.revision) build_game();
    if (!ui_motion_view.state.waiting) {
        if (ui_motion_view.state.game == MOTION_SLING) ui_sling_sync();
        else ui_arcade_sync();
    }
    lv_obj_set_hidden(setup,!ui_motion_view.state.waiting);
    lv_obj_set_hidden(scene,ui_motion_view.state.waiting);
    lv_obj_set_hidden(labels,ui_motion_view.state.waiting);
    if (ui_motion_view.state.waiting) {
        unsigned selected = ui_motion_view.state.speed-GAME_SLOW;
        lv_buttonmatrix_set_button_ctrl(speed_segment,selected,LV_BUTTONMATRIX_CTRL_CHECKED);
        ui_text(setup_text,instructions[ui_motion_view.state.game]);
    }
    unsigned hold = ui_motion_view.state.waiting ? ui_motion_view.state.hold :
        ui_motion_view.state.game == MOTION_SLING ? ui_motion_view.sling.restart_ticks :
        ui_motion_view.state.restart;
    lv_arc_set_value(hold_arc,(int)hold);
    lv_obj_set_pos(hold_arc,ui_motion_view.state.hand.x-32,ui_motion_view.state.hand.y-32);
    lv_obj_set_hidden(hold_arc,!hold);
    sync_input();
    hud_sync();
    unsigned now = lv_tick_get();
    if (now-fps_at >= 1000) {
        unsigned fps = frames*1000/(now-fps_at);
        frames = 0;
        fps_at = now;
        ui_vision_t v = ui_data_vision();
        char text[160];
        snprintf(text,sizeof text,"识别 %u fps · 延迟 %u.%u ms · CPU 空闲 %u%% · 绘制 %u fps",
                 v.fps,v.latency_tenths/10,v.latency_tenths%10,ui_data_system().idle,fps);
        ui_text(perf,text);
    }
}
void ui_motion_update(void)
{
    if (!game_loop_read(&next)) return;
    ui_motion_view = next;
    refresh();
}
static void tick(lv_timer_t *t) { (void)t; ui_motion_update(); }
static void simulate(void *context)
{
    (void)context;
    unsigned revision = ui_motion.revision;
    motion_step();
    if (revision != ui_motion.revision)
        last_segments = last_fast = last_hits = last_near = 0;
}
static void snapshot(void *context, void *destination)
{
    (void)context;
    motion_snapshot_t *view = destination;
    motion_snapshot_copy(view);
    const ui_hand_t *hand = ui_data_hand();
    view->points_present = hand->count != 0;
    if (view->points_present) {
        unsigned largest = 0;
        for (unsigned i = 1; i < hand->count; ++i)
            if (hand->people[i].width*hand->people[i].height >
                hand->people[largest].width*hand->people[largest].height) largest = i;
        for (unsigned i = 0; i < 21; ++i) {
            view->points[i][0] = (int)hand->points[largest][i].x;
            view->points[i][1] = (int)hand->points[largest][i].y;
        }
    }
}
static void report(void *context, unsigned draws, unsigned steps,
                   unsigned late, unsigned mean_us)
{
    (void)context; (void)steps; (void)late; (void)mean_us;
    const motion_hand_t *h = &ui_motion.hand;
    int x = ui_motion.game == MOTION_SLICE && ui_motion.slice.cursor_valid ?
            ui_motion.slice.cursor_x : h->x;
    int y = ui_motion.game == MOTION_SLICE && ui_motion.slice.cursor_valid ?
            ui_motion.slice.cursor_y : h->y;
    char text[180];
    snprintf(text,sizeof text,"game name=%s draw_fps=%u cursor=%d,%d lost=%u cls=%d\r\n",
             motion_name(),draws,x,y,h->lost,h->cls);
    ui_data_grab_output(text);
    if (ui_motion.game == MOTION_SLICE) {
        const slice_state_t *s = &ui_motion.slice;
        snprintf(text,sizeof text,
            "game name=slice segments=%u fast_segments=%u hits=%u near_misses=%u\r\n",
            s->segments-last_segments,s->fast_segments-last_fast,
            s->hits-last_hits,s->near_misses-last_near);
        ui_data_grab_output(text);
        last_segments = s->segments; last_fast = s->fast_segments;
        last_hits = s->hits; last_near = s->near_misses;
    }
}
static void rendered(lv_event_t *e)
{
    (void)e;
    if (painted) { ++frames; game_loop_drawn(); }
    painted = false;
}
static void deleted(lv_event_t *e)
{
    (void)e;
    game_loop_stop();
    motion_finish();
    lv_timer_delete(timer);
    lv_display_remove_event_cb_with_user_data(lv_display_get_default(),rendered,frame);
}
void ui_motion_action(unsigned action)
{
    if (!action) {
        dirty_points();
        keypoints = !keypoints;
        points_revision = ui_motion_view.state.sample-1;
        lv_obj_set_state(key_button,LV_STATE_CHECKED,keypoints);
    } else motion_command(action);
}
static void keypoints_changed(lv_event_t *event)
{ (void)event; ui_motion_action(0); }
static void speed_changed(lv_event_t *event)
{
    unsigned selected = lv_buttonmatrix_get_selected_button(lv_event_get_target_obj(event));
    motion_command(20+selected);
}
void ui_page_motion(lv_obj_t *p)
{
    motion_init();
    motion_select((motion_game_t)ui_motion_entry);
    motion_snapshot_copy(&ui_motion_view);
    last_segments = last_fast = last_hits = last_near = 0;
    lv_obj_t *header = ui_camera_layout(p,names[ui_motion_view.state.game]);
    title = lv_obj_get_child(header,1);
    hud = ui_text_label(header,"0",&game_digits_28,ACCENT);
    lv_obj_set_width(hud,90);
    countdown = lv_bar_create(header);
    lv_obj_set_size(countdown,110,8);
    prompt = ui_text_label(header,"",&sim_font_14,TEXT);
    lv_obj_set_width(prompt,180);
    perf = ui_text_label(header,"等待识别",&sim_font_14,MUTED);
    lv_obj_set_flex_grow(perf,1);
    key_button = ui_flex_switch(header,"关键点",false);
    lv_obj_set_width(lv_obj_get_parent(key_button),140);
    lv_obj_set_style_pad_all(lv_obj_get_parent(key_button),0,0);
    lv_obj_add_event_cb(key_button,keypoints_changed,LV_EVENT_VALUE_CHANGED,NULL);
    frame = surface(lv_screen_active(),720);
    lv_obj_move_to_index(frame,0);
    scene = surface(frame,720);
    lv_obj_add_event_cb(frame,draw_scene,LV_EVENT_DRAW_MAIN,NULL);
    labels = surface(p,720);
    lv_obj_set_ignore_layout(labels,true);
    result = ui_box(p,400,210,480,300,PANEL);
    lv_obj_set_ignore_layout(result,true);
    lv_obj_center(result);
    lv_obj_t *heading = ui_text_label(result,"本局得分",&showcase_bold_24,TEXT);
    lv_obj_align(heading,LV_ALIGN_TOP_MID,0,16);
    result_text = ui_number(result,"0",false);
    lv_obj_align(result_text,LV_ALIGN_TOP_MID,0,48);
    for (unsigned i = 0; i < 3; ++i)
        stars[i] = game_sprite(result,&sling_star,170+70*(int)i,146);
    record_badge = ui_badge(result,"新纪录");
    lv_obj_align(record_badge,LV_ALIGN_TOP_MID,0,184);
    lv_obj_t *again = ui_game_button(result,"再来一局",20,230,212,1);
    lv_obj_set_height(again,48);
    lv_obj_set_style_bg_color(again,lv_color_hex(ACCENT),0);
    lv_obj_set_style_text_color(lv_obj_get_child(again,0),lv_color_hex(PANEL),0);
    lv_obj_t *back = ui_game_button(result,"返回",248,230,212,1000);
    lv_obj_set_height(back,48);
    lv_obj_set_style_border_color(back,lv_color_hex(ACCENT),0);
    lv_obj_set_style_border_width(back,2,0);
    lv_obj_set_hidden(result,true);
    setup = ui_box(p,300,200,680,320,PANEL);
    lv_obj_set_ignore_layout(setup,true);
    setup_title = ui_emphasis(setup,"",false);
    lv_obj_set_pos(setup_title,30,20);
    ui_game_instruction(setup,&ws_cursor_hand_open,"",30,70,620);
    lv_obj_t *row = lv_obj_get_child(setup,-1);
    setup_text = lv_obj_get_child(row,1);
    static const char *const speed_names[] = {"慢","中","快",""};
    speed_segment = ui_segment(setup,speed_names,0);
    lv_obj_set_pos(speed_segment,30,122);
    lv_obj_set_size(speed_segment,620,60);
    lv_obj_set_style_pad_all(speed_segment,0,0);
    lv_obj_set_style_pad_column(speed_segment,40,0);
    lv_obj_add_event_cb(speed_segment,speed_changed,LV_EVENT_VALUE_CHANGED,NULL);
    ui_game_instruction(setup,&ws_cursor_hand_grab,"握拳停留 1 秒选择 / 开始",30,192,620);
    start_button = ui_game_button(setup,"开始",200,242,280,23);
    hold_arc = ui_hold_arc(lv_screen_active(),MOTION_HOLD);
    lv_obj_set_hidden(hold_arc,true);
    overlay = surface(lv_screen_active(),720);
    lv_obj_add_event_cb(overlay,draw_overlay,LV_EVENT_DRAW_MAIN,NULL);
    keypoints = painted = points_visible = cursor_visible = false;
    cursor_x = 640;
    cursor_y = 360;
    cursor_closed = false;
    frames = 0;
    fps_at = lv_tick_get()-1000;
    shown_revision = ui_motion_view.state.revision-1;
    points_revision = ui_motion_view.state.sample;
    timer = lv_timer_create(tick,16,NULL);
    lv_obj_add_event_cb(frame,deleted,LV_EVENT_DELETE,NULL);
    lv_display_add_event_cb(lv_display_get_default(),rendered,LV_EVENT_REFR_READY,frame);
    refresh();
    game_loop_config config = {simulate,snapshot,report,NULL,
        {&snapshots[0],&snapshots[1],&snapshots[2]},sizeof(motion_snapshot_t)};
    game_loop_start(&config);
}
