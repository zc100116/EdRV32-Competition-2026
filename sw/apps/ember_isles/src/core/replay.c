/* File: replay.c
 * Spec: ember_isles tech 3; seed and one eight-bit input per frame.
 * Description: Text replay transport; parsed inputs are also embedded for Spike.
 * Clock domain: host replay setup.
 */
#include "core.h"
#include <stdio.h>
#include <inttypes.h>
#include <stdlib.h>
void ember_replay_load(struct ember_replay *replay, const char *path)
{
    FILE *file = fopen(path, "r");
    if (!file) { perror(path); exit(1); }
    if (fscanf(file, "EMBER1 %" SCNu32 " %" SCNu32, &replay->seed, &replay->count) != 2 ||
        replay->count > EMBER_REPLAY_FRAMES) {
        fprintf(stderr, "Invalid replay header: %s\n", path);
        exit(1);
    }
    for (unsigned i = 0; i < replay->count; ++i) {
        unsigned input;
        if (fscanf(file, "%u", &input) != 1 || input > 255) {
            fprintf(stderr, "Invalid replay input: %s frame %u\n", path, i);
            exit(1);
        }
        replay->input[i] = (uint8_t)input;
    }
    if (fclose(file)) { perror(path); exit(1); }
}
void ember_replay_save(const struct ember_replay *replay, const char *path)
{
    FILE *file = fopen(path, "w");
    if (!file) { perror(path); exit(1); }
    fprintf(file, "EMBER1 %" PRIu32 " %" PRIu32 "\n", replay->seed, replay->count);
    for (unsigned i = 0; i < replay->count; ++i) fprintf(file, "%u\n", replay->input[i]);
    if (fclose(file)) { perror(path); exit(1); }
}
