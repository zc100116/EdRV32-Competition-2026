/* page_arcade.c — T-GAMES-MORE; four sprite scenes on the shared camera overlay.
 * GUI domain; static holes and labels stay valid while moving sprites update locally.
 */
#include "game_view.h"
#include "src/draw/lv_draw_private.h"
#include <stdio.h>
LV_IMAGE_DECLARE(rps_player_rock);
LV_IMAGE_DECLARE(rps_player_scissors);
LV_IMAGE_DECLARE(rps_player_paper);
LV_IMAGE_DECLARE(rps_board_rock);
LV_IMAGE_DECLARE(rps_board_scissors);
LV_IMAGE_DECLARE(rps_board_paper);
LV_IMAGE_DECLARE(rps_win);
LV_IMAGE_DECLARE(rps_lose);
LV_IMAGE_DECLARE(mole_hole);
LV_IMAGE_DECLARE(mole_monster);
LV_IMAGE_DECLARE(mole_monster_hit);
LV_IMAGE_DECLARE(mole_gold);
LV_IMAGE_DECLARE(mole_bomb);
LV_IMAGE_DECLARE(mole_impact);
LV_IMAGE_DECLARE(slice_ruby);
LV_IMAGE_DECLARE(slice_lime);
LV_IMAGE_DECLARE(slice_amber);
LV_IMAGE_DECLARE(slice_berry);
LV_IMAGE_DECLARE(slice_ruby_left);
LV_IMAGE_DECLARE(slice_ruby_right);
LV_IMAGE_DECLARE(slice_lime_left);
LV_IMAGE_DECLARE(slice_lime_right);
LV_IMAGE_DECLARE(slice_amber_left);
LV_IMAGE_DECLARE(slice_amber_right);
LV_IMAGE_DECLARE(slice_berry_left);
LV_IMAGE_DECLARE(slice_berry_right);
LV_IMAGE_DECLARE(slice_bomb);
LV_IMAGE_DECLARE(slice_spark);
LV_IMAGE_DECLARE(slice_trail);
LV_IMAGE_DECLARE(catch_basket);
LV_IMAGE_DECLARE(catch_apple);
LV_IMAGE_DECLARE(catch_pear);
LV_IMAGE_DECLARE(catch_orange);
LV_IMAGE_DECLARE(catch_plum);
LV_IMAGE_DECLARE(catch_bomb);
static const lv_image_dsc_t *const player_signs[] = {
    &rps_player_rock,&rps_player_scissors,&rps_player_paper};
static const lv_image_dsc_t *const board_signs[] = {
    &rps_board_rock,&rps_board_scissors,&rps_board_paper};
static const lv_image_dsc_t *const shapes[] = {
    &slice_ruby,&slice_lime,&slice_amber,&slice_berry};
static const lv_image_dsc_t *const halves[][2] = {
    {&slice_ruby_left,&slice_ruby_right},{&slice_lime_left,&slice_lime_right},
    {&slice_amber_left,&slice_amber_right},{&slice_berry_left,&slice_berry_right}};
static const lv_image_dsc_t *const fruits[] = {
    &catch_apple,&catch_pear,&catch_orange,&catch_plum};
