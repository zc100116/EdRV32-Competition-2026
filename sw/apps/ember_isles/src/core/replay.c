/* File: replay.c
 * Spec: ember_isles tech 3; seed and one sixteen-bit input per frame.
 * Description: Text replay transport; parsed inputs are also embedded for Spike.
 * Clock domain: host replay setup.
 */
#include "core.h"
#include "data.h"
#include <stdio.h>
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>
void ember_replay_load(struct ember_replay *replay, const char *path)
{
    FILE *file = fopen(path, "r");
    if (!file) { perror(path); exit(1); }
    unsigned values[12];
    char magic[16];
    if (fscanf(file, "%15s %" SCNu32 " %" SCNu32, magic, &replay->seed, &replay->count) != 3 ||
        strcmp(magic, "EMBER3") || replay->count > EMBER_REPLAY_FRAMES) {
        fprintf(stderr, "Invalid replay header: %s\n", path);
        exit(1);
    }
    for (unsigned i = 0; i < 12; ++i) {
        if (fscanf(file, "%u", &values[i]) != 1 || values[i] > 255) {
            fprintf(stderr, "Invalid replay configuration: %s field %u\n", path, i);
            exit(1);
        }
    }
    replay->config = (struct ember_run_config){
        .mode = (uint8_t)values[0], .stage = (uint8_t)values[1],
        .character = (uint8_t)values[2], .main_weapon = (uint8_t)values[3],
        .sub_weapon = (uint8_t)values[4], .pet = (uint8_t)values[5],
        .pet_weapon = (uint8_t)values[6],
        .talents = {(uint8_t)values[7], (uint8_t)values[8],
                    (uint8_t)values[9], (uint8_t)values[10]}, .difficulty = (uint8_t)values[11]};
    const struct ember_run_config *c = &replay->config;
    /* GDD 3.3/5c/6: serialized catalog IDs, unique slots and per-row talent choices. */
    if (c->mode > EMBER_ROUTE || c->stage >= EMBER_STAGES_COUNT ||
        c->character >= EMBER_CHARACTERS_COUNT || c->main_weapon >= EMBER_WEAPONS_COUNT ||
        (c->sub_weapon != 255 && (c->sub_weapon >= EMBER_WEAPONS_COUNT ||
            c->sub_weapon == c->main_weapon)) ||
        (c->pet != 255 && c->pet >= EMBER_PETS_COUNT) ||
        (c->pet_weapon != 255 && (c->pet_weapon >= EMBER_PET_WEAPONS_COUNT || c->pet == 255)) ||
        c->talents[0] > 1 || c->difficulty > ember_meta_rules[0].difficulty_affixes) {
        fprintf(stderr, "Replay configuration outside GDD catalog/slot rules: %s\n", path);
        exit(1);
    }
    for (unsigned row = 1; row < 4; ++row)
        if (c->talents[row] != 255 && c->talents[row] > 1) {
            fprintf(stderr, "Invalid replay talent row %u: %s\n", row, path);
            exit(1);
        }
    for (unsigned i = 0; i < replay->count; ++i) {
        unsigned input;
        if (fscanf(file, "%u", &input) != 1 || input > 8191) {
            fprintf(stderr, "Invalid replay input: %s frame %u\n", path, i);
            exit(1);
        }
        replay->input[i] = (uint16_t)input;
    }
    if (fclose(file)) { perror(path); exit(1); }
}
void ember_replay_save(const struct ember_replay *replay, const char *path)
{
    FILE *file = fopen(path, "w");
    if (!file) { perror(path); exit(1); }
    const struct ember_run_config *c = &replay->config;
    fprintf(file, "EMBER3 %" PRIu32 " %" PRIu32 " %u %u %u %u %u %u %u %u %u %u %u %u\n",
        replay->seed, replay->count, c->mode, c->stage, c->character, c->main_weapon,
        c->sub_weapon, c->pet, c->pet_weapon, c->talents[0], c->talents[1],
        c->talents[2], c->talents[3], c->difficulty);
    for (unsigned i = 0; i < replay->count; ++i) fprintf(file, "%u\n", replay->input[i]);
    if (fclose(file)) { perror(path); exit(1); }
}
