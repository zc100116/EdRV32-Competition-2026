/* rps.c — T-GAMES-MORE; debounced frame votes and timed match state machine.
 * CPU domain; LFSR opponent selection is independent of the player's vote.
 */
#include "rps.h"
#include <string.h>
int rps_class(int cls)
{
    return cls == 1 ? 0 : cls == 2 ? 1 : cls == 0 || cls == 11 ? 2 : -1;
}
int rps_outcome(int player, int board)
{
    return player == board ? 0 : (player + 1) % 3 == board ? 1 : -1;
}
int rps_majority(const unsigned votes[3])
{
    if (!votes[0] && !votes[1] && !votes[2]) return -1;
    unsigned best = 0;
    for (unsigned i = 1; i < 3; ++i) if (votes[i] > votes[best]) best = i;
    return (int)best;
}
void rps_init(rps_state_t *s, uint32_t seed)
{
    memset(s,0,sizeof *s);
    s->rng = seed | 1u;
    s->phase = RPS_COUNTDOWN;
    s->player = s->board = -1;
}
void rps_input(rps_state_t *s, int cls, bool present)
{
    int sign = rps_class(cls);
    if (s->phase == RPS_CAST && present && sign >= 0) ++s->votes[sign];
}
void rps_step(rps_state_t *s)
{
    if (s->phase == RPS_DONE) return;
    ++s->ticks;
    if (s->phase == RPS_COUNTDOWN && s->ticks == RPS_COUNT) {
        s->phase = RPS_CAST;
        s->ticks = 0;
        memset(s->votes,0,sizeof s->votes);
        s->board = (int)(game_random(&s->rng) % 3);
    } else if (s->phase == RPS_CAST && s->ticks == RPS_WINDOW) {
        s->player = rps_majority(s->votes);
        if (s->player >= 0) {
            s->outcome = rps_outcome(s->player,s->board);
            ++s->rounds;
            if (s->outcome > 0) ++s->wins;
            else if (s->outcome < 0) ++s->losses;
            else ++s->ties;
        }
        s->phase = RPS_SHOW;
        s->ticks = 0;
    } else if (s->phase == RPS_SHOW && s->ticks == RPS_REVEAL) {
        s->phase = s->wins == RPS_WINS || s->losses == RPS_WINS ||
                   s->rounds == RPS_ROUNDS ? RPS_DONE : RPS_COUNTDOWN;
        s->ticks = 0;
    }
}
int rps_score(const rps_state_t *s)
{
    return (int)s->wins * RPS_WIN_SCORE + (int)s->ties * RPS_TIE_SCORE;
}
