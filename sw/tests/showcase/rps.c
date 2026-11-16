/* rps.c — T-GAMES-MORE acceptance; table, inference votes and empty windows. */
#include "rps.h"
#include <assert.h>
#include <stdio.h>
static void steps(rps_state_t *s, unsigned n) { while (n--) rps_step(s); }
int main(void)
{
    static const int table[3][3] = {{0,1,-1},{-1,0,1},{1,-1,0}};
    for (int p = 0; p < 3; ++p)
        for (int b = 0; b < 3; ++b) assert(rps_outcome(p,b) == table[p][b]);
    assert(rps_class(1) == 0 && rps_class(2) == 1);
    assert(rps_class(0) == 2 && rps_class(11) == 2 && rps_class(5) == -1);
    rps_state_t s;
    rps_init(&s,12345);
    rps_input(&s,1,true);
    assert(!s.votes[0]);
    steps(&s,RPS_COUNT-1);
    assert(s.phase == RPS_COUNTDOWN);
    rps_step(&s);
    assert(s.phase == RPS_CAST && s.board >= 0 && s.board <= 2);
    rps_input(&s,1,true);
    rps_input(&s,2,true);
    rps_input(&s,2,true);
    rps_input(&s,0,false);
    rps_input(&s,5,true);
    steps(&s,RPS_WINDOW);
    assert(s.phase == RPS_SHOW && s.player == 1 && s.rounds == 1);
    steps(&s,RPS_REVEAL+RPS_COUNT+RPS_WINDOW);
    assert(s.phase == RPS_SHOW && s.player == -1 && s.rounds == 1);
    steps(&s,RPS_REVEAL);
    assert(s.phase == RPS_COUNTDOWN);
    rps_init(&s,54321);
    for (unsigned i = 0; i < 3; ++i) {
        steps(&s,RPS_COUNT);
        int player = (s.board+2)%3;
        int cls[] = {1,2,0};
        for (unsigned f = 0; f < 16; ++f) rps_input(&s,cls[player],true);
        steps(&s,RPS_WINDOW+RPS_REVEAL);
    }
    assert(s.phase == RPS_DONE && s.rounds == 3 && s.wins == 3 && rps_score(&s) == 300);
    rps_init(&s,314159);
    for (unsigned i = 0; i < 5; ++i) {
        steps(&s,RPS_COUNT);
        int cls[] = {1,2,0};
        rps_input(&s,cls[s.board],true);
        steps(&s,RPS_WINDOW+RPS_REVEAL);
    }
    assert(s.phase == RPS_DONE && s.rounds == 5 && s.ties == 5 && rps_score(&s) == 125);
    unsigned empty[3] = {0,0,0};
    unsigned paper[3] = {2,1,5};
    assert(rps_majority(empty) == -1 && rps_majority(paper) == 2);
    puts("PASS rps: complete outcome table, 18-tick inference votes, invalid/absent input, "
         "empty-window retry and first-to-three match");
}
