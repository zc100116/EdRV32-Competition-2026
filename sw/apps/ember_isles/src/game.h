/* File: game.h; ember_isles tech 2. Main loop shared by board and PC.
 * Clock domain: fixed 60 Hz game frame.
 */
#ifndef EMBER_GAME_H
#define EMBER_GAME_H
#include "sim/sim.h"
void ember_game_init(void);
void ember_game_frame(unsigned frame);
void ember_game_replay(uint32_t seed);
const struct ember_sim *ember_game_state(void);
const struct ember_replay *ember_game_recording(void);
#endif
