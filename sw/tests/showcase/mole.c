/* mole.c — T-GAMES-MORE acceptance; edge, radius, visible lifetime and scoring. */
#include "mole.h"
#include <assert.h>
#include <stdio.h>
int main(void)
{
    mole_state_t s;
    mole_init(&s,7);
    int x, y;
    mole_center(0,&x,&y);
    assert(y >= 300 && y <= 560);
    s.holes[0].life = 30;
    mole_input(&s,x+71,y,true,true);
    assert(s.score == 0 && s.holes[0].life == 30);
    mole_input(&s,x,y,true,true);
    assert(s.score == 0); /* Moving while held is not a new hit. */
    mole_input(&s,x,y,false,true);
    mole_input(&s,x+70,y,true,true);
    assert(s.score == 10 && !s.holes[0].life && s.holes[0].flash == MOLE_FLASH);
    mole_input(&s,x,y,true,true);
    assert(s.score == 10);
    s.holes[0] = (mole_hole_t){1,0,1};
    mole_input(&s,x,y,false,true);
    mole_step(&s);
    mole_input(&s,x,y,true,true);
    assert(s.score == 10); /* The visible time expired before the hit. */
    s.holes[0] = (mole_hole_t){30,0,1};
    mole_input(&s,x,y,false,true);
    mole_input(&s,x,y,true,false);
    assert(s.score == 10 && s.holes[0].life == 30);
    mole_input(&s,x,y,true,true);
    assert(s.score == 40);
    s.holes[0] = (mole_hole_t){30,0,2};
    mole_input(&s,x,y,false,true);
    mole_input(&s,x,y,true,true);
    assert(s.score == 20);
    for (unsigned i = s.ticks; i < MOLE_SECONDS*GAME_HZ; ++i) {
        mole_step(&s);
        for (unsigned h = 0; h < MOLE_HOLES; ++h) assert(s.holes[h].life <= MOLE_LIFE_MAX);
    }
    assert(s.done);
    int score = s.score;
    mole_input(&s,x,y,false,true);
    mole_input(&s,x,y,true,true);
    assert(s.score == score);
    puts("PASS mole: open/grab edge, inclusive radius, visibility expiry, absent hand, "
         "normal/gold/bomb scores and 45-second end");
}
