/* page_motion.c — T-GAMES-MORE; persistent AR lobby, shared HUD and result controls.
 * GUI clock; one 30 Hz simulation timer and locally invalidated cursor/keypoint overlay.
 */
#include "game_view.h"
#include "sling.h"
#include "src/draw/lv_draw_private.h"
#include <stdio.h>
LV_IMAGE_DECLARE(sling_slingshot);
LV_IMAGE_DECLARE(sling_star);
LV_IMAGE_DECLARE(rps_player_rock);
LV_IMAGE_DECLARE(mole_monster);
LV_IMAGE_DECLARE(slice_ruby);
LV_IMAGE_DECLARE(catch_basket);
static const char *const names[] = {
    "体感游戏", "弹弓打靶", "石头剪刀布", "打地鼠", "切图形", "接物篮"};
static const char *const instructions[] = {
    "光标停在卡片上，握拳保持 1 秒进入；也可点卡片或使用按键",
    "弹丸附近握拳抓起，后拉瞄准，张开发射；手丢失会取消",
    "看倒数，看到出后亮出石头、剪刀或布；五局三胜",
    "对准冒出的怪物，张开再握拳击打；金色加分，炸弹扣分",
    "快速挥手切开宝石；避开炸弹，别漏掉三个",
    "左右移动手掌接住水果；避开炸弹，篮子只跟随横向位置"};
