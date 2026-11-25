/* File: meta.h; GDD 3.3/6, tech 2: requested persistent progression only.
 * Description: Character/talent unlocks, codex and host save transport.
 * Clock domain: host menu/run completion; never accessed by simulation replay.
 */
#ifndef EMBER_META_H
#define EMBER_META_H
#include "core/core.h"
struct ember_sim;
struct ember_codex {
    uint8_t enemies[21], weapons[50], relics[38], inscriptions[18];
    uint8_t blessings[13], resonances[10], pet_weapons[12], pets[6], world[9];
};
struct ember_meta {
    uint32_t fragments, hidden_rooms, arena_pillars, bosses;
    uint8_t characters, difficulty;
    uint8_t unlocked[8], selected[8][4];
    struct ember_codex codex;
};
void ember_meta_init(struct ember_meta *meta);
int ember_meta_character_ready(const struct ember_meta *meta, unsigned character);
int ember_meta_unlock_character(struct ember_meta *meta, unsigned character);
int ember_meta_unlock_talent(struct ember_meta *meta, unsigned character, unsigned node);
int ember_meta_select_talent(struct ember_meta *meta, unsigned character, unsigned node);
void ember_meta_config(const struct ember_meta *meta, unsigned character, unsigned pet,
                        unsigned difficulty, struct ember_run_config *config);
void ember_meta_commit(struct ember_meta *meta, const struct ember_sim *sim);
void ember_meta_load(struct ember_meta *meta, const char *path);
void ember_meta_save(const struct ember_meta *meta, const char *path);
#endif
