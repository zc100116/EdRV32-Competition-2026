/* page_sling.c — T-GAME-SLING; AR sprites and clipped moving overlays on L1.
 * GUI clock; fixed 30 Hz physics, image positions invalidate only old/new bounds.
 */
#include "game_view.h"
#include "sling.h"
#include "src/draw/lv_draw_private.h"
#include "src/misc/lv_area_private.h"
LV_IMAGE_DECLARE(sling_slingshot);
LV_IMAGE_DECLARE(sling_ball);
LV_IMAGE_DECLARE(sling_crate);
LV_IMAGE_DECLARE(sling_balloon_coral);
LV_IMAGE_DECLARE(sling_balloon_blue);
LV_IMAGE_DECLARE(sling_platform);
LV_IMAGE_DECLARE(sling_wood_chip);
LV_IMAGE_DECLARE(sling_balloon_chip);
static lv_obj_t *frame, *ball, *targets[SLING_TARGETS], *chips[SLING_PARTICLES];
static sling_state_t shown;
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
    dirty(SLING_X-38,SLING_Y,x,y,5);
    dirty(SLING_X+38,SLING_Y,x,y,5);
    if (s->phase != SLING_AIM) return;
    sling_body_t p;
    trajectory(s,&p);
    for (unsigned i = 0; i < SLING_PREVIEW; ++i) {
        sling_integrate(&p);
        lv_area_t a = around(p.x/SLING_Q,p.y/SLING_Q,5);
        lv_obj_invalidate_area(frame,&a);
    }
}
void ui_sling_draw(lv_layer_t *layer)
{
    lv_draw_line_dsc_t line;
    lv_draw_line_dsc_init(&line);
    line.color = lv_color_hex(0x633e27);
    line.width = 7;
    if (shown.phase == SLING_AIM || shown.phase == SLING_READY) {
        for (unsigned i = 0; i < 2; ++i) {
            line.p1 = (lv_point_precise_t){SLING_X+(i ? 38 : -38),SLING_Y};
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
}
void ui_sling_sync(void)
{
    sling_state_t *s = &ui_sling;
    if (shown.ball.x != s->ball.x || shown.ball.y != s->ball.y || shown.phase != s->phase) {
        invalidate_aim(&shown);
        invalidate_aim(s);
    }
    game_image(ball,&sling_ball,s->ball.x/SLING_Q,s->ball.y/SLING_Q,
               s->phase != SLING_DONE,255);
    for (unsigned i = 0; i < SLING_TARGETS; ++i)
        lv_obj_set_hidden(targets[i],!s->targets[i].alive);
    for (unsigned i = 0; i < SLING_PARTICLES; ++i) {
        sling_particle_t *p = &s->particles[i];
        game_image(chips[i],p->balloon ? &sling_balloon_chip : &sling_wood_chip,
                   p->body.x/SLING_Q,p->body.y/SLING_Q,p->life != 0,p->life*255/SLING_FADE);
    }
    shown = *s;
}
void ui_sling_build(lv_obj_t *parent)
{
    frame = parent;
    shown = ui_sling;
    game_sprite(frame,&sling_slingshot,SLING_X,SLING_Y+85);
    for (unsigned i = 0; i < 3; ++i)
        game_sprite(frame,&sling_platform,890+140*(int)i,614-160*(int)i);
    for (unsigned i = 0; i < SLING_TARGETS; ++i) {
        sling_target_t *t = &shown.targets[i];
        targets[i] = game_sprite(frame,t->balloon ?
            (i == 3 ? &sling_balloon_blue : &sling_balloon_coral) : &sling_crate,t->x,t->y);
    }
    ball = game_sprite(frame,&sling_ball,SLING_X,SLING_Y);
    for (unsigned i = 0; i < SLING_PARTICLES; ++i) {
        chips[i] = game_sprite(frame,&sling_wood_chip,0,0);
        lv_obj_set_hidden(chips[i],true);
    }
}
