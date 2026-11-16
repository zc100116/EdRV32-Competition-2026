/* motion.c — T-GAMES-MORE; lobby dwell, inference-frame routing and common restart.
 * CPU/GUI cooperative domain; switching games never requests a new vision session.
 */
#include "motion.h"
#include "sling.h"
#include <string.h>
#include <stdio.h>
void ui_data_grab_output(const char *text);
static unsigned speeds[] = {GAME_FAST,GAME_FAST,GAME_FAST,
                            GAME_SLOW,GAME_SLOW,GAME_SLOW};
static const char *const names[] = {"hall","sling","rps","mole","slice","catch"};
const char *motion_name(void) { return names[ui_motion.game]; }
const char *motion_speed_name(void)
{
    return ui_motion.speed == GAME_SLOW ? "慢" :
           ui_motion.speed == GAME_MEDIUM ? "中" : "快";
}
static void event(const char *kind)
{
    char text[160];
    snprintf(text,sizeof text,"game name=%s event=%s speed=%s score=%d dur_ms=%u\r\n",
             motion_name(),kind,motion_speed_name(),motion_score(),
             ui_motion.duration*1000/GAME_HZ);
    ui_data_grab_output(text);
}
void motion_finish(void)
{
    if (ui_motion.running) { event("end"); ui_motion.running = false; }
}
void motion_start(void)
{
    ui_motion.waiting = false;
    ui_motion.running = true;
    ui_motion.hold = 0;
    ui_motion.hovered = -1;
    ui_motion.duration = 0;
    event("start");
}
void motion_speed(unsigned speed)
{
    ui_motion.speed = speeds[ui_motion.game] = speed;
    ui_motion.mole.speed = ui_motion.slice.speed = ui_motion.basket.speed = speed;
}
int motion_setup_hover(int x, int y)
{
    if (y >= 370 && y < 430 && x >= 330 && x < 950) {
        int i = (x-330)/220;
        if ((x-330)%220 < 180) return i;
    }
    if (x >= 500 && x < 780 && y >= 490 && y < 550) return 3;
    return -1;
}
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
    motion_finish();
    ui_motion.game = game;
    ui_motion.waiting = game >= MOTION_MOLE;
    ui_motion.duration = 0;
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
    motion_speed(speeds[game]);
    if (game != MOTION_HALL && !ui_motion.waiting) motion_start();
}
void motion_card(unsigned card, int *x, int *y)
{
    *x = card < 3 ? GAME_SAFE_LEFT+(int)card*300 : 350+(int)(card-3)*300;
    *y = card < 3 ? GAME_SAFE_TOP+30 : 380;
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
    if (!lost) {
        uint32_t elapsed = stamp-ui_motion.seen_at;
        if (ui_motion.have_hand && elapsed) {
            ui_motion.velocity_x = (x-ui_motion.seen_x)*1000/(int)elapsed;
            ui_motion.velocity_y = (y-ui_motion.seen_y)*1000/(int)elapsed;
        }
        ui_motion.seen_x = x;
        ui_motion.seen_y = y;
        ui_motion.seen_at = stamp;
        ui_motion.have_hand = true;
    } else if (ui_motion.have_hand && stamp-ui_motion.seen_at <= MOTION_LOST_MS) {
        int elapsed = (int)(stamp-ui_motion.seen_at);
        x = ui_motion.seen_x + ui_motion.velocity_x*elapsed/1000;
        y = ui_motion.seen_y + ui_motion.velocity_y*elapsed/1000;
        raw_x = x;
        raw_y = y;
        closed = ui_motion.hand.closed;
        cls = ui_motion.hand.cls;
        lost = 0;
    }
    ui_motion.hand = (motion_hand_t){x,y,cls,closed,!lost,lost};
    if (ui_motion.waiting) return;
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
    if (ui_motion.waiting) {
        int hovered = h->present && h->cls == 1 ? motion_setup_hover(h->x,h->y) : -1;
        if (hovered != ui_motion.hovered || hovered < 0) ui_motion.hold = 0;
        ui_motion.hovered = hovered;
        if (hovered >= 0 && ui_motion.hold < MOTION_HOLD &&
            ++ui_motion.hold == MOTION_HOLD) {
            if (hovered == 3) motion_start();
            else motion_speed(GAME_SLOW+(unsigned)hovered);
        }
        return;
    }
    bool was_done = motion_done();
    if (ui_motion.running) ++ui_motion.duration;
    switch (ui_motion.game) {
        case MOTION_SLING: sling_step(&ui_sling); break;
        case MOTION_RPS: rps_step(&ui_motion.rps); break;
        case MOTION_MOLE: mole_step(&ui_motion.mole); break;
        case MOTION_SLICE: slice_step(&ui_motion.slice); break;
        case MOTION_CATCH: catch_step(&ui_motion.basket); break;
        default: break;
    }
    if (motion_done()) motion_finish();
    if (was_done && !motion_done()) motion_start();
    if (ui_motion.game != MOTION_SLING && motion_done()) {
        ui_motion.restart = h->present && h->cls == 1 && h->x >= 420 && h->x <= 860 &&
                            h->y >= 228 && h->y <= 478 ? ui_motion.restart+1 : 0;
        if (ui_motion.restart == MOTION_HOLD) motion_select(ui_motion.game);
    }
}
