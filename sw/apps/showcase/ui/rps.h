/* rps.h — T-GAMES-MORE rock/scissors/paper; five rounds, first to three wins.
 * CPU domain; only inference frames vote during the 18-reference-tick (0.6 s) cast window.
 */
#ifndef SHOWCASE_RPS_H
#define SHOWCASE_RPS_H
#include "game_math.h"
enum { RPS_COUNT = 3*GAME_HZ, RPS_WINDOW = 18, RPS_REVEAL = 45,
       RPS_ROUNDS = 5, RPS_WINS = 3, RPS_STAR_TWO = 2, RPS_WIN_SCORE = 100, RPS_TIE_SCORE = 25 };
typedef enum { RPS_COUNTDOWN, RPS_CAST, RPS_SHOW, RPS_DONE } rps_phase_t;
typedef struct {
    rps_phase_t phase;
    unsigned ticks, rounds, wins, losses, ties, votes[3];
    int player, board, outcome;
    uint32_t rng;
} rps_state_t;
int rps_class(int cls);
int rps_outcome(int player, int board);
int rps_majority(const unsigned votes[3]);
void rps_init(rps_state_t *s, uint32_t seed);
void rps_input(rps_state_t *s, int cls, bool present);
void rps_step(rps_state_t *s);
int rps_score(const rps_state_t *s);
#endif
