/* File: game_render.h
 * Spec: rnd 2.5/2.6/5.4; DISP 5.3; Task B3-3b.
 * Description: Game render submissions and Surface access, separate from game logic.
 * Clock domain: clk_sys CPU.
 */
#ifndef S3_GAME_RENDER_H
#define S3_GAME_RENDER_H
#include "game_logic.h"
void game_render_init(void);
void game_render_frame(const struct game_state *g, unsigned int buffer);
uint64_t game_render_ticks(void);
const void *game_background(void);
const void *game_overlay(unsigned int buffer);
#endif