static lv_obj_t *frame, *actors[SLICE_OBJECTS], *pieces[SLICE_HALVES];
static lv_obj_t *effects[MOLE_HOLES], *trail[SLICE_TRAIL], *basket;
static lv_obj_t *countdown, *outcome;
static int old_trail[SLICE_TRAIL][2];
static unsigned old_trail_count;
static lv_obj_t *hidden_sprite(lv_obj_t *p, const lv_image_dsc_t *src)
{
    lv_obj_t *o = game_sprite(p,src,0,0);
    lv_obj_set_hidden(o,true);
    return o;
}
void ui_arcade_build(lv_obj_t *parent, lv_obj_t *labels)
{
    frame = parent;
    switch (ui_motion.game) {
        case MOTION_RPS:
            actors[0] = hidden_sprite(frame,&rps_player_rock);
            actors[1] = hidden_sprite(frame,&rps_board_rock);
            effects[0] = hidden_sprite(frame,&rps_win);
            countdown = ui_label(labels,"3",440,195,&sim_font_40,TEXT);
            lv_obj_set_width(countdown,400);
            lv_obj_set_style_text_align(countdown,LV_TEXT_ALIGN_CENTER,0);
            outcome = ui_label(labels,"",340,455,&sim_font_28,TEXT);
            lv_obj_set_width(outcome,600);
            lv_obj_set_style_text_align(outcome,LV_TEXT_ALIGN_CENTER,0);
            ui_label(labels,"玩家",380,265,&sim_font_20,TEXT);
            ui_label(labels,"开发板",820,265,&sim_font_20,TEXT);
            break;
        case MOTION_MOLE:
            for (unsigned i = 0; i < MOLE_HOLES; ++i) {
                int x, y;
                mole_center(i,&x,&y);
                game_sprite(frame,&mole_hole,x,y+35);
                actors[i] = hidden_sprite(frame,&mole_monster);
                effects[i] = hidden_sprite(frame,&mole_impact);
            }
            break;
        case MOTION_SLICE:
            for (unsigned i = 0; i < SLICE_OBJECTS; ++i)
                actors[i] = hidden_sprite(frame,&slice_ruby);
            for (unsigned i = 0; i < SLICE_HALVES; ++i)
                pieces[i] = hidden_sprite(frame,&slice_ruby_left);
            for (unsigned i = 0; i < SLICE_TRAIL; ++i)
                trail[i] = hidden_sprite(frame,&slice_trail);
            effects[0] = hidden_sprite(frame,&slice_spark);
            old_trail_count = 0;
            break;
        case MOTION_CATCH:
            for (unsigned i = 0; i < CATCH_OBJECTS; ++i)
                actors[i] = hidden_sprite(frame,&catch_apple);
            basket = game_sprite(frame,&catch_basket,640,CATCH_Y);
            break;
        default: break;
    }
}
static void rps_sync(void)
{
    const rps_state_t *s = &ui_motion.rps;
    bool show = s->phase == RPS_SHOW || s->phase == RPS_DONE;
    game_image(actors[0],s->player >= 0 ? player_signs[s->player] : &rps_player_rock,
               420,390,show && s->player >= 0,255);
    game_image(actors[1],s->board >= 0 ? board_signs[s->board] : &rps_board_rock,
               860,390,show && s->player >= 0,255);
    char text[64];
    if (s->phase == RPS_COUNTDOWN)
        snprintf(text,sizeof text,"%u",RPS_COUNT/GAME_HZ-s->ticks/GAME_HZ);
    else snprintf(text,sizeof text,"%s",s->phase == RPS_CAST ? "出！" : "");
    ui_text(countdown,text);
    ui_text(outcome,!show ? "" : s->player < 0 ? "没看清，再来一次" :
            s->outcome > 0 ? "你赢了！" : s->outcome < 0 ? "开发板获胜" : "平局");
    game_image(effects[0],s->outcome > 0 ? &rps_win : &rps_lose,640,430,
               show && s->player >= 0 && s->outcome != 0,255);
}
static void mole_sync(void)
{
    const mole_state_t *s = &ui_motion.mole;
    for (unsigned i = 0; i < MOLE_HOLES; ++i) {
        const mole_hole_t *h = &s->holes[i];
        int x, y;
        mole_center(i,&x,&y);
        const lv_image_dsc_t *src = h->kind == 2 ? &mole_bomb :
            h->flash ? &mole_monster_hit : h->kind == 1 ? &mole_gold : &mole_monster;
        game_image(actors[i],src,x,y,h->life || h->flash,
                   h->flash ? h->flash*255/MOLE_FLASH : 255);
        game_image(effects[i],&mole_impact,x,y-25,h->flash != 0,h->flash*255/MOLE_FLASH);
    }
}
static void trail_dirty(const int points[][2], unsigned count)
{
    for (unsigned i = 1; i < count; ++i)
        game_dirty(frame,points[i-1][0],points[i-1][1],points[i][0],points[i][1],8);
}
static void slice_sync(void)
{
    const slice_state_t *s = &ui_motion.slice;
    for (unsigned i = 0; i < SLICE_OBJECTS; ++i) {
        const slice_object_t *o = &s->objects[i];
        game_image(actors[i],o->bomb ? &slice_bomb : shapes[o->kind],
                   o->body.x/GAME_Q,o->body.y/GAME_Q,o->active,255);
    }
    for (unsigned i = 0; i < SLICE_HALVES; ++i) {
        const slice_half_t *h = &s->halves[i];
        game_image(pieces[i],halves[h->kind][h->side],h->body.x/GAME_Q,h->body.y/GAME_Q,
                   h->life != 0,h->life*255/SLICE_FADE);
    }
    game_image(effects[0],&slice_spark,s->flash_x,s->flash_y,s->flash != 0,s->flash*255/SLICE_FLASH);
    bool changed = old_trail_count != s->trail_count;
    for (unsigned i = 0; i < s->trail_count; ++i)
        if (old_trail[i][0] != s->trail[i][0] || old_trail[i][1] != s->trail[i][1])
            changed = true;
    if (changed) {
        trail_dirty(old_trail,old_trail_count);
        trail_dirty(s->trail,s->trail_count);
        for (unsigned i = 0; i < SLICE_TRAIL; ++i) {
            old_trail[i][0] = s->trail[i][0];
            old_trail[i][1] = s->trail[i][1];
            game_image(trail[i],&slice_trail,s->trail[i][0],s->trail[i][1],
                       i < s->trail_count,255-i*32);
        }
        old_trail_count = s->trail_count;
    }
}
static void catch_sync(void)
{
    const catch_state_t *s = &ui_motion.basket;
    for (unsigned i = 0; i < CATCH_OBJECTS; ++i) {
        const catch_fruit_t *f = &s->fruit[i];
        game_image(actors[i],f->bomb ? &catch_bomb : fruits[f->kind],
                   f->x/GAME_Q,f->y/GAME_Q,f->active,255);
    }
    game_image(basket,&catch_basket,s->basket_x/GAME_Q,CATCH_Y,true,
               s->flash && (s->flash/2)%2 ? 60 : 255);
}
void ui_arcade_sync(void)
{
    switch (ui_motion.game) {
        case MOTION_RPS: rps_sync(); break;
        case MOTION_MOLE: mole_sync(); break;
        case MOTION_SLICE: slice_sync(); break;
        case MOTION_CATCH: catch_sync(); break;
        default: break;
    }
}
void ui_arcade_draw(lv_layer_t *layer)
{
    if (ui_motion.game != MOTION_SLICE) return;
    const slice_state_t *s = &ui_motion.slice;
    lv_draw_line_dsc_t line;
    lv_draw_line_dsc_init(&line);
    line.color = lv_color_hex(0x56ffd6);
    for (unsigned i = 1; i < s->trail_count; ++i) {
        line.width = 8-(int)i;
        line.opa = 255-i*30;
        line.p1 = (lv_point_precise_t){s->trail[i-1][0],s->trail[i-1][1]};
        line.p2 = (lv_point_precise_t){s->trail[i][0],s->trail[i][1]};
        lv_draw_line(layer,&line);
    }
}