static lv_obj_t *frame, *scene, *overlay, *cards, *labels;
static lv_obj_t *hud, *title, *prompt, *perf, *key_button, *result, *result_text;
static lv_obj_t *stars[3], *rings[MOTION_GAMES], *card_buttons[MOTION_GAMES];
static lv_timer_t *timer;
static uint32_t clock_at, accumulator, shown_revision, points_revision, fps_at;
static unsigned frames;
static bool keypoints, painted;
static int cursor_x, cursor_y, point_xy[21][2];
static bool cursor_closed, cursor_visible, points_visible;
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
    if (ui_motion.game == MOTION_SLING) ui_sling_draw(layer);
    else ui_arcade_draw(layer);
}
static void draw_overlay(lv_event_t *e)
{
    painted = true;
    lv_layer_t *layer = lv_event_get_layer(e);
    lv_draw_rect_dsc_t dot;
    lv_draw_rect_dsc_init(&dot);
    dot.radius = LV_RADIUS_CIRCLE;
    dot.bg_opa = LV_OPA_20;
    dot.bg_color = lv_color_hex(cursor_closed ? 0xffc24c : 0xffffff);
    dot.border_color = dot.bg_color;
    dot.border_width = 3;
    if (cursor_visible) {
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
    motion_hand_t h = ui_motion.hand;
    if (ui_motion.game == MOTION_SLICE && ui_motion.slice.cursor_valid) {
        h.x = ui_motion.slice.cursor_x;
        h.y = ui_motion.slice.cursor_y;
    }
    bool show = h.present || h.lost < SLING_LOST;
    if (h.x != cursor_x || h.y != cursor_y || h.closed != cursor_closed || show != cursor_visible)
        game_dirty(overlay,cursor_x,cursor_y,h.x,h.y,22);
    cursor_x = h.x;
    cursor_y = h.y;
    cursor_closed = h.closed;
    cursor_visible = show;
    if (!keypoints || points_revision == ui_motion.sample) return;
    dirty_points();
    const ui_hand_t *hand = ui_data_hand();
    points_visible = hand->count != 0;
    if (points_visible) {
        unsigned largest = 0;
        for (unsigned i = 1; i < hand->count; ++i)
            if (hand->people[i].width*hand->people[i].height >
                hand->people[largest].width*hand->people[largest].height) largest = i;
        for (unsigned i = 0; i < 21; ++i) {
            point_xy[i][0] = (int)hand->points[largest][i].x;
            point_xy[i][1] = (int)hand->points[largest][i].y;
        }
    }
    dirty_points();
    points_revision = ui_motion.sample;
}
static void build_game(void)
{
    lv_obj_clean(scene);
    lv_obj_clean(labels);
    lv_obj_set_hidden(cards,ui_motion.game != MOTION_HALL);
    lv_obj_set_hidden(result,true);
    ui_text(title,names[ui_motion.game]);
    ui_text(prompt,instructions[ui_motion.game]);
    ui_hint(ui_motion.game == MOTION_HALL ?
        "握拳停留 1 秒选择 · ← → 选择卡片，Enter 进入 · Esc 回首页" :
        "Esc / 返回：游戏大厅 · 结算后握拳 1 秒或点再来一局 · 关键点开关用于调试");
    if (ui_motion.game == MOTION_SLING) ui_sling_build(scene);
    else if (ui_motion.game != MOTION_HALL) ui_arcade_build(scene,labels);
    shown_revision = ui_motion.revision;
    if (ui_motion.game == MOTION_HALL) lv_group_focus_obj(card_buttons[0]);
    lv_obj_update_layout(scene);
}
static void hud_sync(void)
{
    char text[180];
    int score = motion_score();
    switch (ui_motion.game) {
        case MOTION_HALL:
            snprintf(text,sizeof text,"5 个游戏 · 用手来挑战");
            break;
        case MOTION_SLING:
            snprintf(text,sizeof text,"分数 %d   弹丸 %u / %u",score,ui_sling.shots,SLING_SHOTS);
            break;
        case MOTION_RPS:
            snprintf(text,sizeof text,"分数 %d   回合 %u / %u   胜 %u  负 %u",score,
                     ui_motion.rps.rounds,RPS_ROUNDS,ui_motion.rps.wins,ui_motion.rps.losses);
            break;
        case MOTION_MOLE:
            snprintf(text,sizeof text,"分数 %d   剩余 %u 秒",score,
                     MOLE_SECONDS-ui_motion.mole.ticks/GAME_HZ);
            break;
        case MOTION_SLICE:
            snprintf(text,sizeof text,"分数 %d   %u 秒   漏掉 %u / %u",score,
                     SLICE_SECONDS-ui_motion.slice.ticks/GAME_HZ,
                     ui_motion.slice.misses,SLICE_MISSES);
            break;
        case MOTION_CATCH:
            snprintf(text,sizeof text,"分数 %d   剩余 %u 秒",score,
                     CATCH_SECONDS-ui_motion.basket.ticks/GAME_HZ);
            break;
        default: text[0] = 0; break;
    }
    ui_text(hud,text);
    bool done = motion_done();
    lv_obj_set_hidden(result,!done);
    if (done) {
        snprintf(text,sizeof text,"本局得分 %d\n握拳保持 1 秒，再来一局",score);
        ui_text(result_text,text);
        unsigned earned = motion_stars();
        for (unsigned i = 0; i < 3; ++i) {
            unsigned opa = i < earned ? 255 : 50;
            if (lv_obj_get_style_image_opa(stars[i],0) != opa)
                lv_obj_set_style_image_opa(stars[i],opa,0);
        }
    }
}
static void refresh(void)
{
    if (shown_revision != ui_motion.revision) build_game();
    if (ui_motion.game == MOTION_HALL) {
        for (unsigned i = 0; i < MOTION_GAMES; ++i) {
            bool active = ui_motion.hovered == (int)i;
            lv_obj_set_hidden(rings[i],!active);
            if (active) lv_arc_set_value(rings[i],ui_motion.hold);
        }
    } else if (ui_motion.game == MOTION_SLING) ui_sling_sync();
    else ui_arcade_sync();
    sync_input();
    hud_sync();
    unsigned now = lv_tick_get();
    if (now-fps_at >= 1000) {
        unsigned fps = frames*1000/(now-fps_at);
        frames = 0;
        fps_at = now;
        ui_vision_t v = ui_data_vision();
        char text[160];
        snprintf(text,sizeof text,"识别 %u fps   延迟 %u.%u ms\nCPU 空闲 %u%%   游戏绘制 %u fps",
                 v.fps,v.latency_tenths/10,v.latency_tenths%10,ui_data_system().idle,fps);
        ui_text(perf,text);
    }
}
static void tick(lv_timer_t *t)
{
    (void)t;
    unsigned now = lv_tick_get();
    accumulator += (now-clock_at)*GAME_HZ;
    clock_at = now;
    while (accumulator >= 1000) { motion_step(); accumulator -= 1000; }
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
void ui_motion_action(unsigned action)
{
    if (!action) {
        dirty_points();
        keypoints = !keypoints;
        points_revision = ui_motion.sample-1;
        ui_text(lv_obj_get_child(key_button,0),keypoints ? "关键点 开" : "关键点 关");
    } else if (action == 1) motion_select(ui_motion.game);
    else motion_select((motion_game_t)(action-9));
    refresh();
}
bool ui_motion_back(void)
{
    if (ui_motion.game == MOTION_HALL) return false;
    motion_select(MOTION_HALL);
    refresh();
    return true;
}
void ui_page_motion(lv_obj_t *p)
{
    motion_init();
    ui_video_surface(p);
    title = ui_label(p,names[0],24,10,&sim_font_28,TEXT);
    hud = ui_label(p,"",220,15,&sim_font_20,TEXT);
    ui_button(p,"关键点 关",730,6,150,0);
    key_button = lv_obj_get_child(p,-1);
    prompt = ui_label(p,instructions[0],40,86,&sim_font_16,TEXT);
    lv_obj_t *panel = ui_box(p,900,54,356,64,PANEL);
    lv_obj_set_style_bg_opa(panel,LV_OPA_80,0);
    perf = ui_label(panel,"等待识别",12,8,&sim_font_16,TEXT);
    frame = surface(lv_screen_active(),720);
    lv_obj_move_to_index(frame,0);
    scene = surface(frame,720);
    lv_obj_add_event_cb(frame,draw_scene,LV_EVENT_DRAW_MAIN,NULL);
    labels = surface(p,632);
    cards = surface(p,632);
    static const lv_image_dsc_t *const icons[] = {
        &sling_slingshot,&rps_player_rock,&mole_monster,&slice_ruby,&catch_basket};
    static const char *const summaries[] = {
        "抓起后拉，松开发射", "倒数出招，与开发板对战", "对准怪物，张开再握拳",
        "快速挥手，避开炸弹", "左右移篮，接住水果"};
    for (unsigned i = 0; i < MOTION_GAMES; ++i) {
        int x, y;
        motion_card(i,&x,&y);
        ui_button(cards,"",x,y-48,MOTION_CARD_W,10+i);
        lv_obj_t *card = lv_obj_get_child(cards,-1);
        card_buttons[i] = card;
        lv_obj_set_height(card,MOTION_CARD_H);
        lv_obj_set_style_bg_opa(card,LV_OPA_90,0);
        lv_obj_t *icon = game_sprite(card,icons[i],60,75);
        lv_obj_set_size(icon,i == 0 ? 58 : 88,i == 0 ? 100 : 88);
        lv_obj_set_pos(icon,i == 0 ? 31 : 16,i == 0 ? 25 : 31);
        lv_image_set_inner_align(icon,LV_IMAGE_ALIGN_STRETCH);
        ui_label(card,names[i+1],118,34,&sim_font_28,TEXT);
        lv_obj_t *desc = ui_label(card,summaries[i],118,84,&sim_font_16,MUTED);
        lv_obj_set_width(desc,215);
        rings[i] = lv_arc_create(card);
        lv_obj_set_pos(rings[i],282,106);
        lv_obj_set_size(rings[i],52,52);
        lv_arc_set_range(rings[i],0,MOTION_HOLD);
        lv_arc_set_bg_angles(rings[i],0,360);
        lv_arc_set_rotation(rings[i],270);
        lv_obj_remove_style(rings[i],NULL,LV_PART_KNOB);
        lv_obj_set_style_arc_width(rings[i],5,LV_PART_MAIN);
        lv_obj_set_style_arc_width(rings[i],5,LV_PART_INDICATOR);
        lv_obj_set_style_arc_color(rings[i],lv_color_hex(TEAL),LV_PART_INDICATOR);
        lv_obj_set_clickable(rings[i],false);
        lv_obj_set_hidden(rings[i],true);
    }
    result = ui_box(p,420,180,440,250,PANEL);
    lv_obj_set_style_bg_opa(result,LV_OPA_90,0);
    result_text = ui_label(result,"",30,20,&sim_font_20,TEXT);
    for (unsigned i = 0; i < 3; ++i) stars[i] = game_sprite(result,&sling_star,150+70*(int)i,120);
    ui_button(result,"再来一局",110,180,220,1);
    lv_obj_set_hidden(result,true);
    overlay = surface(lv_screen_active(),720);
    lv_obj_add_event_cb(overlay,draw_overlay,LV_EVENT_DRAW_MAIN,NULL);
    keypoints = painted = points_visible = cursor_visible = false;
    cursor_x = 640;
    cursor_y = 360;
    cursor_closed = false;
    accumulator = frames = 0;
    clock_at = fps_at = lv_tick_get();
    shown_revision = ui_motion.revision-1;
    points_revision = ui_motion.sample;
    timer = lv_timer_create(tick,16,NULL);
    lv_obj_add_event_cb(frame,deleted,LV_EVENT_DELETE,NULL);
    lv_display_add_event_cb(lv_display_get_default(),rendered,LV_EVENT_REFR_READY,frame);
    refresh();
}
