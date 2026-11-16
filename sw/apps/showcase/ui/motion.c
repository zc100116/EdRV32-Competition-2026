/* motion.c — T-GAMES-MORE; lobby dwell, inference-frame routing and common restart.
 * CPU/GUI cooperative domain; switching games never requests a new vision session.
 */
#include "motion.h"
#include "sling.h"
#include <string.h>
motion_state_t ui_motion;
void motion_init(void)
{
    memset(&ui_motion,0,sizeof ui_motion);
    ui_motion.rng = 1;
    ui_motion.hovered = -1;
    ui_motion.hand.cls = -1;
    ui_motion.hand.x = 640;
    ui_motion.hand.y = 360;
    ui_motion.hand.lost = SLING_LOST;
}
void motion_seed(uint32_t mtime) { ui_motion.rng = mtime | 1u; }
void motion_select(motion_game_t game)
{
    ui_motion.game = game;
    ui_motion.hold = ui_motion.restart = 0;
    ui_motion.hovered = -1;
    ++ui_motion.revision;
    uint32_t seed = game_random(&ui_motion.rng);
    switch (game) {
        case MOTION_SLING: sling_init(&ui_sling); break;
        case MOTION_RPS: rps_init(&ui_motion.rps,seed); break;
        case MOTION_MOLE: mole_init(&ui_motion.mole,seed); break;
        case MOTION_SLICE: slice_init(&ui_motion.slice,seed); break;
        case MOTION_CATCH: catch_init(&ui_motion.basket,seed); break;
        default: break;
    }
}
void motion_card(unsigned card, int *x, int *y)
{
    *x = card < 3 ? 80+(int)card*385 : 270+(int)(card-3)*385;
    *y = card < 3 ? 180 : 400;
}
int motion_hover(int x, int y)
{
    for (unsigned i = 0; i < MOTION_GAMES; ++i) {
        int cx, cy;
        motion_card(i,&cx,&cy);
        if (x >= cx && x < cx+MOTION_CARD_W && y >= cy && y < cy+MOTION_CARD_H)
            return (int)i;
    }
    return -1;
}
void motion_input(int x, int y, int raw_x, int raw_y, bool closed,
                  unsigned lost, int cls, uint32_t stamp)
{
    ++ui_motion.sample;
    ui_motion.hand = (motion_hand_t){x,y,cls,closed,!lost,lost};
    switch (ui_motion.game) {
        case MOTION_SLING: sling_input(&ui_sling,x,y,closed,lost,cls); break;
        case MOTION_RPS: rps_input(&ui_motion.rps,cls,!lost); break;
        case MOTION_MOLE: mole_input(&ui_motion.mole,x,y,closed,!lost); break;
        case MOTION_SLICE: slice_input(&ui_motion.slice,raw_x,raw_y,!lost,stamp); break;
        case MOTION_CATCH: catch_input(&ui_motion.basket,x,!lost); break;
        default: break;
    }
}
bool motion_done(void)
{
    switch (ui_motion.game) {
        case MOTION_SLING: return ui_sling.phase == SLING_DONE;
        case MOTION_RPS: return ui_motion.rps.phase == RPS_DONE;
        case MOTION_MOLE: return ui_motion.mole.done;
        case MOTION_SLICE: return ui_motion.slice.done;
        case MOTION_CATCH: return ui_motion.basket.done;
        default: return false;
    }
}
int motion_score(void)
{
    switch (ui_motion.game) {
        case MOTION_SLING: return (int)ui_sling.score;
        case MOTION_RPS: return rps_score(&ui_motion.rps);
        case MOTION_MOLE: return ui_motion.mole.score;
        case MOTION_SLICE: return ui_motion.slice.score;
        case MOTION_CATCH: return ui_motion.basket.score;
        default: return 0;
    }
}
unsigned motion_stars(void)
{
    int score = motion_score();
    switch (ui_motion.game) {
        case MOTION_SLING: return sling_stars(&ui_sling);
        case MOTION_RPS: return ui_motion.rps.wins >= RPS_WINS ? 3 :
                   ui_motion.rps.wins >= RPS_STAR_TWO ? 2 : 1;
        case MOTION_MOLE:
            return score >= MOLE_STAR_THREE ? 3 : score >= MOLE_STAR_TWO ? 2 : 1;
        case MOTION_SLICE:
            return score >= SLICE_STAR_THREE ? 3 : score >= SLICE_STAR_TWO ? 2 : 1;
        case MOTION_CATCH:
            return score >= CATCH_STAR_THREE ? 3 : score >= CATCH_STAR_TWO ? 2 : 1;
        default: return 1;
    }
}
void motion_step(void)
{
    const motion_hand_t *h = &ui_motion.hand;
    if (ui_motion.game == MOTION_HALL) {
        int hovered = h->present && h->cls == 1 ? motion_hover(h->x,h->y) : -1;
        if (hovered != ui_motion.hovered || hovered < 0) ui_motion.hold = 0;
        ui_motion.hovered = hovered;
        if (hovered >= 0 && ++ui_motion.hold == MOTION_HOLD)
            motion_select((motion_game_t)(hovered+1));
        return;
    }
    switch (ui_motion.game) {
        case MOTION_SLING: sling_step(&ui_sling); break;
        case MOTION_RPS: rps_step(&ui_motion.rps); break;
        case MOTION_MOLE: mole_step(&ui_motion.mole); break;
        case MOTION_SLICE: slice_step(&ui_motion.slice); break;
        case MOTION_CATCH: catch_step(&ui_motion.basket); break;
        default: break;
    }
    if (ui_motion.game != MOTION_SLING && motion_done()) {
        ui_motion.restart = h->present && h->cls == 1 ? ui_motion.restart+1 : 0;
        if (ui_motion.restart == MOTION_HOLD) motion_select(ui_motion.game);
    }
}
