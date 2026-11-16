/* motion.c — T-GAMES-MORE acceptance; lobby dwell and shared game restart. */
#include "motion.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned starts, ends;
static char log_line[200];
void ui_data_grab_output(const char *text)
{
    snprintf(log_line,sizeof log_line,"%s",text);
    if (strstr(text,"event=start")) ++starts;
    if (strstr(text,"event=end")) ++ends;
}
int main(void)
{
    for (unsigned card = 0; card < MOTION_GAMES; ++card) {
        motion_init();
        motion_seed(123456);
        int x, y;
        motion_card(card,&x,&y);
        assert(x >= GAME_SAFE_LEFT && x+MOTION_CARD_W <= GAME_SAFE_RIGHT);
        assert(y >= GAME_SAFE_TOP && y+MOTION_CARD_H <= GAME_SAFE_BOTTOM);
        assert(motion_hover(x+50,y+50) == (int)card);
        motion_input(x+50,y+50,x+50,y+50,true,0,1,1000);
        for (unsigned i = 0; i < MOTION_HOLD-1; ++i) motion_step();
        assert(ui_motion.game == MOTION_HALL && ui_motion.hold == MOTION_HOLD-1);
        motion_step();
        assert(ui_motion.game == (motion_game_t)(card+1));
    }
    motion_init();
    int x, y;
    motion_card(0,&x,&y);
    motion_input(x+50,y+50,x,y,true,0,1,1000);
    for (unsigned i = 0; i < 20; ++i) motion_step();
    motion_input(x+50,y+50,x,y,false,0,0,2000);
    motion_step();
    assert(!ui_motion.hold && ui_motion.game == MOTION_HALL);
    motion_input(x+50,y+50,x,y,true,0,1,3000);
    for (unsigned i = 0; i < 20; ++i) motion_step();
    motion_input(x+50,y+50,x,y,true,1,1,3100);
    motion_step();
    assert(!ui_motion.hold);
    motion_input(0,0,0,0,true,0,1,3200);
    for (unsigned i = 0; i < 40; ++i) motion_step();
    assert(ui_motion.game == MOTION_HALL);
    motion_select(MOTION_MOLE);
    assert(ui_motion.waiting && ui_motion.speed == GAME_SLOW);
    for (unsigned i = 0; i < GAME_HZ; ++i) motion_step();
    assert(!ui_motion.mole.ticks);
    motion_start();
    ui_motion.mole.done = true;
    ui_motion.mole.score = 250;
    assert(motion_done() && motion_stars() == 3);
    motion_input(640,360,640,360,true,0,1,4000);
    for (unsigned i = 0; i < MOTION_HOLD; ++i) motion_step();
    assert(ui_motion.game == MOTION_MOLE && !motion_done() && motion_score() == 0);
    assert(ui_motion.waiting);
    motion_input(800,400,800,400,true,0,1,5000);
    for (unsigned i = 0; i < MOTION_HOLD; ++i) motion_step();
    assert(ui_motion.speed == GAME_FAST);
    motion_input(640,520,640,520,true,0,1,5100);
    for (unsigned i = 0; i < MOTION_HOLD; ++i) motion_step();
    assert(!ui_motion.waiting && ui_motion.running);
    assert(strstr(log_line,"name=mole event=start speed=快 score=0 dur_ms=0"));
    for (unsigned i = 0; i < GAME_HZ; ++i) motion_step();
    motion_select(MOTION_HALL);
    assert(strstr(log_line,"event=end speed=快") && strstr(log_line,"dur_ms=1000"));
    motion_select(MOTION_MOLE);
    assert(ui_motion.waiting && ui_motion.speed == GAME_FAST);
    assert(starts && ends);
    puts("PASS lobby: all five cards, exact one-second fist hold, open/loss/outside reset "
         "and shared result restart");
}
