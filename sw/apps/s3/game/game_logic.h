/* File: game_logic.h
 * Spec: design rnd-disp 5.2; SoC 3.5; Task B3-3b.
 * Description: Deterministic 60 Hz platform game, independent of display and RND.
 * Clock domain: clk_sys CPU, host in acceptance tests.
 */
#ifndef S3_GAME_LOGIC_H
#define S3_GAME_LOGIC_H
#include <stdint.h>
enum {
    GAME_WIDTH = 5120, GAME_HEIGHT = 720, GAME_SCREEN = 1280,
    GAME_PLAYER_W = 32, GAME_PLAYER_H = 48, GAME_COINS = 12, GAME_ENEMIES = 2
};
enum game_mode { GAME_PLAY, GAME_PAUSE, GAME_DEAD, GAME_WON, GAME_EXIT };
struct game_state {
    int x;
    int y;
    int vy;
    int grounded;
    int facing_left;
    int camera;
    unsigned int frame;
    unsigned int score;
    unsigned int deaths;
    uint32_t collected;
    uint32_t defeated;
    uint32_t previous_keys;
    enum game_mode mode;
    unsigned int selection;
};
struct game_object { int x; int y; int w; int h; };
extern const struct game_object game_coins[GAME_COINS];
extern const struct game_object game_spikes[2];
void game_reset(struct game_state *g);
void game_step(struct game_state *g, uint32_t keys);
int game_enemy_x(const struct game_state *g, unsigned int enemy);
#endif
