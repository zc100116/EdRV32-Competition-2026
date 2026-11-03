/* games.h — showcase 4.5.5; immutable list and append-only 8 MiB upload arena. */
#ifndef SHOWCASE_GAMES_H
#define SHOWCASE_GAMES_H
#include "records.h"
void board_games_init(void);
void board_games_step(void);
uint32_t board_game_destination(void);
uint32_t board_game_available(void);
unsigned board_game_append(uint32_t bytes, uint32_t *index);
const struct game_record *board_game(unsigned index);
void board_nes_select(unsigned index);
extern const struct app nes_app;
#endif
